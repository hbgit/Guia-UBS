/// Download retomável com verificação de integridade.
///
/// Componente COMPARTILHADO: usado pelo download do modelo SLM (ADR-003) e,
/// no `sync_service` (FSM-B), pelo download de pacotes de conteúdo. As duas
/// necessidades são a mesma — baixar um arquivo grande por uma rede que cai no
/// meio, e só aceitá-lo se o conteúdo for exatamente o esperado.
///
/// Duas propriedades governam o desenho:
///
/// 1. **Retomar, não recomeçar.** Em janela de conectividade ruim, recomeçar
///    1,2 GB do zero a cada corte significa nunca terminar. O progresso vive
///    num arquivo `.parcial` que sobrevive ao fechamento do app.
/// 2. **Verificar antes de aceitar.** O arquivo só assume o nome definitivo
///    depois do SHA-256 conferido. Até lá ele é `.parcial`, e nenhum código
///    adiante consegue confundi-lo com um artefato válido.
///
/// O hash é calculado sobre o arquivo COMPLETO ao final, não incrementalmente:
/// um download retomado atravessa execuções do app, e estado de hash não
/// sobrevive a isso. Reler 1,2 GB custa segundos; aceitar arquivo corrompido
/// custa uma triagem errada.
library;

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

/// Notificação de progresso: bytes recebidos e total esperado.
///
/// O total pode ser 0 quando o servidor não informa `Content-Length` e o
/// chamador não ofereceu um valor de reserva — nesse caso a UI deve mostrar
/// progresso indeterminado em vez de inventar uma porcentagem.
typedef DownloadProgress = void Function(int received, int total);

/// Resultado de uma tentativa de download.
@immutable
sealed class DownloadOutcome {
  const DownloadOutcome();
}

/// Baixado e verificado. O arquivo está em [file], já com o nome definitivo.
@immutable
final class DownloadCompleted extends DownloadOutcome {
  const DownloadCompleted(this.file, {required this.bytes});

  final File file;
  final int bytes;
}

/// Interrompido, mas o progresso foi preservado — **tente de novo depois**.
///
/// É o desfecho esperado quando uma janela de conectividade fecha, não um
/// defeito: a próxima tentativa continua de [bytesSoFar].
@immutable
final class DownloadInterrupted extends DownloadOutcome {
  const DownloadInterrupted({required this.bytesSoFar, required this.reason});

  final int bytesSoFar;
  final String reason;
}

/// Rejeitado em definitivo — repetir com a mesma URL e hash não vai ajudar.
///
/// O parcial é descartado: manter bytes que já sabemos estar errados só
/// contaminaria a próxima tentativa.
@immutable
final class DownloadRejected extends DownloadOutcome {
  const DownloadRejected(this.reason);

  final String reason;
}

/// Baixa arquivos grandes de forma retomável e verificada.
class ResumableDownloader {
  ResumableDownloader({
    HttpClient? client,
    this.idleTimeout = const Duration(seconds: 30),
    this.connectTimeout = const Duration(seconds: 15),
  }) : _client = client ?? HttpClient();

  final HttpClient _client;

  /// Tempo máximo sem receber bytes antes de considerar a janela fechada.
  final Duration idleTimeout;

  /// Tempo máximo para estabelecer a conexão.
  final Duration connectTimeout;

