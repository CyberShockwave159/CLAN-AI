/// Shared constants used across the application.
/// Centralizes magic numbers and strings to eliminate duplication.

const Duration undoTimeoutDuration = Duration(seconds: 5);
const Duration uiThrottleInterval = Duration(milliseconds: 20);
const Duration healthPollInterval = Duration(seconds: 15);
const int autoTitleMaxLen = 32;
const int messagePreviewLen = 100;
const int reservedOutputTokensDefault = 512;
const int minContextSize = 128;
const int maxContextSize = 1000000;
const int defaultRagLimit = 100;
const int defaultRagTopK = 3;
const String defaultBaseUrl = 'http://127.0.0.1:8080';
const String defaultSystemPrompt = 'You are a helpful, brilliant, and honest AI assistant.';
const String defaultServerName = 'Local llama.cpp';
const double maxBubbleWidth = 600.0;
const double defaultBubblePadding = 16.0;
