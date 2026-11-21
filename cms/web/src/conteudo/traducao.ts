/**
 * Conversao entre a linha de `*_translation` e o formulario de traducao.
 *
 * O `<textarea>` so conhece string, e o banco tem `audioRef` nulavel com FK para
 * `asset`: um `''` que escapasse do formulario seria recusado pela FK, e toda
 * regravacao de traducao sem audio falharia. Por isso o vazio vive SO aqui
 * dentro, e na fronteira vira `null`.
 */

/** Os `campos` da linha, com nulo/ausente omitido (nunca `''`). */
export function paraFormulario(
  linha: Record<string, unknown>,
  campos: readonly string[],
): Record<string, string> {
  const texto: Record<string, string> = {};
  for (const c of campos) {
    const v = linha[c];
    if (v !== null && v !== undefined) texto[c] = String(v);
  }
  return texto;
}

/** Todo campo de `campos`; vazio ou ausente vira `null`. */
export function paraEnvio(
  texto: Record<string, string>,
  campos: readonly string[],
): Record<string, string | null> {
  const corpo: Record<string, string | null> = {};
  for (const c of campos) corpo[c] = texto[c] ? texto[c] : null;
  return corpo;
}
