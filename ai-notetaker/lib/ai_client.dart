import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'ai_settings.dart';
import 'models.dart';

class AiException implements Exception {
  AiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Anthropic models that accept the server-side refusal fallback ("default").
const _fallbackModels = {
  'claude-opus-5-5',
  'claude-opus-5',
  'claude-fable-5-1',
  'claude-sonnet-5-5',
};

/// Talks to whichever provider the user configured: any OpenAI-compatible
/// API (OpenAI, Gemini, Groq, OpenRouter, DeepSeek, Ollama, …) or Anthropic.
class AiClient {
  AiClient(this.settings, {http.Client? client}) : _http = client ?? http.Client();

  final AiSettings settings;
  final http.Client _http;

  String _url(String base, String path) =>
      '${base.trim().replaceAll(RegExp(r'/+$'), '')}$path';

  Map<String, String> _chatHeaders() {
    final key = settings.chatApiKey.trim();
    if (settings.chatFormat == ApiFormat.anthropic) {
      return {
        'content-type': 'application/json',
        'x-api-key': key,
        'anthropic-version': '2023-06-01',
        if (_fallbackModels.contains(settings.chatModel))
          'anthropic-beta': 'server-side-fallback-2026-07-01',
      };
    }
    return {
      'content-type': 'application/json',
      if (key.isNotEmpty) 'authorization': 'Bearer $key',
      if (settings.chatProvider == 'openrouter') 'X-Title': 'Minuta',
    };
  }

  /// Streams the assistant reply as text chunks.
  Stream<String> chatStream({
    required String system,
    required List<ChatMessage> messages,
  }) async* {
    if (!settings.chatReady) {
      throw AiException('Configure o provedor de IA em Ajustes.');
    }
    final anthropic = settings.chatFormat == ApiFormat.anthropic;
    final body = anthropic
        ? {
            'model': settings.chatModel,
            'max_tokens': 16000,
            'stream': true,
            'system': system,
            'messages': [
              for (final m in messages)
                {
                  'role': m.role,
                  'content': m.imageJpeg == null
                      ? m.text
                      : [
                          {
                            'type': 'image',
                            'source': {
                              'type': 'base64',
                              'media_type': 'image/jpeg',
                              'data': base64Encode(m.imageJpeg!),
                            },
                          },
                          {'type': 'text', 'text': m.text},
                        ],
                },
            ],
            if (_fallbackModels.contains(settings.chatModel)) 'fallbacks': 'default',
          }
        : {
            'model': settings.chatModel,
            'stream': true,
            'messages': [
              {'role': 'system', 'content': system},
              for (final m in messages)
                {
                  'role': m.role,
                  'content': m.imageJpeg == null
                      ? m.text
                      : [
                          {'type': 'text', 'text': m.text},
                          {
                            'type': 'image_url',
                            'image_url': {'url': 'data:image/jpeg;base64,${base64Encode(m.imageJpeg!)}'},
                          },
                        ],
                },
            ],
          };

    final req = http.Request(
      'POST',
      Uri.parse(_url(settings.chatBaseUrl, anthropic ? '/messages' : '/chat/completions')),
    )
      ..headers.addAll(_chatHeaders())
      ..body = jsonEncode(body);

    final http.StreamedResponse res;
    try {
      res = await _http.send(req).timeout(const Duration(seconds: 60));
    } on SocketException catch (e) {
      throw AiException('Sem conexão com o provedor: ${e.message}');
    } on TimeoutException {
      throw AiException('O provedor demorou demais para responder.');
    }
    if (res.statusCode >= 400) {
      throw AiException(_errorMessage(res.statusCode, await res.stream.bytesToString()));
    }

    final lines = res.stream.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data.isEmpty || data == '[DONE]') continue;
      final Map<String, dynamic> event;
      try {
        event = jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      if (anthropic) {
        switch (event['type']) {
          case 'content_block_delta':
            final delta = event['delta'] as Map<String, dynamic>?;
            if (delta?['type'] == 'text_delta') yield delta!['text'] as String;
          case 'message_delta':
            final delta = event['delta'] as Map<String, dynamic>?;
            if (delta?['stop_reason'] == 'refusal') {
              throw AiException('O modelo recusou responder este pedido.');
            }
          case 'error':
            final err = event['error'] as Map<String, dynamic>?;
            throw AiException(err?['message'] as String? ?? 'Erro do provedor');
        }
      } else {
        if (event['error'] != null) {
          final err = event['error'];
          throw AiException(err is Map ? '${err['message']}' : '$err');
        }
        final choices = event['choices'] as List?;
        if (choices == null || choices.isEmpty) continue;
        final delta = (choices.first as Map<String, dynamic>)['delta'] as Map<String, dynamic>?;
        final content = delta?['content'];
        if (content is String && content.isNotEmpty) yield content;
      }
    }
  }

