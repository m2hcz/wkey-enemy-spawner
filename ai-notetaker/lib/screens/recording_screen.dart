import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/services.dart';

import '../models.dart';
import '../recorder.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/ask_view.dart';
import '../widgets/waveform.dart';

/// Full-screen recorder: timer, live waveform, live transcript and the
/// pause / stop / ask control pill. Pops with the finished [Note].
class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  late final Note _note = Note(
    id: newNoteId(),
    title: 'Gravação de ${formatDate(DateTime.now())}',
    createdAt: DateTime.now(),
  );
  late final RecordingController _rec = RecordingController(_note);
  final _scroll = ScrollController();
  String _phase = '';
  int _lastSegments = 0;

  @override
  void initState() {
    super.initState();
    _rec.addListener(_onChange);
    _begin();
  }

  Future<void> _begin() async {
    final ok = await _rec.start();
    if (!ok && mounted) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Microfone bloqueado'),
          content: const Text('\nPermita o acesso ao microfone nas configurações do Android.'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    }
  }

  void _onChange() {
    if (_note.transcript.length != _lastSegments) {
      _lastSegments = _note.transcript.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        }
      });
    }
  }

  @override
  void dispose() {
    _rec.removeListener(_onChange);
    _rec.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _stop() async {
    HapticFeedback.heavyImpact();
    setState(() => _phase = 'Transcrevendo…');
    await _rec.finish();
    if (!_rec.canTranscribe) {
      _note.error = 'Transcrição não configurada. Configure em Ajustes e toque em "Gerar notas novamente".';
    } else if (_note.transcriptText.isNotEmpty) {
      setState(() => _phase = 'Gerando notas…');
      await generateNotes(_note);
    } else {
      _note.error = _rec.transcriptionError ?? 'Nenhuma fala foi detectada.';
    }
    await NotesStore.instance.upsert(_note);
    if (mounted) Navigator.pop(context, _note);
  }

  Future<void> _cancel() async {
    final discard = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Descartar esta gravação?'),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Descartar'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Salvar nota'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Continuar gravando'),
        ),
      ),
    );
    if (discard == null) return;
    if (discard) {
      await _rec.discard();
      await NotesStore.instance.delete(_note);
      if (mounted) Navigator.pop(context);
    } else {
      await _stop();
    }
  }

  void _openAsk() {
    HapticFeedback.selectionClick();
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => _AskSheet(note: _note, listenable: _rec),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _phase.isEmpty) _cancel();
      },
      child: CupertinoPageScaffold(
        backgroundColor: AppColors.bg(context),
        navigationBar: CupertinoNavigationBar(
          backgroundColor: AppColors.bg(context),
          border: null,
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _phase.isEmpty ? _cancel : null,
            child: const Icon(CupertinoIcons.xmark, size: 22),
          ),
          middle: ListenableBuilder(
            listenable: _rec,
            builder: (_, _) => _StatusBadge(state: _rec.state),
          ),
        ),
        child: SafeArea(
          child: ListenableBuilder(
            listenable: _rec,
            builder: (context, _) {
              final paused = _rec.state == RecState.paused;
              return Column(
                children: [
                  const SizedBox(height: 12),
                  Text(
                    formatDuration(_rec.elapsedSec),
                    style: TextStyle(
                      fontSize: 64,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 1,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: AppColors.label(context),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
                    child: Waveform(levels: _rec.levels, active: !paused),
                  ),
                  Expanded(child: _transcriptCard(context)),
                  if (_phase.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(26),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CupertinoActivityIndicator(),
                          const SizedBox(width: 10),
                          Text(_phase,
                              style: TextStyle(
                                  fontSize: 16, color: AppColors.secondary(context))),
                        ],
                      ),
                    )
                  else
                    _ControlPill(
                      paused: paused,
                      onPause: () {
                        HapticFeedback.selectionClick();
                        paused ? _rec.resume() : _rec.pause();
                      },
                      onStop: _stop,
                      onAsk: _openAsk,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _transcriptCard(BuildContext context) {
    final segments = _note.transcript;
    final secondary = AppColors.secondary(context);
    Widget body;
    if (!_rec.canTranscribe) {
      body = Text('Transcrição ao vivo desativada: configure a API de transcrição em Ajustes. '
          'O áudio está sendo gravado normalmente.',
          style: TextStyle(color: secondary, height: 1.4));
    } else if (segments.isEmpty) {
      body = Text(
        _rec.pendingTranscriptions > 0
            ? 'Transcrevendo…'
            : 'Ouvindo… a transcrição aparece aqui a cada ~${RecordingController.segmentSeconds}s.',
        style: TextStyle(color: secondary, height: 1.4),
      );
    } else {
      body = ListView.builder(
        controller: _scroll,
        padding: EdgeInsets.zero,
        itemCount: segments.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 46,
                child: Text(formatDuration(segments[i].startSec),
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.tertiary(context),
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ),
              Expanded(
                child: Text(segments[i].text,
                    style: TextStyle(fontSize: 15.5, height: 1.4, color: AppColors.label(context))),
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('TRANSCRIÇÃO AO VIVO',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: secondary, letterSpacing: .4)),
              const Spacer(),
              if (_rec.pendingTranscriptions > 0) const CupertinoActivityIndicator(radius: 7),
            ],
          ),
          if (_rec.transcriptionError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('⚠️ ${_rec.transcriptionError}',
                  style: const TextStyle(fontSize: 13, color: CupertinoColors.systemOrange)),
            ),
          const SizedBox(height: 10),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.state});
  final RecState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      RecState.recording => ('Gravando', AppColors.record),
      RecState.paused => ('Pausado', CupertinoColors.systemOrange),
      RecState.finishing => ('Finalizando', AppColors.accent),
      RecState.idle => ('Preparando', CupertinoColors.systemGrey),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// The floating pause / stop / ask pill.
class _ControlPill extends StatelessWidget {
  const _ControlPill({
    required this.paused,
    required this.onPause,
    required this.onStop,
    required this.onAsk,
  });

  final bool paused;
  final VoidCallback onPause;
  final VoidCallback onStop;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    Widget circle(Widget child, Color bg, VoidCallback onTap, {double size = 52}) =>
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: child,
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(48),
          boxShadow: AppColors.shadow(context),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            circle(
              Icon(paused ? CupertinoIcons.play_fill : CupertinoIcons.pause_fill,
                  color: AppColors.label(context), size: 24),
              AppColors.fill(context),
              onPause,
            ),
            const SizedBox(width: 18),
            circle(
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              AppColors.record,
              onStop,
              size: 66,
            ),
            const SizedBox(width: 18),
            GestureDetector(
              onTap: onAsk,
              child: Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(gradient: AppColors.gradient, shape: BoxShape.circle),
                child: const Icon(CupertinoIcons.sparkles, color: Colors.white, size: 24),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AskSheet extends StatelessWidget {
  const _AskSheet({required this.note, required this.listenable});
  final Note note;
  final Listenable listenable;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height * 0.86;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        height: h,
        decoration: BoxDecoration(
          color: AppColors.bg(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 38,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.tertiary(context),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 4),
              child: Row(
                children: [
                  Text('Perguntar',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.label(context))),
                  const Spacer(),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.pop(context),
                    child: const Text('OK'),
                  ),
                ],
              ),
            ),
            Expanded(child: AskView(note: note, live: true)),
          ],
        ),
      ),
    );
  }
}
