/// Catálogo do modelo SLM distribuído — a fonte de verdade do que o app aceita.
///
/// ===========================================================================
/// O SHA-256 VIVE AQUI, NÃO NO SERVIDOR
/// ===========================================================================
///
/// O hash é versionado junto com o código do app e embarcado no APK. Isso é o
/// que impede um espelho comprometido de se autoautenticar: se o servidor
/// pudesse informar o próprio hash, ele poderia entregar qualquer coisa e
/// declarar que está correta.
///
/// Trocar de modelo é, portanto, uma mudança de código que passa por revisão —
/// não uma alteração de configuração remota.
library;

import 'model_downloader.dart';

/// De onde baixar o modelo — o storage do próprio projeto (ADR-004).
///
/// ===========================================================================
/// SEM VALOR PADRÃO, DE PROPÓSITO
/// ===========================================================================
///
/// Um padrão aqui seria um host escondido: o build que esqueceu o
/// `--dart-define` sairia baixando de um lugar que ninguém escolheu (é o
/// defeito da #45 em `PACK_MANIFEST_URL`). Vazio, o artefato se declara não
/// configurado (`ModelArtifact.isConfigured`) e o app segue sem o assistente,
/// sem nenhuma requisição. Quem impede esse build de sair por engano é
/// `tool/build_apk.sh`, que roda `tool/model_url_check.dart` antes de compilar.
///
/// O valor chega por `--dart-define-from-file=config/defines.<modo>.json`.
/// O isolate do WorkManager não precisa de nada à parte: `--dart-define` é
/// constante de compilação do snapshot AOT, o mesmo para `main` e para
/// `gubsCallbackDispatcher`.
///
/// Trocar a URL não faz aparelho nenhum baixar de novo: a identidade do
/// modelo é o [ModelArtifact.sha256] e o [ModelArtifact.fileName] abaixo.
const String modelUrl = String.fromEnvironment('MODEL_URL');

/// Modelo padrão do MVP (ADR-003).
///
/// Gemma 3 1B Q4_K_M: o melhor equilíbrio da avaliação de oito modelos
/// (arquitetura.md §5.1) — 17/20 de acerto, 4731 ms de p95 e 832 MB de RAM
/// medidos em aparelho arm64. Redistribuído sob os Gemma Terms of Use
/// (ADR-004).
const ModelArtifact gemma3_1bQ4 = ModelArtifact(
  url: modelUrl,
  sha256: '8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135',
  sizeBytes: 806058240,
  fileName: 'gemma-3-1b-q4.gguf',
);

/// O artefato que este build do app usa.
const ModelArtifact activeModel = gemma3_1bQ4;
