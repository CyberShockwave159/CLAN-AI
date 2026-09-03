import 'package:clan_ai/core/utils/latency_meter.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/chat_thread.dart';
import 'package:clan_ai/data/models/character_profile.dart';
import 'package:clan_ai/data/models/persona_template.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/data/models/server_profile.dart';
import 'package:clan_ai/domain/models/generation_params.dart';

// --- ChatThread factories ---

ChatThread buildThread({
  String? id,
  String title = 'Test Thread',
  String? systemPrompt,
  String? modelId,
  bool isPinned = false,
  String? branchFromThreadId,
  String? characterId,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  return ChatThread(
    id: id ?? 'thread-${DateTime.now().millisecondsSinceEpoch}',
    title: title,
    systemPrompt: systemPrompt,
    modelId: modelId,
    isPinned: isPinned,
    branchFromThreadId: branchFromThreadId,
    characterId: characterId,
    createdAt: createdAt ?? DateTime.now(),
    updatedAt: updatedAt ?? DateTime.now(),
  );
}

// --- ChatMessage factories ---

ChatMessage buildMessage({
  String? id,
  String threadId = 'thread-1',
  String? parentId,
  MessageRole role = MessageRole.user,
  String content = 'Hello',
  MessageStatus status = MessageStatus.completed,
  double? tokensPerSecond,
  int? totalTokens,
  int? timeToFirstTokenMs,
  double? generationTimeSec,
  String? errorMessage,
  int variantIndex = 0,
  int totalVariants = 1,
  List<String> siblingIds = const [],
  DateTime? createdAt,
  bool isEdited = false,
  DateTime? updatedAt,
  int? ragMemoryCount,
  String reasoningContent = '',
}) {
  return ChatMessage(
    id: id ?? 'msg-${DateTime.now().millisecondsSinceEpoch}',
    threadId: threadId,
    parentId: parentId,
    role: role,
    content: content,
    status: status,
    tokensPerSecond: tokensPerSecond,
    totalTokens: totalTokens,
    timeToFirstTokenMs: timeToFirstTokenMs,
    generationTimeSec: generationTimeSec,
    errorMessage: errorMessage,
    variantIndex: variantIndex,
    totalVariants: totalVariants,
    siblingIds: siblingIds,
    createdAt: createdAt ?? DateTime.now(),
    isEdited: isEdited,
    updatedAt: updatedAt,
    ragMemoryCount: ragMemoryCount,
    reasoningContent: reasoningContent,
  );
}

// --- CharacterProfile factories ---

CharacterProfile buildCharacter({
  String? id,
  String name = 'Test Character',
  String personality = 'Friendly and helpful',
  String firstMessage = 'Hello there!',
  String? setting,
  String? userPersona,
  bool isFavorite = false,
  String? systemPrompt,
  String? postHistoryInstructions,
  List<String>? alternateGreetings,
}) {
  return CharacterProfile(
    id: id ?? 'char-${DateTime.now().millisecondsSinceEpoch}',
    name: name,
    personality: personality,
    firstMessage: firstMessage,
    setting: setting,
    userPersona: userPersona,
    isFavorite: isFavorite,
    systemPrompt: systemPrompt,
    postHistoryInstructions: postHistoryInstructions,
    alternateGreetings: alternateGreetings ?? [],
  );
}

// --- PersonaTemplate factories ---

PersonaTemplate buildPersonaTemplate({
  String? id,
  String name = 'Test Template',
  String description = 'A test persona description',
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  return PersonaTemplate(
    id: id ?? 'tpl-${DateTime.now().millisecondsSinceEpoch}',
    name: name,
    description: description,
    createdAt: createdAt ?? DateTime.now(),
    updatedAt: updatedAt ?? DateTime.now(),
  );
}

// --- ServerConfig factories ---

ServerConfig buildServerConfig({
  String name = 'Test Server',
  String? selectedModel,
  GenerationParams? defaultParams,
  ServerHealthStatus healthStatus = ServerHealthStatus.offline,
  int latencyMs = -1,
  String? systemPrompt,
  bool confirmDeleteMessage = true,
  bool reasoning = false,
  String? legacyBaseUrl,
  String? legacyApiKey,
}) {
  return ServerConfig(
    name: name,
    selectedModel: selectedModel,
    defaultParams: defaultParams ?? const GenerationParams(),
    healthStatus: healthStatus,
    latencyMs: latencyMs,
    systemPrompt: systemPrompt ?? 'You are a helpful AI.',
    confirmDeleteMessage: confirmDeleteMessage,
    reasoning: reasoning,
    legacyBaseUrl: legacyBaseUrl,
    legacyApiKey: legacyApiKey,
  );
}

// --- ServerProfile factories ---

ServerProfile buildServerProfile({
  String? id,
  String name = 'Test Profile',
  String? baseUrl,
  String? apiKey,
  ApiProtocol protocol = ApiProtocol.openAi,
}) {
  return ServerProfile(
    id: id ?? 'profile-${DateTime.now().millisecondsSinceEpoch}',
    name: name,
    baseUrl: baseUrl ?? 'http://localhost:8080',
    apiKey: apiKey,
    protocol: protocol,
  );
}
