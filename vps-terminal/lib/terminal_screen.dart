import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import 'config.dart';
import 'settings_screen.dart';
import 'special_keys.dart';

enum _Status { connecting, connected, disconnected }

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key, required this.config});

  final VpsConfig config;

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen>
    with WidgetsBindingObserver {
  late final _modifiers = StickyModifiers(defaultInputHandler);
  late final _terminal = Terminal(maxLines: 10000, inputHandler: _modifiers);
  final _terminalController = TerminalController();
  final _focusNode = FocusNode();

  late double _fontSize = widget.config.fontSize;
  SSHClient? _client;
  SSHSession? _session;
  _Status _status = _Status.disconnected;
  String _title = '';
  String? _lastError;
  int _attempt = 0;
  int _generation = 0;
  Timer? _retryTimer;
  bool _disposed = false;

  VpsConfig get _cfg => widget.config;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _title = '${_cfg.username}@${_cfg.host}';

    _terminal.onOutput = (data) {
      final out = _modifiers.transformOutput(data);
      _session?.write(utf8.encode(out));
    };
    _terminal.onResize = (w, h, pw, ph) {
      _session?.resizeTerminal(w, h, pw, ph);
    };
    _terminal.onTitleChange = (t) {
      if (t.isNotEmpty) setState(() => _title = t);
    };

    if (_cfg.autoConnect) {
      _connect();
    } else {
      _terminal.write('Toque em "Conectar" para abrir a shell.\r\n');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Mobile OSes kill sockets in background; reconnect when we come back.
    if (state == AppLifecycleState.resumed &&
        _status == _Status.disconnected &&
        _cfg.autoConnect) {
      _connect();
    }
  }

  Future<void> _connect() async {
    _retryTimer?.cancel();
    if (_status == _Status.connecting) return;
    final gen = ++_generation;
    setState(() {
      _status = _Status.connecting;
      _lastError = null;
    });
    _terminal.write(
        '\x1b[90mConectando em ${_cfg.username}@${_cfg.host}:${_cfg.port}...\x1b[0m\r\n');

    try {
      final socket = await SSHSocket.connect(
        _cfg.host,
        _cfg.port,
        timeout: const Duration(seconds: 15),
      );

      final client = SSHClient(
        socket,
        username: _cfg.username,
        identities: _cfg.usesKey
            ? SSHKeyPair.fromPem(
                _cfg.privateKey,
                _cfg.passphrase.isEmpty ? null : _cfg.passphrase,
              )
            : null,
        onPasswordRequest: _cfg.usesKey ? null : () => _cfg.password,
        onUserInfoRequest: _cfg.usesKey
            ? null
            : (req) => req.prompts.map((_) => _cfg.password).toList(),
        onVerifyHostKey: _verifyHostKey,
        keepAliveInterval: const Duration(seconds: 15),
      );

      await client.authenticated;

      final session = await client.shell(
        pty: SSHPtyConfig(
          type: 'xterm-256color',
          width: max(_terminal.viewWidth, 20),
          height: max(_terminal.viewHeight, 5),
        ),
      );

      if (gen != _generation || _disposed) {
        client.close();
        return;
      }

      _client = client;
      _session = session;
      _attempt = 0;

      session.stdout
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(_terminal.write);
      session.stderr
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(_terminal.write);

      setState(() => _status = _Status.connected);
      _focusNode.requestFocus();

      session.done.whenComplete(() => _onDisconnected(gen, null));
      client.done.then(
        (_) => _onDisconnected(gen, null),
        onError: (Object e) => _onDisconnected(gen, e),
      );
    } catch (e) {
      _onDisconnected(gen, e);
    }
  }

  void _onDisconnected(int gen, Object? error) {
    if (gen != _generation || _disposed) return;
    if (_status == _Status.disconnected) return;
    _generation++;
    _session = null;
    _client?.close();
    _client = null;

    final msg = error == null ? 'Sessão encerrada' : _describe(error);
    _terminal.write('\r\n\x1b[31m[$msg]\x1b[0m\r\n');
    setState(() {
      _status = _Status.disconnected;
      _lastError = msg;
    });

    final authFailure = error is SSHAuthFailError || error is _HostKeyRejected;
    if (_cfg.autoConnect && !authFailure) {
      _attempt++;
      final delay = Duration(seconds: min(30, 1 << min(_attempt, 5)));
      _terminal.write(
          '\x1b[90mReconectando em ${delay.inSeconds}s...\x1b[0m\r\n');
      _retryTimer = Timer(delay, _connect);
    }
  }

  String _describe(Object e) {
    if (e is SSHAuthFailError) {
      return 'Falha de autenticação: verifique usuário/senha/chave';
    }
    if (e is _HostKeyRejected) return e.toString();
    if (e is SocketException || e is TimeoutException) {
      return 'Sem conexão com ${_cfg.host}:${_cfg.port}';
    }
    return e.toString();
  }

  /// Trust-on-first-use host key check, like OpenSSH's known_hosts.
  Future<bool> _verifyHostKey(String type, Uint8List fingerprint) async {
    final fp = 'SHA256:${base64.encode(fingerprint).replaceAll('=', '')}';
    final known = await ConfigStore.knownHostKey(_cfg.host, _cfg.port);
    if (known == null) {
      await ConfigStore.trustHostKey(_cfg.host, _cfg.port, fp);
      _terminal.write(
          '\x1b[90mChave do servidor salva ($type $fp)\x1b[0m\r\n');
      return true;
    }
    if (known == fp) return true;

    if (!mounted) return false;
    final accept = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠ Chave do servidor mudou'),
        content: Text(
          'A identidade de ${_cfg.host} é diferente da salva.\n\n'
          'Salva:\n$known\n\nRecebida:\n$fp\n\n'
          'Isso acontece se a VPS foi reinstalada — ou pode ser um ataque '
          '(man-in-the-middle). Só aceite se você tiver certeza.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Recusar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confiar na nova chave'),
          ),
        ],
      ),
    );
    if (accept == true) {
      await ConfigStore.trustHostKey(_cfg.host, _cfg.port, fp);
      return true;
    }
    throw _HostKeyRejected();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) _terminal.paste(text);
  }

  void _copySelection() {
    final selection = _terminalController.selection;
    if (selection == null) return;
    final text = _terminal.buffer.getText(selection);
    Clipboard.setData(ClipboardData(text: text));
    _terminalController.clearSelection();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copiado'), duration: Duration(seconds: 1)),
    );
  }

  void _setFontSize(double size) {
    setState(() => _fontSize = size.clamp(8, 24));
    ConfigStore.save(VpsConfig(
      host: _cfg.host,
      port: _cfg.port,
      username: _cfg.username,
      password: _cfg.password,
      privateKey: _cfg.privateKey,
      passphrase: _cfg.passphrase,
      autoConnect: _cfg.autoConnect,
      fontSize: _fontSize,
    ));
  }

  void _disconnect() {
    _retryTimer?.cancel();
    _generation++;
    _session?.close();
    _client?.close();
    _session = null;
    _client = null;
    _terminal.write('\r\n\x1b[90m[Desconectado]\x1b[0m\r\n');
    setState(() => _status = _Status.disconnected);
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SettingsScreen(initial: _cfg),
    ));
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    _session?.close();
    _client?.close();
    _focusNode.dispose();
    _terminalController.dispose();
    _modifiers.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (_status) {
      _Status.connected => Colors.greenAccent,
      _Status.connecting => Colors.amber,
      _Status.disconnected => Colors.redAccent,
    };

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        toolbarHeight: 44,
        titleSpacing: 12,
        title: Row(
          children: [
            Icon(Icons.circle, size: 10, color: statusColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
        actions: [
          if (_status == _Status.disconnected)
            IconButton(
              tooltip: 'Conectar',
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _attempt = 0;
                _connect();
              },
            ),
          IconButton(
            tooltip: 'Copiar seleção',
            icon: const Icon(Icons.copy, size: 20),
            onPressed: _copySelection,
          ),
          IconButton(
            tooltip: 'Teclado',
            icon: const Icon(Icons.keyboard, size: 20),
            onPressed: () {
              if (_focusNode.hasFocus) {
                _focusNode.unfocus();
              } else {
                _focusNode.requestFocus();
              }
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'font+':
                  _setFontSize(_fontSize + 1);
                case 'font-':
                  _setFontSize(_fontSize - 1);
                case 'disconnect':
                  _disconnect();
                case 'settings':
                  _openSettings();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'font+', child: Text('Aumentar fonte')),
              const PopupMenuItem(value: 'font-', child: Text('Diminuir fonte')),
              if (_status != _Status.disconnected)
                const PopupMenuItem(
                    value: 'disconnect', child: Text('Desconectar')),
              const PopupMenuItem(
                  value: 'settings', child: Text('Configurações da VPS')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_status == _Status.disconnected && _lastError != null)
              MaterialBanner(
                backgroundColor: const Color(0xFF3A1E1E),
                content: Text(_lastError!,
                    style: const TextStyle(color: Colors.white)),
                actions: [
                  TextButton(
                    onPressed: () {
                      _attempt = 0;
                      _connect();
                    },
                    child: const Text('Reconectar'),
                  ),
                ],
              ),
            Expanded(
              child: TerminalView(
                _terminal,
                controller: _terminalController,
                focusNode: _focusNode,
                autofocus: true,
                backgroundOpacity: 1,
                padding: const EdgeInsets.all(4),
                textStyle: TerminalStyle(fontSize: _fontSize),
                keyboardType: TextInputType.visiblePassword,
                deleteDetection: true,
                onSecondaryTapDown: (_, _) => _paste(),
              ),
            ),
            SpecialKeysBar(
              terminal: _terminal,
              modifiers: _modifiers,
              onPaste: _paste,
            ),
          ],
        ),
      ),
    );
  }
}

class _HostKeyRejected implements Exception {
  @override
  String toString() => 'Chave do servidor recusada';
}
