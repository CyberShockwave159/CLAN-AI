import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/core/network/http_client.dart';
import 'package:clan_ai/core/utils/latency_meter.dart';
import 'package:clan_ai/data/datasources/llama_api_service.dart';
import 'package:clan_ai/data/datasources/local_storage.dart';
import 'package:clan_ai/data/models/app_mode.dart';
import 'package:clan_ai/data/models/app_theme_mode.dart';
import 'package:clan_ai/data/models/custom_theme_colors.dart';
import 'package:clan_ai/data/repositories/character_repository.dart';
import 'package:clan_ai/data/repositories/chat_repository.dart';
import 'package:clan_ai/data/repositories/server_repository.dart';
import 'package:clan_ai/ui/features/chat/view_models/chat_view_model.dart';
import 'package:clan_ai/ui/features/chat/views/chat_screen.dart';
import 'package:clan_ai/ui/features/roleplay/views/roleplay_screen.dart';
import 'package:clan_ai/ui/features/roleplay/view_models/persona_template_view_model.dart';
import 'package:clan_ai/ui/features/roleplay/view_models/roleplay_view_model.dart';
import 'package:clan_ai/ui/features/settings/view_models/settings_view_model.dart';
import 'package:clan_ai/ui/shared/widgets/desktop_keyboard_shortcuts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

// Global flag to track if SQLite FFI factory has been initialized
bool _sqfliteFfiInitialized = false;

void _initSqliteFfi() {
  if (_sqfliteFfiInitialized) return;
  if (kIsWeb) {
    // Web: sqlite runs in-browser via WASM, persisted in IndexedDB
    // (sqflite_common_ffi_web, shared-worker backed). The getter throws on
    // native platforms, but this branch only executes on web.
    databaseFactory = databaseFactoryFfiWeb;
    _sqfliteFfiInitialized = true;
    return;
  }
  if (defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _sqfliteFfiInitialized = true;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite FFI factory ONCE at app startup
  _initSqliteFfi();

  // Initialize local persistence
  await LocalDatabase.instance.database;

  // Create shared HTTP client and latency meter
  final sharedHttpClient = ApiHttpClient();
  final latencyMeter = LatencyMeter(sharedHttpClient);
  final apiService = LlamaApiService(sharedHttpClient, latencyMeter);
  final serverRepository = ServerRepository(apiService);
  final chatRepository = ChatRepository(apiService);
  final characterRepository = CharacterRepository();
  final navigatorKey = GlobalKey<NavigatorState>();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => SettingsViewModel(serverRepository),
        ),
        ChangeNotifierProvider(
          create: (_) => ChatViewModel(chatRepository),
        ),
        ChangeNotifierProvider(
          create: (_) => PersonaTemplateViewModel(),
        ),
        ChangeNotifierProvider(
          create: (_) => RoleplayViewModel(chatRepository, characterRepository),
        ),
        Provider<CharacterRepository>.value(value: characterRepository),
      ],
      child: DesktopKeyboardShortcuts(
        navigatorKey: navigatorKey,
        child: ClanAiApp(
          httpClient: sharedHttpClient,
          navigatorKey: navigatorKey,
        ),
      ),
    ),
  );
}

class ClanAiApp extends StatefulWidget {
  final ApiHttpClient httpClient;
  final GlobalKey<NavigatorState> navigatorKey;

  const ClanAiApp({
    required this.httpClient,
    required this.navigatorKey,
    super.key,
  });

  @override
  State<ClanAiApp> createState() => _ClanAiAppState();
}

class _ClanAiAppState extends State<ClanAiApp> with WidgetsBindingObserver {
  ThemeData _currentTheme = AppTheme.darkTheme;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAppThemeMode();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  Future<void> _loadAppThemeMode() async {
    try {
      final mode = await LocalDatabase.instance.loadAppThemeMode();
      final colors = await LocalDatabase.instance.loadCustomThemeColors();
      if (mounted) {
        setState(() {
          _currentTheme = _buildTheme(mode, colors);
        });
      }
    } catch (e, st) {
      // Keep the default dark theme, but surface the failure for debugging.
      debugPrint('Failed to load app theme mode: $e\n$st');
    }
  }

  ThemeData _buildTheme(AppThemeMode mode, CustomThemeColors? colors) {
    switch (mode) {
      case AppThemeMode.dark:
        return AppTheme.darkTheme;
      case AppThemeMode.light:
        return AppTheme.lightTheme;
      case AppThemeMode.custom:
        return colors != null
            ? AppTheme.customTheme(colors)
            : AppTheme.darkTheme;
    }
  }

  void _refreshTheme() {
    if (mounted) {
      _loadAppThemeMode();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: widget.navigatorKey,
      title: 'CLAN AI',
      debugShowCheckedModeBanner: false,
      theme: _currentTheme,
      home: _HomeScreen(themeRefresh: _refreshTheme),
    );
  }
}

class _HomeScreen extends StatefulWidget {
  final VoidCallback themeRefresh;

  const _HomeScreen({required this.themeRefresh});

  @override
  State<_HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<_HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Register the theme-refresh callback exactly once. Doing this in build()
    // (via addPostFrameCallback) is a side effect in build and re-registers on
    // every rebuild.
    context.read<SettingsViewModel>().setOnThemeChanged(widget.themeRefresh);
  }

  @override
  Widget build(BuildContext context) {
    final appMode = context.watch<SettingsViewModel>().appMode;

    if (appMode == AppMode.roleplay) {
      return RoleplayScreen(themeRefresh: widget.themeRefresh);
    }

    return ChatScreen(themeRefresh: widget.themeRefresh);
  }
}
