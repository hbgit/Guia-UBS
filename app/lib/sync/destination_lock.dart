/// Trava de escritor único por destino, válida entre isolates **e** entre
/// processos.
///
/// ===========================================================================
/// POR QUE EXISTE (issue 31)
/// ===========================================================================
///
/// O worker do WorkManager roda no MESMO processo Android do app, mas num
/// isolate próprio (outro FlutterEngine). Os dois baixavam o mesmo modelo e
/// escreviam no mesmo `.parcial` — confirmado no emulador. O resultado é um
/// arquivo com trechos intercalados que só o SHA-256 final recusa, depois de
/// centenas de MB jogados fora.
///
/// ## Por que não `RandomAccessFile.lock`
///
/// Porque ele é **por processo**, e o problema é entre isolates do mesmo
/// processo. A própria documentação do SDK diz isso em `file.dart`
/// (`RandomAccessFile.lock`): o lock não impede outro isolate do mesmo processo
/// de obtê-lo. O experimento da Task 4 confirmou: com o principal segurando
/// `FileLock.exclusive`, um `Isolate.spawn` obtém o mesmo lock exclusivo na
/// hora. Daí a trava ser um ARQUIVO criado com `O_EXCL`
/// (`File.create(exclusive: true)`), que é atômico no kernel para qualquer
/// chamador.
///
/// ## Por que o batimento
///
/// Trava em arquivo sobrevive ao dono. E o dono morre sem aviso: o Android
/// encerra o worker com `engine.destroy()`, que mata o isolate sem rodar
/// `finally` nenhum — o `release()` simplesmente não acontece. Então o dono
/// renova o `mtime` a cada [LockTiming.heartbeat], e uma trava cujo `mtime`
/// ficou mais velho que [LockTiming.staleAfter] é órfã. O pid sozinho não
/// basta justamente nesse caso: o isolate morto tinha o MESMO pid do
/// processo que continua vivo.
///
/// ## Por que o critério de pid é confiável no Android
///
/// Quando o pid gravado é de outro processo, ausência em `/proc/<pid>` permite
/// tomar a trava sem esperar `staleAfter`. No Android o `/proc` é montado com
/// `hidepid`, mas processos do **mesmo UID** continuam visíveis. Logo, um pid
/// do próprio app que esteja vivo sempre aparece; um ausente está morto ou foi
/// reusado por processo de outro UID — invisível, e para nós equivalente a
/// morto, porque não escreve nos nossos arquivos. Sem `/proc` (outro SO), o
/// critério se desliga e vale só o batimento.
///
/// ## Limite conhecido: tomada simultânea
///
/// Dois candidatos podem julgar a mesma trava órfã ao mesmo tempo. A releitura
/// (conteúdo E `mtime` iguais aos lidos) antes do `delete` estreita a janela,
/// mas não a fecha: entre a releitura e o `delete`, outro pode ter apagado e
/// recriado o arquivo, e nós apagamos a trava nova. Dois donos, por um
/// instante. Isso é coberto em duas camadas: a **cerca** — o batimento relê o
/// arquivo e derruba [DestinationLock.isHeld] assim que o conteúdo deixa de
/// ser o nosso, e [DestinationLock.confirmHeld] é conferido antes do `rename`
/// — e, no fim, o **SHA-256** do arquivo inteiro, que recusa qualquer
/// resultado intercalado. A trava evita o desperdício; quem garante a
/// integridade continua sendo o hash.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:meta/meta.dart';

@immutable
class LockTiming {
  const LockTiming({
    this.staleAfter = const Duration(seconds: 60),
    this.heartbeat = const Duration(seconds: 10),
    this.poll = const Duration(milliseconds: 500),
  });

  /// `mtime` mais velho que isto = dono morto sem soltar.
  final Duration staleAfter;

  /// Intervalo de renovação do `mtime` pelo dono. Bem menor que [staleAfter].
  final Duration heartbeat;

  /// Intervalo entre tentativas enquanto espera.
  final Duration poll;
}

final class DestinationLock {
  DestinationLock._(this._file, this._content, LockTiming timing) {
    _timer = Timer.periodic(timing.heartbeat, (_) => _beat());
  }

  final File _file;
  final String _content;
  late final Timer _timer;
  bool _held = true;

  /// `<dir>/.<basename>.trava`. Começa com ponto: ver achado 4
  /// (`PackStore.dropUnreferenced` apaga tudo que começa com `pack-` e não
  /// está referenciado — a trava de um pack em download sumiria debaixo do
  /// dono).
  static File fileFor(File destination) {
    final name = destination.uri.pathSegments.last;
    return File('${destination.parent.path}/.$name.trava');
  }

