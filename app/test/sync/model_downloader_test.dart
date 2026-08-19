/// Política do download do modelo: o portão de 3 GB e a garantia de que
/// nenhuma falha vira exceção.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/core/disk_space.dart';
import 'package:guia_ubs/sync/model_downloader.dart';
import 'package:guia_ubs/sync/resumable_downloader.dart';

/// Downloader falso: substitui a rede por um desfecho escolhido no teste.
class _FakeDownloader implements ResumableDownloader {
  _FakeDownloader(this._outcome);

  final DownloadOutcome Function(File destination) _outcome;
  int calls = 0;

  @override
  Future<DownloadOutcome> fetch({
    required Uri url,
    required File destination,
    required String expectedSha256,
    DownloadProgress? onProgress,
    int fallbackTotalBytes = 0,
  }) async {
    calls++;
    return _outcome(destination);
  }

  @override
  void close() {}

  @override
  Duration get idleTimeout => Duration.zero;

  @override
  Duration get connectTimeout => Duration.zero;
}

void main() {
  late Directory tmp;

  final payload = utf8.encode('modelo falso');
  final hash = sha256.convert(payload).toString();

  setUp(() => tmp = Directory.systemTemp.createTempSync('gubs_md_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  ModelArtifact artifact() => ModelArtifact(
        url: 'http://example.invalid/modelo.gguf',
        sha256: hash,
        sizeBytes: payload.length,
        fileName: 'modelo.gguf',
      );

  test('espaço insuficiente impede QUALQUER byte de rede', () async {
    // O ponto do portão não é falhar bonito: é não começar. Um download de
    // 1,2 GB que enche o armazenamento e morre no fim é o pior desfecho.
    final fake = _FakeDownloader((f) => DownloadCompleted(f, bytes: 0));
    final downloader = ModelDownloader(
      artifact: artifact(),
      destination: File('${tmp.path}/modelo.gguf'),
      downloader: fake,
      requiredFreeBytes: 1 << 62, // exigência impossível
    );

    final result = await downloader.ensureAvailable();

    expect(result, isA<ModelUnavailable>());
    expect((result as ModelUnavailable).reason,
        ModelUnavailableReason.insufficientDiskSpace);
    expect(fake.calls, 0, reason: 'nao pode nem tentar');
  });

  test('modelo já presente ignora o portão de disco', () async {
    // Recusar por falta de espaço um modelo que JÁ está em disco desligaria o
    // SLM justamente em aparelhos onde ele funcionava — sem liberar um byte.
    final dest = File('${tmp.path}/modelo.gguf')..writeAsBytesSync(payload);
    final fake =
        _FakeDownloader((f) => DownloadCompleted(f, bytes: payload.length));

    final result = await ModelDownloader(
      artifact: artifact(),
      destination: dest,
      downloader: fake,
      requiredFreeBytes: 1 << 62,
    ).ensureAvailable();

    expect(result, isA<ModelReady>());
    expect(fake.calls, 1, reason: 'segue para a verificacao de integridade');
  });

  test('espaço suficiente libera o download', () async {
    final fake = _FakeDownloader((f) => DownloadCompleted(f, bytes: 12));

    final result = await ModelDownloader(
      artifact: artifact(),
      destination: File('${tmp.path}/modelo.gguf'),
      downloader: fake,
      requiredFreeBytes: 1024, // 1 KB: qualquer disco tem
    ).ensureAvailable();

    expect(result, isA<ModelReady>());
    expect(fake.calls, 1);
  });

  test('interrupção preserva o progresso e não é permanente', () async {
    final fake = _FakeDownloader(
      (_) =>
          const DownloadInterrupted(bytesSoFar: 4096, reason: 'janela fechou'),
    );

    final result = await ModelDownloader(
      artifact: artifact(),
      destination: File('${tmp.path}/modelo.gguf'),
      downloader: fake,
      requiredFreeBytes: 1024,
    ).ensureAvailable();

    expect((result as ModelUnavailable).reason,
        ModelUnavailableReason.interrupted);
    expect(result.bytesSoFar, 4096);
  });

  test('rejeição por hash é reportada como permanente', () async {
    final fake =
        _FakeDownloader((_) => const DownloadRejected('SHA-256 nao confere'));

    final result = await ModelDownloader(
      artifact: artifact(),
      destination: File('${tmp.path}/modelo.gguf'),
      downloader: fake,
      requiredFreeBytes: 1024,
    ).ensureAvailable();

    expect((result as ModelUnavailable).reason, ModelUnavailableReason.rejected);
  });

  group('checkDiskSpace', () {
    test('mede algo plausível no diretório temporário', () {
      final free = freeDiskBytes(tmp.path);
      // Em plataforma sem statvfs devolve null — resposta válida, não falha.
      if (free != null) {
        expect(free, greaterThan(0));
        expect(free, lessThan(1 << 50), reason: 'sanidade: menos de 1 PB');
      }
    });

    test('exigência impossível reprova; exigência trivial aprova', () {
      final impossible = checkDiskSpace(tmp.path, requiredBytes: 1 << 62);
      final trivial = checkDiskSpace(tmp.path, requiredBytes: 1);

      // Onde não há statvfs ambos são `unknown` — e `unknown` não bloqueia.
      if (impossible != DiskSpaceVerdict.unknown) {
        expect(impossible, DiskSpaceVerdict.insufficient);
        expect(trivial, DiskSpaceVerdict.sufficient);
      }
    });

    test('caminho inexistente não lança', () {
      expect(() => checkDiskSpace('/caminho/que/nao/existe/nunca'),
          returnsNormally);
    });
  });
}
