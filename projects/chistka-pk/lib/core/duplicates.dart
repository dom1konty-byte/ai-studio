import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'fs_walk.dart';
import 'hidden.dart';
import 'models.dart';

/// Файлы меньше 1 МБ в поиске дубликатов не участвуют.
const minDuplicateSize = 1024 * 1024;

/// Сколько читать с начала и с конца файла для частичного хеша.
const partialHashChunk = 64 * 1024;

/// Группа одинаковых файлов. [files] отсортированы так, что первый — тот, что
/// остаётся по умолчанию: самая старая копия (по дате изменения), при равенстве —
/// с более коротким путём, затем по алфавиту.
class DupGroup {
  DupGroup(List<FileInfo> files) : files = (List.of(files)..sort(compareKeeper));
  final List<FileInfo> files;

  int get size => files.first.size;
  FileInfo get keeper => files.first;
  int get wasted => size * (files.length - 1);
}

int compareKeeper(FileInfo a, FileInfo b) {
  final d = a.modified.compareTo(b.modified);
  if (d != 0) return d;
  final l = a.path.length.compareTo(b.path.length);
  if (l != 0) return l;
  return a.path.compareTo(b.path);
}

/// Текст прогресса поиска: «Ищу… N %».
String dupProgressText(int done, int total) {
  final pct = total <= 0 ? 0 : (done * 100 ~/ total).clamp(0, 100);
  return 'Ищу… $pct %';
}

/// Пропускает обновления не чаще раза в [every]; первое проходит сразу.
class ProgressThrottle {
  ProgressThrottle({this.every = const Duration(milliseconds: 200), DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;
  final Duration every;
  final DateTime Function() _clock;
  DateTime? _last;

  bool allow() {
    final now = _clock();
    final l = _last;
    if (l != null && now.difference(l) < every) return false;
    _last = now;
    return true;
  }
}

Digest? _hashParts(File f, int size, {required bool partial}) {
  RandomAccessFile? raf;
  try {
    raf = f.openSync();
    final out = _Sink();
    final conv = sha256.startChunkedConversion(out);
    conv.add(Uint8List.fromList('$size:'.codeUnits));
    if (partial) {
      if (size <= partialHashChunk * 2) {
        _readAll(raf, conv);
      } else {
        conv.add(raf.readSync(partialHashChunk));
        raf.setPositionSync(size - partialHashChunk);
        conv.add(raf.readSync(partialHashChunk));
      }
    } else {
      _readAll(raf, conv);
    }
    conv.close();
    return out.value;
  } catch (_) {
    return null; // файл пропал или не читается — пропускаем
  } finally {
    try {
      raf?.closeSync();
    } catch (_) {}
  }
}

void _readAll(RandomAccessFile raf, Sink<List<int>> sink) {
  while (true) {
    final b = raf.readSync(1024 * 1024);
    if (b.isEmpty) break;
    sink.add(b);
  }
}

class _Sink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest d) => value = d;
  @override
  void close() {}
}

/// Группировка: размер → частичный хеш → полный SHA-256 только для совпавших.
/// Синхронно (вызывать из Isolate). Группы по убыванию «лишнего».
List<DupGroup> groupDuplicatesSync(
  List<FileInfo> files, {
  void Function(String stage)? onStage,
  bool Function()? cancelled,
}) {
  bool stop() => cancelled?.call() ?? false;
  final bySize = <int, List<FileInfo>>{};
  for (final f in files) {
    (bySize[f.size] ??= []).add(f);
  }
  onStage?.call('Ищу… 0 %');
  final cand = bySize.values.where((l) => l.length > 1).toList();

  var n = 0;
  final total = cand.fold<int>(0, (a, l) => a + l.length);
  final groups = <DupGroup>[];
  for (final sameSize in cand) {
    if (stop()) return const [];
    final byPartial = <String, List<FileInfo>>{};
    for (final f in sameSize) {
      n++;
      if (n % 20 == 0) onStage?.call(dupProgressText(n, total));
      final h = _hashParts(File(f.path), f.size, partial: true);
      if (h != null) (byPartial[h.toString()] ??= []).add(f);
    }
    for (final part in byPartial.values) {
      if (part.length < 2) continue;
      if (stop()) return const [];
      final byFull = <String, List<FileInfo>>{};
      for (final f in part) {
        onStage?.call(dupProgressText(n, total));
        final h = _hashParts(File(f.path), f.size, partial: false);
        if (h != null) (byFull[h.toString()] ??= []).add(f);
      }
      for (final g in byFull.values) {
        if (g.length > 1) groups.add(DupGroup(g));
      }
    }
  }
  groups.sort((a, b) => b.wasted.compareTo(a.wasted));
  return groups;
}

