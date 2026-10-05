import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show DefaultMaterialLocalizations, Material, MaterialType, Colors;
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:minuta_native/minuta_native.dart';

import '../ai_client.dart';
import '../ai_settings.dart';
import '../models.dart';
import '../recorder.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/ask_view.dart' show markdownStyle;

/// Size of the floating window, in dp.
const panelHeight = 480;
const bubbleSize = 68;

/// The floating assistant. Runs in its own Flutter engine inside the overlay
/// service, so it keeps listening while the user is in other apps.
class AssistantOverlayApp extends StatelessWidget {
  const AssistantOverlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const CupertinoApp(
      debugShowCheckedModeBanner: false,
      color: Color(0x00000000),
      theme: CupertinoThemeData(brightness: Brightness.dark, primaryColor: AppColors.accent),
      localizationsDelegates: [
        DefaultMaterialLocalizations.delegate,
        DefaultCupertinoLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      home: AssistantOverlay(),
    );
  }
}

class AssistantOverlay extends StatefulWidget {
  const AssistantOverlay({super.key});

  @override
  State<AssistantOverlay> createState() => _AssistantOverlayState();
}

class _AssistantOverlayState extends State<AssistantOverlay> {
  StreamSubscription<Map<String, dynamic>>? _sub;
  final _input = TextEditingController();
  final _scroll = ScrollController();

  Note? _note;
  RecordingController? _rec;
  bool _expanded = true;
  bool _busy = false;
  bool _auto = false;
  bool _hidden = false;
  String? _status;
  int _seenSegments = 0;