  Future<String> chat({required String system, required List<ChatMessage> messages}) async {
    final buffer = StringBuffer();
    await for (final chunk in chatStream(system: system, messages: messages)) {
      buffer.write(chunk);
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) throw AiException('O provedor devolveu uma resposta vazia.');
    return text;
  }

  /// Lists model ids from GET /models (OpenAI-compatible and Anthropic).
  Future<List<String>> listModels() async {
    final res = await _http
        .get(Uri.parse(_url(settings.chatBaseUrl, '/models?limit=100')), headers: _chatHeaders())
        .timeout(const Duration(seconds: 20));
    if (res.statusCode >= 400) throw AiException(_errorMessage(res.statusCode, res.body));
    final json = jsonDecode(res.body);
    final list = (json is Map ? json['data'] ?? json['models'] : json) as List? ?? [];
    final ids = list
        .map((e) => e is Map ? (e['id'] ?? e['name'])?.toString() : e.toString())
        .whereType<String>()
        .map((id) => id.replaceFirst('models/', ''))
        .toList()
      ..sort();
    return ids;
  }

  /// Transcribes one audio file with an OpenAI-compatible Whisper endpoint.
  Future<String> transcribe(File audio) async {
    if (!settings.sttReady) {
      throw AiException('Configure a transcrição em Ajustes.');
    }
    final req = http.MultipartRequest(
      'POST',
      Uri.parse(_url(settings.sttBaseUrl, '/audio/transcriptions')),
    )
      ..headers['authorization'] = 'Bearer ${settings.effectiveSttKey.trim()}'
      ..fields['model'] = settings.sttModel
      ..fields['response_format'] = 'json'
      ..files.add(await http.MultipartFile.fromPath('file', audio.path,
          filename: audio.uri.pathSegments.last));
    if (settings.language.isNotEmpty) req.fields['language'] = settings.language;

    final http.Response res;
    try {
      res = await http.Response.fromStream(
          await _http.send(req).timeout(const Duration(seconds: 120)));
    } on SocketException catch (e) {
      throw AiException('Sem conexão com a transcrição: ${e.message}');
    } on TimeoutException {
      throw AiException('A transcrição demorou demais.');
    }
    if (res.statusCode >= 400) throw AiException(_errorMessage(res.statusCode, res.body));
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return (json['text'] as String? ?? '').trim();
  }

  String _errorMessage(int status, String body) {
    String detail = body;
    try {
      final j = jsonDecode(body);
      if (j is Map) {
        final err = j['error'];
        detail = err is Map ? '${err['message'] ?? err}' : '${err ?? j['message'] ?? body}';
      } else if (j is List && j.isNotEmpty && j.first is Map) {
        detail = '${(j.first as Map)['error']?['message'] ?? body}';
      }
    } catch (_) {}
    if (detail.length > 300) detail = '${detail.substring(0, 300)}…';
    final hint = switch (status) {
      401 || 403 => 'Chave de API inválida ou sem permissão',
      404 => 'URL ou modelo não encontrado',
      429 => 'Limite de uso atingido',
      _ => 'Erro $status',
    };
    return '$hint: $detail';
  }

  void close() => _http.close();
}

/// Prompts used by the app.
class Prompts {
  static String _lang(AiSettings s) => switch (s.language) {
        'pt' => 'português do Brasil',
        'en' => 'English',
        'es' => 'español',
        '' => 'the same language as the transcript',
        final other => 'the language with ISO code "$other"',
      };

