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

/// Modelo padrão do MVP (ADR-003).
///
/// Gemma 3 1B Q4_K_M: o melhor equilíbrio da avaliação de oito modelos
/// (arquitetura.md §5.1) — 17/20 de acerto, 4731 ms de p95 e 832 MB de RAM
/// medidos em aparelho arm64.
const ModelArtifact gemma3_1bQ4 = ModelArtifact(
  url: 'https://huggingface.co/ggml-org/gemma-3-1b-it-GGUF/resolve/main/'
      'gemma-3-1b-it-Q4_K_M.gguf',
  sha256: '8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135',
  sizeBytes: 806058240,
  fileName: 'gemma-3-1b-q4.gguf',
);

/// O artefato que este build do app usa.
const ModelArtifact activeModel = gemma3_1bQ4;
