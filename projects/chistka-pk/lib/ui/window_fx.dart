import 'dart:async';

import 'package:material_ui/material_ui.dart';

/// Анимация содержимого окна внутри Flutter (вместе с системным AnimateWindow):
/// открытие 0,94 → 1 за 320 мс (easeOutCubic), закрытие 1 → 0,92 за 280 мс
/// (easeInCubic). Окно при этом не двигается.
class WindowFx {
  _WindowFxHostState? _host;

  /// Нет хоста (тесты, до runApp) или включено «Убрать анимации» — сразу готово.
  Future<void> playHide() => _host?._run(hide: true) ?? Future.value();
  Future<void> playShow() => _host?._run(hide: false) ?? Future.value();

  /// До показа окна: содержимое в начальном масштабе 0,94.
  void prepareShow() => _host?._prepareShow();

  /// После hide / после показа: содержимое в обычном виде.
  void reset() => _host?._reset();

  /// Текущая степень «спрятанности» 0..1 (для тестов).
  double get amount => _host?._k ?? 0;
}

final windowFx = WindowFx();

const windowFxShowDuration = Duration(milliseconds: 320);
const windowFxHideDuration = Duration(milliseconds: 280);
const windowFxShowScale = 0.94;
const windowFxHideScale = 0.92;

class WindowFxHost extends StatefulWidget {
  const WindowFxHost({super.key, required this.child, this.fx});
  final Widget child;
  final WindowFx? fx;

  @override
  State<WindowFxHost> createState() => _WindowFxHostState();
}

enum _Mode { idle, hide, show }

class _WindowFxHostState extends State<WindowFxHost> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(vsync: this);
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
      await _ctl
          .animateTo(1,
              duration: hide ? windowFxHideDuration : windowFxShowDuration,
              curve: Curves.linear)
          .orCancel;
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

  double get _scale {
    switch (_mode) {
      case _Mode.idle:
        return 1;
      case _Mode.hide:
        return 1 - (1 - windowFxHideScale) * _k;
      case _Mode.show:
        return 1 - (1 - windowFxShowScale) * _k;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Фон под уменьшающимся содержимым — цвет фона приложения.
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return ColoredBox(
      color: bg,
      child: Transform.scale(scale: _scale, child: widget.child),
    );
  }
}
