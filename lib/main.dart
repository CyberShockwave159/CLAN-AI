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
import 'package:clan_ai/data/repositories/character_repository.dart';
import 'package:clan_ai/data/repositories/chat_repository.dart';
import 'package:clan_ai/data/repositories/server_repository.dart';
import 'package:clan_ai/ui/features/chat/view_models/chat_view_model.dart';
import 'package:clan_ai/ui/features/chat/views/chat_screen.dart';
import 'package:clan_ai/ui/features/roleplay/views/roleplay_screen.dart';
import 'package:clan_ai/ui/features/roleplay/view_models/roleplay_view_model.dart';
import 'package:clan_ai/ui/features/settings/view_models/settings_view_model.dart';
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
          create: (_) => RoleplayViewModel(
            chatRepository: chatRepository,
            characterRepository: CharacterRepository(),
          ),
        ),
        Provider(
          create: (_) => CharacterRepository(),
        ),
      ],
      child: ClanAiApp(httpClient: sharedHttpClient),
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      widget.httpClient.close();
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
      title: 'CLAN AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      home: const _HomeScreen(),
    );
  }

  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    try {
      final mode = await LocalDatabase.instance.loadThemeMode();
      if (mounted) {
        setState(() {
          _themeMode = ThemeMode.values.firstWhere(
            (m) => m.name == mode,
            orElse: () => ThemeMode.dark,
          );
        });
      }
    } catch (_) {
      // Keep default dark theme
    }
  }
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen();

  @override
  Widget build(BuildContext context) {
    final appMode = context.watch<SettingsViewModel>().appMode;

    if (appMode == AppMode.roleplay) {
      return const RoleplayScreen();
    }

    return const ChatScreen();
  }
}
