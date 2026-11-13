/// De onde baixar o modelo SLM: do manifest assinado, com fallback no
/// `MODEL_URL` embarcado (plano B; Revisão do ADR-004, Q-B2).
///
/// Trocar de HOST vira uma edição assinada do manifest; trocar de MODELO
/// continua exigindo release, porque a identidade (sha, tamanho, nome do
/// arquivo) mora em `model_catalog.dart` e nada aqui a altera.
///
/// O valor é calculado UMA vez por processo — no `main` e em cada disparo do
/// worker. Um manifest novo só muda o host do modelo na próxima abertura do
/// app (ou no próximo disparo do worker). Um download pela metade continua
/// contra o host novo: o parcial é por arquivo, e o sha confere no fim.
library;

import 'endpoint_config.dart';
import 'model_catalog.dart';
import 'model_downloader.dart';
import 'pack_manifest.dart';
import 'pack_store.dart';

/// A URL efetiva do modelo, ou `null` se nenhuma serve.
///
/// A do manifest prevalece só se TODAS valerem:
/// - é do mesmo modelo que este binário compilou ([ModelArtifact.sha256]);
/// - resolvida contra [manifestUrl], é uma origem utilizável neste build;
/// - fica na origem do manifest, ou no host do `MODEL_URL` compilado. As duas
///   chamadas de rede do app nunca vão a um terceiro host, nem com manifest
///   assinado: é o que `docs/dados-do-usuario.md` §3 promete.
///
/// [requireHttps] nulo usa a regra do build (`isUsableEndpoint`).
Uri? resolveModelUri({
  required ModelArtifact compiled,
  required ManifestModel? fromManifest,
  required Uri manifestUrl,
  bool? requireHttps,
}) {
  bool usable(Uri u) => requireHttps == null
      ? isUsableEndpoint(u)
      : isUsableEndpoint(u, requireHttps: requireHttps);

  if (fromManifest != null && fromManifest.sha256 == compiled.sha256) {
    final candidate = manifestUrl.resolve(fromManifest.url);
    final sameOrigin = manifestUrl.isAbsolute &&
        candidate.scheme == manifestUrl.scheme &&
        candidate.host == manifestUrl.host &&
        candidate.port == manifestUrl.port;
    final compiledHost =
        usable(compiled.uri) && candidate.host == compiled.uri.host;
    if (usable(candidate) && (sameOrigin || compiledHost)) return candidate;
  }
  return usable(compiled.uri) ? compiled.uri : null;
}

/// O artefato que o download deve usar agora: o [compiled] com a URL de
/// [resolveModelUri], ou o [compiled] sem mudança.
///
/// Nunca lança: manifest ilegível, inválido ou ausente vale como "sem
/// manifest" (INV-8) — o modelo nunca deixa de baixar por causa do conteúdo.
Future<ModelArtifact> effectiveModel({
  required PackStore store,
  required Uri manifestUrl,
  ModelArtifact compiled = activeModel,
  bool? requireHttps,
}) async {
  ManifestModel? fromManifest;
  try {
    fromManifest = (await store.loadActive())?.manifest.model;
  } on Object {
    fromManifest = null;
  }
  final uri = resolveModelUri(
    compiled: compiled,
    fromManifest: fromManifest,
    manifestUrl: manifestUrl,
    requireHttps: requireHttps,
  );
  if (uri == null || uri == compiled.uri) return compiled;
  return compiled.withUrl(uri.toString());
}
