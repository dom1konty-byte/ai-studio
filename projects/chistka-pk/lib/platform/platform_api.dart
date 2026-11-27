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
}
