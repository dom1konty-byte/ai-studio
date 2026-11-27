import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/update.dart';

/// Сеть обновлений за интерфейсом: в тестах подменяется фейком.
abstract class UpdateNetwork {
  /// Свежий подходящий релиз или null, если релизов нет. Ошибка сети — исключение.
  Future<UpdateInfo?> fetchLatest();

  /// Текст небольшого файла (.sha256).
  Future<String> fetchText(Uri url);

  /// Скачивает файл в [dest]; [onProgress] получает (скачано, всего или -1).
  Future<void> download(Uri url, File dest, void Function(int received, int total) onProgress);
}

class UpdateException implements Exception {
  UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

class HttpUpdateNetwork implements UpdateNetwork {
  HttpUpdateNetwork({required this.version, this.timeout = const Duration(seconds: 15)});
  final String version;
  final Duration timeout;

  HttpClient _client() => HttpClient()
    ..connectionTimeout = timeout
    ..userAgent = 'ChistoDisk/$version';

  /// GET с ручным следованием перенаправлениям: каждый адрес должен быть безопасным.
  Future<HttpClientResponse> _get(HttpClient client, Uri url, {bool api = false}) async {
    var cur = url;
    for (var hop = 0; hop < 6; hop++) {
      if (!api && !isSafeDownloadUrl(cur)) {
        throw UpdateException('Небезопасный адрес загрузки');
      }
      final req = await client.getUrl(cur).timeout(timeout);
      req.followRedirects = false;
      if (api) req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final resp = await req.close().timeout(timeout);
      if (resp.isRedirect) {
        final loc = resp.headers.value(HttpHeaders.locationHeader);
        await resp.drain<void>();
        if (loc == null) throw UpdateException('Пустое перенаправление');
        cur = cur.resolve(loc);
        api = false; // после перенаправления — уже загрузка, проверяем хост
        continue;
      }
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        throw UpdateException('Сервер ответил ${resp.statusCode}');
      }
      return resp;
    }
    throw UpdateException('Слишком много перенаправлений');
  }

  @override
  Future<UpdateInfo?> fetchLatest() async {
    final c = _client();
    try {
      final resp = await _get(c, releasesApiUrl, api: true);
      final body = await resp.transform(utf8.decoder).join().timeout(timeout);
      return pickLatestFromBody(body);
    } finally {
      c.close(force: true);
    }
  }

  @override
  Future<String> fetchText(Uri url) async {
    final c = _client();
    try {
      final resp = await _get(c, url);
      return await resp.transform(utf8.decoder).join().timeout(timeout);
    } finally {
      c.close(force: true);
    }
  }

  @override
  Future<void> download(Uri url, File dest, void Function(int received, int total) onProgress) async {
    final c = _client();
    try {
      final resp = await _get(c, url);
      await dest.parent.create(recursive: true);
      final sink = dest.openWrite();
      var got = 0;
      try {
        await for (final chunk in resp.timeout(timeout)) {
          sink.add(chunk);
          got += chunk.length;
          onProgress(got, resp.contentLength);
        }
      } finally {
        await sink.close();
      }
    } finally {
      c.close(force: true);
    }
  }
}
