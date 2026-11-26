import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Читает и пишет число в shared_preferences.
class CounterStore {
  static const key = 'counter';

  /// Ошибка чтения или отсутствие значения — 0.
  Future<int> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getInt(key) ?? 0;
      return value < 0 ? 0 : value;
    } catch (_) {
      return 0;
    }
  }

  Future<void> save(int value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(key, value);
    } catch (_) {
      // Не удалось сохранить — число остаётся на экране, приложение не падает.
    }
  }
}

/// Логика счётчика без UI: +1, −1 (не ниже 0), сброс.
class CounterController extends ChangeNotifier {
  CounterController(this._store);

  final CounterStore _store;
  int _value = 0;
  bool _loaded = false;
  bool _disposed = false;

  int get value => _value;
  bool get loaded => _loaded;

  Future<void> load() async {
    final loaded = await _store.load();
    if (_disposed) return;
    _value = loaded;
    _loaded = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void increment() => _set(_value + 1);

  void decrement() {
    if (_value > 0) _set(_value - 1);
  }

  void reset() {
    if (_value != 0) _set(0);
  }

  void _set(int v) {
    _value = v;
    notifyListeners();
    // Намеренно: UI берёт значение из памяти.
    unawaited(_store.save(v));
  }
}
