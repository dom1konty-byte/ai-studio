/// Всё, что зависит от Windows, спрятано за этим интерфейсом (в тестах — фейк).
abstract class PlatformApi {
  /// Перемещает файл в Корзину. true — получилось.
  Future<bool> moveToRecycleBin(String path);

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
}
