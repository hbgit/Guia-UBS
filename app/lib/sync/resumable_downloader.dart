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

import 'destination_lock.dart';

/// Notificação de progresso: bytes recebidos e total esperado.
///
/// O total pode ser 0 quando o servidor não informa `Content-Length` e o
/// chamador não ofereceu um valor de reserva — nesse caso a UI deve mostrar
/// progresso indeterminado em vez de inventar uma porcentagem.
typedef DownloadProgress = void Function(int received, int total);

/// Destino das linhas de diagnóstico do download (ver [ResumableDownloader]).
typedef DownloadTrace = void Function(String line);

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

/// Por que um download foi recusado em definitivo.
///
/// A distinção existe porque as duas causas têm consequências diferentes rio
/// acima: conteúdo que não confere com o hash de um manifest autêntico é um
/// artefato adulterado e vai para a blacklist (FSM-B linha B10); um 404 é o
/// servidor mal configurado, e blacklistar o hash por causa dele bloquearia um
/// pack legítimo assim que o operador consertasse a publicação.
enum DownloadRejectionKind {
  /// O arquivo baixou inteiro mas o SHA-256 não é o esperado.
  digestMismatch,

  /// O servidor respondeu 4xx — recurso ausente ou URL errada.
  permanentHttpError,
}

/// Rejeitado em definitivo — repetir com a mesma URL e hash não vai ajudar.
///
/// O parcial é descartado: manter bytes que já sabemos estar errados só
/// contaminaria a próxima tentativa.
@immutable
final class DownloadRejected extends DownloadOutcome {
  const DownloadRejected(this.reason, {required this.kind});

  final String reason;
  final DownloadRejectionKind kind;
}

/// Baixa arquivos grandes de forma retomável e verificada.
class ResumableDownloader {
  ResumableDownloader({
    HttpClient? client,
    this.idleTimeout = const Duration(seconds: 30),
    this.connectTimeout = const Duration(seconds: 15),
    this.writerLabel = '?',
    this.trace,
    this.writerWait = Duration.zero,
    this.lockTiming = const LockTiming(),
    @visibleForTesting this._digestOf,
  }) : _client = client ?? HttpClient();

  final HttpClient _client;

  /// Tempo máximo sem receber bytes antes de considerar a janela fechada.
  final Duration idleTimeout;

  /// Tempo máximo para estabelecer a conexão.
  final Duration connectTimeout;

  /// Quem está escrevendo (ex.: `worker`, `primeiro-plano`) nas linhas de rastro.
  ///
  /// Dois isolates podem baixar o mesmo modelo; sem rótulo, o `logcat` não diz
  /// de qual deles veio cada linha.
  final String writerLabel;

  /// Recebe as linhas `gubs-dl w=<rótulo> ...`. Só contadores, nomes de
  /// arquivo e durações: nenhum dado de pessoa (INV-2). O formato é contrato
  /// com o `grep` do `logcat` usado para diagnosticar escritas concorrentes.
  final DownloadTrace? trace;

  /// Quanto esperar por outro escritor do MESMO destino antes de desistir
  /// (issue 31).
  ///
  /// O primeiro plano espera (o usuário está olhando a barra, e o outro
  /// escritor está fazendo exatamente o trabalho que ele quer); o worker e o
  /// `SyncService` usam o padrão zero e desistem — a próxima janela do
  /// WorkManager tenta de novo, retomando do que estiver em disco.
  final Duration writerWait;

  /// Ritmo da [DestinationLock]: batimento, órfã e intervalo de espera.
  final LockTiming lockTiming;

  /// Substituto do SHA-256 real, só para testes (hash lento, usurpação
  /// durante o hash).
  final Future<String> Function(File file)? _digestOf;

  void _t(String s) => trace?.call('gubs-dl w=$writerLabel $s');