  static String notesSystem(AiSettings s) => '''
You are an expert meeting and lecture note-taker. You receive a raw speech-to-text transcript (it can contain recognition errors, filler words and no speaker labels) and turn it into clear, well-organized notes.

Write everything in ${_lang(s)}.

Output format (Markdown):
- The very first line must be: TITLE: <a short, specific title, at most 8 words>
- Then a "## " section with a 2-4 sentence summary.
- Then "## " sections for action items (as "- [ ] " checkboxes with owner and deadline when they were mentioned), key points, decisions, and open questions. Leave out any section that has no content instead of writing "none".
- Use concise bullet points. Keep names, numbers, dates and technical terms exactly as said. Silently fix obvious transcription errors.
- Never invent facts that are not in the transcript.
${s.extraInstructions.trim().isEmpty ? '' : '\nAdditional instructions from the user:\n${s.extraInstructions.trim()}'}''';

  static String notesUser(Note note) => '''
Recording date: ${formatDate(note.createdAt)}
Duration: ${formatDuration(note.durationSec)}

<transcript>
${note.transcriptWithTimestamps}
</transcript>''';

  static String askSystem(AiSettings s, Note note, {required bool live}) => '''
You are an assistant helping the user with a ${live ? 'meeting or conversation that is happening right now' : 'recorded meeting or conversation'}. Answer the user's questions using the transcript${note.notes.isNotEmpty ? ' and notes' : ''} below. Be direct and concise — the user is reading on a phone${live ? ' while the conversation is still going' : ''}. When the transcript does not contain the answer, say so briefly and then help with your general knowledge, making clear which part comes from the transcript and which does not. Answer in ${_lang(s)} unless the user writes in another language.

<transcript>
${note.transcriptWithTimestamps.isEmpty ? '(no speech transcribed yet)' : note.transcriptWithTimestamps}
</transcript>
${note.notes.isEmpty ? '' : '\n<notes>\n${note.notes}\n</notes>'}''';

  static String assistantSystem(AiSettings s, Note note) => '''
You are a real-time AI assistant in a floating window on the user's phone, helping them during a live conversation (meeting, call, interview, class, sales or negotiation). You get the transcript captured by the phone's microphone so far (no speaker labels, may contain recognition errors) and sometimes a screenshot of the user's screen.

The user glances at your answer while the conversation keeps going, so:
- Lead with the answer. No preamble, no restating the question.
- Keep it short: at most about 80 words, bullets when helpful, unless the user asks for more.
- When you suggest what to say, write it as lines the user can say word for word.
- Do not invent facts that are not in the transcript or the screenshot; when you add general knowledge, keep it clearly separate.

Answer in ${_lang(s)} unless the user writes in another language.
${s.extraInstructions.trim().isEmpty ? '' : '\nAdditional instructions from the user:\n${s.extraInstructions.trim()}\n'}
<transcript>
${note.transcriptWithTimestamps.isEmpty ? '(nothing transcribed yet)' : note.transcriptWithTimestamps}
</transcript>''';

  static const whatToSay =
      'What should I say next? Give 2-3 short options I can say word for word, based on the latest part of the conversation.';
  static const analyzeScreen =
      'Look at my screen and help me with what is on it. If there is a question, problem, message or form to answer, give the answer directly. Relate it to the conversation when relevant.';
  static const summarySoFar =
      'Summarize the conversation so far in 3-5 bullets, then list decisions and action items, if any.';
  static const questionsToAsk = 'Suggest 3 smart, specific questions I could ask right now.';
  static const autoInsight =
      'Give one short, useful insight, fact-check or suggestion about the latest part of the conversation, in at most 2 lines. If there is nothing genuinely useful to add, reply with exactly: -';

  /// Splits the "TITLE: ..." first line off the generated notes.
  static (String?, String) splitTitle(String output) {
    final lines = output.trim().split('\n');
    if (lines.isNotEmpty) {
      final m = RegExp(r'^\s*\**\s*(TITLE|TÍTULO|TITULO)\s*:\s*\**\s*(.+?)\**\s*$', caseSensitive: false)
          .firstMatch(lines.first);
      if (m != null) {
        return (m.group(2)!.replaceAll(RegExp(r'^#+\s*'), '').trim(), lines.skip(1).join('\n').trim());
      }
    }
    return (null, output.trim());
  }
}