  @override
  void initState() {
    super.initState();
    _sub = MinutaNative.messages.listen((m) {
      switch (m['cmd']) {
        case 'start':
          _start();
        case 'stop':
          _end();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _rec?.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- session

  Future<void> _start() async {
    if (_rec != null) return;
    await SettingsStore.instance.load();
    await NotesStore.instance.load();
    final now = DateTime.now();
    final note = Note(id: newNoteId(), title: 'Assistente — ${formatDate(now)}', createdAt: now);
    final rec = RecordingController(note, keepScreenOn: false)..addListener(_onRecording);
    setState(() {
      _note = note;
      _rec = rec;
      _expanded = true;
      _seenSegments = 0;
      _status = null;
    });
    if (!await rec.start(checkPermission: false)) {
      setState(() => _status = rec.transcriptionError ?? 'Não foi possível usar o microfone.');
    }
  }

  void _onRecording() {
    final rec = _rec;
    final note = _note;
    if (rec == null || note == null || !mounted) return;
    final segments = note.transcript.length;
    if (segments != _seenSegments) {
      _seenSegments = segments;
      if (_auto && !_busy && rec.state == RecState.recording) {
        _ask(Prompts.autoInsight, label: '⚡ Auto', auto: true);
      }
    }
    setState(() {});
  }

  Future<void> _end() async {
    final rec = _rec;
    final note = _note;
    if (rec == null || note == null || rec.state == RecState.finishing) return;
    setState(() => _status = 'Finalizando e gerando notas…');
    await rec.finish();
    if (note.transcriptText.isNotEmpty) {
      await generateNotes(note);
    } else {
      note.error = rec.transcriptionError ?? 'Nenhuma fala foi transcrita.';
    }
    await NotesStore.instance.upsert(note);
    await MinutaNative.stopScreenCapture();
    await MinutaNative.broadcast({'event': 'saved', 'id': note.id});
    await MinutaNative.openApp();
    rec.removeListener(_onRecording);
    rec.dispose();
    setState(() {
      _rec = null;
      _note = null;
      _status = null;
      _busy = false;
    });
    await FlutterOverlayWindow.closeOverlay();
  }

  // ----------------------------------------------------------------- window

  Future<void> _setExpanded(bool expanded) async {
    HapticFeedback.selectionClick();
    if (expanded) {
      await FlutterOverlayWindow.resizeOverlay(WindowSize.matchParent, panelHeight, false);
      await FlutterOverlayWindow.moveOverlay(const OverlayPosition(0, 0));
      await FlutterOverlayWindow.updateFlag(OverlayFlag.focusPointer);
    } else {
      FocusManager.instance.primaryFocus?.unfocus();
      await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
      await FlutterOverlayWindow.resizeOverlay(bubbleSize, bubbleSize, true);
      // Park the bubble on the right edge, clear of the status bar. The window
      // is centred horizontally, so x is an offset from the screen centre.
      final display = WidgetsBinding.instance.platformDispatcher.displays.first;
      final screenWidthDp = display.size.width / display.devicePixelRatio;
      await FlutterOverlayWindow.moveOverlay(
          OverlayPosition(screenWidthDp / 2 - bubbleSize / 2 - 6, 140));
    }
    if (mounted) setState(() => _expanded = expanded);
  }

  /// Takes a screenshot without the assistant itself in it.
  Future<List<int>?> _captureScreen() async {
    if (!await MinutaNative.isScreenCaptureActive()) {
      await _setExpanded(false);
      final granted = await MinutaNative.requestScreenCapture();
      await _setExpanded(true);
      if (!granted) {
        _toast('Permissão para ver a tela negada.');
        return null;
      }
    }
    setState(() => _hidden = true);
    await FlutterOverlayWindow.resizeOverlay(1, 1, false);
    await Future.delayed(const Duration(milliseconds: 450));
    final shot = await MinutaNative.captureScreen();
    await FlutterOverlayWindow.resizeOverlay(WindowSize.matchParent, panelHeight, false);
    if (mounted) setState(() => _hidden = false);
    if (shot == null) _toast('Não consegui capturar a tela.');
    return shot;
  }

  void _toast(String msg) {
    setState(() => _status = msg);
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _status == msg) setState(() => _status = null);
    });
  }

  // --------------------------------------------------------------------- AI

  Future<void> _ask(String prompt, {required String label, bool screen = false, bool auto = false}) async {
    final note = _note;
    if (note == null || _busy) return;
    List<int>? image;
    if (screen) {
      image = await _captureScreen();
      if (image == null) return;
    }
    final settings = SettingsStore.instance.value;
    // Earlier turns go as text only; only the new turn carries a screenshot.
    final history = [
      for (final m in note.chat.length > 12 ? note.chat.sublist(note.chat.length - 12) : note.chat)
        ChatMessage(role: m.role, text: m.text),
      ChatMessage(role: 'user', text: prompt, imageJpeg: image),
    ];
    final question = ChatMessage(role: 'user', text: label, hasImage: image != null);
    final reply = ChatMessage(role: 'assistant', text: '');
    setState(() {
      _busy = true;
      note.chat
        ..add(question)
        ..add(reply);
    });
    _scrollToEnd();
    final client = AiClient(settings);
    try {
      await for (final chunk in client.chatStream(
        system: Prompts.assistantSystem(settings, note),
        messages: history,
      )) {
        if (!mounted) break;
        setState(() => reply.text += chunk);
        _scrollToEnd();
      }
      final text = reply.text.trim();
      if (auto && (text.isEmpty || text == '-' || text == '—')) {
        setState(() => note.chat
          ..remove(question)
          ..remove(reply));
      } else if (text.isEmpty) {
        reply.text = '_(resposta vazia)_';
      }
    } catch (e) {
      if (auto) {
        note.chat
          ..remove(question)
          ..remove(reply);
      } else {
        reply.text = '⚠️ $e';
      }
    } finally {
      client.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    _ask(text, label: text);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
      }
    });
  }

  // --------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    return Material(
      type: MaterialType.transparency,
      child: _expanded ? _panel(context) : _bubble(),
    );
  }

  Widget _bubble() {
    final rec = _rec;
    final dotColor = switch (rec?.state) {
      RecState.recording => AppColors.record,
      RecState.paused => CupertinoColors.systemOrange,
      _ => CupertinoColors.systemGrey,
    };
    return GestureDetector(
      onTap: () => _setExpanded(true),
      child: Center(
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: AppColors.gradient,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 10)],
          ),
          child: Stack(
            children: [
              const Center(child: Icon(CupertinoIcons.sparkles, color: Colors.white, size: 26)),
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panel(BuildContext context) {
    final rec = _rec;
    final note = _note;
    final paused = rec?.state == RecState.paused;
    final lastLine = note == null || note.transcript.isEmpty ? null : note.transcript.last.text.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 30, 8, 6),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xF2121216),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 24)],
        ),
        child: Column(
          children: [
            // Header: status, auto, pause, minimize, stop.
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 6, 2),
              child: Row(
                children: [
                  _LiveDot(active: rec?.state == RecState.recording),
                  const SizedBox(width: 8),
                  Text(
                    rec == null
                        ? 'Iniciando…'
                        : '${paused ? 'Pausado' : 'Ouvindo'} · ${formatDuration(rec.elapsedSec)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  if ((rec?.pendingTranscriptions ?? 0) > 0) ...[
                    const SizedBox(width: 8),
                    const CupertinoActivityIndicator(radius: 6, color: Colors.white54),
                  ],
                  const Spacer(),
                  _HeaderButton(
                    icon: CupertinoIcons.bolt_fill,
                    active: _auto,
                    tooltip: 'Auto',
                    onTap: () => setState(() => _auto = !_auto),
                  ),
                  _HeaderButton(
                    icon: paused ? CupertinoIcons.play_fill : CupertinoIcons.pause_fill,
                    onTap: rec == null ? null : () => paused ? rec.resume() : rec.pause(),
                  ),
                  _HeaderButton(
                    icon: CupertinoIcons.minus,
                    onTap: () => _setExpanded(false),
                  ),
                  _HeaderButton(
                    icon: CupertinoIcons.stop_fill,
                    color: AppColors.record,
                    onTap: rec == null ? null : _end,
                  ),
                ],
              ),
            ),
            // Quick actions.
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  _Chip('O que dizer?', CupertinoIcons.sparkles, primary: true,
                      onTap: () => _ask(Prompts.whatToSay, label: '✦ O que dizer?')),
                  _Chip('Analisar tela', CupertinoIcons.device_phone_portrait,
                      onTap: () => _ask(Prompts.analyzeScreen, label: '🖥 Analisar tela', screen: true)),
                  _Chip('Resumo', CupertinoIcons.text_alignleft,
                      onTap: () => _ask(Prompts.summarySoFar, label: '≡ Resumo até agora')),
                  _Chip('Perguntas', CupertinoIcons.question_circle,
                      onTap: () => _ask(Prompts.questionsToAsk, label: '? Perguntas para fazer')),
                ],
              ),
            ),
            // Live transcript ticker / status.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  _status ??
                      rec?.transcriptionError ??
                      (lastLine == null ? 'A transcrição aparece aqui a cada ~25s.' : '“$lastLine”'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _status != null || rec?.transcriptionError != null
                        ? CupertinoColors.systemOrange
                        : Colors.white54,
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
            Container(height: 0.5, color: Colors.white12),
            Expanded(child: _answers(context, note)),
            _inputBar(),
          ],
        ),
      ),
    );
  }

  Widget _answers(BuildContext context, Note? note) {
    final chat = note?.chat ?? const <ChatMessage>[];
    if (chat.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Toque em "O que dizer?" a qualquer momento, analise a tela ou pergunte algo. '
            'Ative ⚡ para receber dicas automáticas.\n\n'
            'Toque em — (no topo) para minimizar em um balão. Toque no balão para abrir de novo.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.4),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      itemCount: chat.length,
      itemBuilder: (context, i) {
        final m = chat[i];
        if (m.isUser) {
          return Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4),
            child: Text(m.text,
                style: const TextStyle(
                    color: AppColors.accent, fontSize: 13, fontWeight: FontWeight.w600)),
          );
        }
        if (m.text.isEmpty && _busy && i == chat.length - 1) {
          return const Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: CupertinoActivityIndicator(color: Colors.white70),
            ),
          );
        }
        return GestureDetector(
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: m.text));
            HapticFeedback.mediumImpact();
            _toast('Copiado');
          },
          child: MarkdownBody(data: m.text, styleSheet: markdownStyle(context, fontSize: 15)),
        );
      },
    );
  }

  Widget _inputBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 10),
      child: Row(
        children: [
          Expanded(
            child: CupertinoTextField(
              controller: _input,
              placeholder: 'Pergunte qualquer coisa…',
              placeholderStyle: const TextStyle(color: Colors.white38),
              style: const TextStyle(color: Colors.white, fontSize: 15),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.only(left: 6),
            minimumSize: const Size(36, 36),
            onPressed: _busy ? null : _send,
            child: _busy
                ? const CupertinoActivityIndicator(color: Colors.white70)
                : const Icon(CupertinoIcons.arrow_up_circle_fill, size: 34, color: AppColors.accent),
          ),
        ],
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot({required this.active});
  final bool active;

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: widget.active ? Tween(begin: 0.35, end: 1.0).animate(_c) : const AlwaysStoppedAnimation(1),
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: widget.active ? AppColors.record : CupertinoColors.systemOrange,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.icon, this.onTap, this.active = false, this.color, this.tooltip});
  final IconData icon;
  final VoidCallback? onTap;
  final bool active;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      minimumSize: const Size(34, 34),
      onPressed: onTap,
      child: Icon(
        icon,
        size: 19,
        color: color ?? (active ? CupertinoColors.systemYellow : Colors.white70),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.icon, {required this.onTap, this.primary = false});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            gradient: primary ? AppColors.gradient : null,
            color: primary ? null : Colors.white.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: Colors.white),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
