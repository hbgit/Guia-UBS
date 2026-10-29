/// Política do download do modelo: o portão de 3 GB e a garantia de que
/// nenhuma falha vira exceção.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/core/disk_space.dart';
import 'package:guia_ubs/sync/destination_lock.dart';
import 'package:guia_ubs/sync/endpoint_config.dart';
import 'package:guia_ubs/legal/terms.dart';
import 'package:guia_ubs/sync/model_background_sync.dart';
import 'package:guia_ubs/sync/model_downloader.dart';
import 'package:guia_ubs/sync/resumable_downloader.dart';

/// Downloader falso: substitui a rede por um desfecho escolhido no teste.
class _FakeDownloader implements ResumableDownloader {
  _FakeDownloader(this._outcome);

  final DownloadOutcome Function(File destination) _outcome;
  int calls = 0;

  @override
  String get writerLabel => 'fake';

  @override
  DownloadTrace? get trace => null;

  @override
  Duration get writerWait => Duration.zero;

  @override
  LockTiming get lockTiming => const LockTiming();

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
        _FakeDownloader((_) => const DownloadRejected('SHA-256 nao confere', kind: DownloadRejectionKind.digestMismatch));

    final result = await ModelDownloader(
      artifact: artifact(),
      destination: File('${tmp.path}/modelo.gguf'),
      downloader: fake,
      requiredFreeBytes: 1024,
    ).ensureAvailable();

