import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/core/network/http_client.dart';
import 'package:clan_ai/core/utils/latency_meter.dart';
import 'package:clan_ai/core/utils/pwa_update_checker.dart';
import 'package:clan_ai/core/utils/web_page_reloader.dart';
import 'package:clan_ai/data/datasources/aprox_rag_client.dart';
import 'package:clan_ai/data/datasources/llama_api_service.dart';
import 'package:clan_ai/data/datasources/local_storage.dart';
import 'package:clan_ai/data/models/app_mode.dart';
import 'package:clan_ai/data/models/app_theme_mode.dart';
import 'package:clan_ai/data/models/character_profile.dart';
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
        // Exposed for the auxiliary character-image calls (style detection),
        // which run outside any view model and need a one-shot completion.
        Provider<ChatRepository>.value(value: chatRepository),
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
    _wireAppearanceSync();
  }

  /// Mirrors a character's appearance sheet into the A-PROX RAG store whenever
  /// the character is saved.
  ///
  /// Wired here rather than in `main()` because it needs both the character
  /// repository and the *active* server profile, and the profile only exists
  /// once `SettingsViewModel` has loaded. Idempotent: the callback is installed
  /// once, and the repository skips the call when no sink is set.
  void _wireAppearanceSync() {
    final characterRepository = context.read<CharacterRepository>();
    if (characterRepository.onAppearanceChanged != null) return;

    final ragClient = AproxRagClient(widget.httpClient);
    characterRepository.onAppearanceChanged = (character, appearance) async {
      final settingsVM = context.read<SettingsViewModel>();
      final connection = settingsVM.connectionDetails;
      // Only mirror when the server can actually store it.
      if (!AproxRagClient.isAvailable(connection)) return;
      if (appearance == null || appearance.trim().isEmpty) return;
      await ragClient.ingest(
        connection: connection,
        collection: AproxRagClient.visualCollection(character.id),
        sourceUri: AproxRagClient.visualSourceUri(character.id),
        content: _appearanceDocument(character),
      );
    };
  }

  /// Renders a character's appearance sheet as a retrievable document.
  ///
  /// Appearance only — wardrobe deliberately excluded, since it should change
  /// with the scene rather than being pinned. The name is in the text because
  /// A-PROX retrieves by embedding similarity, not by exact match.
  static String _appearanceDocument(CharacterProfile character) {
    return '[Character Visual Sheet: ${character.name}]\n'
        '${character.appearance!.trim()}';
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
  PwaUpdateChecker? _updateChecker;

  @override
  void initState() {
    super.initState();
    // Register the theme-refresh callback exactly once. Doing this in build()
    // (via addPostFrameCallback) is a side effect in build and re-registers on
    // every rebuild.
    context.read<SettingsViewModel>().setOnThemeChanged(widget.themeRefresh);

    // Web only: poll version.json so users running an old build get prompted to
    // reload as soon as a new release is deployed.
    if (kIsWeb) {
      _updateChecker = PwaUpdateChecker()..addListener(_onUpdateAvailable);
      _updateChecker!.start();
    }
  }

  void _onUpdateAvailable() {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('A new version of CLAN AI is available.'),
          duration: const Duration(seconds: 30),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          action: SnackBarAction(label: 'Reload', onPressed: reloadAppPage),
        ),
      );
  }

  @override
  void dispose() {
    _updateChecker?.removeListener(_onUpdateAvailable);
    _updateChecker?.dispose();
    super.dispose();
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
