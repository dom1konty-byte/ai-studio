import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/setup_service.dart';

enum InstallRun { idle, running, ok, failed }

class ToolItem {
  ToolItem(this.spec);

  final ToolSpec spec;
  bool installed = false;
  bool selected = false;
  InstallRun run = InstallRun.idle;
  String log = '';

  /// «через winget», «скачиваю с официального сайта» и т. п.
  String status = '';

  /// Процент скачивания (null — неизвестно).
  int? percent;

  String get statusText =>
      percent == null ? status : '$status $percent%';
}

/// Мастер первого запуска: 4 шага (программы, GitHub, Claude, папка студии).
class WizardController extends ChangeNotifier {
  WizardController({
    required this.service,
    required this.defaultFolder,
    String? initialFolder,
    required this.onFinish,
    this.copyText,
  }) : folder = (initialFolder == null || initialFolder.isEmpty)
            ? defaultFolder
            : initialFolder;

  final SetupService service;
  final String defaultFolder;

  /// Закрыть мастер: передать выбранную папку приложению. true — закрылся.
  final Future<bool> Function(String folder) onFinish;

  /// Положить текст в буфер обмена (в тестах не задаётся).
  final void Function(String text)? copyText;

  final List<ToolItem> tools = [for (final s in toolSpecs) ToolItem(s)];
  final _touched = <String>{};

  bool wingetOk = true;
  bool busy = false;
  bool checking = false;
  int step = 0;

  String installMessage = '';
  String ghMessage = '';
  String ghCode = '';
  String ghError = '';
  bool ghLoginRunning = false;
  GhLoginSession? _ghSession;
  bool ghOk = false;
  String claudeMessage = '';
  LoginState claudeState = LoginState.no;

