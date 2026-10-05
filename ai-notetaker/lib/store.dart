import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Keeps each note as its own JSON file in the app's private documents
/// folder, so the main screen and the floating assistant (separate Flutter
/// engines) can both save notes without overwriting each other.
class NotesStore extends ChangeNotifier {
  NotesStore._();

  static final instance = NotesStore._();

  final List<Note> _notes = [];
  Directory? _root;

  List<Note> get notes => List.unmodifiable(_notes);

  Note? byId(String id) {
    for (final n in _notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  Future<Directory> _dir() async {
    if (_root != null) return _root!;
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory('${docs.path}/notes');
    await root.create(recursive: true);
    return _root = root;
  }

  Future<void> load() => reload();

  /// Re-reads every note from disk (picks up notes saved by the assistant).
  Future<void> reload() async {
    final root = await _dir();
    final loaded = <Note>[];
    final legacy = File('${root.path}/index.json');
    if (await legacy.exists()) {
      try {
        final list = jsonDecode(await legacy.readAsString()) as List;
        for (final e in list) {
          final n = Note.fromJson(e as Map<String, dynamic>);
          await _write(n);
        }
        await legacy.delete();
      } catch (e) {
        debugPrint('Failed to migrate notes: $e');
      }
    }
    await for (final f in root.list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      try {
        loaded.add(Note.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>));
      } catch (e) {
        debugPrint('Skipping unreadable note ${f.path}: $e');
      }
    }
    loaded.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _notes
      ..clear()
      ..addAll(loaded);
    notifyListeners();
  }

  /// Folder holding a note's audio segments.
  Future<Directory> audioDir(String noteId) async {
    final dir = Directory('${(await _dir()).path}/$noteId');
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> upsert(Note note) async {
    final i = _notes.indexWhere((n) => n.id == note.id);
    if (i >= 0) {
      _notes[i] = note;
    } else {
      _notes.add(note);
    }
    _notes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
    await _write(note);
  }

  Future<void> delete(Note note) async {
    _notes.removeWhere((n) => n.id == note.id);
    notifyListeners();
    final root = await _dir();
    final file = File('${root.path}/${note.id}.json');
    if (await file.exists()) await file.delete();
    final dir = Directory('${root.path}/${note.id}');
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<void> _write(Note note) async {
    final root = await _dir();
    final file = File('${root.path}/${note.id}.json');
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(note.toJson()));
    await tmp.rename(file.path);
  }
}
