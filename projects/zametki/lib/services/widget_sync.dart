import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../models/note.dart';

/// Передаёт данные виджетам главного экрана.
abstract class WidgetSync {
  Future<void> refresh(List<Note> notes);
}

/// Ничего не делает (тесты, платформы без виджетов).
class NoopWidgetSync implements WidgetSync {
  const NoopWidgetSync();

  @override
  Future<void> refresh(List<Note> notes) async {}
}

/// Данные для виджетов в виде JSON (читает Kotlin-код в android/).
class WidgetPayload {
  static const maxRecent = 5;

  /// Последние заметки (по дате изменения).
  static String recent(List<Note> notes) {
    final sorted = [...notes]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final list = sorted
        .where((n) => n.id != null)
        .take(maxRecent)
        .map((n) => {
              'id': n.id,
              'title': n.displayTitle,
              'preview': n.previewLines(1).firstOrNull ?? '',
              'color': n.color,
            })
        .toList();
    return jsonEncode(list);
  }

  /// Самая свежая из закреплённых; пустая строка, если закреплённых нет.
  static String pinned(List<Note> notes) {
    final pinned = notes.where((n) => n.pinned && n.id != null).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (pinned.isEmpty) return '';
    final n = pinned.first;
    return jsonEncode({
      'id': n.id,
      'title': n.displayTitle,
      'text': n.fullText,
      'color': n.color,
    });
  }
}

/// Реализация через пакет home_widget (Android).
class HomeWidgetSync implements WidgetSync {
  const HomeWidgetSync();

  static const providers = ['RecentNotesWidgetProvider', 'PinnedNoteWidgetProvider'];

  @override
  Future<void> refresh(List<Note> notes) async {
    try {
      await HomeWidget.saveWidgetData<String>('recent', WidgetPayload.recent(notes));
      await HomeWidget.saveWidgetData<String>('pinned', WidgetPayload.pinned(notes));
      for (final name in providers) {
        await HomeWidget.updateWidget(androidName: name);
      }
    } catch (e) {
      // Виджеты — не критично: приложение работает и без них.
      debugPrint('Не удалось обновить виджеты: $e');
    }
  }
}
