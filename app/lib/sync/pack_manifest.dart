/// O `manifest.json` — único objeto mutável que o servidor de conteúdo serve.
///
/// Este arquivo é a **fronteira de confiança do conteúdo**. Tudo que vem do
/// servidor entra por aqui, e nada sai daqui sem ter passado pela assinatura
/// Ed25519. O espelho, a CDN e o cache do operador são infraestrutura
/// **não-confiável** por decisão explícita ([stack.md §4.2]) — é justamente
/// isso que torna barato federar espelhos municipais e distribuir por
/// pendrive: ninguém precisa confiar no transporte.
///
/// ## A ordem de validação não é negociável (espec.md §4.2 / FSM-B)
///
/// 1. assinatura Ed25519 sobre o manifest canônico;
/// 2. `packVersion` maior que a ativa (anti-downgrade, INV-7);
/// 3. `schemaVersion` major suportado (INV-6);
/// 4. SHA-256 de cada artefato baixado (INV-3);
/// 5. só então o swap atômico.
///
/// ## Por que verificar ANTES de tipar
///
/// A verificação roda sobre o JSON **cru** que chegou, não sobre o objeto já
/// convertido para os tipos do Dart. Se convertêssemos primeiro e assinássemos
/// o resultado, qualquer campo que o nosso parser desconhecesse sumiria dos
/// bytes verificados — e um campo que some da verificação é um campo que o
/// atacante controla de graça. Verificando o cru, um manifest com campo extra
/// só passa se o assinante realmente o tiver assinado.
library;

import 'dart:convert';

import 'package:meta/meta.dart';

/// Major do `schemaVersion` que este binário sabe ler.
///
/// Major diferente = formato de pack que este código não entende. Aceitar
/// seria pior que recusar: leríamos colunas que mudaram de significado.
const int supportedPackSchemaMajor = 1;

/// Referência a um artefato (o pack ou um asset), sempre com hash e tamanho.
@immutable
class ArtifactRef {
  const ArtifactRef({
    required this.ref,
    required this.url,
    required this.sha256,
    required this.bytes,
  });

  /// Identificador lógico (`icon.fever`). Vazio para o pack, que não tem ref.
  final String ref;

  /// Caminho relativo à base do servidor de conteúdo.
  final String url;

  final String sha256;
  final int bytes;
}

/// Manifest já **verificado**. Não existe instância desta classe cuja
/// assinatura não tenha sido conferida: o único caminho de construção passa
/// por [ManifestVerifier].
@immutable
class PackManifest {
  const PackManifest({
    required this.schemaVersion,
    required this.packVersion,
    required this.municipality,
    required this.pack,
    required this.assets,
    required this.minAppBuild,
    required this.publishedAt,
    required this.keyId,
    required this.rawBytes,
  });

  final String schemaVersion;

  /// Monotônico por município. Nunca decresce, nem com assinatura válida.
  final int packVersion;

  final String municipality;
  final ArtifactRef pack;
  final List<ArtifactRef> assets;
  final int minAppBuild;
  final String publishedAt;

  /// Qual chave pública embarcada validou a assinatura (rotação dual-key).
  final String keyId;

  /// Bytes exatos como chegaram. Guardados para poder **regravar em disco o
  /// que foi verificado**, e não uma reserialização nossa: no cold start o
  /// app confere a assinatura de novo (INV-3), e ela só fecha sobre os bytes
  /// originais.
  final List<int> rawBytes;

  /// Major do schema, para o guard de compatibilidade.
  int get schemaMajor => int.parse(schemaVersion.split('.').first);

  bool get isSchemaSupported => schemaMajor == supportedPackSchemaMajor;
}

/// Erro de formato do manifest. Sempre permanente: repetir o download do mesmo
/// arquivo produziria o mesmo resultado (FSM-B → F2_REJECTED).
@immutable
class ManifestFormatException implements Exception {
  const ManifestFormatException(this.message);

  final String message;

  @override
  String toString() => 'manifest inválido: $message';
}

