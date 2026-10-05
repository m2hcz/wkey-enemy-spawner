# Minuta: copiloto de IA em tempo real (Android)

Um assistente no estilo do Cluely para o celular, feito em Flutter com visual de
iPhone (Cupertino). Ele **flutua sobre qualquer app**, ouve a conversa, vê a tela
quando você pede e diz o que responder. No fim, gera as notas. Funciona **com a
API que você escolher**.

## Assistente flutuante (Android)

Toque em **Iniciar assistente**. O app pede três permissões: microfone, sobrepor
a outros apps e, se você quiser, ver a tela. Depois ele vai para o segundo plano
e deixa um painel flutuante com:

- **O que dizer?**: 2 ou 3 frases prontas para falar, com base no fim da conversa.
- **Analisar tela**: tira uma captura da tela (sem o painel) e responde sobre
  ela, por exemplo uma pergunta, uma mensagem ou um formulário. Precisa de um
  modelo com visão.
- **Resumo** e **Perguntas**: o resumo até agora e perguntas para fazer.
- Campo para **perguntar qualquer coisa**.
- **⚡ Auto**: a cada trecho transcrito, uma dica curta, só quando há algo útil.
- **Minimizar** o painel para um balão arrastável. **Pausar** e **encerrar**
  (⏹): ao encerrar, gera as notas e abre o app na nota.

O painel roda em um serviço em primeiro plano, então continua ouvindo enquanto
você usa outros apps.

**Limitação do Android:** com o painel, o app ouve pelo microfone do celular
(reunião presencial, aula, ligação no viva-voz de outro aparelho). Se a chamada
(Meet, Zoom, WhatsApp) estiver **no mesmo celular**, o Android não deixa outros
apps ouvirem o áudio da chamada.

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

- `lib/overlay/assistant_overlay.dart`: painel flutuante (motor Flutter próprio).
- `lib/assistant_launcher.dart`: pede as permissões e abre o painel.
- `packages/minuta_native/`: plugin Android próprio (captura de tela com
  MediaProjection, serviço em primeiro plano, mensagens entre o app e o painel).
- `lib/recorder.dart`: gravação em blocos, fila de transcrição e geração das notas.
- `lib/ai_client.dart`: cliente HTTP para APIs compatíveis com OpenAI e para a
  Messages API da Anthropic (streaming), Whisper, listagem de modelos e prompts.
- `lib/ai_settings.dart`: provedores e ajustes salvos com segurança.
- `lib/screens/`: telas Início, Gravação, Nota e Ajustes.
- `lib/widgets/`: chat "Perguntar" e ondas de áudio.
