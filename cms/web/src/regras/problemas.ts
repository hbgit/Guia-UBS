/**
 * O que cada problema de validacao significa para quem escreve a regra.
 *
 * `Record<ProblemaDeRegra['codigo'], …>` de proposito: um codigo novo em
 * `rule-validation.ts` deixa este mapa incompleto e reprova `tsc -p cms/web` no
 * mesmo PR. A alternativa — cair num texto generico — faria a tela mostrar
 * "problema desconhecido" para uma validacao que alguem acabou de escrever com
 * cuidado.
 *
 * O `mensagem` do servidor ja e legivel; o que se acrescenta aqui e o QUE FAZER.
 */
import type { ProblemaDeRegra } from '@guia-ubs/cms/src/services/rule-validation.js';

export type CodigoDeProblema = ProblemaDeRegra['codigo'];

export const COMO_RESOLVER: Readonly<Record<CodigoDeProblema, string>> = {
  sem_termos: 'Acrescente ao menos um termo — uma regra sem termos nunca dispara.',
  token_inexistente: 'O token citado nao existe. Confira o identificador ou cadastre-o em Conteudo.',
  token_descontinuado:
    'O token esta marcado como descontinuado. Escolha o que o substituiu, ou reative-o em Conteudo.',
  desfecho_inexistente:
    'O desfecho nao existe. Cadastre-o em Conteudo antes — sem ele nao ha o que comparar na simulacao.',
  grupo_contraditorio:
    'O grupo exige e nega o mesmo token, entao ele nunca casa. Remova um dos dois.',
  grupos_duplicados: 'Dois grupos sao identicos. Um deles nao muda nada; remova-o.',
  prioridade_duplicada:
    'Outra regra ja usa esta prioridade. Escolha outra para a ordem de avaliacao ficar definida.',
};

/**
 * `simulacao` vem `null` exatamente quando ha `desfecho_inexistente`.
 *
 * Nao e uma coincidencia a memorizar: `desfechoPadrao()` deriva o padrao dos
 * desfechos cadastrados e lanca quando nao ha nenhum, e a rota transforma isso em
 * `simulacao: null` em vez de 500. A tela precisa dizer POR QUE nao ha simulacao,
 * senao parece que ela falhou.
 */
export function semDesfecho(problemas: readonly ProblemaDeRegra[]): boolean {
  return problemas.some((p) => p.codigo === 'desfecho_inexistente');
}
