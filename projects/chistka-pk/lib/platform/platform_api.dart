import '../core/programs.dart';

/// Результат запуска программы удаления.
class UninstallRun {
  const UninstallRun({required this.started, this.cancelled = false, this.exitCode, this.error});

  /// Процесс запущен (и завершился — запуск ждёт окончания).
  final bool started;

  /// Пользователь отказал в запросе прав администратора (UAC).
  final bool cancelled;
  final int? exitCode;
  final String? error;
}

/// Всё, что зависит от Windows, спрятано за этим интерфейсом (в тестах — фейк).
abstract class PlatformApi {
  /// Отправляет файлы в Корзину ОДНИМ пакетным вызовом. Файл, который нельзя
  /// безопасно отправить (диск не локальный, нет Корзины и т.п.), пропускается.
  /// Результат по каждому пути: null — файл в Корзине, строка — причина пропуска.
  Future<Map<String, String?>> moveToRecycleBin(List<String> paths);

  /// Размер и число элементов в Корзине (null — не удалось узнать).
  Future<({int bytes, int items})?> recycleBinInfo();

  /// Очищает Корзину. true — получилось.
  Future<bool> emptyRecycleBin();

  /// Свободно/всего на диске, например `C:\`.
  Future<({int free, int total})?> diskSpace(String root);

  /// Названия запущенных браузеров (Chrome, Edge, Firefox, Яндекс).
  Future<List<String>> runningBrowsers();

  /// Путь Steam из реестра (null — не найден).
  Future<String?> steamPath();

  /// Открывает текстовый файл в Блокноте.
  Future<void> openFile(String path);

  /// Открывает папку в Проводнике.
  Future<void> openFolder(String path);

  /// Записи разделов Uninstall: HKCU, HKLM, HKLM\WOW6432Node (только чтение).
  Future<List<RawUninstall>> readUninstallEntries();

  /// Имена подключей ключа вида `HKCU\Software` (пусто, если нет ключа/доступа).
  Future<List<String>> regSubKeys(String key);

  /// Запускает программу удаления через ShellExecute (Windows сама покажет UAC)
  /// и ждёт её завершения.
  Future<UninstallRun> runUninstaller(String exe, String args);

  /// `reg.exe export <ключ> <файл> /y`. true — файл создан.
  Future<bool> exportRegKey(String key, String file);

  /// `reg.exe delete <ключ> /f`. true — ключ удалён.
  Future<bool> deleteRegKey(String key);
}
