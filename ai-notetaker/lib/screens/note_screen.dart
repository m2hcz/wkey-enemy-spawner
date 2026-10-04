import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../ai_client.dart';
import '../ai_settings.dart';
import '../models.dart';
import '../recorder.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/ask_view.dart';

enum _Tab { notes, transcript, ask }

class NoteScreen extends StatefulWidget {
  const NoteScreen({super.key, required this.note});
  final Note note;

  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {
  _Tab _tab = _Tab.notes;
  bool _working = false;
  String _workingLabel = '';

  Note get note => widget.note;

  Future<void> _save() => NotesStore.instance.upsert(note);

  Future<void> _regenerate() async {
    setState(() {
      _working = true;
      _workingLabel = 'Gerando notas…';
    });
    if (note.transcript.isEmpty) await _retranscribe(save: false);
    if (note.transcript.isNotEmpty) await generateNotes(note);
    await _save();
    if (mounted) setState(() => _working = false);
  }

  /// Transcribes the stored audio segments again (e.g. after fixing the key).
  Future<void> _retranscribe({bool save = true}) async {
    setState(() {
      _working = true;
      _workingLabel = 'Transcrevendo áudio…';
    });
    final dir = await NotesStore.instance.audioDir(note.id);
    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.m4a')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final client = AiClient(SettingsStore.instance.value);
    final segments = <TranscriptSegment>[];
    try {
      for (var i = 0; i < files.length; i++) {
        final text = await client.transcribe(files[i]);
        if (text.isNotEmpty) {
          segments.add(TranscriptSegment(startSec: i * RecordingController.segmentSeconds, text: text));
        }
      }
      note.transcript = segments;
      note.error = segments.isEmpty ? 'Nenhuma fala foi detectada no áudio.' : null;
    } catch (e) {
      note.error = '$e';
    } finally {
      client.close();
    }
    if (save) {
      await _save();
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _rename() async {
    final ctrl = TextEditingController(text: note.title);
    final name = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Renomear'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(controller: ctrl, autofocus: true),
        ),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      setState(() => note.title = name);
      await _save();
    }
  }

  void _copy() {
    final text = switch (_tab) {
      _Tab.transcript => note.transcriptWithTimestamps,
      _ => '# ${note.title}\n\n${note.notes}',
    };
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.mediumImpact();
    showCupertinoDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        Future.delayed(const Duration(milliseconds: 900), () {
          if (ctx.mounted && Navigator.canPop(ctx)) Navigator.pop(ctx);
        });
        return const CupertinoAlertDialog(title: Text('Copiado ✓'));
      },
    );
  }

  Future<void> _menu() async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(ctx, 'copy'), child: const Text('Copiar')),
          CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(ctx, 'rename'), child: const Text('Renomear')),
          CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(ctx, 'regen'),
              child: const Text('Gerar notas novamente')),
          CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(ctx, 'retranscribe'),
              child: const Text('Transcrever o áudio novamente')),
          CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(ctx, 'delete'),
              child: const Text('Apagar nota')),
        ],
        cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
      ),
    );
    switch (action) {
      case 'copy':
        _copy();
      case 'rename':
        _rename();
      case 'regen':
        _regenerate();
      case 'retranscribe':
        await _retranscribe();
        if (note.transcript.isNotEmpty) await _regenerate();
      case 'delete':
        await NotesStore.instance.delete(note);
        if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: AppColors.bg(context),
      navigationBar: CupertinoNavigationBar(
        backgroundColor: AppColors.bg(context).withValues(alpha: 0.9),
        border: null,
        previousPageTitle: 'Notas',
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _working ? null : _menu,
          child: const Icon(CupertinoIcons.ellipsis_circle, size: 25),
        ),
      ),
      child: SafeArea(
        bottom: _tab != _Tab.ask,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: _rename,
                    child: Text(note.title,
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                            color: AppColors.label(context))),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _Meta(icon: CupertinoIcons.calendar, text: formatDate(note.createdAt)),
                      const SizedBox(width: 8),
                      _Meta(icon: CupertinoIcons.time, text: formatDuration(note.durationSec)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoSlidingSegmentedControl<_Tab>(
                      groupValue: _tab,
                      onValueChanged: (t) => setState(() => _tab = t ?? _Tab.notes),
                      children: const {
                        _Tab.notes: Text('Notas'),
                        _Tab.transcript: Text('Transcrição'),
                        _Tab.ask: Text('Perguntar'),
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (_working)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CupertinoActivityIndicator(),
                    const SizedBox(width: 8),
                    Text(_workingLabel, style: TextStyle(color: AppColors.secondary(context))),
                  ],
                ),
              ),
            Expanded(
              child: switch (_tab) {
                _Tab.notes => _notesView(context),
                _Tab.transcript => _transcriptView(context),
                _Tab.ask => AskView(note: note, onChanged: _save),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CupertinoColors.systemOrange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(note.error!, style: TextStyle(color: AppColors.label(context), height: 1.35)),
          const SizedBox(height: 8),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 30),
            onPressed: _working ? null : _regenerate,
            child: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  Widget _notesView(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          if (note.error != null) _errorCard(context),
          if (note.notes.isEmpty && note.error == null && !_working)
            Text('Sem notas ainda.', style: TextStyle(color: AppColors.secondary(context))),
          if (note.notes.isNotEmpty)
            MarkdownBody(data: note.notes, styleSheet: markdownStyle(context)),
        ],
      ),
    );
  }

  Widget _transcriptView(BuildContext context) {
    if (note.transcript.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (note.error != null) _errorCard(context),
          Text('Sem transcrição.', style: TextStyle(color: AppColors.secondary(context))),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      itemCount: note.transcript.length,
      itemBuilder: (_, i) {
        final s = note.transcript[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(formatDuration(s.startSec),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accent)),
              const SizedBox(height: 4),
              Text(s.text,
                  style: TextStyle(fontSize: 16, height: 1.45, color: AppColors.label(context))),
            ],
          ),
        );
      },
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.fill(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.secondary(context)),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 12.5, color: AppColors.secondary(context))),
        ],
      ),
    );
  }
}
