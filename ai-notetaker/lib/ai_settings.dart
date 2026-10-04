import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wire format a chat provider speaks.
enum ApiFormat { openai, anthropic }

class ChatPreset {
  const ChatPreset(this.id, this.name, this.baseUrl, this.model, this.format,
      {this.needsKey = true});

  final String id;
  final String name;
  final String baseUrl;
  final String model;
  final ApiFormat format;
  final bool needsKey;
}

/// Model names are only suggestions: the settings screen can list the
/// provider's live models, and any model name can be typed by hand.
const chatPresets = <ChatPreset>[
  ChatPreset('anthropic', 'Anthropic (Claude)', 'https://api.anthropic.com/v1',
      'claude-opus-5-5', ApiFormat.anthropic),
  ChatPreset('openai', 'OpenAI', 'https://api.openai.com/v1', 'gpt-4o-mini',
      ApiFormat.openai),
  ChatPreset('gemini', 'Google Gemini',
      'https://generativelanguage.googleapis.com/v1beta/openai', 'gemini-2.5-flash',
      ApiFormat.openai),
  ChatPreset('groq', 'Groq', 'https://api.groq.com/openai/v1',
      'llama-3.3-70b-versatile', ApiFormat.openai),
  ChatPreset('openrouter', 'OpenRouter', 'https://openrouter.ai/api/v1',
      'openrouter/auto', ApiFormat.openai),
  ChatPreset('deepseek', 'DeepSeek', 'https://api.deepseek.com/v1', 'deepseek-chat',
      ApiFormat.openai),
  ChatPreset('ollama', 'Ollama / LM Studio (local)', 'http://192.168.0.10:11434/v1',
      'llama3.1', ApiFormat.openai,
      needsKey: false),
  ChatPreset('custom', 'Personalizado (compatível OpenAI)', 'https://', '',
      ApiFormat.openai,
      needsKey: false),
];

class SttPreset {
  const SttPreset(this.id, this.name, this.baseUrl, this.model);

  final String id;
  final String name;
  final String baseUrl;
  final String model;
}

/// Speech-to-text providers that implement OpenAI's /audio/transcriptions.
const sttPresets = <SttPreset>[
  SttPreset('groq', 'Groq Whisper (rápido, tem plano grátis)',
      'https://api.groq.com/openai/v1', 'whisper-large-v3-turbo'),
  SttPreset('openai', 'OpenAI Whisper', 'https://api.openai.com/v1', 'whisper-1'),
  SttPreset('custom', 'Personalizado (compatível OpenAI)', 'https://', 'whisper-1'),
];

ChatPreset chatPresetById(String id) =>
    chatPresets.firstWhere((p) => p.id == id, orElse: () => chatPresets.last);

SttPreset sttPresetById(String id) =>
    sttPresets.firstWhere((p) => p.id == id, orElse: () => sttPresets.last);

class AiSettings {
  AiSettings({
    this.chatProvider = 'anthropic',
    String? chatBaseUrl,
    this.chatApiKey = '',
    String? chatModel,
    this.sttProvider = 'groq',
    String? sttBaseUrl,
    this.sttApiKey = '',
    String? sttModel,
    this.sttUseChatKey = false,
    this.language = 'pt',
    this.extraInstructions = '',
  })  : chatBaseUrl = chatBaseUrl ?? chatPresetById(chatProvider).baseUrl,
        chatModel = chatModel ?? chatPresetById(chatProvider).model,
        sttBaseUrl = sttBaseUrl ?? sttPresetById(sttProvider).baseUrl,
        sttModel = sttModel ?? sttPresetById(sttProvider).model;

  String chatProvider;
  String chatBaseUrl;
  String chatApiKey;
  String chatModel;
  String sttProvider;
  String sttBaseUrl;
  String sttApiKey;
  String sttModel;

  /// Reuse the chat key for transcription (when both are the same vendor).
  bool sttUseChatKey;

  /// ISO-639-1 code for transcription and notes, or '' for auto.
  String language;
  String extraInstructions;

  ApiFormat get chatFormat => chatPresetById(chatProvider).format;
  String get effectiveSttKey => sttUseChatKey ? chatApiKey : sttApiKey;

  bool get chatReady =>
      chatBaseUrl.startsWith('http') &&
      chatModel.isNotEmpty &&
      (chatApiKey.isNotEmpty || !chatPresetById(chatProvider).needsKey);

  bool get sttReady =>
      sttBaseUrl.startsWith('http') && sttModel.isNotEmpty && effectiveSttKey.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'chatProvider': chatProvider,
        'chatBaseUrl': chatBaseUrl,
        'chatApiKey': chatApiKey,
        'chatModel': chatModel,
        'sttProvider': sttProvider,
        'sttBaseUrl': sttBaseUrl,
        'sttApiKey': sttApiKey,
        'sttModel': sttModel,
        'sttUseChatKey': sttUseChatKey,
        'language': language,
        'extraInstructions': extraInstructions,
      };

  factory AiSettings.fromJson(Map<String, dynamic> j) => AiSettings(
        chatProvider: j['chatProvider'] as String? ?? 'anthropic',
        chatBaseUrl: j['chatBaseUrl'] as String?,
        chatApiKey: j['chatApiKey'] as String? ?? '',
        chatModel: j['chatModel'] as String?,
        sttProvider: j['sttProvider'] as String? ?? 'groq',
        sttBaseUrl: j['sttBaseUrl'] as String?,
        sttApiKey: j['sttApiKey'] as String? ?? '',
        sttModel: j['sttModel'] as String?,
        sttUseChatKey: j['sttUseChatKey'] as bool? ?? false,
        language: j['language'] as String? ?? 'pt',
        extraInstructions: j['extraInstructions'] as String? ?? '',
      );

  AiSettings copy() => AiSettings.fromJson(toJson());
}

/// API keys live in the Android Keystore / iOS Keychain.
class SettingsStore extends ValueNotifier<AiSettings> {
  SettingsStore._() : super(AiSettings());

  static final instance = SettingsStore._();
  static const _storage = FlutterSecureStorage();
  static const _key = 'ai_settings';

  Future<void> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw != null) {
        value = AiSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('Failed to read settings: $e');
    }
  }

  Future<void> save(AiSettings settings) async {
    value = settings;
    await _storage.write(key: _key, value: jsonEncode(settings.toJson()));
  }
}