  /// `null` se não obteve dentro de [wait]. Lança só erro de E/S que não seja
  /// "já existe" (o chamador trata como interrupção — nunca escreve sem trava).
  static Future<DestinationLock?> acquire(
    File destination, {
    Duration wait = Duration.zero,
    LockTiming timing = const LockTiming(),
    void Function()? onWaiting,
    void Function(String event)? onEvent,
  }) async {
    final file = fileFor(destination);
    final content = '$pid:${_newToken()}';
    final deadline = DateTime.now().add(wait);
    var announcedWait = false;

    while (true) {
      try {
        file.createSync(exclusive: true);
      } on PathExistsException {
        final seen = _inspect(file);
        if (seen == null) continue; // sumiu entre o create e a leitura

        final reason = _orphanReason(seen, timing);
        if (reason != null) {
          final again = _inspect(file);
          if (again != null &&
              again.content == seen.content &&
              again.modified == seen.modified) {
            try {
              file.deleteSync();
            } on PathNotFoundException {
              // Outro candidato apagou primeiro; disputamos o create.
            }
            onEvent?.call('orfa tomada motivo=$reason');
          }
          continue; // sem dormir
        }

        if (!announcedWait) {
          announcedWait = true;
          onEvent?.call('aguardando dono=${_describeOwner(seen.content)}');
        }
        if (!DateTime.now().isBefore(deadline)) return null;
        onWaiting?.call();
        await Future<void>.delayed(timing.poll);
        continue;
      }

      try {
        file.writeAsStringSync(content, flush: true);
      } catch (_) {
        try {
          file.deleteSync();
        } on FileSystemException {
          // Já não existe; nada a desfazer.
        }
        rethrow;
      }
      return DestinationLock._(file, content, timing);
    }
  }

  /// `false` assim que o batimento descobrir que o arquivo não é mais nosso
  /// (cerca), ou depois de [release].
  bool get isHeld => _held;

  /// Releitura síncrona do arquivo: ainda é nosso? Usado antes do `rename`.
  bool confirmHeld() {
    if (!_held) return false;
    return _readOrNull(_file) == _content;
  }

  /// Para o batimento e apaga o arquivo SÓ se o conteúdo ainda for o nosso.
  Future<void> release() async {
    _timer.cancel();
    _held = false;
    if (_readOrNull(_file) != _content) return;
    try {
      await _file.delete();
    } on PathNotFoundException {
      // Já foi tomada e solta por outro; nada a fazer.
    }
  }

  /// Renova o `mtime` reescrevendo os NOSSOS bytes no lugar, pelo mesmo
  /// descritor em que conferiu que eles são nossos.
  ///
  /// Não usamos `setLastModifiedSync`: no SDK atual ele (e `lastModifiedSync`)
  /// trabalha em segundos inteiros — medido na Task 4 —, então uma trava viva
  /// poderia parecer até 1 s mais velha do que é. O `write()` atualiza o
  /// `mtime` na precisão do kernel. Conferir e escrever pelo MESMO descritor
  /// também fecha a corrida com quem troca o arquivo: se o caminho passou a
  /// ser de outro depois da abertura, escrevemos num inode desligado, sem
  /// tocar a trava alheia.
  void _beat() {
    if (!_held) return;
    if (!_file.existsSync()) return _lose();
    RandomAccessFile? raf;
    try {
      // `append` não trunca (diferente de `write`); posicionamos à mão.
      raf = _file.openSync(mode: FileMode.append)..setPositionSync(0);
      final seen = String.fromCharCodes(raf.readSync(_content.length + 1));
      if (seen != _content) return _lose();
      raf
        ..setPositionSync(0)
        ..writeStringSync(_content)
        ..flushSync();
    } on FileSystemException {
      // Falha transitória de E/S: o próximo batimento tenta de novo. Se
      // persistir, a trava envelhece e outro a toma — e a cerca nos avisa.
    } finally {
      raf?.closeSync();
    }
  }

  void _lose() {
    _held = false;
    _timer.cancel();
  }

  // -------------------------------------------------------------------------

  static String _newToken() {
    final random = Random.secure();
    return List<String>.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static String? _readOrNull(File file) {
    try {
      return file.readAsStringSync();
    } on FileSystemException {
      return null;
    }
  }

  /// `null` só se o arquivo sumiu. Qualquer outro erro de E/S sobe: o
  /// chamador trata como interrupção, e girar no laço não o resolveria.
  static _Seen? _inspect(File file) {
    // `statSync`, não `lastModifiedSync`: este trunca para segundos.
    final stat = file.statSync();
    if (stat.type == FileSystemEntityType.notFound) return null;
    try {
      return _Seen(file.readAsStringSync(), stat.modified);
    } on PathNotFoundException {
      return null;
    }
  }

  /// `'pid'`, `'batimento'` ou `null` se o dono parece vivo. Conteúdo vazio ou
  /// ilegível (janela entre `create` e a gravação) conta só pelo `mtime`.
  static String? _orphanReason(_Seen seen, LockTiming timing) {
    final ownerPid = int.tryParse(seen.content.split(':').first);
    if (ownerPid != null && ownerPid != pid && _procAvailable) {
      if (!Directory('/proc/$ownerPid').existsSync()) return 'pid';
    }
    if (DateTime.now().difference(seen.modified) > timing.staleAfter) {
      return 'batimento';
    }
    return null;
  }

  static bool get _procAvailable => Directory('/proc/self').existsSync();

  static String _describeOwner(String content) {
    final sep = content.indexOf(':');
    if (sep < 0) return content.isEmpty ? '?' : content;
    final token = content.substring(sep + 1);
    return '${content.substring(0, sep)}:'
        '${token.length > 6 ? token.substring(0, 6) : token}';
  }
}

class _Seen {
  const _Seen(this.content, this.modified);
  final String content;
  final DateTime modified;
}