    expect((result as ModelUnavailable).reason, ModelUnavailableReason.rejected);
  });

  test('modelo já verificado: o worker conclui sem rede (tarefa devolve true)',
      () async {
    // Configuração do worker (`model_background_sync.dart`): espera zero pela
    // trava. Com o modelo íntegro em disco, ele precisa terminar em
    // `ModelReady` — que o `runModelSyncTask` traduz em `true`, sem
    // reagendamento — e sem uma requisição sequer.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requests = 0;
    server.listen((r) {
      requests++;
      r.response
        ..statusCode = HttpStatus.internalServerError
        ..close();
    });
    final dest = File('${tmp.path}/modelo.gguf')..writeAsBytesSync(payload);
    final real = ResumableDownloader(writerLabel: 'worker');

    final downloader = ModelDownloader(
      artifact: ModelArtifact(
        url: 'http://${server.address.host}:${server.port}/modelo.gguf',
        sha256: hash,
        sizeBytes: payload.length,
        fileName: 'modelo.gguf',
      ),
      destination: dest,
      downloader: real,
      requiredFreeBytes: 1 << 62,
    );
    addTearDown(downloader.close);

    final result = await downloader.ensureAvailable();

    expect(result, isA<ModelReady>());
    expect(requests, 0);
  });

  group('build sem MODEL_URL (P1-1)', () {
    ModelArtifact semUrl() => ModelArtifact(
          url: '',
          sha256: hash,
          sizeBytes: payload.length,
          fileName: 'modelo.gguf',
        );

    test('em release, MODEL_URL http conta como nao configurada (#45)', () {
      expect(
        isUsableEndpoint(Uri.parse('http://h/x.gguf'), requireHttps: true),
        isFalse,
      );
    });

    test('URL vazia ou relativa nao conta como configurada', () {
      expect(semUrl().isConfigured, isFalse);
      expect(
        ModelArtifact(url: 'models/x.gguf', sha256: hash, sizeBytes: 1, fileName: 'x')
            .isConfigured,
        isFalse,
      );
      expect(artifact().isConfigured, isTrue);
    });

    test('URL ausente e sem arquivo: notConfigured sem nenhum byte de rede',
        () async {
      final fake = _FakeDownloader((_) => throw StateError('nao devia buscar'));
      final result = await ModelDownloader(
        artifact: semUrl(),
        destination: File('${tmp.path}/modelo.gguf'),
        downloader: fake,
        requiredFreeBytes: 0,
      ).ensureAvailable();

      expect((result as ModelUnavailable).reason,
          ModelUnavailableReason.notConfigured);
      expect(fake.calls, 0);
    });

    test('URL ausente com modelo ja verificado: ModelReady sem rede', () async {
      final dest = File('${tmp.path}/modelo.gguf')..writeAsBytesSync(payload);
      final downloader = ModelDownloader(
        artifact: semUrl(),
        destination: dest,
        downloader: ResumableDownloader(writerLabel: 'teste'),
        requiredFreeBytes: 1 << 62,
      );
      addTearDown(downloader.close);

      expect(await downloader.ensureAvailable(), isA<ModelReady>());
    });

    test('URL ausente com parcial completo (OTG): ModelReady sem rede',
        () async {
      final dest = File('${tmp.path}/modelo.gguf');
      File('${dest.path}.parcial').writeAsBytesSync(payload);
      final downloader = ModelDownloader(
        artifact: semUrl(),
        destination: dest,
        downloader: ResumableDownloader(writerLabel: 'teste'),
        requiredFreeBytes: 0,
      );
      addTearDown(downloader.close);

      expect(await downloader.ensureAvailable(), isA<ModelReady>());
      expect(dest.readAsBytesSync(), payload);
    });

    test('parcial incompleto sem URL: notConfigured, zero requisicoes',
        () async {
      // Sem a regra, o parcial incompleto seguiria para o `fetch` com URL vazia
      // e voltaria como um erro de rede confuso.
      final dest = File('${tmp.path}/modelo.gguf');
      final partial = File('${dest.path}.parcial')
        ..writeAsBytesSync(payload.sublist(0, payload.length ~/ 2));
      final fake = _FakeDownloader((_) => throw StateError('nao devia buscar'));

      final result = await ModelDownloader(
        artifact: semUrl(),
        destination: dest,
        downloader: fake,
        requiredFreeBytes: 0,
      ).ensureAvailable();

      expect((result as ModelUnavailable).reason,
          ModelUnavailableReason.notConfigured);
      expect(fake.calls, 0);
      expect(partial.lengthSync(), payload.length ~/ 2,
          reason: 'o parcial fica: uma URL futura retoma dele');
    });
  });

  test('parcial de outro host retoma no novo host com o mesmo conteudo',
      () async {
    // Aparelho que comecou a baixar do Hugging Face e passa a baixar do
    // storage proprio: os bytes sao os mesmos (mesmo SHA-256), entao o Range
    // anexado e valido.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final ranges = <String?>[];
    server.listen((r) {
      final range = r.headers.value(HttpHeaders.rangeHeader);
      ranges.add(range);
      final from = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range!)!.group(1)!);
      r.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(HttpHeaders.contentRangeHeader,
            'bytes $from-${payload.length - 1}/${payload.length}')
        ..contentLength = payload.length - from
        ..add(payload.sublist(from))
        ..close();
    });
    final dest = File('${tmp.path}/modelo.gguf');
    File('${dest.path}.parcial').writeAsBytesSync(payload.sublist(0, 5));
    final downloader = ModelDownloader(
      artifact: ModelArtifact(
        url: 'http://${server.address.host}:${server.port}/models/modelo-$hash.gguf',
        sha256: hash,
        sizeBytes: payload.length,
        fileName: 'modelo.gguf',
      ),
      destination: dest,
      downloader: ResumableDownloader(writerLabel: 'teste'),
      requiredFreeBytes: 0,
    );
    addTearDown(downloader.close);

    expect(await downloader.ensureAvailable(), isA<ModelReady>());
    expect(ranges, ['bytes=5-']);
    expect(dest.readAsBytesSync(), payload);
  });

  test('worker sem aceite dos termos nao baixa e nao pede reagendamento',
      () async {
    // ADR-004: o job periodico de uma versao anterior sobrevive a
    // atualizacao. Sem esta guarda, ele baixaria 806 MB do Hugging Face para
    // quem tocou "usar sem o assistente". `true` = nao reagendar.
    var abriuDisco = false;
    final resultado = await runModelSyncTask(
      termsAccepted: () async => false,
      modelsDir: () async {
        abriuDisco = true;
        return tmp;
      },
    );
    expect(resultado, isTrue);
    expect(abriuDisco, isFalse, reason: 'parou antes de tocar o disco');
  });

  test('aceite so vale para a versao vigente dos termos', () {
    expect(acceptsCurrentTerms(version: termsVersion, accepted: true), isTrue);
    expect(acceptsCurrentTerms(version: termsVersion, accepted: false), isFalse);
    expect(acceptsCurrentTerms(version: '2026-08-22', accepted: true), isFalse);
    expect(acceptsCurrentTerms(version: null, accepted: true), isFalse);
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
