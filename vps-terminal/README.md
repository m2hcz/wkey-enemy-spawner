# VPS Terminal

App mobile (Android e iOS, Flutter) que conecta automaticamente na sua VPS via SSH
e abre a shell numa interface de terminal padrão (xterm-256color), com barra de
teclas especiais.

## Recursos

- **Conexão automática** ao abrir o app e **reconexão automática** se a conexão
  cair ou o app voltar do segundo plano (backoff de 2s até 30s).
- Autenticação por **senha** ou **chave SSH** (OpenSSH/PEM, com passphrase opcional).
- Credenciais salvas no armazenamento seguro do aparelho (Android Keystore / iOS Keychain).
- Verificação da chave do servidor estilo `known_hosts` (confia na primeira vez,
  alerta se mudar).
- Terminal completo: cores, `vim`, `htop`, `nano`, `tmux`, redimensionamento, 10 000 linhas de histórico.
- **Barra de teclas especiais** acima do teclado:
  - Linha 1: `ESC` `TAB` `CTRL` `ALT` `SHIFT` `←` `↓` `↑` `→` `HOME` `END` `PGUP` `PGDN` `DEL` `INS`
  - Linha 2: atalhos `^C` `^D` `^Z` `^L` `^R` e símbolos `| / - ~ _ : ; & * $ < > { } [ ]` etc.
  - Botão `Fn` alterna para `F1`–`F12`; botão de colar.
  - `CTRL`/`ALT`/`SHIFT`: 1 toque = vale para a próxima tecla (verde);
    2 toques = travado (laranja); 3º toque desliga.
  - Setas e `DEL` repetem ao segurar.
- Copiar seleção, colar, ajustar tamanho da fonte.

## Instalar

### Android (APK pronto)

Cada push em `vps-terminal/` roda o workflow **VPS Terminal APK** no GitHub Actions.
Abra a execução em *Actions*, baixe o artefato `vps-terminal-apk`, extraia o
`app-release.apk` e instale no celular (permita "fontes desconhecidas").

### Compilar localmente

Requer [Flutter](https://docs.flutter.dev/get-started/install) (stable).

```bash
cd vps-terminal
flutter pub get
flutter run                 # com o celular conectado via USB
flutter build apk --release # APK em build/app/outputs/flutter-apk/
flutter build ipa           # iOS (requer macOS + Xcode + conta Apple)
```

## Uso

1. Na primeira abertura, informe host/IP, porta, usuário e senha ou chave privada.
2. Toque em **Salvar e conectar**. A partir daí o app abre direto na shell.
3. Para trocar de VPS ou credenciais: menu `⋮` → **Configurações da VPS**.

## Estrutura

- `lib/main.dart` — decide entre tela de configuração e terminal (auto-connect).
- `lib/terminal_screen.dart` — sessão SSH, PTY, reconexão, verificação de host key.
- `lib/special_keys.dart` — barra de teclas especiais e modificadores CTRL/ALT/SHIFT.
- `lib/settings_screen.dart` — formulário de conexão.
- `lib/config.dart` — persistência segura das configurações.
