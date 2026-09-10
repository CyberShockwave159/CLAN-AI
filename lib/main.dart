import 'dart:io';
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

// Global flag to track if SQLite FFI factory has been initialized
bool _sqfliteFfiInitialized = false;

void _initSqliteFfi() {
  if (_sqfliteFfiInitialized) return;
  if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
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
  final latencyMeter = LatencyMeter(httpClient: sharedHttpClient);
  final apiService = LlamaApiService(
    httpClient: sharedHttpClient,
    latencyMeter: latencyMeter,
  );
  final serverRepository = ServerRepository(apiService: apiService);
  final chatRepository = ChatRepository(apiService: apiService);
  final characterRepository = CharacterRepository();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => SettingsViewModel(serverRepository: serverRepository),
        ),
        ChangeNotifierProvider(
          create: (_) => ChatViewModel(chatRepository: chatRepository),
        ),
        ChangeNotifierProvider(
          create: (_) => PersonaTemplateViewModel(),
        ),
        ChangeNotifierProvider(
          create: (_) => RoleplayViewModel(
            chatRepository: chatRepository,
            characterRepository: characterRepository,
          ),
        ),
        Provider<CharacterRepository>.value(value: characterRepository),
      ],
      child: DesktopKeyboardShortcuts(
        child: ClanAiApp(httpClient: sharedHttpClient),
      ),
    ),
  );
}

class ClanAiApp extends StatefulWidget {
  final ApiHttpClient httpClient;

  const ClanAiApp({required this.httpClient, super.key});

  @override
  State<ClanAiApp> createState() => _ClanAiAppState();
}

class _ClanAiAppState extends State<ClanAiApp> with WidgetsBindingObserver {
  final navigatorKey = GlobalKey<NavigatorState>();
  ThemeData _currentTheme = AppTheme.darkTheme;

  @override
  void initState() {
    super.initState();
    DesktopKeyboardShortcuts.navigatorKey = navigatorKey;
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
    } catch (_) {
      // Keep default dark theme
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
      navigatorKey: navigatorKey,
      title: 'CLAN AI',
      debugShowCheckedModeBanner: false,
      theme: _currentTheme,
      home: _HomeScreen(themeRefresh: _refreshTheme),
    );
  }
}

class _HomeScreen extends StatelessWidget {
  final VoidCallback themeRefresh;

  const _HomeScreen({required this.themeRefresh});

  @override
  Widget build(BuildContext context) {
    final appMode = context.watch<SettingsViewModel>().appMode;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settingsVM = context.read<SettingsViewModel>();
      settingsVM.setOnThemeChanged(themeRefresh);
    });

    if (appMode == AppMode.roleplay) {
      return RoleplayScreen(themeRefresh: themeRefresh);
    }

    return ChatScreen(themeRefresh: themeRefresh);
  }
}
