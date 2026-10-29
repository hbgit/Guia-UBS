/// Guarda de build do `MODEL_URL` (P1-1, ADR-004).
///
/// O catálogo do modelo não tem host padrão (`lib/sync/model_catalog.dart`):
/// um build sem `--dart-define=MODEL_URL` compila e sai sem assistente. Isto
/// impede que ele saia assim POR ENGANO, e que saia apontando para o lugar
/// errado. Roda antes de compilar, chamado por `tool/build_apk.sh`:
///
/// ```sh
/// dart run tool/model_url_check.dart --config config/defines.release.json --mode release
/// ```
///
/// Saída: 0 ok; 1 `MODEL_URL` reprovada; 64 uso.
library;

import 'dart:convert';
import 'dart:io';

import 'package:guia_ubs/sync/model_catalog.dart';

/// `null` quando [url] serve; senão, a mensagem que explica por quê.
///
/// A ordem das regras é a ordem em que um humano corrige: primeiro existir,
/// depois ser absoluta, depois apontar para o lugar certo, depois ser segura,
/// e por fim ser do modelo que este build aceita.
String? modelUrlProblem(
  String? url, {
  required bool release,
  required String expectedSha256,
}) {
  if (url == null || url.trim().isEmpty) {
    return 'MODEL_URL ausente: passe --dart-define-from-file com a URL do '
        'modelo no storage do projeto (docs/operacao.md, "Publicar o modelo")';
  }
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return 'MODEL_URL precisa ser absoluta (https://<host>/...): "$url"';
  }
  if (uri.host == 'huggingface.co' || uri.host.endsWith('.huggingface.co')) {
    return 'MODEL_URL aponta para ${uri.host}: o modelo vem do storage proprio '
        '(ADR-004), nao de terceiro';
  }
  if (release && uri.scheme != 'https') {
    return 'MODEL_URL precisa ser https no release (LGPD-RF17): "$url"';
  }
  if (!uri.path.toLowerCase().endsWith('-${expectedSha256.toLowerCase()}.gguf')) {
    return 'MODEL_URL nao e o objeto do modelo deste build: o caminho precisa '
        'terminar em -$expectedSha256.gguf';
  }
  return null;
}

void main(List<String> args) {
  String? config;
  String? mode;
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--config') config = args[i + 1];
    if (args[i] == '--mode') mode = args[i + 1];
  }
  if (config == null || !const {'debug', 'profile', 'release'}.contains(mode)) {
    stderr.writeln('uso: dart run tool/model_url_check.dart '
        '--config <defines.json> --mode <debug|profile|release>');
    exit(64);
  }

  final file = File(config);
  String? url;
  if (file.existsSync()) {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is Map && decoded['MODEL_URL'] is String) {
      url = decoded['MODEL_URL'] as String;
    }
  }

  final problem = modelUrlProblem(
    url,
    release: mode == 'release',
    expectedSha256: activeModel.sha256,
  );
  if (problem != null) {
    stderr.writeln('FALHOU  $problem  ($config)');
    exit(1);
  }
  stdout.writeln('ok  MODEL_URL $url');
}
