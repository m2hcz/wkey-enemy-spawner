import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../ai_client.dart';
import '../ai_settings.dart';
import '../models.dart';
import '../theme.dart';

const _languages = {
  'pt': 'Português',
  'en': 'English',
  'es': 'Español',
  '': 'Automático',
};

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final AiSettings _s = SettingsStore.instance.value.copy();
  late final _chatUrl = TextEditingController(text: _s.chatBaseUrl);
  late final _chatKey = TextEditingController(text: _s.chatApiKey);
  late final _chatModel = TextEditingController(text: _s.chatModel);
  late final _sttUrl = TextEditingController(text: _s.sttBaseUrl);
  late final _sttKey = TextEditingController(text: _s.sttApiKey);
  late final _sttModel = TextEditingController(text: _s.sttModel);
  late final _extra = TextEditingController(text: _s.extraInstructions);
  Timer? _debounce;
  bool _testing = false;
  bool _loadingModels = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _sync();
    SettingsStore.instance.save(_s);
    for (final c in [_chatUrl, _chatKey, _chatModel, _sttUrl, _sttKey, _sttModel, _extra]) {
      c.dispose();
    }
    super.dispose();
  }

  void _sync() {
    _s
      ..chatBaseUrl = _chatUrl.text.trim()
      ..chatApiKey = _chatKey.text.trim()
      ..chatModel = _chatModel.text.trim()
      ..sttBaseUrl = _sttUrl.text.trim()
      ..sttApiKey = _sttKey.text.trim()
      ..sttModel = _sttModel.text.trim()
      ..extraInstructions = _extra.text;
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _sync();
      SettingsStore.instance.save(_s.copy());
    });
  }

  Future<T?> _pick<T>(String title, Map<T, String> options) {
    return showCupertinoModalPopup<T>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(title),
        actions: [
          for (final e in options.entries)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(ctx, e.key),
              child: Text(e.value, textAlign: TextAlign.center),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
      ),
    );
  }

  Future<void> _pickChatProvider() async {
    final id = await _pick('Provedor de IA', {for (final p in chatPresets) p.id: p.name});
    if (id == null) return;
    final p = chatPresetById(id);
    setState(() {
      _s.chatProvider = id;
      _chatUrl.text = p.baseUrl;
      _chatModel.text = p.model;
    });
    _changed();
  }

  Future<void> _pickSttProvider() async {
    final id = await _pick('Transcrição', {for (final p in sttPresets) p.id: p.name});
    if (id == null) return;
    final p = sttPresetById(id);
    setState(() {
      _s.sttProvider = id;
      _sttUrl.text = p.baseUrl;
      _sttModel.text = p.model;
      _s.sttUseChatKey = _s.sttUseChatKey && id == _s.chatProvider;
    });
    _changed();
  }

  Future<void> _pickLanguage() async {
    final code = await _pick('Idioma', _languages);
    if (code == null) return;
    setState(() => _s.language = code);
    _changed();
  }

  Future<void> _chooseModel() async {
    _sync();
    setState(() => _loadingModels = true);
    final client = AiClient(_s.copy());
    try {
      final models = await client.listModels();
      if (!mounted) return;
      if (models.isEmpty) {
        _alert('Nenhum modelo', 'O provedor não listou modelos. Digite o nome manualmente.');
        return;
      }
      final picked = await showCupertinoModalPopup<String>(
        context: context,
        builder: (ctx) => _ModelPicker(models: models, current: _chatModel.text),
      );
      if (picked != null) {
        setState(() => _chatModel.text = picked);
        _changed();
      }
    } catch (e) {
      _alert('Não foi possível listar', '$e');
    } finally {
      client.close();
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  Future<void> _test() async {
    _sync();
    setState(() => _testing = true);
    final client = AiClient(_s.copy());
    try {
      final reply = await client.chat(
        system: 'Reply with one short friendly sentence.',
        messages: [ChatMessage(role: 'user', text: 'Say hi, in Portuguese.')],
      );
      _alert('Conectado ✓', reply);
    } catch (e) {
      _alert('Falhou', '$e');
    } finally {
      client.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  void _alert(String title, String msg) {
    if (!mounted) return;
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(padding: const EdgeInsets.only(top: 8), child: Text(msg)),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c,
      {String? placeholder, bool secret = false, Widget? suffix}) {
    return CupertinoListTile(
      padding: const EdgeInsets.fromLTRB(20, 6, 12, 6),
      title: Row(
        children: [
          SizedBox(width: 78, child: Text(label)),
          Expanded(
            child: CupertinoTextField.borderless(
              controller: c,
              placeholder: placeholder,
              obscureText: secret,
              autocorrect: false,
              enableSuggestions: false,
              padding: const EdgeInsets.symmetric(vertical: 6),
              style: TextStyle(color: AppColors.secondary(context), fontSize: 16),
              onChanged: (_) => _changed(),
            ),
          ),
          ?suffix,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatPreset = chatPresetById(_s.chatProvider);
    final sttPreset = sttPresetById(_s.sttProvider);
    return CupertinoPageScaffold(
      backgroundColor: AppColors.bg(context),
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Ajustes'),
            previousPageTitle: 'Notas',
            backgroundColor: AppColors.bg(context).withValues(alpha: 0.85),
            border: null,
          ),
          SliverList.list(children: [
            CupertinoListSection.insetGrouped(
              header: const SectionLabel('IA para notas e perguntas'),
              footer: SectionLabel(
                  chatPreset.id == 'ollama'
                      ? 'Use o IP do computador que roda o Ollama/LM Studio na mesma rede Wi-Fi.'
                      : 'Qualquer API compatível com OpenAI funciona em "Personalizado".',
                  footer: true),
              children: [
                CupertinoListTile(
                  title: const Text('Provedor'),
                  additionalInfo: Text(chatPreset.name),
                  trailing: const CupertinoListTileChevron(),
                  onTap: _pickChatProvider,
                ),
                _field('URL', _chatUrl, placeholder: 'https://…/v1'),
                _field('Chave', _chatKey,
                    placeholder: chatPreset.needsKey ? 'Obrigatória' : 'Opcional', secret: true),
                _field(
                  'Modelo',
                  _chatModel,
                  placeholder: 'nome-do-modelo',
                  suffix: CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 30),
                    onPressed: _loadingModels ? null : _chooseModel,
                    child: _loadingModels
                        ? const CupertinoActivityIndicator()
                        : const Text('Listar', style: TextStyle(fontSize: 15)),
                  ),
                ),
                CupertinoListTile(
                  title: Text('Testar conexão',
                      style: TextStyle(color: CupertinoTheme.of(context).primaryColor)),
                  trailing: _testing ? const CupertinoActivityIndicator() : null,
                  onTap: _testing ? null : _test,
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: const SectionLabel('Transcrição (voz em texto)'),
              footer: const SectionLabel(
                  'Usa o endpoint /audio/transcriptions (Whisper). O Groq tem plano gratuito.',
                  footer: true),
              children: [
                CupertinoListTile(
                  title: const Text('Provedor'),
                  additionalInfo: Text(sttPreset.name.split(' (').first),
                  trailing: const CupertinoListTileChevron(),
                  onTap: _pickSttProvider,
                ),
                if (_s.chatProvider == _s.sttProvider)
                  CupertinoListTile(
                    title: const Text('Usar a mesma chave da IA'),
                    trailing: CupertinoSwitch(
                      value: _s.sttUseChatKey,
                      onChanged: (v) {
                        setState(() => _s.sttUseChatKey = v);
                        _changed();
                      },
                    ),
                  ),
                _field('URL', _sttUrl, placeholder: 'https://…/v1'),
                if (!(_s.sttUseChatKey && _s.chatProvider == _s.sttProvider))
                  _field('Chave', _sttKey, placeholder: 'Obrigatória', secret: true),
                _field('Modelo', _sttModel, placeholder: 'whisper-1'),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: const SectionLabel('Notas'),
              children: [
                CupertinoListTile(
                  title: const Text('Idioma'),
                  additionalInfo: Text(_languages[_s.language] ?? _s.language),
                  trailing: const CupertinoListTileChevron(),
                  onTap: _pickLanguage,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: CupertinoTextField(
                    controller: _extra,
                    minLines: 3,
                    maxLines: 6,
                    placeholder:
                        'Instruções extras (opcional). Ex.: "Sou professor, destaque tarefas dos alunos."',
                    onChanged: (_) => _changed(),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
              child: Text(
                'As chaves ficam no armazenamento seguro do aparelho e são enviadas apenas para as URLs acima.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: AppColors.secondary(context)),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _ModelPicker extends StatefulWidget {
  const _ModelPicker({required this.models, required this.current});
  final List<String> models;
  final String current;

  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = widget.models.where((m) => m.toLowerCase().contains(_q.toLowerCase())).toList();
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.75,
      decoration: BoxDecoration(
        color: AppColors.bg(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: CupertinoSearchTextField(
                placeholder: 'Buscar modelo',
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  CupertinoListSection.insetGrouped(
                    children: [
                      for (final m in list)
                        CupertinoListTile(
                          title: Text(m, style: const TextStyle(fontSize: 15)),
                          trailing: m == widget.current
                              ? const Icon(CupertinoIcons.check_mark, color: AppColors.accent)
                              : null,
                          onTap: () => Navigator.pop(context, m),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
