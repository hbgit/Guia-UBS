import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/sync/destination_lock.dart';
import 'package:guia_ubs/sync/pack_store.dart';

/// Tempos curtos para o teste caber em segundos. A proporção é a da produção:
/// o batimento bate várias vezes dentro de `staleAfter`.
const LockTiming _timing = LockTiming(
  staleAfter: Duration(milliseconds: 300),
  heartbeat: Duration(milliseconds: 50),
  poll: Duration(milliseconds: 20),
);

/// Dono em OUTRO isolate — o cenário da issue 31 (WorkManager num segundo
/// FlutterEngine, mesmo processo). Adquire, avisa e segura até receber
/// `'soltar'`; responde `'solto'` depois do `release()`.
Future<void> _ownerIsolate(List<Object> args) async {
  final path = args[0] as String;
  final reply = args[1] as SendPort;
  final lock = await DestinationLock.acquire(File(path), timing: _timing);
  final commands = ReceivePort();
  reply.send(<Object?>[lock != null, commands.sendPort]);
  await for (final msg in commands) {
    if (msg == 'soltar') {
      await lock?.release();
      reply.send('solto');
      commands.close();
    }
  }
}

class _Owner {
  _Owner(this.isolate, this.commands, this.events);
  final Isolate isolate;
  final SendPort commands;
  final StreamIterator<Object?> events;

  static Future<_Owner> spawn(File dest) async {
    final port = ReceivePort();
    final isolate = await Isolate.spawn(
      _ownerIsolate,
      <Object>[dest.path, port.sendPort],
    );
    final events = StreamIterator<Object?>(port);
    expect(await events.moveNext(), isTrue);
    final first = events.current! as List<Object?>;
    expect(first[0], isTrue, reason: 'o isolate dono deveria obter a trava');
    return _Owner(isolate, first[1]! as SendPort, events);
  }

  Future<void> release() async {
    commands.send('soltar');
    expect(await events.moveNext(), isTrue);
    expect(events.current, 'solto');
  }

  Future<void> dispose() async {
    isolate.kill(priority: Isolate.immediate);
    await events.cancel();
  }
}

void main() {
  late Directory dir;
  late File dest;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('destination_lock_test');
    dest = File('${dir.path}/modelo.gguf.parcial');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('exclui outro isolate enquanto o dono vive', () async {
    final owner = await _Owner.spawn(dest);
    addTearDown(owner.dispose);

    final lock = await DestinationLock.acquire(
      dest,
      wait: const Duration(milliseconds: 200),
      timing: _timing,
    );
    expect(lock, isNull);
  });

  test('batimento mantém a trava viva além de staleAfter, entre isolates',
      () async {
    final owner = await _Owner.spawn(dest);
    addTearDown(owner.dispose);

    final events = <String>[];
    final blocked = await DestinationLock.acquire(
      dest,
      wait: const Duration(milliseconds: 900),
      timing: _timing,
      onEvent: events.add,
    );
    expect(blocked, isNull);
    expect(events.where((e) => e.startsWith('aguardando dono=')), hasLength(1));
    expect(events.where((e) => e.startsWith('orfa')), isEmpty);

    await owner.release();
    final lock = await DestinationLock.acquire(
      dest,
      wait: const Duration(milliseconds: 500),
      timing: _timing,
    );
    expect(lock, isNotNull);
    await lock!.release();
  });

  test('trava de isolate morto é tomada só depois de staleAfter', () async {
    final owner = await _Owner.spawn(dest);
    owner.isolate.kill(priority: Isolate.immediate);
    await owner.events.cancel();

    final events = <String>[];
    final watch = Stopwatch()..start();
    final lock = await DestinationLock.acquire(
      dest,
      wait: const Duration(seconds: 2),
      timing: _timing,
      onEvent: events.add,
    );
    watch.stop();

    expect(lock, isNotNull);
    expect(watch.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 200)));
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(events, contains('orfa tomada motivo=batimento'));
    await lock!.release();
  });

  test('trava de processo morto é tomada na hora', () async {
    DestinationLock.fileFor(dest).writeAsStringSync('999999999:deadbeef');

    final events = <String>[];
    final lock = await DestinationLock.acquire(
      dest,
      timing: _timing,
      onEvent: events.add,
    );
    expect(lock, isNotNull);
    expect(events, contains('orfa tomada motivo=pid'));
    await lock!.release();
  }, skip: Directory('/proc/self').existsSync() ? false : 'requer /proc');

  test('trava velha é tomada', () async {
    final file = DestinationLock.fileFor(dest)..writeAsStringSync('$pid:outro');
    file.setLastModifiedSync(
      DateTime.now().subtract(const Duration(seconds: 1)),
    );

    final events = <String>[];
    final lock = await DestinationLock.acquire(
      dest,
      timing: _timing,
      onEvent: events.add,
    );
    expect(lock, isNotNull);
    expect(events, contains('orfa tomada motivo=batimento'));
    await lock!.release();
  });

  test('cerca: dono que perdeu o arquivo sabe disso', () async {
    final lock = await DestinationLock.acquire(dest, timing: _timing);
    expect(lock, isNotNull);
    expect(lock!.isHeld, isTrue);
    expect(lock.confirmHeld(), isTrue);

    DestinationLock.fileFor(dest).writeAsStringSync('$pid:alheio');
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(lock.isHeld, isFalse);
    expect(lock.confirmHeld(), isFalse);
    await lock.release();
  });

  test('release não apaga trava alheia', () async {
    final lock = await DestinationLock.acquire(dest, timing: _timing);
    expect(lock, isNotNull);

    final file = DestinationLock.fileFor(dest)..writeAsStringSync('$pid:alheio');
    await lock!.release();

    expect(file.existsSync(), isTrue);
    expect(file.readAsStringSync(), '$pid:alheio');
  });

  test('release libera para o próximo', () async {
    final lock = await DestinationLock.acquire(dest, timing: _timing);
    expect(lock, isNotNull);
    await lock!.release();

    expect(DestinationLock.fileFor(dest).existsSync(), isFalse);
    final next = await DestinationLock.acquire(dest, timing: _timing);
    expect(next, isNotNull);
    await next!.release();
  });

  test('trava de pack sobrevive a dropUnreferenced', () async {
    final store = PackStore(dir);
    final packDest = store.packFile('ab' * 32);
    final lock = await DestinationLock.acquire(packDest, timing: _timing);
    expect(lock, isNotNull);

    await store.dropUnreferenced(keep: 'cd' * 32);

    expect(DestinationLock.fileFor(packDest).existsSync(), isTrue);
    await lock!.release();
  });
}
