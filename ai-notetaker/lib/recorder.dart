import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'ai_client.dart';
import 'ai_settings.dart';
import 'models.dart';
import 'store.dart';

enum RecState { idle, recording, paused, finishing }

class _Chunk {
  _Chunk(this.file, this.startSec);
  final File file;
  final int startSec;
  bool done = false;
}

/// Records the microphone in short segments and transcribes each segment as
/// soon as it is closed, so the transcript (and "Ask") work during recording.
class RecordingController extends ChangeNotifier {
  RecordingController(this.note, {this.keepScreenOn = true});

  /// Seconds of audio per transcription segment.
  static const segmentSeconds = 25;

  final Note note;

  /// Keep the screen awake while recording (needs an Activity, so the
  /// floating assistant turns it off).
  final bool keepScreenOn;
  final _recorder = AudioRecorder();
  final List<_Chunk> _chunks = [];
  final List<double> levels = List.filled(48, 0, growable: true);

  RecState state = RecState.idle;
  int elapsedSec = 0;
  int _segmentElapsed = 0;
  int _segmentIndex = 0;
  int _currentSegmentStart = 0;
  Timer? _ticker;
  StreamSubscription<Amplitude>? _ampSub;
  Directory? _dir;
  bool _rotating = false;

  int pendingTranscriptions = 0;
  String? transcriptionError;
  Future<void> _queue = Future.value();

  AiSettings get _settings => SettingsStore.instance.value;
  bool get canTranscribe => _settings.sttReady;

  /// [checkPermission] must be false where there is no Activity (the
  /// floating assistant); the app checks the permission before opening it.
  Future<bool> start({bool checkPermission = true}) async {
    if (checkPermission && !await _recorder.hasPermission()) return false;
    _dir = await NotesStore.instance.audioDir(note.id);
    try {
      await _startSegment();
    } catch (e) {
      transcriptionError = 'Não foi possível usar o microfone: $e';
      notifyListeners();
      return false;
    }
    state = RecState.recording;
    _wake(true);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 90))
        .listen(_onAmplitude);
    notifyListeners();
    return true;
  }

  Future<void> _startSegment() async {
    final path = '${_dir!.path}/seg_${_segmentIndex.toString().padLeft(4, '0')}.m4a';
    _currentSegmentStart = elapsedSec;
    _segmentElapsed = 0;
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 48000,
        noiseSuppress: true,
        autoGain: true,
      ),
      path: path,
    );
  }

  void _onAmplitude(Amplitude a) {
    // dBFS (-160..0) -> 0..1, with a floor so silence looks flat.
    final v = ((a.current + 50) / 50).clamp(0.0, 1.0);
    levels
      ..removeAt(0)
      ..add(state == RecState.recording ? v.toDouble() : 0);
    notifyListeners();
  }

  void _tick() {
    if (state != RecState.recording) return;
    elapsedSec++;
    _segmentElapsed++;
    notifyListeners();
    if (_segmentElapsed >= segmentSeconds && !_rotating) _rotate();
  }

  /// Closes the current segment, queues it for transcription, opens the next.
  Future<void> _rotate() async {
    _rotating = true;
    try {
      final path = await _recorder.stop();
      _enqueue(path, _currentSegmentStart);
      _segmentIndex++;
      if (state == RecState.recording || state == RecState.paused) {
        await _startSegment();
        if (state == RecState.paused) await _recorder.pause();
      }
    } finally {
      _rotating = false;
    }
  }

  void _enqueue(String? path, int startSec) {
    if (path == null) return;
    final file = File(path);
    if (!file.existsSync() || file.lengthSync() < 2000) return;
    final chunk = _Chunk(file, startSec);
    _chunks.add(chunk);
    if (!canTranscribe) return;
    pendingTranscriptions++;
    notifyListeners();
    _queue = _queue.then((_) => _transcribe(chunk));
  }

  Future<void> _transcribe(_Chunk chunk) async {
    final client = AiClient(_settings);
    try {
      for (var attempt = 0; attempt < 3 && !chunk.done; attempt++) {
        try {
          final text = await client.transcribe(chunk.file);
          chunk.done = true;
          transcriptionError = null;
          if (text.isNotEmpty) {
            note.transcript
              ..add(TranscriptSegment(startSec: chunk.startSec, text: text))
              ..sort((a, b) => a.startSec.compareTo(b.startSec));
          }
        } on AiException catch (e) {
          transcriptionError = e.message;
          await Future.delayed(Duration(seconds: 2 << attempt));
        }
      }
    } catch (e) {
      transcriptionError = '$e';
    } finally {
      client.close();
      pendingTranscriptions = max(0, pendingTranscriptions - 1);
      notifyListeners();
    }
  }

  Future<void> pause() async {
    if (state != RecState.recording) return;
    await _recorder.pause();
    state = RecState.paused;
    notifyListeners();
  }

  Future<void> resume() async {
    if (state != RecState.paused) return;
    await _recorder.resume();
    state = RecState.recording;
    notifyListeners();
  }

  /// Stops recording and waits until every segment is transcribed.
  Future<void> finish() async {
    if (state == RecState.idle || state == RecState.finishing) return;
    while (_rotating) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    state = RecState.finishing;
    notifyListeners();
    _ticker?.cancel();
    await _ampSub?.cancel();
    _enqueue(await _recorder.stop(), _currentSegmentStart);
    note.durationSec = elapsedSec;
    _wake(false);
    await _queue;
    // Retry anything that failed during the meeting (e.g. network drop).
    for (final c in _chunks.where((c) => !c.done)) {
      if (!canTranscribe) break;
      pendingTranscriptions++;
      notifyListeners();
      await _transcribe(c);
    }
  }

  Future<void> discard() async {
    _ticker?.cancel();
    await _ampSub?.cancel();
    await _recorder.cancel();
    _wake(false);
    state = RecState.idle;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ampSub?.cancel();
    _recorder.dispose();
    _wake(false);
    super.dispose();
  }

  void _wake(bool on) {
    if (!keepScreenOn) return;
    (on ? WakelockPlus.enable() : WakelockPlus.disable()).catchError((Object _) {});
  }
}

/// Regenerates title + notes for a note with the configured chat model.
Future<void> generateNotes(Note note) async {
  final settings = SettingsStore.instance.value;
  if (note.transcriptText.trim().isEmpty) {
    note.error = 'Nenhuma fala foi transcrita.';
    return;
  }
  final client = AiClient(settings);
  try {
    final output = await client.chat(
      system: Prompts.notesSystem(settings),
      messages: [ChatMessage(role: 'user', text: Prompts.notesUser(note))],
    );
    final (title, body) = Prompts.splitTitle(output);
    if (title != null && title.isNotEmpty) note.title = title;
    note.notes = body;
    note.error = null;
  } on AiException catch (e) {
    note.error = e.message;
  } catch (e) {
    note.error = '$e';
  } finally {
    client.close();
  }
}

String newNoteId() =>
    '${DateTime.now().millisecondsSinceEpoch}${Random().nextInt(9999).toString().padLeft(4, '0')}';