  /// Busca [url] para [destination], retomando um `.parcial` se existir.
  ///
  /// [expectedSha256] é obrigatório: não existe caminho neste componente que
  /// aceite arquivo sem conferir procedência. Se o servidor devolver conteúdo
  /// diferente do esperado — espelho comprometido, cache envenenado,
  /// truncamento silencioso — o arquivo é descartado.
  ///
  /// **Um escritor por destino** (issue 31): o corpo inteiro roda sob uma
  /// [DestinationLock], válida entre isolates. Quem não obtém a trava dentro
  /// de [writerWait] devolve [DownloadInterrupted] sem abrir nem apagar o
  /// `.parcial` — os bytes são do outro escritor, que continua trabalhando.
  ///
  /// **Nunca lança.** Toda falha vira um [DownloadOutcome].
  Future<DownloadOutcome> fetch({
    required Uri url,
    required File destination,
    required String expectedSha256,
    DownloadProgress? onProgress,
    int fallbackTotalBytes = 0,
  }) async {
    final outcome = await _fetchLocked(
      url: url,
      destination: destination,
      expectedSha256: expectedSha256,
      onProgress: onProgress,
      fallbackTotalBytes: fallbackTotalBytes,
    );
    // Único ponto de saída do rastro: toda rota de retorno passa por aqui.
    final (name, bytes) = switch (outcome) {
      DownloadCompleted(:final bytes) => ('Completed', bytes),
      DownloadInterrupted(:final bytesSoFar) => ('Interrupted', bytesSoFar),
      DownloadRejected() => ('Rejected', 0),
    };
    _t('fim desfecho=$name bytes=$bytes');
    return outcome;
  }

  /// Obtém a trava e roda [_fetchUnlocked] INTEIRO com ela: até o
  /// `resumeFrom` precisa ser lido já com exclusão, senão dois escritores
  /// partem do mesmo offset e anexam os mesmos bytes.
  Future<DownloadOutcome> _fetchLocked({
    required Uri url,
    required File destination,
    required String expectedSha256,
    DownloadProgress? onProgress,
    int fallbackTotalBytes = 0,
  }) async {
    final partial = File('${destination.path}.parcial');
    int partialLength() {
      try {
        return partial.existsSync() ? partial.lengthSync() : 0;
      } on FileSystemException {
        return 0;
      }
    }

    final DestinationLock? lock;
    final waited = Stopwatch()..start();
    try {
      // A trava mora ao lado do destino: sem o diretório, não há onde criá-la.
      await destination.parent.create(recursive: true);
      lock = await DestinationLock.acquire(
        destination,
        wait: writerWait,
        timing: lockTiming,
        // Enquanto o outro escritor trabalha, a barra acompanha o disco dele.
        onWaiting: () {
          if (partial.existsSync()) {
            onProgress?.call(partialLength(), fallbackTotalBytes);
          }
        },
        onEvent: (e) => _t('trava $e'),
      );
    } on Object catch (error) {
      // Sem trava, nada é escrito: nem o `.parcial`, nem uma requisição.
      return DownloadInterrupted(
        bytesSoFar: partialLength(),
        reason: 'trava indisponivel: $error',
      );
    }
    if (lock == null) {
      _t('trava ocupada desiste');
      return DownloadInterrupted(
        bytesSoFar: partialLength(),
        reason: 'outro escritor ativo neste destino',
      );
    }
    _t('trava obtida espera=${waited.elapsedMilliseconds}');
    try {
      return await _fetchUnlocked(
        lock: lock,
        url: url,
        destination: destination,
        expectedSha256: expectedSha256,
        onProgress: onProgress,
        fallbackTotalBytes: fallbackTotalBytes,
      );
    } finally {
      // Sempre: o batimento é um `Timer.periodic` e mantém o isolate vivo.
      // E sem lançar: um erro de E/S ao apagar a trava não pode substituir o
      // desfecho (`fetch` nunca lança). O timer já foi parado antes do
      // `delete`; uma trava que sobrar envelhece e vira órfã.
      try {
        await lock.release();
      } on Object catch (e) {
        _t('trava release falhou: $e');
      }
    }
  }

  /// Interrupção sem `rename`: a trava deixou de ser nossa entre o fim do
  /// download e o nome definitivo. Os bytes ficam para quem a tem agora.
  DownloadInterrupted _lostBeforeRename(File partial) => DownloadInterrupted(
    bytesSoFar: _diskLength(partial),
    reason: 'trava usurpada antes do rename',
  );

