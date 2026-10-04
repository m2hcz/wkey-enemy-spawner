class TranscriptSegment {
  TranscriptSegment({required this.startSec, required this.text});

  final int startSec;
  final String text;

  Map<String, dynamic> toJson() => {'s': startSec, 't': text};

  factory TranscriptSegment.fromJson(Map<String, dynamic> j) =>
      TranscriptSegment(startSec: j['s'] as int? ?? 0, text: j['t'] as String? ?? '');
}

class ChatMessage {
  ChatMessage({required this.role, required this.text});

  /// 'user' or 'assistant'
  final String role;
  String text;

  bool get isUser => role == 'user';

  Map<String, dynamic> toJson() => {'r': role, 't': text};

  factory ChatMessage.fromJson(Map<String, dynamic> j) =>
      ChatMessage(role: j['r'] as String? ?? 'user', text: j['t'] as String? ?? '');
}

class Note {
  Note({
    required this.id,
    required this.title,
    required this.createdAt,
    this.durationSec = 0,
    List<TranscriptSegment>? transcript,
    this.notes = '',
    List<ChatMessage>? chat,
    this.error,
  })  : transcript = transcript ?? [],
        chat = chat ?? [];

  final String id;
  String title;
  final DateTime createdAt;
  int durationSec;
  List<TranscriptSegment> transcript;

  /// AI-generated notes, in Markdown.
  String notes;
  List<ChatMessage> chat;

  /// Last processing error, shown on the note so the user can retry.
  String? error;

  String get transcriptText => transcript.map((s) => s.text.trim()).where((t) => t.isNotEmpty).join('\n');

  String get transcriptWithTimestamps =>
      transcript.map((s) => '[${formatDuration(s.startSec)}] ${s.text.trim()}').join('\n');

  String get preview {
    final source = notes.isNotEmpty
        ? notes.split('\n').where((l) => !l.trimLeft().startsWith('#')).join(' ')
        : transcriptText;
    return source
        .replaceAll(RegExp(r'[#*_>`\-\[\]]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'durationSec': durationSec,
        'transcript': transcript.map((s) => s.toJson()).toList(),
        'notes': notes,
        'chat': chat.map((m) => m.toJson()).toList(),
        'error': error,
      };

  factory Note.fromJson(Map<String, dynamic> j) => Note(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'Sem título',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        durationSec: j['durationSec'] as int? ?? 0,
        transcript: (j['transcript'] as List? ?? [])
            .map((e) => TranscriptSegment.fromJson(e as Map<String, dynamic>))
            .toList(),
        notes: j['notes'] as String? ?? '',
        chat: (j['chat'] as List? ?? [])
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList(),
        error: j['error'] as String?,
      );
}

String formatDuration(int totalSec) {
  final h = totalSec ~/ 3600;
  final m = (totalSec % 3600) ~/ 60;
  final s = totalSec % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

const _months = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];

String formatDate(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.day} ${_months[d.month - 1]} ${d.year}, ${two(d.hour)}:${two(d.minute)}';
}

String formatTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
