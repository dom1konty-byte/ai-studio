import 'dart:io';
import 'dart:typed_data';

final List<int> _crcTable = () {
  final t = List<int>.filled(256, 0);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    t[n] = c;
  }
  return t;
}();

int _crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

void _u32(BytesBuilder b, int v) =>
    b.add([(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);

void _chunk(BytesBuilder out, String type, List<int> data) {
  _u32(out, data.length);
  final body = [...type.codeUnits, ...data];
  out.add(body);
  _u32(out, _crc32(body));
}

/// Кодирует RGBA (по 4 байта на пиксель, строки сверху вниз) в PNG.
/// Нужен для значков программ: Image.memory понимает PNG на любой платформе.
Uint8List encodePngRgba(int width, int height, Uint8List rgba) {
  if (width <= 0 || height <= 0 || rgba.length != width * height * 4) {
    throw ArgumentError('размер данных не совпадает с размером картинки');
  }
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0); // фильтр «без фильтра»
    raw.add(Uint8List.sublistView(rgba, y * width * 4, (y + 1) * width * 4));
  }
  final out = BytesBuilder()..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final head = BytesBuilder();
  _u32(head, width);
  _u32(head, height);
  head.add([8, 6, 0, 0, 0]); // 8 бит, RGBA
  _chunk(out, 'IHDR', head.toBytes());
  _chunk(out, 'IDAT', ZLibEncoder().convert(raw.toBytes()));
  _chunk(out, 'IEND', const []);
  return out.toBytes();
}
