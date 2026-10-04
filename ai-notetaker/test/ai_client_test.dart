import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minuta/ai_client.dart';
import 'package:minuta/ai_settings.dart';
import 'package:minuta/models.dart';

http.StreamedResponse sse(List<String> lines, {int status = 200}) =>
    http.StreamedResponse(Stream.value(utf8.encode(lines.join('\n'))), status);

void main() {
  final msgs = [ChatMessage(role: 'user', text: 'oi')];

  test('OpenAI-compatible streaming', () async {
    late http.BaseRequest seen;
    final client = MockClient.streaming((req, _) async {
      seen = req;
      return sse([
        'data: {"choices":[{"delta":{"role":"assistant"}}]}',
        'data: {"choices":[{"delta":{"content":"Olá"}}]}',
        '',
        'data: {"choices":[{"delta":{"content":", mundo"}}]}',
        'data: [DONE]',
      ]);
    });
    final s = AiSettings(chatProvider: 'groq', chatApiKey: 'k');
    final out = await AiClient(s, client: client).chat(system: 'sys', messages: msgs);
    expect(out, 'Olá, mundo');
    expect(seen.url.toString(), 'https://api.groq.com/openai/v1/chat/completions');
    expect(seen.headers['authorization'], 'Bearer k');
  });

  test('Anthropic streaming with fallback header', () async {
    late http.Request seen;
    final client = MockClient.streaming((req, body) async {
      seen = req as http.Request;
      return sse([
        'event: message_start',
        'data: {"type":"message_start","message":{}}',
        'event: content_block_delta',
        'data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"x"}}',
        'data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Oi"}}',
        'data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"!"}}',
        'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}',
        'data: {"type":"message_stop"}',
      ]);
    });
    final s = AiSettings(chatProvider: 'anthropic', chatApiKey: 'sk');
    final out = await AiClient(s, client: client).chat(system: 'sys', messages: msgs);
    expect(out, 'Oi!');
    expect(seen.url.toString(), 'https://api.anthropic.com/v1/messages');
    expect(seen.headers['x-api-key'], 'sk');
    expect(seen.headers['anthropic-version'], '2023-06-01');
    expect(seen.headers['anthropic-beta'], 'server-side-fallback-2026-07-01');
    final body = jsonDecode(seen.body) as Map<String, dynamic>;
    expect(body['model'], 'claude-opus-5-5');
    expect(body['system'], 'sys');
    expect(body['fallbacks'], 'default');
    expect(body['stream'], true);
  });

  test('Anthropic refusal surfaces as error', () async {
    final client = MockClient.streaming((_, _) async => sse([
          'data: {"type":"message_delta","delta":{"stop_reason":"refusal"}}',
        ]));
    final s = AiSettings(chatProvider: 'anthropic', chatApiKey: 'sk');
    expect(AiClient(s, client: client).chat(system: 's', messages: msgs),
        throwsA(isA<AiException>()));
  });

  test('HTTP errors become readable messages', () async {
    final client = MockClient.streaming((_, _) async => http.StreamedResponse(
        Stream.value(utf8.encode('{"error":{"message":"Invalid API key"}}')), 401));
    final s = AiSettings(chatProvider: 'openai', chatApiKey: 'bad');
    await expectLater(
      AiClient(s, client: client).chat(system: 's', messages: msgs),
      throwsA(predicate((e) => '$e'.contains('Chave de API inválida') && '$e'.contains('Invalid API key'))),
    );
  });

  test('transcription multipart request', () async {
    final dir = await Directory.systemTemp.createTemp();
    final f = File('${dir.path}/seg_0000.m4a')..writeAsBytesSync(List.filled(3000, 1));
    late http.BaseRequest seen;
    final client = MockClient((req) async {
      seen = req;
      return http.Response('{"text":" bom dia a todos "}', 200);
    });
    final s = AiSettings(sttProvider: 'groq', sttApiKey: 'g', language: 'pt');
    final text = await AiClient(s, client: client).transcribe(f);
    expect(text, 'bom dia a todos');
    expect(seen.url.toString(), 'https://api.groq.com/openai/v1/audio/transcriptions');
    expect(seen.headers['authorization'], 'Bearer g');
    expect(seen.headers['content-type'], startsWith('multipart/form-data'));
  });

  test('listModels parses both formats', () async {
    final client = MockClient((_) async =>
        http.Response('{"data":[{"id":"b-model"},{"id":"a-model"}]}', 200));
    final s = AiSettings(chatProvider: 'openai', chatApiKey: 'k');
    expect(await AiClient(s, client: client).listModels(), ['a-model', 'b-model']);
  });

  test('splitTitle', () {
    expect(Prompts.splitTitle('TITLE: Reunião de produto\n## Resumo\nTexto'),
        ('Reunião de produto', '## Resumo\nTexto'));
    expect(Prompts.splitTitle('**Título:** Aula 3\nx'), ('Aula 3', 'x'));
    expect(Prompts.splitTitle('## Resumo\nTexto'), (null, '## Resumo\nTexto'));
  });

  test('settings readiness', () {
    expect(AiSettings().chatReady, false);
    expect(AiSettings(chatProvider: 'ollama').chatReady, true);
    expect(AiSettings(chatProvider: 'groq', sttProvider: 'groq', chatApiKey: 'k', sttUseChatKey: true).sttReady, true);
  });
}
