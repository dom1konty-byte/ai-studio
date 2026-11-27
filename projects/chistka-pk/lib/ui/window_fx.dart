import 'dart:async';

import 'package:material_ui/material_ui.dart';

/// Анимация сворачивания/разворачивания внутри Flutter: содержимое окна
/// уменьшается к правому нижнему углу (1 → 0,85) и затухает. Окно при этом
/// не двигается (покадровый setBounds убран).
class WindowFx {
  _WindowFxHostState? _host;

  /// Нет хоста (тесты, до runApp) или включено «Убрать анимации» — сразу готово.
  Future<void> playHide() => _host?._run(hide: true) ?? Future.value();
  Future<void> playShow() => _host?._run(hide: false) ?? Future.value();

  /// До `windowManager.show()`: содержимое «спрятано» (масштаб 0,85, прозрачность 0).
  void prepareShow() => _host?._prepareShow();

  /// После hide / после показа: содержимое в обычном виде.
  void reset() => _host?._reset();

  /// Текущая степень «спрятанности» 0..1 (для тестов).
  double get amount => _host?._k ?? 0;
}

final windowFx = WindowFx();

const windowFxDuration = Duration(milliseconds: 220);

class WindowFxHost extends StatefulWidget {
  const WindowFxHost({super.key, required this.child, this.fx});
  final Widget child;
  final WindowFx? fx;

  @override
  State<WindowFxHost> createState() => _WindowFxHostState();
}

enum _Mode { idle, hide, show }

class _WindowFxHostState extends State<WindowFxHost> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl =
      AnimationController(vsync: this, duration: windowFxDuration);
  _Mode _mode = _Mode.idle;
  late final WindowFx _fx = widget.fx ?? windowFx;

  @override
  void initState() {
    super.initState();
    _fx._host = this;
    _ctl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    if (_fx._host == this) _fx._host = null;
    _ctl.dispose();
    super.dispose();
  }

  /// 0 — обычный вид, 1 — спрятано.
  double get _k {
    switch (_mode) {
      case _Mode.idle:
        return 0;
      case _Mode.hide:
        return Curves.easeInCubic.transform(_ctl.value);
      case _Mode.show:
        return 1 - Curves.easeOutCubic.transform(_ctl.value);
    }
  }

  bool get _noAnim => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  Future<void> _run({required bool hide}) async {
    if (_noAnim) {
      _mode = hide ? _Mode.hide : _Mode.idle;
      if (mounted) setState(() {});
      return;
    }
    _mode = hide ? _Mode.hide : _Mode.show;
    try {
      await _ctl.forward(from: 0).orCancel;
    } on TickerCanceled {
      return;
    }
    if (!hide) {
      _mode = _Mode.idle;
      if (mounted) setState(() {});
    }
  }

  void _prepareShow() {
    if (_noAnim) return;
    _ctl.value = 0;
    _mode = _Mode.show;
    setState(() {});
  }

  void _reset() {
    _ctl.stop();
    _ctl.value = 0;
    _mode = _Mode.idle;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final k = _k;
    // Фон под уменьшающимся содержимым — цвет фона приложения.
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return ColoredBox(
      color: bg,
      child: Opacity(
        opacity: (1 - k).clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 1 - 0.15 * k,
          alignment: Alignment.bottomRight,
          child: widget.child,
        ),
      ),
    );
  }
}
