/**
 * Leitura de erro do banco — um lugar so.
 *
 * ## Por que isto existe
 *
 * O Drizzle SUBSTITUI a mensagem do driver por `Failed query: <sql>` e guarda a
 * original em `cause`. Quem casar so com `error.message` nunca ve
 * `FOREIGN KEY constraint failed` — e o efeito nao e cosmetico: a protecao
 * referencial funcionando passa a responder 500, o editor le "erro interno" e
 * aprende a insistir numa operacao que o banco esta certo em recusar.
 *
 * O defeito apareceu tres vezes no item 18 (fabrica de CRUD, editor de regras e
 * o log de erro do app) antes de virar modulo. Sao os tres unicos lugares que
 * interpretam erro de banco, e agora leem pela mesma funcao.
 */

/** Mensagem do erro concatenada com toda a cadeia de `cause`. */
export function mensagemDoErro(erro: unknown): string {
  const partes: string[] = [];
  let atual: unknown = erro;
  for (let profundidade = 0; atual instanceof Error && profundidade < 5; profundidade += 1) {
    partes.push(atual.message);
    atual = (atual as { cause?: unknown }).cause;
  }
  return partes.length > 0 ? partes.join(' <- ') : String(erro);
}

export type ClasseDeViolacao = 'referencia' | 'duplicidade' | 'dominio' | null;

/** Classifica a violacao, ou `null` quando o erro nao e de integridade. */
export function classificarViolacao(erro: unknown): ClasseDeViolacao {
  const mensagem = mensagemDoErro(erro);
  if (/FOREIGN KEY constraint failed/i.test(mensagem)) return 'referencia';
  if (/UNIQUE constraint failed|PRIMARY KEY/i.test(mensagem)) return 'duplicidade';
  if (/CHECK constraint failed/i.test(mensagem)) return 'dominio';
  return null;
}

export const MENSAGENS: Readonly<Record<Exclude<ClasseDeViolacao, null>, string>> = {
  referencia:
    'a operacao violaria uma referencia: outra linha depende desta, ou uma referencia informada nao existe',
  duplicidade: 'ja existe uma linha com essa chave',
  dominio: 'valor fora do dominio permitido pelo banco',
};

export const STATUS: Readonly<Record<Exclude<ClasseDeViolacao, null>, 409 | 422>> = {
  referencia: 409,
  duplicidade: 409,
  dominio: 422,
};
