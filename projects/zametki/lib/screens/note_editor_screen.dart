import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../models/note.dart';
import '../models/note_colors.dart';
import '../services/notes_service.dart';
import '../widgets/color_picker_sheet.dart';

/// Пауза после последней правки, через которую заметка сохраняется сама.
const _autosaveDelay = Duration(milliseconds: 1500);

class _Item {
  _Item(String text, this.checked, VoidCallback onChanged)
      : controller = TextEditingController(text: text) {
    controller.addListener(onChanged);
  }

  final TextEditingController controller;
  final FocusNode focus = FocusNode();
  final Key key = UniqueKey();
  bool checked;

  void dispose() {
    controller.dispose();
    focus.dispose();
  }
}

/// Редактор заметки. [noteId] == null и [initial] == null — новая заметка.
class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({super.key, required this.service, this.initial});

  final NotesService service;
  final Note? initial;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> with WidgetsBindingObserver {
  late Note _original;
  late final TextEditingController _title;
  late final TextEditingController _body;
  final List<_Item> _items = [];
  late bool _isChecklist;
  late int _color;
  late bool _pinned;
  int? _id;
  bool _deleted = false;
  Timer? _timer;
  Future<void> _saveQueue = Future.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _original = widget.initial ?? Note(updatedAt: DateTime.now());
    _id = _original.id;
    _title = TextEditingController(text: _original.title)..addListener(_scheduleSave);
    _body = TextEditingController(text: _original.body)..addListener(_scheduleSave);
    _isChecklist = _original.isChecklist;
    _color = _original.color;
    _pinned = _original.pinned;
    for (final i in _original.items) {
      _items.add(_Item(i.text, i.checked, _scheduleSave));
    }
    if (_isChecklist && _items.isEmpty) _items.add(_Item('', false, _scheduleSave));
    widget.service.registerFlusher(_flush);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    widget.service.unregisterFlusher(_flush);
    _title.removeListener(_scheduleSave);
    _body.removeListener(_scheduleSave);
    _title.dispose();
    _body.dispose();
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _flush();
    }
  }

  void _scheduleSave() {
    if (_deleted) return;
    _timer?.cancel();
    _timer = Timer(_autosaveDelay, _save);
  }

  /// Сохраняет сразу (отменяя ожидание автосохранения).
  Future<void> _flush() {
    _timer?.cancel();
    return _save();
  }

  Note _current() => Note(
        id: _id,
        title: _title.text,
        body: _isChecklist ? '' : _body.text,
        isChecklist: _isChecklist,
        items: _isChecklist
            ? [
                for (final i in _items)
                  if (i.controller.text.trim().isNotEmpty)
                    ChecklistItem(text: i.controller.text.trim(), checked: i.checked),
              ]
            : const [],
        color: _color,
        pinned: _pinned,
        updatedAt: _original.updatedAt,
      );

  /// Сохраняет, если есть что сохранять. Пустую заметку не создаём (а у старой — удаляем).
  /// Сохранения идут строго по очереди: иначе две вставки подряд создадут дубль.
  Future<void> _save() {
    final next = _saveQueue.then((_) => _doSave());
    _saveQueue = next;
    return next;
  }

  Future<void> _doSave() async {
    if (_deleted) return;
    final note = _current();
    try {
      if (note.isEmpty) {
        if (_id != null) {
          await widget.service.delete(_id!);
          _id = null;
          _original = note.copyWith(id: null);
        }
        return;
      }
      if (_id != null && note.sameContent(_original)) return;
      final saved = await widget.service.save(note);
      _id = saved.id;
      _original = saved;
    } catch (_) {
      if (mounted) {
        final cs = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: cs.errorContainer,
          content: Text('Не удалось сохранить. Попробуйте ещё раз',
              style: TextStyle(color: cs.onErrorContainer)),
        ));
      }
    }
  }

  Future<void> _saveAndClose() async {
    await _flush();
    if (mounted) Navigator.of(context).pop();
  }

  void _setChecklist(bool value) {
    if (value == _isChecklist) return;
    setState(() {
      if (value) {
        final items = Note.itemsFromText(_body.text);
        for (final i in _items) {
          i.dispose();
        }
        _items
          ..clear()
          ..addAll(items.map((e) => _Item(e.text, false, _scheduleSave)));
        if (_items.isEmpty) _items.add(_Item('', false, _scheduleSave));
      } else {
        _body.text = Note.textFromItems([
          for (final i in _items) ChecklistItem(text: i.controller.text, checked: i.checked),
        ]);
        for (final i in _items) {
          i.dispose();
        }
        _items.clear();
      }
      _isChecklist = value;
    });
  }

  void _toggleItem(_Item item, bool checked) {
    setState(() {
      item.checked = checked;
      _scheduleSave();
      // Отмеченные уходят вниз (порядок внутри групп сохраняется).
      final open = _items.where((e) => !e.checked).toList();
      final done = _items.where((e) => e.checked).toList();
      _items
        ..clear()
        ..addAll(open)
        ..addAll(done);
    });
  }

  void _addItem() {
    final item = _Item('', false, _scheduleSave);
    setState(() {
      final firstDone = _items.indexWhere((e) => e.checked);
      _items.insert(firstDone == -1 ? _items.length : firstDone, item);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => item.focus.requestFocus());
  }

  void _removeItem(_Item item) {
    setState(() {
      _items.remove(item);
      if (_items.isEmpty) _items.add(_Item('', false, _scheduleSave));
    });
    item.dispose();
    _scheduleSave();
  }

  Future<void> _pickColor() async {
    final picked = await showColorPicker(context, selected: _color);
    if (picked != null) {
      setState(() => _color = picked);
      _scheduleSave();
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return AlertDialog(
          title: const Text('Удалить заметку?'),
          content: const Text('Точно удалить? Вернуть будет нельзя.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) return;
    _timer?.cancel();
    await _saveQueue;
    if (!mounted) return;
    _deleted = true;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      if (_id != null) await widget.service.delete(_id!);
    } catch (_) {
      _deleted = false;
      messenger.showSnackBar(const SnackBar(content: Text('Не удалось удалить')));
      return;
    }
    navigator.pop();
    messenger.showSnackBar(const SnackBar(content: Text('Заметка удалена')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final textColor = NoteColors.text(brightness);
    final bg = NoteColors.background(_color, brightness);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _saveAndClose();
      },
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          scrolledUnderElevation: 0,
          leading: BackButton(onPressed: _saveAndClose),
          actions: [
            IconButton(
              tooltip: _pinned ? 'Открепить' : 'Закрепить',
              icon: Icon(_pinned ? Icons.push_pin : Icons.push_pin_outlined),
              color: _pinned ? theme.colorScheme.primary : null,
              onPressed: () {
                setState(() => _pinned = !_pinned);
                _scheduleSave();
              },
            ),
            IconButton(
              tooltip: 'Цвет',
              icon: const Icon(Icons.palette_outlined),
              onPressed: _pickColor,
            ),
            IconButton(
              tooltip: 'Удалить',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const Key('title_field'),
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(color: textColor, fontWeight: FontWeight.w500),
                  decoration: const InputDecoration(
                    hintText: 'Заголовок',
                    border: InputBorder.none,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Текст')),
                    ButtonSegment(value: true, label: Text('Чек-лист')),
                  ],
                  selected: {_isChecklist},
                  onSelectionChanged: (s) => _setChecklist(s.first),
                ),
                const SizedBox(height: 8),
                Expanded(child: _isChecklist ? _buildChecklist(theme, textColor) : _buildText(theme, textColor)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildText(ThemeData theme, Color textColor) {
    return TextField(
      key: const Key('body_field'),
      controller: _body,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      textCapitalization: TextCapitalization.sentences,
      style: theme.textTheme.bodyLarge?.copyWith(color: textColor),
      decoration: const InputDecoration(
        hintText: 'Текст заметки',
        border: InputBorder.none,
      ),
    );
  }

  Widget _buildChecklist(ThemeData theme, Color textColor) {
    return ListView(
      children: [
        for (final item in _items)
          Row(
            key: item.key,
            children: [
              Checkbox(
                value: item.checked,
                onChanged: (v) => _toggleItem(item, v ?? false),
              ),
              Expanded(
                child: TextField(
                  controller: item.controller,
                  focusNode: item.focus,
                  textCapitalization: TextCapitalization.sentences,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: item.checked ? textColor.withValues(alpha: 0.55) : textColor,
                    decoration: item.checked ? TextDecoration.lineThrough : null,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Пункт',
                    border: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Удалить пункт',
                icon: const Icon(Icons.close),
                onPressed: () => _removeItem(item),
              ),
            ],
          ),
        TextButton.icon(
          onPressed: _addItem,
          icon: const Icon(Icons.add),
          label: const Text('Пункт'),
          style: TextButton.styleFrom(alignment: Alignment.centerLeft),
        ),
      ],
    );
  }
}