/// Полный поиск (вызывать из Isolate): обход без ссылок, скрытые/системные
/// файлы и папки и файлы меньше [minSize] пропускаются.
List<DupGroup> scanDuplicatesSync(
  List<String> roots, {
  int minSize = minDuplicateSize,
  HiddenCheck hidden = isHiddenOrSystem,
  HiddenCheck cloudOnly = isCloudOnly,
  void Function(String stage)? onStage,
  bool Function()? cancelled,
}) {
  final files = <FileInfo>[];
  final seen = <String>{};
  var counter = 0;
  for (final r in roots) {
    final label = r.split(RegExp(r'[\\/]')).last;
    onStage?.call('Ищу файлы: $label…');
    walkTreeSync(Directory(r), (f) {
      if (++counter % 500 == 0) onStage?.call('Ищу файлы: ${files.length}…');
      try {
        if (hidden(f.path)) return;
        if (cloudOnly(f.path)) return; // облачный файл OneDrive: чтение скачало бы его
        final st = f.statSync();
        if (st.size < minSize) return;
        if (seen.add(f.path.toLowerCase())) files.add(FileInfo(f.path, st.size, st.modified));
      } catch (_) {}
    }, skipDir: (d) => hidden(d.path));
    if (cancelled?.call() ?? false) return const [];
  }
  return groupDuplicatesSync(files, onStage: onStage, cancelled: cancelled);
}

/// Поиск в отдельном Isolate; [cancel] останавливает его.
class DupScanJob {
  DupScanJob(this.result, this.cancel);
  final Future<List<DupGroup>> result;
  final void Function() cancel;
}

typedef DupScanner = DupScanJob Function(List<String> roots, void Function(String) onProgress);

class _Args {
  _Args(this.port, this.roots);
  final SendPort port;
  final List<String> roots;
}

void _worker(_Args a) {
  try {
    final th = ProgressThrottle();
    final res = scanDuplicatesSync(a.roots, onStage: (s) {
      if (th.allow()) a.port.send(s);
    });
    a.port.send(res);
  } catch (_) {
    a.port.send(0); // ошибка
  }
}

DupScanJob startDupScan(List<String> roots, void Function(String) onProgress) {
  final port = ReceivePort();
  final done = Completer<List<DupGroup>>();
  Isolate? iso;
  var cancelled = false;
  void finish() {
    port.close();
    iso?.kill(priority: Isolate.immediate);
  }

  Isolate.spawn(_worker, _Args(port.sendPort, roots)).then((i) {
    iso = i;
    if (cancelled) i.kill(priority: Isolate.immediate);
  }, onError: (Object e) {
    if (!done.isCompleted) done.completeError(e);
    port.close();
  });
  port.listen((m) {
    if (m is String) {
      onProgress(m);
    } else if (m is List<DupGroup>) {
      if (!done.isCompleted) done.complete(m);
      finish();
    } else {
      if (!done.isCompleted) done.completeError(StateError('scan failed'));
      finish();
    }
  });
  return DupScanJob(done.future, () {
    cancelled = true;
    if (!done.isCompleted) done.completeError(StateError('cancelled'));
    finish();
  });
}

// ---------- выбор копий ----------

/// По умолчанию отмечены все копии, кроме одной (первой в группе).
Set<String> defaultDupSelection(List<DupGroup> groups) =>
    {for (final g in groups) for (final f in g.files.skip(1)) f.path};

/// Отмечает/снимает [path]. Отметить последнюю неотмеченную копию нельзя: false.
bool trySelectDup(DupGroup g, Set<String> selected, String path, bool on) {
  if (!on) {
    selected.remove(path);
    return true;
  }
  if (!g.files.any((f) => f.path == path)) return false;
  final others = g.files.where((f) => f.path != path && !selected.contains(f.path));
  if (others.isEmpty) return false;
  selected.add(path);
  return true;
}

/// Единственная неотмеченная копия группы (её нельзя отметить), иначе null.
String? lockedDupPath(DupGroup g, Set<String> selected) {
  final free = g.files.where((f) => !selected.contains(f.path)).toList();
  return free.length == 1 ? free.first.path : null;
}

class DupDeletePlan {
  DupDeletePlan(this.files, this.skipped);
  final List<FileInfo> files;

  /// Сколько отмеченных файлов не пойдёт в удаление (изменились, пропали, нет оставшейся копии).
  final int skipped;
}

/// Дата изменения не сдвинулась (допуск 2 с: точность файловых систем разная).
bool sameModified(DateTime actual, DateTime expected) =>
    actual.difference(expected).abs() <= const Duration(seconds: 2);

bool _sameFile(FileInfo f) {
  try {
    if (FileSystemEntity.typeSync(f.path, followLinks: false) != FileSystemEntityType.file) {
      return false;
    }
    final file = File(f.path);
    if (file.lengthSync() != f.size) return false;
    return sameModified(file.lastModifiedSync(), f.modified);
  } catch (_) {
    return false;
  }
}

/// Перепроверка перед удалением. В группе всегда остаётся хотя бы одна копия:
/// если отмечены все, или ни одна из оставшихся не существует с прежним размером
/// — группа пропускается целиком. Удаляются только существующие файлы прежнего размера.
DupDeletePlan planDupDelete(List<DupGroup> groups, Set<String> selected,
    {bool Function(FileInfo f) check = _sameFile}) {
  final out = <FileInfo>[];
  var skipped = 0;
  for (final g in groups) {
    final sel = g.files.where((f) => selected.contains(f.path)).toList();
    if (sel.isEmpty) continue;
    final rest = g.files.where((f) => !selected.contains(f.path)).toList();
    if (rest.isEmpty || !rest.any(check)) {
      skipped += sel.length;
      continue;
    }
    for (final f in sel) {
      if (check(f)) {
        out.add(f);
      } else {
        skipped++;
      }
    }
  }
  return DupDeletePlan(out, skipped);
}