  /// Busca [url] para [destination], retomando um `.parcial` se existir.
  ///
  /// [expectedSha256] é obrigatório: não existe caminho neste componente que
  /// aceite arquivo sem conferir procedência. Se o servidor devolver conteúdo
  /// diferente do esperado — espelho comprometido, cache envenenado,
  /// truncamento silencioso — o arquivo é descartado.
  ///
  /// **Nunca lança.** Toda falha vira um [DownloadOutcome].
  Future<DownloadOutcome> fetch({
    required Uri url,
    required File destination,
    required String expectedSha256,
    DownloadProgress? onProgress,
    int fallbackTotalBytes = 0,
  }) async {
    final partial = File('${destination.path}.parcial');

    try {
      if (destination.existsSync()) {
        // Já temos o arquivo. Conferimos mesmo assim: o disco pode ter
        // corrompido, e reler é barato perto da consequência.
        final digest = await _sha256Of(destination);
        if (_matches(digest, expectedSha256)) {
          return DownloadCompleted(destination, bytes: destination.lengthSync());
        }
        await destination.delete();
      }

      await destination.parent.create(recursive: true);
      final resumeFrom = partial.existsSync() ? partial.lengthSync() : 0;

      // Atalho SEM REDE: o parcial já tem o tamanho esperado. Acontece quando
      // o arquivo veio de um pendrive (importação OTG) ou quando o download
      // terminou e o app morreu antes do rename. Verificar aqui evita uma
      // requisição inútil — e, no caso do pendrive, evita exigir rede que o
      // posto não tem.
      if (resumeFrom > 0 && resumeFrom == fallbackTotalBytes) {
        final digest = await _sha256Of(partial);
        if (_matches(digest, expectedSha256)) {
          await partial.rename(destination.path);
          return DownloadCompleted(destination, bytes: resumeFrom);
        }
        // Tamanho certo e conteúdo errado: não é retomada, é arquivo errado.
        await partial.delete();
        return DownloadRejected(
          'arquivo local com tamanho esperado mas SHA-256 divergente: $digest',
        );
      }

      final failure = await _download(
        url,
        partial,
        resumeFrom,
        onProgress,
        fallbackTotalBytes,
      );
      if (failure != null) return failure;

      final digest = await _sha256Of(partial);
      if (!_matches(digest, expectedSha256)) {
        await partial.delete();
        return DownloadRejected(
          'SHA-256 nao confere: esperado $expectedSha256, obtido $digest',
        );
      }

      // Rename no mesmo diretório é atômico: nenhum leitor jamais vê o nome
      // definitivo apontando para conteúdo não verificado.
      final bytes = partial.lengthSync();
      await partial.rename(destination.path);
      return DownloadCompleted(destination, bytes: bytes);
    } on Object catch (error) {
      final soFar = partial.existsSync() ? partial.lengthSync() : 0;
      return DownloadInterrupted(bytesSoFar: soFar, reason: '$error');
    }
  }

  /// Baixa para [partial] a partir de [resumeFrom]. Devolve `null` em sucesso,
  /// ou o [DownloadOutcome] que explica por que não deu.
  Future<DownloadOutcome?> _download(
    Uri url,
    File partial,
    int resumeFrom,
    DownloadProgress? onProgress,
    int fallbackTotalBytes,
  ) async {
    final request = await _client.getUrl(url).timeout(connectTimeout);
    if (resumeFrom > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$resumeFrom-');
    }

    final response = await request.close().timeout(connectTimeout);

    var offset = resumeFrom;
    switch (response.statusCode) {
      case HttpStatus.partialContent:
        break; // 206: servidor honrou o Range; seguimos anexando.
      case HttpStatus.ok:
        // 200 tendo pedido Range = o servidor ignorou o cabeçalho e está
        // mandando o arquivo inteiro. Recomeçar do zero é a única leitura
        // correta; anexar produziria um arquivo com prefixo duplicado.
        offset = 0;
        break;
      case HttpStatus.requestedRangeNotSatisfiable:
        // O parcial é maior que o recurso — provavelmente o arquivo mudou no
        // servidor. Descartar e recomeçar na próxima janela.
        await response.drain<void>();
        if (partial.existsSync()) await partial.delete();
        return const DownloadInterrupted(
          bytesSoFar: 0,
          reason: 'servidor rejeitou o Range (416); parcial descartado',
        );
      default:
        await response.drain<void>();
        final code = response.statusCode;
        // 4xx é problema nosso (URL errada, recurso removido) e repetir não
        // resolve; 5xx e falha de rede são transitórios.
        return code >= 400 && code < 500
            ? DownloadRejected('HTTP $code em $url')
            : DownloadInterrupted(bytesSoFar: resumeFrom, reason: 'HTTP $code');
    }

    // Total absoluto do arquivo, não do trecho: numa retomada o servidor
    // informa só o que resta, e uma barra que reinicia em 0% a cada retomada
    // faria o usuário achar que perdeu o progresso.
    final remaining = response.contentLength;
    var total = remaining > 0 ? offset + remaining : fallbackTotalBytes;
    if (total < offset) total = offset;

    var received = offset;
    onProgress?.call(received, total);

    final sink = partial.openWrite(
      mode: offset > 0 ? FileMode.append : FileMode.write,
    );
    try {
      await response.timeout(idleTimeout).forEach((chunk) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      });
      await sink.flush();
    } finally {
      await sink.close();
    }
    return null;
  }

  Future<String> _sha256Of(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// Comparação sem sensibilidade a caixa — hashes circulam em maiúsculas e
  /// minúsculas conforme a ferramenta que os gerou.
  bool _matches(String actual, String expected) =>
      actual.toLowerCase() == expected.toLowerCase();

  void close() => _client.close(force: true);
}
