/// Decodificação restrita da saída do modelo local.
///
/// ===========================================================================
/// CÓDIGO CRÍTICO DE SEGURANÇA DO PACIENTE
/// ===========================================================================
///
/// A saída do SLM é tratada como **entrada não confiável**. Ela não é
/// interpretada, não é parseada como estrutura e não pode carregar severidade:
/// o único poder que o modelo tem é NOMEAR um desfecho que já existe no pacote
/// e já passou por dual review clínico.
///
/// A severidade vem sempre da tabela `routing_outcome`, nunca do texto gerado.
/// Combinado com `mergeVerdict` (INV-1), isso deixa o modelo com um espaço de
/// ação minúsculo: escalar para um desfecho revisado, ou ser ignorado.
///
/// Toda ambiguidade resolve para `null` ("sem opinião"), o que devolve a
/// decisão ao gate determinístico. Alucinar não é um caminho de falha exótico:
/// é o caminho comum, e ele é seguro.
library;

import '../domain/routing_rule.dart';
import 'triage_engine.dart';

/// Teto de caracteres examinados. Um modelo em laço degenerado pode emitir
/// texto até o limite de tokens; não há motivo para varrer tudo.
const int maxDecodedChars = 512;

/// Converte a saída bruta do modelo em uma sugestão, ou `null`.
///
/// Retorna `null` quando:
/// * nenhum identificador conhecido aparece (alucinação, texto vazio, lixo);
/// * mais de um identificador aparece — o modelo não escolheu, e não escolhemos
///   por ele;
/// * dois identificadores do pacote colidem ao normalizar (pacote ambíguo).
EngineSuggestion? decodeSuggestion(String raw, RuleModel model) {
  if (raw.isEmpty) return null;

  // Índice normalizado. Se dois desfechos distintos colapsarem na mesma chave,
  // o pacote é ambíguo e nenhuma resposta do modelo pode ser resolvida com
  // segurança — abstemo-nos por completo em vez de escolher pelo primeiro.
  final byNormalized = <String, String>{};
  for (final id in model.outcomes.keys) {
    final key = id.toUpperCase();
    if (byNormalized.containsKey(key)) return null;
    byNormalized[key] = id;
  }

  final window =
      raw.length > maxDecodedChars ? raw.substring(0, maxDecodedChars) : raw;

  // Compara palavra inteira, não subsequência: com desfechos `EMERGENCY` e
  // `EMERGENCY_PEDIATRICA` no mesmo pacote, busca por substring acharia os dois
  // em qualquer um dos casos e a decodificação viraria sorteio.
  final words = window.toUpperCase().split(RegExp(r'[^A-Z0-9_]+'));

  final matched = <String>{};
  for (final word in words) {
    final id = byNormalized[word];
    if (id != null) matched.add(id);
  }

  if (matched.length != 1) return null;

  final outcome = model.outcomes[matched.first];
  if (outcome == null) return null;

  return EngineSuggestion(
    outcomeId: outcome.id,
    severityLevel: outcome.severityLevel,
  );
}