  String repoSlug = defaultRepoSlug;
  String folder;
  FolderState folderState = FolderState.invalid;
  bool identityOk = false;
  String folderMessage = '';
  String finishMessage = '';

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final s = _ghSession;
    if (s != null) unawaited(s.cancel());
    super.dispose();
  }

  ToolItem tool(String id) => tools.firstWhere((t) => t.spec.id == id);

  bool get programsDone =>
      tools.every((t) => t.installed || !t.spec.mandatory);
  bool get ghDone => tool('gh').installed && ghOk;
  bool get claudeDone =>
      tool('claude').installed && claudeState != LoginState.no;
  bool get folderDone => folderState == FolderState.ready && identityOk;
  bool get allDone => programsDone && ghDone && claudeDone && folderDone;

  List<bool> get stepsDone => [programsDone, ghDone, claudeDone, folderDone];

  bool get hasSelection => tools.any((t) => t.selected && !t.installed);

  void goTo(int i) {
    if (i < 0 || i > 3) return;
    step = i;
    notifyListeners();
  }

  void toggle(String id, bool value) {
    final t = tool(id);
    if (t.installed || busy) return;
    _touched.add(id);
    t.selected = value;
    notifyListeners();
  }

  /// Проверить всё заново (после установки, входа, смены папки).
  Future<void> refresh({bool pickStep = false}) async {
    if (checking) return;
    checking = true;
    notifyListeners();
    try {
      await service.refreshEnvironment();
      wingetOk = await service.hasWinget();
      for (final t in tools) {
        t.installed = await service.isInstalled(t.spec.id);
        if (t.installed) {
          t.selected = false;
          if (t.run != InstallRun.idle) t.run = InstallRun.ok;
        } else if (!_touched.contains(t.spec.id)) {
          t.selected = true;
        }
      }
      ghOk = tool('gh').installed && await service.ghAuthOk();
      claudeState = tool('claude').installed
          ? await service.claudeLogin()
          : LoginState.no;
      await _checkFolder();
      if (pickStep) {
        final i = stepsDone.indexWhere((d) => !d);
        step = i < 0 ? 0 : i;
      }
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  // ---------- Шаг 1 ----------

  /// Повторить установку одной программы.
  Future<void> retry(String id) => installSelected(only: id);

  Future<void> installSelected({String? only}) async {
    if (busy) return;
    final queue = tools
        .where((t) => (only == null ? t.selected : t.spec.id == only) && !t.installed)
        .toList();
    if (queue.isEmpty) return;
    busy = true;
    installMessage = '';
    for (final t in queue) {
      t.run = InstallRun.idle;
      t.log = '';
    }
    notifyListeners();
    try {
      for (final t in queue) {
        t.run = InstallRun.running;
        t.log = 'Устанавливается… Может появиться окно Windows с вопросом — '
            'нажми «Да».';
        notifyListeners();
        var ok = false;
        t.status = '';
        t.percent = null;
        if (wingetOk) {
          t.status = 'через winget';
          notifyListeners();
          final r = await service.wingetInstall(t.spec);
          t.log = shortLog(r);
          ok = r.ok;
        }
        if (!ok) {
          final wingetLog = wingetOk ? t.log : '';
          t.log = 'Windows может спросить разрешение — нажми «Да».';
          notifyListeners();
          final err = await service.directInstall(t.spec.id, (s, pct) {
            t.status = s;
            t.percent = pct;
            notifyListeners();
          });
          t.percent = null;
          ok = err == null;
          t.log = ok
              ? ''
              : [if (wingetLog.isNotEmpty) wingetLog, err].join('\n');
        }
        if (!ok && t.spec.id == 'claude') {
          await service.refreshEnvironment();
          if (await service.isInstalled('node')) {
            t.status = 'через Node.js (npm)';
            t.log = 'Другой способ: через Node.js…';
            notifyListeners();
            final r = await service.npmInstallClaude();
            t.log = shortLog(r);
            ok = r.ok;
          } else {
            t.log = '${t.log}\nДля другого способа сначала нужен Node.js.'.trim();
          }
        }
        if (ok) await service.refreshEnvironment();
        t.status = '';
        t.run = ok ? InstallRun.ok : InstallRun.failed;
        notifyListeners();
      }
    } finally {
      busy = false;
    }
    await refresh();
    final failed = tools.where((t) => t.run == InstallRun.failed && !t.installed);
    final notSeen = tools.where((t) => t.run == InstallRun.ok && !t.installed);
    if (failed.isNotEmpty) {
      installMessage = 'Не получилось: ${failed.map((t) => t.spec.title).join(', ')}. '
          'Можно нажать «Установить выбранное» ещё раз.';
    } else if (notSeen.isNotEmpty) {
      installMessage = 'Поставилось, но Рубка пока не видит: '
          '${notSeen.map((t) => t.spec.title).join(', ')}. '
          'Закрой и снова открой Рубку.';
    } else {
      installMessage = 'Готово.';
    }
    notifyListeners();
  }

  // ---------- Шаг 2 ----------

  /// Вход в GitHub: код показываем в мастере, процесс ждём до конца.
  Future<void> startGhLogin() async {
    if (busy || ghLoginRunning) return;
    if (!tool('gh').installed) {
      ghMessage = 'Сначала поставь GitHub CLI (шаг «Программы»).';
      notifyListeners();
      return;
    }
    busy = true;
    ghMessage = '';
    ghCode = '';
    ghError = '';
    notifyListeners();
    try {
      if (await service.ghAuthOk()) {
        await _finishGhLogin();
        return;
      }
      ghLoginRunning = true;
      ghMessage = 'Запускаю вход…';
      notifyListeners();
      final session = await service.startGhLogin((code) {
        ghCode = code;
        ghMessage = '';
        copyText?.call(code);
        unawaited(service.openGithubDevice());
        notifyListeners();
      });
      _ghSession = session;
      final err = await session.result;
      _ghSession = null;
      ghLoginRunning = false;
      if (err != null) {
        ghError = err;
        ghMessage = '';
        ghCode = '';
      } else {
        await _finishGhLogin();
      }
    } finally {
      ghLoginRunning = false;
      _ghSession = null;
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _finishGhLogin() async {
    ghOk = await service.ghAuthOk();
    ghCode = '';
    if (!ghOk) {
      ghError = 'GitHub не подтвердил вход. Попробуй снова.';
      ghMessage = '';
      return;
    }
    final r = await service.ghSetupGit();
    ghMessage = r.ok
        ? 'Вход выполнен.'
        : 'Вход выполнен, но настроить Git не вышло: ${shortLog(r)}';
    await _checkFolder();
  }

  Future<void> cancelGhLogin() async {
    await _ghSession?.cancel();
  }

  /// Скопировать код ещё раз.
  void copyGhCode() {
    if (ghCode.isNotEmpty) copyText?.call(ghCode);
  }

  void openGhDevicePage() {
    unawaited(service.openGithubDevice());
  }

  Future<void> checkGh() async {
    if (busy || !tool('gh').installed) return;
    busy = true;
    notifyListeners();
    try {
      ghOk = await service.ghAuthOk();
      if (ghOk) {
        final r = await service.ghSetupGit();
        ghMessage = r.ok
            ? 'Вход выполнен.'
            : 'Вход выполнен, но настроить Git не вышло: ${shortLog(r)}';
        await _checkFolder();
      } else {
        ghMessage = 'Входа пока нет. Закончи вход в окне и нажми «Проверить».';
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  // ---------- Шаг 3 ----------

  Future<void> launchClaudeLogin() async {
    if (!tool('claude').installed) {
      claudeMessage = 'Сначала поставь Claude Code (шаг «Программы»).';
      notifyListeners();
      return;
    }
    final r = await service.launchClaudeLogin();
    claudeMessage = r.error ??
        (r.plain
            ? 'Открылось чёрное окно. Напиши в нём /login и войди по подсказке. '
                'Потом вернись сюда и нажми «Проверить».'
            : 'Открылось чёрное окно. Войди по подсказке в окне и в браузере. '
                'Потом вернись сюда и нажми «Проверить».');
    notifyListeners();
  }

  Future<void> checkClaude() async {
    if (busy || !tool('claude').installed) return;
    busy = true;
    notifyListeners();
    try {
      claudeState = await service.claudeLogin();
      claudeMessage = switch (claudeState) {
        LoginState.yes => 'Вход выполнен.',
        LoginState.unknown => 'Эта версия не умеет проверять вход. Если Рубка '
            'потом не отвечает — открой окно с командой claude и войди (/login).',
        LoginState.no => 'Входа пока нет. Закончи вход в окне и нажми «Проверить».',
      };
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  // ---------- Шаг 4 ----------

  void setRepoSlug(String v) {
    repoSlug = v.trim();
    notifyListeners();
  }

  /// Новая папка (поле «Указать папку вручную») и проверка.
  Future<void> setFolder(String v) async {
    if (busy) return;
    folder = v.trim().isEmpty ? defaultFolder : v.trim();
    await checkFolder();
  }

  Future<void> checkFolder() async {
    if (busy) return;
    busy = true;
    notifyListeners();
    try {
      await _checkFolder();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _checkFolder() async {
    folderState = await service.inspectFolder(folder);
    identityOk = false;
    switch (folderState) {
      case FolderState.invalid:
        folderMessage = r'Путь неверный. Нужен полный путь, например C:\Users\Имя\ai-studio.';
      case FolderState.foreign:
        folderMessage = 'Папка уже есть, но это не студия. Выбери другую '
            '(«Указать папку вручную»).';
      case FolderState.needsClone:
        folderMessage = 'Студии в этой папке пока нет — её можно скачать.';
      case FolderState.ready:
        identityOk = await service.hasGitIdentity();
        String? err;
        if (!identityOk && ghOk) {
          err = await service.ensureGitIdentity();
          identityOk = err == null;
        }
        if (identityOk) {
          folderMessage = 'Студия на месте, Git настроен.';
        } else {
          folderMessage = err ??
              'Студия на месте, но Git не знает твоё имя. '
                  'Войди в GitHub (шаг 2) — имя заполнится само.';
        }
    }
  }

  Future<void> downloadStudio() async {
    if (busy) return;
    if (!ghDone) {
      folderMessage = 'Сначала войди в GitHub (шаг 2).';
      notifyListeners();
      return;
    }
    busy = true;
    folderMessage = 'Скачиваю студию… это может занять минуту.';
    notifyListeners();
    try {
      final err = await service.cloneStudio(repoSlug, folder);
      await _checkFolder();
      if (err != null) folderMessage = err;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  // ---------- Конец ----------

  Future<void> finish() async {
    if (busy || !allDone) return;
    busy = true;
    finishMessage = '';
    notifyListeners();
    try {
      final closed = await onFinish(folder);
      if (!closed) {
        finishMessage = 'Рубка ещё не видит всё нужное. Закрой и снова '
            'открой Рубку, потом нажми «Готово».';
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
