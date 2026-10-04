import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/services.dart';

import '../ai_settings.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import 'note_screen.dart';
import 'recording_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _query = '';

  Future<void> _startRecording() async {
    HapticFeedback.mediumImpact();
    final s = SettingsStore.instance.value;
    if (!s.chatReady || !s.sttReady) {
      final go = await showCupertinoDialog<bool>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Conecte sua IA'),
          content: const Text(
              '\nPara transcrever e gerar notas, informe as chaves de API do provedor que você quiser usar.'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Gravar mesmo assim'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Configurar'),
            ),
          ],
        ),
      );
      if (go == null || !mounted) return;
      if (go) {
        _openSettings();
        return;
      }
    }
    final note = await Navigator.of(context, rootNavigator: true).push<Note>(
      CupertinoPageRoute(fullscreenDialog: true, builder: (_) => const RecordingScreen()),
    );
    if (note != null && mounted) _open(note);
  }

  void _open(Note note) {
    Navigator.of(context).push(CupertinoPageRoute(builder: (_) => NoteScreen(note: note)));
  }

  void _openSettings() {
    Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const SettingsScreen()));
  }

  Map<String, List<Note>> _group(List<Note> notes) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final groups = <String, List<Note>>{};
    for (final n in notes) {
      final d = DateTime(n.createdAt.year, n.createdAt.month, n.createdAt.day);
      final diff = today.difference(d).inDays;
      final key = switch (diff) {
        0 => 'Hoje',
        1 => 'Ontem',
        < 7 => 'Últimos 7 dias',
        < 30 => 'Últimos 30 dias',
        _ => 'Mais antigas',
      };
      groups.putIfAbsent(key, () => []).add(n);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: AppColors.bg(context),
      child: Stack(
        children: [
          ListenableBuilder(
            listenable: NotesStore.instance,
            builder: (context, _) {
              final q = _query.toLowerCase();
              final notes = NotesStore.instance.notes
                  .where((n) =>
                      q.isEmpty ||
                      n.title.toLowerCase().contains(q) ||
                      n.notes.toLowerCase().contains(q) ||
                      n.transcriptText.toLowerCase().contains(q))
                  .toList();
              final groups = _group(notes);
              return CustomScrollView(
                slivers: [
                  CupertinoSliverNavigationBar(
                    largeTitle: const Text('Notas'),
                    leading: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: AppMark(size: 28),
                    ),
                    trailing: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _openSettings,
                      child: const Icon(CupertinoIcons.gear_alt, size: 24),
                    ),
                    backgroundColor: AppColors.bg(context).withValues(alpha: 0.85),
                    border: null,
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: CupertinoSearchTextField(
                        placeholder: 'Buscar',
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                  ),
                  if (NotesStore.instance.notes.isEmpty)
                    const SliverFillRemaining(hasScrollBody: false, child: _EmptyState())
                  else ...[
                    for (final entry in groups.entries)
                      SliverToBoxAdapter(
                        child: CupertinoListSection.insetGrouped(
                          header: SectionLabel(entry.key),
                          children: [
                            for (final n in entry.value)
                              _NoteTile(note: n, onTap: () => _open(n)),
                          ],
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 140)),
                  ],
                ],
              );
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Center(child: _RecordButton(onTap: _startRecording)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.note, required this.onTap});
  final Note note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile.notched(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
      title: Text(note.title, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          note.preview.isEmpty ? 'Sem conteúdo' : note.preview,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.secondary(context), fontSize: 14),
        ),
      ),
      additionalInfo: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(formatTime(note.createdAt), style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 2),
          Text(formatDuration(note.durationSec),
              style: TextStyle(fontSize: 12, color: AppColors.tertiary(context))),
        ],
      ),
      trailing: note.error != null
          ? const Icon(CupertinoIcons.exclamationmark_circle_fill,
              color: CupertinoColors.systemOrange, size: 20)
          : const CupertinoListTileChevron(),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 40, 40, 160),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const AppMark(size: 72),
          const SizedBox(height: 20),
          Text('Notas instantâneas com IA',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.label(context))),
          const SizedBox(height: 8),
          Text(
            'Grave reuniões, aulas e conversas. A IA transcreve, resume e responde suas perguntas — com a API que você escolher.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.4, color: AppColors.secondary(context)),
          ),
        ],
      ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 26, 14),
        decoration: BoxDecoration(
          gradient: AppColors.gradient,
          borderRadius: BorderRadius.circular(40),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.45),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.mic_fill, color: Colors.white, size: 22),
            SizedBox(width: 10),
            Text('Nova gravação',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
