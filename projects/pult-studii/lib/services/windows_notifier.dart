import 'package:local_notifier/local_notifier.dart';

import 'notifications.dart';

/// Тосты Windows через пакет local_notifier.
class WindowsNotifier implements AppNotifier {
  void Function(String key)? _onClick;
  bool _ready = false;
  final _live = <LocalNotification>{};

  @override
  Future<void> init(void Function(String key) onClick) async {
    _onClick = onClick;
    try {
      await localNotifier.setup(
        appName: notifyTitle,
        // ярлык «AI Studio» с тем же AppUserModelID создаёт установщик
        shortcutPolicy: ShortcutPolicy.requireNoCreate,
      );
      _ready = true;
    } catch (_) {
      _ready = false; // уведомления не работают, остальное — да
    }
  }

  @override
  Future<void> show({
    required String title,
    required String body,
    required String key,
  }) async {
    if (!_ready) return;
    final n = LocalNotification(title: title, body: body);
    n.onClick = () => _onClick?.call(key);
    n.onClose = (_) {
      _live.remove(n);
      n.destroy();
    };
    _live.add(n); // держим ссылку, чтобы обработчики не пропали
    try {
      await n.show();
    } catch (_) {
      _live.remove(n);
    }
  }
}
