/// Download do modelo SLM no 1º acesso (ADR-003, RNF-03).
///
/// Fina camada de POLÍTICA sobre o [ResumableDownloader]: o transporte
/// retomável e a verificação de integridade são os mesmos que o sync de
/// pacotes usa. O que é específico do modelo mora aqui:
///
/// * o portão de **3 GB livres** antes de começar;
/// * o fato de que falhar é normal e nunca bloqueia o app.
///
/// ===========================================================================
/// FALHAR AQUI É UM DESFECHO PREVISTO, NÃO UM ERRO
/// ===========================================================================
///
/// Sem modelo, a triagem roda pelo `RuleOnlyEngine` (RF-12) e continua
/// clinicamente correta — o gate determinístico decide sozinho e a INV-1
/// protege as emergências. Por isso nenhum caminho deste arquivo lança, e
/// nenhum deles deve virar diálogo de erro: o usuário não pediu o modelo, não
/// precisa saber que ele existe, e não tem o que fazer a respeito.
library;

import 'dart:io';

import 'package:meta/meta.dart';

import '../core/disk_space.dart';
import 'resumable_downloader.dart';

/// Por que o modelo não está disponível — para telemetria agregada, nunca
/// para a tela.
enum ModelUnavailableReason {
  /// Menos de 3 GB livres. Não chegamos a tentar.
  insufficientDiskSpace,

  /// Janela de rede fechou; o progresso foi preservado.
  interrupted,

  /// Conteúdo não confere com o hash esperado, ou recurso inexistente.
  rejected,
}

@immutable
sealed class ModelFetchResult {
  const ModelFetchResult();
}

/// Modelo pronto para uso em [file].
@immutable
final class ModelReady extends ModelFetchResult {
  const ModelReady(this.file);

  final File file;
}

/// Modelo indisponível — o app segue em modo degradado.
@immutable
final class ModelUnavailable extends ModelFetchResult {
  const ModelUnavailable(this.reason, {this.detail, this.bytesSoFar = 0});

  final ModelUnavailableReason reason;

  /// Diagnóstico técnico para o log local (ring buffer, sem PII).
  final String? detail;

  /// Quanto já foi baixado, quando aplicável — a próxima janela continua daqui.
  final int bytesSoFar;
}

/// Descrição do artefato a baixar. O `sha256` vem versionado no código do app,
/// não do servidor: um espelho comprometido não pode se autoautenticar.
@immutable
class ModelArtifact {
  const ModelArtifact({
    required this.url,
    required this.sha256,
    required this.sizeBytes,
  });

  final Uri url;
  final String sha256;

  /// Tamanho anunciado do artefato.
  final int sizeBytes;
}

class ModelDownloader {
  ModelDownloader({
    required this.artifact,
    required this.destination,
    ResumableDownloader? downloader,
    this.requiredFreeBytes = requiredFreeBytesForModel,
  }) : _downloader = downloader ?? ResumableDownloader();

  final ModelArtifact artifact;
  final File destination;
  final ResumableDownloader _downloader;

  /// Exigência de espaço livre. Padrão: os 3 GB do RNF-03.
  final int requiredFreeBytes;

  /// Garante o modelo em disco. Idempotente: se já existe e confere, não baixa.
  Future<ModelFetchResult> ensureAvailable() async {
    // Portão de disco ANTES de qualquer byte de rede. Começar um download de
    // 1,2 GB num aparelho sem espaço deixa o usuário pior do que não começar.
    //
    // Arquivo já baixado é exceção: se ele existe, não vamos consumir mais
    // espaço, e recusar por falta de disco desligaria o SLM justamente em
    // aparelhos onde ele já estava funcionando.
    if (!destination.existsSync()) {
      final verdict = checkDiskSpace(
        destination.parent.path,
        requiredBytes: requiredFreeBytes,
      );
      if (verdict == DiskSpaceVerdict.insufficient) {
        final free = freeDiskBytes(destination.parent.path);
        return ModelUnavailable(
          ModelUnavailableReason.insufficientDiskSpace,
          detail: 'livre=${free ?? "?"}B, exigido=${requiredFreeBytes}B',
        );
      }
      // `unknown` segue adiante de propósito: ver `checkDiskSpace`.
    }

    final outcome = await _downloader.fetch(
      url: artifact.url,
      destination: destination,
      expectedSha256: artifact.sha256,
    );

    return switch (outcome) {
      DownloadCompleted(:final file) => ModelReady(file),
      DownloadInterrupted(:final bytesSoFar, :final reason) => ModelUnavailable(
          ModelUnavailableReason.interrupted,
          detail: reason,
          bytesSoFar: bytesSoFar,
        ),
      DownloadRejected(:final reason) => ModelUnavailable(
          ModelUnavailableReason.rejected,
          detail: reason,
        ),
    };
  }

  void close() => _downloader.close();
}
