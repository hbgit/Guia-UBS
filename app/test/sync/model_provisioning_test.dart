/// O fluxo de First-Time Setup: a trava de operação, o consentimento, o
/// override do administrador e a importação por pendrive.
///
/// Nenhum teste toca em rede, plugin ou aparelho — a política inteira é
/// injetável de propósito.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/sync/model_downloader.dart';
import 'package:guia_ubs/sync/model_provisioning.dart';
import 'package:guia_ubs/sync/model_sync_scheduler.dart';
import 'package:guia_ubs/sync/resumable_downloader.dart';

class _FakeDownloader implements ResumableDownloader {
  _FakeDownloader();

  /// Quando nulo, imita o comportamento real de "parcial completo".
  DownloadOutcome Function(File destination, DownloadProgress? onProgress)?
      outcome;
  int calls = 0;
  final List<Uri> requested = [];

  @override
  Future<DownloadOutcome> fetch({
    required Uri url,
    required File destination,
    required String expectedSha256,
    DownloadProgress? onProgress,
    int fallbackTotalBytes = 0,
  }) async {
    calls++;
    requested.add(url);
    final handler = outcome;
    if (handler != null) return handler(destination, onProgress);

    // Comportamento padrão: aceita um parcial já completo (caminho do OTG).
    final partial = File('${destination.path}.parcial');
    if (partial.existsSync()) {
      final digest = await sha256.bind(partial.openRead()).first;
      if (digest.toString() == expectedSha256) {
        await partial.rename(destination.path);
        return DownloadCompleted(destination, bytes: destination.lengthSync());
      }
      await partial.delete();
      return const DownloadRejected('hash divergente', kind: DownloadRejectionKind.digestMismatch);
    }
    if (destination.existsSync()) {
      final digest = await sha256.bind(destination.openRead()).first;
      if (digest.toString() == expectedSha256) {
        return DownloadCompleted(destination, bytes: destination.lengthSync());
      }
      await destination.delete();
    }
    return const DownloadInterrupted(bytesSoFar: 0, reason: 'sem rede no fake');
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
  final payload = utf8.encode('modelo de mentira' * 64);
  final hash = sha256.convert(payload).toString();

  setUp(() => tmp = Directory.systemTemp.createTempSync('gubs_prov_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  ModelArtifact artifact() => ModelArtifact(
        url: 'http://espelho.invalid/modelo.gguf',
        sha256: hash,
        sizeBytes: payload.length,
        fileName: 'modelo.gguf',
      );

  ModelProvisioning make({
    required NetworkClass network,
    _FakeDownloader? downloader,
    int requiredFreeBytes = 1024,
  }) =>
      ModelProvisioning(
        artifact: artifact(),
        destinationDirectory: () async => tmp,
        networkClass: () async => network,
        downloader: downloader ?? _FakeDownloader(),
        requiredFreeBytes: requiredFreeBytes,
      );

  group('trava de operação', () {
    test('bloqueia a tela clínica em TODO estado que não seja pronto', () {
      const liberam = {SetupStage.ready, SetupStage.readyDegraded};
      for (final stage in SetupStage.values) {
        final blocks = SetupState(stage: stage).blocksClinicalScreen;
        expect(blocks, !liberam.contains(stage),
            reason: 'estágio $stage decidiu errado sobre a trava');
      }
    });
  });

  group('saída de emergência — seguir sem o modelo', () {
    test('libera a tela clínica em modo degradado a partir de um bloqueio',
        () async {
      final p = make(network: NetworkClass.none);
      final blocked = await p.checkPrerequisites();
      expect(blocked.blocksClinicalScreen, isTrue);

      final state = p.continueWithoutModel();

      expect(state.stage, SetupStage.readyDegraded);
      expect(state.blocksClinicalScreen, isFalse,
          reason: 'um posto sem rede nao pode ficar sem orientacao alguma');
      expect(state.isDegraded, isTrue,
          reason: 'o orquestrador precisa saber que nao ha SLM');
      await p.dispose();
    });

    test('NÃO se confunde com pronto-com-modelo', () async {
      const comModelo = SetupState(stage: SetupStage.ready);
      const semModelo = SetupState(stage: SetupStage.readyDegraded);

      expect(comModelo.isDegraded, isFalse);
      expect(semModelo.isDegraded, isTrue);
      expect(comModelo.blocksClinicalScreen, semModelo.blocksClinicalScreen,
          reason: 'ambos liberam a tela; o que muda e o motor');
    });

    test('só vale a partir de bloqueio — não atalha o setup', () async {
      final p = make(network: NetworkClass.unmetered);
      await p.checkPrerequisites(); // fica em awaitingConsent

      final state = p.continueWithoutModel();

      expect(state.stage, SetupStage.awaitingConsent,
          reason: 'pular o setup por acidente seria pior que a trava');
      await p.dispose();
    });

    test('depois de degradado, o download ainda pode concluir', () async {
      // A escolha é sobre AGORA, não sobre sempre: o agendador continua
      // tentando, e ao concluir o app volta a `ready` sozinho.
      final fake = _FakeDownloader();
      final p = make(network: NetworkClass.none, downloader: fake);
      await p.checkPrerequisites();
      p.continueWithoutModel();

      fake.outcome = (destination, _) {
        destination.writeAsBytesSync(payload);
        return DownloadCompleted(destination, bytes: payload.length);
      };
      final state = await p.startDownload();

      expect(state.stage, SetupStage.ready);
      expect(state.isDegraded, isFalse);
      await p.dispose();
    });
  });

  group('passo 1 — checagem de pré-requisitos', () {
    test('sem rede alguma, bloqueia com motivo explícito', () async {
      final p = make(network: NetworkClass.none);
      final state = await p.checkPrerequisites();

      expect(state.stage, SetupStage.blocked);
      expect(state.blockReason, SetupBlockReason.offline);
      await p.dispose();
    });

    test('só dados móveis bloqueia por padrão', () async {
      final p = make(network: NetworkClass.metered);
      final state = await p.checkPrerequisites();

      expect(state.blockReason, SetupBlockReason.meteredOnly);
      await p.dispose();
    });

    test('override do administrador libera dados móveis', () async {
      final p = make(network: NetworkClass.metered)..allowMeteredNetworks = true;
      final state = await p.checkPrerequisites();

      expect(state.stage, SetupStage.awaitingConsent,
          reason: 'a urgencia precisa ter uma saida');
      await p.dispose();
    });

    test('com Wi-Fi, PEDE consentimento em vez de baixar sozinho', () async {
      final fake = _FakeDownloader();
      final p = make(network: NetworkClass.unmetered, downloader: fake);
      final state = await p.checkPrerequisites();

      expect(state.stage, SetupStage.awaitingConsent);
      expect(state.totalBytes, payload.length);
      expect(fake.calls, 0, reason: '800 MB nao se baixa sem o usuario dizer sim');
      await p.dispose();
    });

    test('modelo já em disco pula direto para pronto', () async {
      File('${tmp.path}/modelo.gguf').writeAsBytesSync(payload);
      final p = make(network: NetworkClass.none); // nem precisa de rede

      final state = await p.checkPrerequisites();

      expect(state.stage, SetupStage.ready);
      await p.dispose();
    });

    test('segunda abertura não reverifica o hash — trava é só do 1º acesso',
        () async {
      // Medido no aparelho: SHA-256 de 806 MB em Dart puro custa ~12 s. Fazer
      // isso a cada boot travaria a tela clínica toda vez, contrariando a
      // exceção registrada na INV-8 (que vale só no primeiro provisionamento).
      final fake = _FakeDownloader();
      final p1 = make(network: NetworkClass.unmetered, downloader: fake);
      fake.outcome = (destination, _) {
        destination.writeAsBytesSync(payload);
        return DownloadCompleted(destination, bytes: payload.length);
      };
      await p1.checkPrerequisites();
      expect((await p1.startDownload()).stage, SetupStage.ready);
      final chamadasApos1a = fake.calls;
      await p1.dispose();

      // Segunda abertura, mesmo diretório.
      final fake2 = _FakeDownloader();
      final p2 = make(network: NetworkClass.none, downloader: fake2);
      final state = await p2.checkPrerequisites();

      expect(state.stage, SetupStage.ready);
      expect(fake2.calls, 0,
          reason: 'nao pode reverificar nem tocar na rede na 2a abertura');
      expect(chamadasApos1a, greaterThan(0));
      await p2.dispose();
    });

    test('arquivo alterado após o marcador volta a ser verificado', () async {
      final fake = _FakeDownloader();
      final p1 = make(network: NetworkClass.unmetered, downloader: fake);
      fake.outcome = (destination, _) {
        destination.writeAsBytesSync(payload);
        return DownloadCompleted(destination, bytes: payload.length);
      };
      await p1.checkPrerequisites();
      await p1.startDownload();
      await p1.dispose();

      // Alguém trocou o arquivo: tamanho diferente invalida o marcador.
      File('${tmp.path}/modelo.gguf').writeAsBytesSync(utf8.encode('trocado'));

      final p2 = make(network: NetworkClass.none);
      final state = await p2.checkPrerequisites();

      expect(state.stage, isNot(SetupStage.ready),
          reason: 'marcador nao pode blindar um arquivo trocado');
      await p2.dispose();
    });

    test('arquivo presente porém corrompido NÃO libera a trava', () async {
      File('${tmp.path}/modelo.gguf').writeAsBytesSync(utf8.encode('lixo'));
      final p = make(network: NetworkClass.none);

      final state = await p.checkPrerequisites();

      expect(state.stage, isNot(SetupStage.ready));
      await p.dispose();
    });
  });

  group('passo 2 — download com progresso', () {
    test('emite porcentagem crescente durante a transferência', () async {
      final fake = _FakeDownloader();
      fake.outcome = (destination, onProgress) {
        onProgress?.call(0, 100);
        onProgress?.call(50, 100);
        onProgress?.call(100, 100);
        destination.writeAsBytesSync(payload);
        return DownloadCompleted(destination, bytes: payload.length);
      };

      final p = make(network: NetworkClass.unmetered, downloader: fake);
      final seen = <int?>[];
      final sub = p.states.listen((s) {
        if (s.stage == SetupStage.downloading) seen.add(s.percent);
      });

      await p.checkPrerequisites();
      final state = await p.startDownload();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(seen, containsAllInOrder(<int>[0, 50, 100]));
      expect(state.stage, SetupStage.ready);
      await p.dispose();
    });

    test('total desconhecido vira progresso indeterminado, não 0%', () {
      const state = SetupState(stage: SetupStage.downloading, receivedBytes: 10);
      expect(state.percent, isNull,
          reason: 'sem denominador, fingir porcentagem engana o usuario');
    });

    test('interrupção preserva o progresso e permite retomar', () async {
      final fake = _FakeDownloader();
      fake.outcome = (_, _) =>
          const DownloadInterrupted(bytesSoFar: 512, reason: 'wifi caiu');

      final p = make(network: NetworkClass.unmetered, downloader: fake);
      await p.checkPrerequisites();
      final blocked = await p.startDownload();

      expect(blocked.stage, SetupStage.blocked);
      expect(blocked.blockReason, SetupBlockReason.interrupted);
      expect(blocked.receivedBytes, 512, reason: 'os 80% nao podem sumir');

      // Retomada: o mesmo objeto continua utilizável.
      fake.outcome = (destination, _) {
        destination.writeAsBytesSync(payload);
        return DownloadCompleted(destination, bytes: payload.length);
      };
      final done = await p.startDownload();
      expect(done.stage, SetupStage.ready);
      await p.dispose();
    });

    test('hash divergente bloqueia como falha de integridade', () async {
      final fake = _FakeDownloader();
      fake.outcome = (_, _) => const DownloadRejected('SHA-256 nao confere', kind: DownloadRejectionKind.digestMismatch);

      final p = make(network: NetworkClass.unmetered, downloader: fake);
      await p.checkPrerequisites();
      final state = await p.startDownload();

      expect(state.blockReason, SetupBlockReason.integrityFailed);
      expect(state.blocksClinicalScreen, isTrue);
      await p.dispose();
    });
  });

  group('importação por pendrive/OTG', () {
    test('arquivo válido libera a trava SEM rede', () async {
      final pendrive = File('${tmp.path}/origem.gguf')..writeAsBytesSync(payload);
      final fake = _FakeDownloader();
      final p = make(network: NetworkClass.none, downloader: fake);

      final state = await p.importFromLocalFile(pendrive);

      expect(state.stage, SetupStage.ready);
      await p.dispose();
    });

    test('pendrive com arquivo errado é REJEITADO como qualquer outro', () async {
      // A procedência não muda o que exigimos: um pendrive que passou por dez
      // mãos não é mais confiável que um espelho HTTP.
      final pendrive = File('${tmp.path}/origem.gguf')
        ..writeAsBytesSync(utf8.encode('modelo trocado'));
      final p = make(network: NetworkClass.none);

      final state = await p.importFromLocalFile(pendrive);

      expect(state.stage, SetupStage.blocked);
      expect(File('${tmp.path}/modelo.gguf').existsSync(), isFalse);
      await p.dispose();
    });

    test('com o downloader REAL, o OTG não toca na rede', () async {
      // A URL é inalcançável de propósito: se o atalho offline não existisse,
      // este teste falharia por timeout de conexão. É a prova de que um posto
      // sem rede consegue provisionar por pendrive.
      final pendrive = File('${tmp.path}/origem.gguf')
        ..writeAsBytesSync(payload);
      final p = ModelProvisioning(
        artifact: artifact(),
        destinationDirectory: () async => tmp,
        networkClass: () async => NetworkClass.none,
        downloader: ResumableDownloader(
          connectTimeout: const Duration(milliseconds: 200),
          idleTimeout: const Duration(milliseconds: 200),
        ),
        requiredFreeBytes: 1024,
      );

      final state = await p.importFromLocalFile(pendrive);

      expect(state.stage, SetupStage.ready);
      expect(File('${tmp.path}/modelo.gguf').readAsBytesSync(), payload);
      await p.dispose();
    });

    test('origem inexistente não lança', () async {
      final p = make(network: NetworkClass.none);
      final state = await p.importFromLocalFile(File('${tmp.path}/nao_existe'));

      expect(state.stage, SetupStage.blocked);
      await p.dispose();
    });
  });

  group('política do WorkManager', () {
    const policy = ModelSyncPolicy();

    test('UNMETERED barra dados móveis', () {
      expect(
        shouldAttemptDownload(
          network: NetworkClass.metered,
          policy: policy,
          batteryLow: false,
          alreadyProvisioned: false,
        ),
        isFalse,
      );
    });

    test('override do administrador libera dados móveis', () {
      expect(
        shouldAttemptDownload(
          network: NetworkClass.metered,
          policy: policy.withMeteredOverride(allowed: true),
          batteryLow: false,
          alreadyProvisioned: false,
        ),
        isTrue,
      );
    });

    test('não acorda se já está provisionado nem com bateria baixa', () {
      expect(
        shouldAttemptDownload(
          network: NetworkClass.unmetered,
          policy: policy,
          batteryLow: false,
          alreadyProvisioned: true,
        ),
        isFalse,
      );
      expect(
        shouldAttemptDownload(
          network: NetworkClass.unmetered,
          policy: policy,
          batteryLow: true,
          alreadyProvisioned: false,
        ),
        isFalse,
      );
    });

    test('Wi-Fi com bateria ok libera', () {
      expect(
        shouldAttemptDownload(
          network: NetworkClass.unmetered,
          policy: policy,
          batteryLow: false,
          alreadyProvisioned: false,
        ),
        isTrue,
      );
    });
  });
}
