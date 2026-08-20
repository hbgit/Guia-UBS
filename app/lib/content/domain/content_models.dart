/// O que as telas leem do `content.db`.
///
/// Modelos deliberadamente magros: são projeções de leitura, não entidades de
/// domínio. O app nunca escreve conteúdo — ele troca o arquivo inteiro quando o
/// sync instala uma versão nova (FSM-B).
///
/// Todo texto aqui já vem **resolvido para um idioma**, e carrega junto se
/// aquele texto é do idioma pedido ou de recuo. Ver [Localized].
library;

import 'package:meta/meta.dart';

/// Texto vindo do pack, com a procedência do idioma.
///
/// O packer **bloqueia a publicação** de pack com tradução faltando, então
/// `isFallback` verdadeiro no aparelho significa pack corrompido ou idioma que
/// o pack não conhece — defeito, não caminho normal. Mesmo assim o campo
/// existe, porque a alternativa a recuar é sumir com o item da tela, e sumir
/// com "Onde ir" de quem precisa é pior que mostrá-lo em português para um
/// hispanofalante: o ícone continua correto, e as duas línguas são próximas.
/// O sinal fica disponível para telemetria agregada contar o defeito.
@immutable
class Localized {
  const Localized(this.value, {this.isFallback = false});

  final String value;

  /// `true` quando o idioma pedido não existia e caiu no idioma base.
  final bool isFallback;

  @override
  String toString() => value;
}

/// Referência a um arquivo do pack (ícone, imagem, áudio).
@immutable
class AssetRef {
  const AssetRef({
    required this.ref,
    required this.kind,
    required this.path,
    required this.sha256,
    required this.bytes,
  });

  final String ref;
  final String kind;
  final String path;
  final String sha256;
  final int bytes;
}

/// Um sintoma que o usuário pode tocar (CAP-03).
@immutable
class SymptomToken {
  const SymptomToken({
    required this.id,
    required this.kind,
    required this.iconRef,
    required this.label,
    required this.sortOrder,
    this.audioRef,
  });

  final String id;

  /// `region` (parte do corpo), `symptom`, `modifier`… definido pela ontologia.
  final String kind;

  final String iconRef;
  final Localized label;
  final int sortOrder;
  final String? audioRef;
}

/// Cartão de orientação — a saída da triagem e das telas estáticas.
@immutable
class ContentCard {
  const ContentCard({
    required this.id,
    required this.kind,
    required this.iconRef,
    required this.colorToken,
    required this.title,
    this.body,
    this.audioRef,
  });

  final String id;
  final String kind;
  final String iconRef;

  /// Token de cor **do pack**, não uma cor. Quem converte para pixel é a UI,
  /// via `GubsColors` — o pack não dita paleta.
  final String colorToken;

  final Localized title;
  final Localized? body;
  final String? audioRef;
}

/// Local de atendimento: UBS, UPA, hospital.
@immutable
class Venue {
  const Venue({
    required this.id,
    required this.iconRef,
    required this.colorToken,
    required this.label,
    this.audioRef,
  });

  final String id;
  final String iconRef;
  final String colorToken;
  final Localized label;
  final String? audioRef;
}

/// Serviço oferecido por um local (vacina, curativo, consulta).
@immutable
class Service {
  const Service({
    required this.id,
    required this.venueId,
    required this.iconRef,
    required this.label,
    required this.sortOrder,
    this.audioRef,
  });

  final String id;
  final String venueId;
  final String iconRef;
  final Localized label;
  final int sortOrder;
  final String? audioRef;
}

/// Documento que o usuário deve levar (RF-08).
@immutable
class RequiredDocument {
  const RequiredDocument({
    required this.id,
    required this.iconRef,
    required this.label,
    required this.required,
    this.hint,
    this.imageRef,
    this.audioRef,
  });

  final String id;
  final String iconRef;
  final Localized label;

  /// `false` para documentos que ajudam mas não impedem o atendimento. A
  /// distinção importa: ninguém pode ser mandado embora por falta de
  /// comprovante de endereço, e a tela precisa poder dizer isso.
  final bool required;

  final Localized? hint;
  final String? imageRef;
  final String? audioRef;
}

/// Passo do fluxo de atendimento (RF-09).
@immutable
class FlowStep {
  const FlowStep({
    required this.id,
    required this.venueId,
    required this.stepOrder,
    required this.iconRef,
    required this.title,
    this.body,
    this.audioRef,
  });

  final String id;
  final String venueId;
  final int stepOrder;
  final String iconRef;
  final Localized title;
  final Localized? body;
  final String? audioRef;
}

/// Identidade do pack ativo.
@immutable
class PackInfo {
  const PackInfo({
    required this.packVersion,
    required this.schemaVersion,
    required this.builtAt,
    required this.defaultOutcomeId,
    this.municipalityCode,
    this.sourceCommit,
  });

  final int packVersion;
  final String schemaVersion;
  final String builtAt;
  final String defaultOutcomeId;
  final String? municipalityCode;
  final String? sourceCommit;
}
