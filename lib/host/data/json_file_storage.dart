import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Thread-safe (serialized) JSON list file storage.
class JsonFileStorage<T> {
  final String fileName;
  final T Function(Map<String, dynamic> json) fromJson;
  final Map<String, dynamic> Function(T item) toJson;

  Future<void> _writeLock = Future.value();

  JsonFileStorage({
    required this.fileName,
    required this.fromJson,
    required this.toJson,
  });

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$fileName');
  }

  Future<R> _synchronized<R>(Future<R> Function() action) {
    final completer = Completer<R>();
    _writeLock = _writeLock.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<List<T>> loadAll() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList
          .whereType<Map<String, dynamic>>()
          .map(fromJson)
          .toList();
    } catch (e) {
      debugPrint('Error loading $fileName: $e');
      rethrow;
    }
  }

  Future<List<T>> loadAllOrEmpty() async {
    try {
      return await loadAll();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAll(List<T> items) async {
    final file = await _getFile();
    final content = jsonEncode(items.map(toJson).toList());
    await file.writeAsString(content, flush: true);
  }

  Future<void> mutate(void Function(List<T> items) updater) {
    return _synchronized(() async {
      final items = await loadAll();
      updater(items);
      await saveAll(items);
    });
  }
}
