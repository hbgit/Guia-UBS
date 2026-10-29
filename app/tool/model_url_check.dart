/// Guarda de build de `MODEL_URL` (P1-1, ADR-004) e `PACK_MANIFEST_URL` (#45).
///
/// Nenhuma das duas tem host padrão (`lib/sync/model_catalog.dart`,
/// `lib/sync/pack_background_sync.dart`): um build sem elas compila e sai sem
/// assistente e sem conteúdo novo. Isto impede que ele saia assim POR ENGANO,
/// e que saia apontando para o lugar errado. Roda antes de compilar, chamado
/// por `tool/build_apk.sh`:
///
/// ```sh
/// dart run tool/model_url_check.dart --config config/defines.release.json --mode release
/// ```
///
/// Saída: 0 ok; 1 alguma URL reprovada; 64 uso.
///
/// O app tem a sua própria proteção (`lib/sync/endpoint_config.dart`): fora do
/// debug, URL sem `https` conta como não configurada. Este guarda é mais
/// estrito, porque roda onde ainda dá para corrigir.
library;

import 'dart:convert';
import 'dart:io';

import 'package:guia_ubs/sync/endpoint_config.dart';
import 'package:guia_ubs/sync/model_catalog.dart';

/// A exceção do ADR-004: enquanto o projeto não tem servidor, o modelo vem
/// direto do Hugging Face, NESTA URL e só nela.
///
/// Fixada no commit `f9c28bc` do repositório da `ggml-org`, e não em `main`:
/// um push lá poderia trocar o arquivo sob o mesmo nome. O SHA-256 do app
/// recusaria, mas a frota ficaria sem modelo sem ninguém ter mudado nada aqui.
///
/// Mora aqui, no guarda de build, e não em `lib/`: o app continua sem host
/// nenhum no código. O fim da exceção é trocar o `MODEL_URL` do build para o
/// storage do projeto (`npm run model:publish`).
const String huggingFaceExceptionUrl =
    'https://huggingface.co/ggml-org/gemma-3-1b-it-GGUF/resolve/'
    'f9c28bcd85737ffc5aef028638d3341d49869c27/gemma-3-1b-it-Q4_K_M.gguf';

/// O modelo para o qual a exceção vale. Trocar de modelo encerra a exceção:
/// ela não é um passe livre para o domínio inteiro.
const String huggingFaceExceptionSha256 =
    '8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135';

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
  if (url == huggingFaceExceptionUrl &&
      expectedSha256.toLowerCase() == huggingFaceExceptionSha256) {
    return null;
  }
  if (uri.host == 'huggingface.co' || uri.host.endsWith('.huggingface.co')) {
    if (uri.path.contains('/resolve/main/')) {
      return 'MODEL_URL usa resolve/main: a excecao do ADR-004 e uma revisao '
          'fixa, nunca main ($huggingFaceExceptionUrl)';
    }
    return 'MODEL_URL aponta para ${uri.host} fora da excecao do ADR-004: o '
        'modelo vem do storage proprio, ou exatamente de '
        '$huggingFaceExceptionUrl, e so para o modelo '
        '$huggingFaceExceptionSha256';
  }
  if (release && uri.scheme != 'https') {
    return 'MODEL_URL precisa ser https no release (LGPD-RF17): "$url"';
  }
  if (release && isLocalOrReservedHost(uri.host)) {
    return 'MODEL_URL aponta para um host local ou reservado (${uri.host}): '
        'um release assim nao baixa nada no aparelho de ninguem';
  }
  if (!uri.path.toLowerCase().endsWith('-${expectedSha256.toLowerCase()}.gguf')) {
    return 'MODEL_URL nao e o objeto do modelo deste build: o caminho precisa '
        'terminar em -$expectedSha256.gguf';
  }
  return null;
}

/// `null` quando [url] serve como `PACK_MANIFEST_URL` (#45).
String? packManifestUrlProblem(String? url, {required bool release}) {
  if (url == null || url.trim().isEmpty) {
    return 'PACK_MANIFEST_URL ausente: passe --dart-define-from-file com a URL '
        'do manifest.json do municipio no storage do projeto';
  }
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return 'PACK_MANIFEST_URL precisa ser absoluta (https://<host>/...): "$url"';
  }
  if (release && uri.scheme != 'https') {
    return 'PACK_MANIFEST_URL precisa ser https no release (LGPD-RF17): "$url"';
  }
  if (release && isLocalOrReservedHost(uri.host)) {
    return 'PACK_MANIFEST_URL aponta para um host local ou reservado '
        '(${uri.host}): um release assim nao recebe conteudo';
  }
  if (!uri.path.endsWith('/manifest.json')) {
    return 'PACK_MANIFEST_URL precisa apontar para o manifest.json: "$url"';
  }
  return null;
}

/// No release, o modelo e o manifest saem do MESMO edge de conteúdo (#45):
/// pega configurações misturadas que nenhuma lista de hosts pegaria.
///
/// Exceção: o `MODEL_URL` da exceção do ADR-004 (Hugging Face). Quando a #55
/// encerrar a exceção, a regra passa a valer inteira.
String? sameHostProblem(
  String modelUrl,
  String manifestUrl, {
  required bool release,
}) {
  if (!release || modelUrl == huggingFaceExceptionUrl) return null;
  final model = Uri.tryParse(modelUrl)?.host ?? '';
  final pack = Uri.tryParse(manifestUrl)?.host ?? '';
  if (model == pack) return null;
  return 'MODEL_URL ($model) e PACK_MANIFEST_URL ($pack) precisam ser do mesmo '
      'host no release: os dois saem do mesmo edge de conteudo';
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
  final defines = <String, String>{};
  if (file.existsSync()) {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is Map) {
      for (final MapEntry(:key, :value) in decoded.entries) {
        if (key is String && value is String) defines[key] = value;
      }
    }
  }
  final model = defines['MODEL_URL'];
  final pack = defines['PACK_MANIFEST_URL'];
  // Profile tem as regras de release: o app exige `https` fora do debug
  // (`endpoint_config.dart`), então um profile com `http` sairia sem origem.
  final release = mode != 'debug';

  final problems = [
    modelUrlProblem(model, release: release, expectedSha256: activeModel.sha256),
    packManifestUrlProblem(pack, release: release),
    if (model != null && pack != null)
      sameHostProblem(model, pack, release: release),
  ].whereType<String>().toList();

  for (final p in problems) {
    stderr.writeln('FALHOU  $p  ($config)');
  }
  if (problems.isNotEmpty) exit(1);
  stdout
    ..writeln('ok  MODEL_URL $model')
    ..writeln('ok  PACK_MANIFEST_URL $pack');
}
