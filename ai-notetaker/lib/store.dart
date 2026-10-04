import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Keeps every note as JSON in the app's private documents folder.
class NotesStore extends ChangeNotifier {
  NotesStore._();

  static final instance = NotesStore._();

  final List<Note> _notes = [];
  late Directory _root;
  bool _loaded = false;

  List<Note> get notes => List.unmodifiable(_notes);

  Future<void> load() async {
    if (_loaded) return;
    final docs = await getApplicationDocumentsDirectory();
    _root = Directory('${docs.path}/notes');
    await _root.create(recursive: true);
    final file = File('${_root.path}/index.json');
    if (await file.exists()) {
      try {
        final list = jsonDecode(await file.readAsString()) as List;
        _notes
          ..clear()
          ..addAll(list.map((e) => Note.fromJson(e as Map<String, dynamic>)));
        _notes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      } catch (e) {
        debugPrint('Failed to read notes: $e');
      }
    }
    _loaded = true;
    notifyListeners();
  }

  /// Folder holding a note's audio segments.
  Future<Directory> audioDir(String noteId) async {
    final dir = Directory('${_root.path}/$noteId');
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> upsert(Note note) async {
    final i = _notes.indexWhere((n) => n.id == note.id);
    if (i >= 0) {
      _notes[i] = note;
    } else {
      _notes.insert(0, note);
    }
    _notes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
    await _persist();
  }

  Future<void> delete(Note note) async {
    _notes.removeWhere((n) => n.id == note.id);
    notifyListeners();
    final dir = Directory('${_root.path}/${note.id}');
    if (await dir.exists()) await dir.delete(recursive: true);
    await _persist();
  }

  Future<void> _persist() async {
    final file = File('${_root.path}/index.json');
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(_notes.map((n) => n.toJson()).toList()));
    await tmp.rename(file.path);
  }
}
