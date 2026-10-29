/// A versão vigente dos termos de uso e a regra de aceite (ADR-004).
///
/// Fora de `ui/` de propósito: o worker do WorkManager, que não tem tela,
/// precisa da mesma regra para não baixar o modelo sem aceite.
library;

/// Versão vigente dos termos de uso do app (`termos_{pt,es}.md`).
///
/// Constante, e não leitura do asset, porque decide o portão "li e concordo"
/// no PRIMEIRO quadro: uma leitura assíncrona deixaria a pessoa entrar no app
/// e, um instante depois, puxaria o portão no meio do uso. Um teste confere
/// que os dois arquivos declaram exatamente esta versão.
const String termsVersion = '2026-10-29';

/// `true` só com aceite da versão VIGENTE. Aceite de versão anterior não vale
/// para a nova; sem resposta, o modelo não é baixado nem carregado.
bool acceptsCurrentTerms({required String? version, required bool accepted}) =>
    accepted && version == termsVersion;