/// Serialização canônica: JSON com chaves ordenadas, sem espaços, **sem** o
/// campo `signature`.
///
/// Precisa produzir os mesmos bytes que `canonicalPayload` em
/// `contract/src/manifest.ts`. Emissor (Node) e verificador (Dart) divergindo
/// em um único byte faz toda assinatura válida parecer inválida — a frota
/// pararia de receber conteúdo sem nenhum erro aparente. Por isso existe um
/// teste que confere esta função contra um manifest assinado pelo packer real,
/// e não apenas contra outro manifest gerado em Dart.
///
/// A ordenação usa `compareTo` do Dart, que ordena por unidade de código
/// UTF-16 — exatamente o mesmo critério do `<`/`>` do JavaScript.
String canonicalPayload(Map<String, Object?> manifest) {
  final withoutSignature = Map<String, Object?>.from(manifest)..remove('signature');
  return _stableStringify(withoutSignature);
}

String _stableStringify(Object? value) {
  if (value is List) {
    return '[${value.map(_stableStringify).join(',')}]';
  }
  if (value is Map) {
    final keys = value.keys.map((k) => k as String).toList()..sort();
    final entries = keys.map(
      (k) => '${jsonEncode(k)}:${_stableStringify(value[k])}',
    );
    return '{${entries.join(',')}}';
  }
  return jsonEncode(value);
}

// ---------------------------------------------------------------------------
// Tipagem estrita — roda DEPOIS da assinatura conferida
// ---------------------------------------------------------------------------

/// Converte o mapa já verificado em [PackManifest], recusando qualquer desvio
/// do contrato. Espelha `manifestSchema` (Zod) em `contract/src/manifest.ts`.
PackManifest parseVerifiedManifest(
  Map<String, Object?> json,
  List<int> rawBytes,
  String keyId,
) {
  final schemaVersion = _string(json, 'schemaVersion');
  if (!RegExp(r'^\d+\.\d+$').hasMatch(schemaVersion)) {
    throw const ManifestFormatException('schemaVersion deve ser "major.minor"');
  }

  final publishedAt = _string(json, 'publishedAt');
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(publishedAt)) {
    throw const ManifestFormatException('publishedAt deve ser YYYY-MM-DD');
  }

  final assetsRaw = json['assets'];
  if (assetsRaw is! List) {
    throw const ManifestFormatException('assets ausente ou não é lista');
  }

  return PackManifest(
    schemaVersion: schemaVersion,
    packVersion: _positiveInt(json, 'packVersion'),
    municipality: _string(json, 'municipality'),
    pack: _artifact(json['pack'], 'pack', requireRef: false),
    assets: [
      for (var i = 0; i < assetsRaw.length; i++)
        _artifact(assetsRaw[i], 'assets[$i]', requireRef: true),
    ],
    minAppBuild: _nonNegativeInt(json, 'minAppBuild'),
    publishedAt: publishedAt,
    keyId: keyId,
    rawBytes: rawBytes,
  );
}

final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

ArtifactRef _artifact(Object? value, String path, {required bool requireRef}) {
  if (value is! Map<String, Object?>) {
    throw ManifestFormatException('$path ausente ou não é objeto');
  }
  final sha = _string(value, 'sha256');
  if (!_sha256Pattern.hasMatch(sha)) {
    throw ManifestFormatException('$path.sha256 não é hex minúsculo de 64');
  }
  return ArtifactRef(
    ref: requireRef ? _string(value, 'ref') : '',
    url: _string(value, 'url'),
    sha256: sha,
    bytes: _positiveInt(value, 'bytes'),
  );
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw ManifestFormatException('$key ausente ou não é string não-vazia');
  }
  return value;
}

int _positiveInt(Map<String, Object?> json, String key) {
  final value = _nonNegativeInt(json, key);
  if (value <= 0) throw ManifestFormatException('$key deve ser positivo');
  return value;
}

int _nonNegativeInt(Map<String, Object?> json, String key) {
  final value = json[key];
  // `is! int` recusa `1.0` de propósito: o schema diz inteiro, e um double
  // que chegou até aqui indica emissor fora do contrato.
  if (value is! int || value < 0) {
    throw ManifestFormatException('$key ausente ou não é inteiro não-negativo');
  }
  return value;
}
