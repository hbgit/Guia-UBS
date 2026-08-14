/// Verifica que o shim nativo CARREGA dentro do runtime Android.
///
/// Os testes de `test/` provam a política do motor sem biblioteca nativa, e o
/// CI prova que o `.so` compila. Nenhum dos dois prova o que fica no meio: que
/// o linker do Android encontra `libgubs_llama.so` dentro do APK, que ele
/// resolve `libllama.so` e `libc++_shared.so` ao lado, e que a ABI compilada é
/// a que o Dart espera.
///
/// Esse é exatamente o degrau onde uma integração nativa costuma falhar — e
/// falharia em silêncio, porque o app degradaria para o `RuleOnlyEngine`
/// (RF-12) sem nenhum sintoma visível. Um app permanentemente degradado que
/// parece saudável é pior que um app que quebra.
///
/// Rodar com aparelho ou emulador conectado:
///   flutter test integration_test/native_shim_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:guia_ubs/triage/engine/llama_bindings.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('libgubs_llama carrega e reporta a ABI esperada', (tester) async {
    final lib = openShimLibrary();

    expect(
      lib,
      isNotNull,
      reason: 'o linker não encontrou libgubs_llama.so no APK — confira '
          'abiFilters e externalNativeBuild em android/app/build.gradle.kts',
    );

    final shim = GubsLlamaShim(lib!);

    expect(
      shim.abiVersion(),
      expectedAbiVersion,
      reason: 'ABI divergente: o .so embarcado não é da mesma geração que o '
          'Dart deste build (GUBS_LLAMA_ABI_VERSION vs expectedAbiVersion)',
    );
  });

  testWidgets('modelo ausente degrada em vez de quebrar', (tester) async {
    // Caminho que todo aparelho percorre antes de o GGUF ser baixado.
    final lib = openShimLibrary();
    expect(lib, isNotNull);

    final handle = GubsLlamaShim(lib!)
        .open('/nao/existe/modelo.gguf', contextTokens: 512, threads: 2);

    expect(handle.address, 0, reason: 'deveria devolver nullptr, não crashar');
  });
}