  Future<DownloadOutcome> _fetchUnlocked({
    required DestinationLock lock,
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
        final digest = await _sha256Traced(destination, expectedSha256);
        if (_matches(digest, expectedSha256)) {
          return DownloadCompleted(
            destination,
            bytes: destination.lengthSync(),
          );
        }
        await destination.delete();
      }

      await destination.parent.create(recursive: true);
      final resumeFrom = partial.existsSync() ? partial.lengthSync() : 0;
      _t('inicio off=$resumeFrom destino=${destination.uri.pathSegments.last}');

      // Atalho SEM REDE: o parcial já tem o tamanho esperado. Acontece quando
      // o arquivo veio de um pendrive (importação OTG) ou quando o download
      // terminou e o app morreu antes do rename. Verificar aqui evita uma
      // requisição inútil — e, no caso do pendrive, evita exigir rede que o
      // posto não tem.
      if (resumeFrom > 0 && resumeFrom == fallbackTotalBytes) {
        final digest = await _sha256Traced(partial, expectedSha256);
        if (_matches(digest, expectedSha256)) {
          if (!lock.confirmHeld()) return _lostBeforeRename(partial);
          await partial.rename(destination.path);
          return DownloadCompleted(destination, bytes: resumeFrom);
        }
        // Tamanho certo e conteúdo errado: não é retomada, é arquivo errado.
        await partial.delete();
        return DownloadRejected(
          'arquivo local com tamanho esperado mas SHA-256 divergente: $digest',
          kind: DownloadRejectionKind.digestMismatch,
        );
      }

      final failure = await _download(
        lock,
        url,
        partial,
        resumeFrom,
        onProgress,
        fallbackTotalBytes,
      );
      if (failure != null) return failure;

      final digest = await _sha256Traced(partial, expectedSha256);
      if (!_matches(digest, expectedSha256)) {
        await partial.delete();
        return DownloadRejected(
          'SHA-256 nao confere: esperado $expectedSha256, obtido $digest',
          kind: DownloadRejectionKind.digestMismatch,
        );
      }

      // Rename no mesmo diretório é atômico: nenhum leitor jamais vê o nome
      // definitivo apontando para conteúdo não verificado.
      final bytes = partial.lengthSync();
      if (!lock.confirmHeld()) return _lostBeforeRename(partial);
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
    DestinationLock lock,
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
    _t(
      'http status=${response.statusCode} range=${resumeFrom > 0 ? resumeFrom : '-'}',
    );

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
            ? DownloadRejected(
                'HTTP $code em $url',
                kind: DownloadRejectionKind.permanentHttpError,
              )
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
    var nextMark = received - (received % _progressMark) + _progressMark;
    var anomalyReported = false;
    try {
      await response.timeout(idleTimeout).forEach((chunk) {
        // Cerca: o batimento descobriu que a trava não é mais nossa. Parar
        // de anexar ANTES do próximo byte; o `catch` de fora vira interrupção.
        if (!lock.isHeld) throw StateError('trava perdida');
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);

        // `received` é o total ABSOLUTO esperado no disco (offset + esta
        // resposta). O buffer do IOSink só deixa o arquivo ATRÁS desse total;
        // disco à frente dele é prova de que outro escritor anexou bytes.
        if (!anomalyReported) {
          final onDisk = _diskLength(partial);
          if (onDisk > received) {
            anomalyReported = true;
            _t('ANOMALIA recebidos=$received disco=$onDisk');
          }
        }
        if (received >= nextMark) {
          nextMark = received - (received % _progressMark) + _progressMark;
          _t('progresso recebidos=$received disco=${_diskLength(partial)}');
        }
      });
      await sink.flush();
    } finally {
      await sink.close();
    }
    return null;
  }

  /// Tamanho em disco, 0 se ainda não existe: o `openWrite` cria o arquivo de
  /// forma assíncrona, e o rastro não pode derrubar o download por isso.
  int _diskLength(File f) {
    try {
      return f.lengthSync();
    } on FileSystemException {
      return 0;
    }
  }

  /// Intervalo (64 MiB) entre linhas de `progresso` no rastro.
  static const _progressMark = 1 << 26;

  /// Hash com rastro: a duração alimenta a escolha de `staleAfter` do trinco.
  Future<String> _sha256Traced(File file, String expected) async {
    final watch = Stopwatch()..start();
    final digest = await (_digestOf ?? _sha256Of)(file);
    watch.stop();
    final verdict = _matches(digest, expected) ? 'ok' : 'divergente';
    _t(
      'sha $verdict bytes=${file.lengthSync()} ms=${watch.elapsedMilliseconds}',
    );
    return digest;
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
