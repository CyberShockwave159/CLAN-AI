import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/data/datasources/llama_api_service.dart';
import 'package:clan_ai/data/datasources/local_storage.dart';
import 'package:clan_ai/data/repositories/chat_repository.dart';
import 'package:clan_ai/data/repositories/server_repository.dart';
import 'package:clan_ai/ui/features/chat/view_models/chat_view_model.dart';
import 'package:clan_ai/ui/features/chat/views/chat_screen.dart';
import 'package:clan_ai/ui/features/settings/view_models/settings_view_model.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize local persistence
  await LocalDatabase.instance.database;

  final apiService = LlamaApiService();
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
      ],
      child: const ClanAiApp(),
    ),
  );
}

class ClanAiApp extends StatelessWidget {
  const ClanAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CLAN AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark, // Default to sleek dark OLED mode
      home: const ChatScreen(),
    );
  }
}
