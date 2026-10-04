# Minuta: anotações com IA (Android e iOS)

Aplicativo de anotações com IA, no visual do iPhone (Cupertino), feito em Flutter.
Ele grava reuniões, aulas e conversas, transcreve enquanto você grava, gera notas
organizadas e responde perguntas sobre o que foi dito, **com a API que você escolher**.

## Recursos

- **Gravação** com timer, ondas de áudio ao vivo, pausar/retomar e parar.
- **Transcrição ao vivo**: o áudio é enviado em blocos de ~25s para um endpoint
  Whisper (`/audio/transcriptions`) e o texto aparece durante a gravação.
- **Perguntar durante a conversa** (botão ✦): um chat que conhece a transcrição até aquele momento.
- **Notas automáticas** ao parar: título, resumo, itens de ação, pontos principais,
  decisões e perguntas em aberto, em Markdown.
- Cada nota tem as abas **Notas | Transcrição | Perguntar**, além de renomear,
  copiar, gerar de novo, transcrever o áudio de novo e apagar.
- Busca, notas agrupadas por data (Hoje, Ontem…), tema claro e escuro automáticos.

## Conecte a API que você quiser

Em **Ajustes**:

| Uso | Provedores prontos |
|---|---|
| Notas e perguntas (chat) | Anthropic (Claude), OpenAI, Google Gemini, Groq, OpenRouter, DeepSeek, Ollama/LM Studio (local) e **qualquer API compatível com OpenAI** |
| Transcrição (voz → texto) | Groq Whisper (tem plano grátis), OpenAI Whisper, ou qualquer endpoint compatível |

- **Listar** busca os modelos disponíveis direto do provedor (`GET /models`).
- **Testar conexão** faz uma chamada real para conferir chave, URL e modelo.
- As chaves ficam no armazenamento seguro do aparelho (Android Keystore / iOS
  Keychain) e só são enviadas para as URLs configuradas.
- Para Ollama/LM Studio, use o IP do computador na mesma rede Wi-Fi
  (ex.: `http://192.168.0.10:11434/v1`).

## Instalar

APK pronto para Android (arm64): `release/Minuta-arm64.apk`.

Para compilar:

```bash
cd ai-notetaker
flutter pub get
flutter test
flutter build apk --release --split-per-abi   # Android
flutter build ipa                             # iOS (requer macOS + Xcode)
```

## Limitações

- A gravação acontece com o app aberto: a tela fica ligada enquanto você grava,
  mas não há gravação em segundo plano com a tela bloqueada.
- Entre um bloco de áudio e o próximo há uma pausa de fração de segundo, então
  uma sílaba pode se perder.
- A transcrição não separa quem está falando.

## Estrutura

- `lib/recorder.dart`: gravação em blocos, fila de transcrição e geração das notas.
- `lib/ai_client.dart`: cliente HTTP para APIs compatíveis com OpenAI e para a
  Messages API da Anthropic (streaming), Whisper, listagem de modelos e prompts.
- `lib/ai_settings.dart`: provedores e ajustes salvos com segurança.
- `lib/screens/`: telas Início, Gravação, Nota e Ajustes.
- `lib/widgets/`: chat "Perguntar" e ondas de áudio.
