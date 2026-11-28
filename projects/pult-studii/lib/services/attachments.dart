// Вложения чата: имена, лимиты, копирование в папку AI Studio.
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/safety.dart';

/// Не больше файлов в одном сообщении.
const maxAttachments = 10;

/// Не больше байт в одном файле (20 МБ).
const maxAttachmentBytes = 20 * 1024 * 1024;

/// Не больше символов в имени файла.
const maxAttachmentNameLength = 80;

/// Что-то не так с вложением (текст показываем в красном чипе).
class AttachmentException implements Exception {
  AttachmentException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Скопированный файл вложения.
class Attachment {
  const Attachment(this.path, this.name, this.size);

  final String path;
  final String name;
  final int size;

  bool get isImage => isImagePath(path);
}

final _badNameChars = RegExp(r'[^A-Za-z0-9._а-яА-Я-]');
final _imageRe = RegExp(r'\.(png|jpe?g|gif|webp|bmp)$', caseSensitive: false);
final _openableRe = RegExp(
    r'\.(png|jpe?g|gif|webp|bmp|pdf|txt|md|csv|json|log|rtf|docx?|xlsx?|pptx?)$',
    caseSensitive: false);

/// Безопасное имя: только `A-Za-z0-9._-` и русские буквы, не длиннее 80.
String safeAttachmentName(String name) {
  var n = name.split(RegExp(r'[\\/]')).last;
  n = n.replaceAll(_badNameChars, '_');
  n = n.replaceFirst(RegExp(r'^[.-]+'), '');
  n = n.replaceFirst(RegExp(r'\.+$'), '');
  if (n.length > maxAttachmentNameLength) {
    final dot = n.lastIndexOf('.');
    final ext = dot > 0 && n.length - dot <= 12 ? n.substring(dot) : '';
    n = n.substring(0, maxAttachmentNameLength - ext.length) + ext;
    n = n.replaceFirst(RegExp(r'\.+$'), '');
  }
  return n.isEmpty ? 'file' : n;
}

String _two(int v) => v.toString().padLeft(2, '0');

/// `20261128-101530`.
String attachmentStamp(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}${_two(t.month)}${_two(t.day)}-'
    '${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';

/// Папка чата в папке вложений: безопасное имя из ключа чата.
String attachmentChatDir(String root, String chatKey) {
  var k = chatKey.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  if (k.isEmpty || RegExp(r'^\.+$').hasMatch(k)) k = '_';
  return p.join(root, k);
}

bool isImagePath(String path) => _imageRe.hasMatch(path);

/// Такой файл можно открывать через Проводник (не программа и не скрипт).
bool isOpenableAttachment(String path) => _openableRe.hasMatch(path);

/// Блок для директора: полные пути, которые он откроет инструментом Read.
String attachmentsBlock(List<String> paths) =>
    'Вложения (открой инструментом Read):\n${paths.map((x) => '- $x').join('\n')}';

/// Папку можно передать в `--add-dir` (полный путь без спецсимволов оболочки).
bool isSafeAddDir(String dir) =>
    isSafeLaunchPath(dir) &&
    (p.isAbsolute(dir) || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(dir));

/// Размер файла словами: «12 КБ», «3,4 МБ».
String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} КБ';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} МБ';
}

/// Расширение картинки из буфера обмена по первым байтам.
String imageExtension(List<int> b) {
  if (b.length >= 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E) {
    return 'png';
  }
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return 'jpg';
  }
  if (b.length >= 3 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
    return 'gif';
  }
  if (b.length >= 2 && b[0] == 0x42 && b[1] == 0x4D) return 'bmp';
  return 'png';
}

/// Куда копируются вложения (подменяется в тестах).
abstract class AttachmentStore {
  /// Корневая папка вложений (`%APPDATA%\pult-studii\attachments`).
  String get root;

  /// Папка вложений одного чата.
  String dirFor(String chatKey);

  /// Скопировать файл [srcPath] в папку чата.
  Future<Attachment> addFile(String chatKey, String srcPath);

  /// Сохранить байты (картинка из буфера) под именем [name].
  Future<Attachment> addBytes(String chatKey, String name, List<int> bytes);
}

class FileAttachmentStore implements AttachmentStore {
  FileAttachmentStore(this.root, {DateTime Function()? clock})
      : _now = clock ?? DateTime.now;

  @override
  final String root;
  final DateTime Function() _now;

  @override
  String dirFor(String chatKey) => attachmentChatDir(root, chatKey);

  Future<File> _target(String chatKey, String name) async {
    final dir = dirFor(chatKey);
    if (!isSafeAddDir(dir)) {
      throw AttachmentException(
          'в пути к папке вложений есть недопустимые символы');
    }
    await Directory(dir).create(recursive: true);
    final base = '${attachmentStamp(_now())}_';
    final safe = safeAttachmentName(name);
    var f = File(p.join(dir, '$base$safe'));
    for (var i = 2; await f.exists(); i++) {
      f = File(p.join(dir, '$base${i}_$safe'));
    }
    return f;
  }

  @override
  Future<Attachment> addFile(String chatKey, String srcPath) async {
    final type = await FileSystemEntity.type(srcPath);
    if (type != FileSystemEntityType.file) {
      throw AttachmentException(type == FileSystemEntityType.directory
          ? 'это папка, а не файл'
          : 'файл не найден');
    }
    final src = File(srcPath);
    final size = await src.length();
    if (size > maxAttachmentBytes) throw AttachmentException('больше 20 МБ');
    final dest = await _target(chatKey, p.basename(srcPath));
    await src.copy(dest.path);
    return Attachment(dest.path, p.basename(dest.path), size);
  }

  @override
  Future<Attachment> addBytes(
      String chatKey, String name, List<int> bytes) async {
    if (bytes.length > maxAttachmentBytes) {
      throw AttachmentException('больше 20 МБ');
    }
    final dest = await _target(chatKey, name);
    await dest.writeAsBytes(bytes, flush: true);
    return Attachment(dest.path, p.basename(dest.path), bytes.length);
  }
}
