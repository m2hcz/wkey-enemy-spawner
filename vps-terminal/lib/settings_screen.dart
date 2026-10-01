import 'package:flutter/material.dart';

import 'config.dart';
import 'terminal_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.firstRun = false, this.initial});

  final bool firstRun;
  final VpsConfig? initial;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _form = GlobalKey<FormState>();
  late final _host = TextEditingController(text: widget.initial?.host);
  late final _port =
      TextEditingController(text: '${widget.initial?.port ?? 22}');
  late final _user =
      TextEditingController(text: widget.initial?.username ?? 'root');
  late final _password = TextEditingController(text: widget.initial?.password);
  late final _key = TextEditingController(text: widget.initial?.privateKey);
  late final _passphrase =
      TextEditingController(text: widget.initial?.passphrase);
  late bool _useKey = widget.initial?.usesKey ?? false;
  late bool _autoConnect = widget.initial?.autoConnect ?? true;
  late double _fontSize = widget.initial?.fontSize ?? 13;
  bool _obscure = true;

  @override
  void dispose() {
    for (final c in [_host, _port, _user, _password, _key, _passphrase]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final config = VpsConfig(
      host: _host.text.trim(),
      port: int.parse(_port.text.trim()),
      username: _user.text.trim(),
      password: _useKey ? '' : _password.text,
      privateKey: _useKey ? _key.text.trim() : '',
      passphrase: _useKey ? _passphrase.text : '',
      autoConnect: _autoConnect,
      fontSize: _fontSize,
    );
    final old = widget.initial;
    if (old != null && (old.host != config.host || old.port != config.port)) {
      await ConfigStore.forgetHostKey(old.host, old.port);
    }
    await ConfigStore.save(config);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => TerminalScreen(config: config)),
      (_) => false,
    );
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Obrigatório' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.firstRun ? 'Configurar VPS' : 'Configurações'),
        automaticallyImplyLeading: !widget.firstRun,
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _host,
                decoration: const InputDecoration(
                  labelText: 'Host / IP da VPS',
                  hintText: '203.0.113.10 ou vps.meudominio.com',
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
                validator: _required,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _user,
                      decoration: const InputDecoration(labelText: 'Usuário'),
                      autocorrect: false,
                      validator: _required,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _port,
                      decoration: const InputDecoration(labelText: 'Porta'),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final p = int.tryParse(v?.trim() ?? '');
                        return (p == null || p < 1 || p > 65535)
                            ? 'Inválida'
                            : null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Senha'),
                    icon: Icon(Icons.password),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Chave SSH'),
                    icon: Icon(Icons.key),
                  ),
                ],
                selected: {_useKey},
                onSelectionChanged: (s) => setState(() => _useKey = s.first),
              ),
              const SizedBox(height: 12),
              if (!_useKey)
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Senha',
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: _required,
                )
              else ...[
                TextFormField(
                  controller: _key,
                  minLines: 4,
                  maxLines: 8,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  decoration: const InputDecoration(
                    labelText: 'Chave privada (PEM / OpenSSH)',
                    hintText: '-----BEGIN OPENSSH PRIVATE KEY-----\n...',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || !v.contains('PRIVATE KEY'))
                          ? 'Cole a chave privada completa'
                          : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passphrase,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Passphrase da chave (opcional)',
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Conectar automaticamente ao abrir'),
                subtitle: const Text('E reconectar se a conexão cair'),
                value: _autoConnect,
                onChanged: (v) => setState(() => _autoConnect = v),
              ),
              Row(
                children: [
                  const Text('Fonte'),
                  Expanded(
                    child: Slider(
                      min: 8,
                      max: 22,
                      divisions: 14,
                      value: _fontSize,
                      label: _fontSize.toStringAsFixed(0),
                      onChanged: (v) => setState(() => _fontSize = v),
                    ),
                  ),
                  Text(_fontSize.toStringAsFixed(0)),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.terminal),
                label: const Text('Salvar e conectar'),
              ),
              const SizedBox(height: 12),
              const Text(
                'As credenciais ficam guardadas no armazenamento seguro do '
                'aparelho (Keystore/Keychain), nunca em texto puro.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
