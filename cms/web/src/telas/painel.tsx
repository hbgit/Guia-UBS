/**
 * O painel, e o estado vazio por papel.
 *
 * ## Por que o estado vazio e o conteudo principal desta tela
 *
 * O primeiro operador do sistema e criado por `cms:create-admin` e e um
 * **admin** — e `admin` nao tem `content:write` nem `approval:decide`
 * (`auth/permissions.ts`: "concentrar os tres no admin desfaria a segregacao com
 * uma linha de tabela"). Ou seja: a primeira pessoa a abrir esta interface e
 * exatamente a que menos botoes enxerga.
 *
 * Sem dizer isso em voz alta, a conclusao razoavel de quem chega e "esta
 * quebrado". O texto por papel existe para transformar uma tela vazia numa tela
 * que explica a segregacao que a LGPD-RF11 exige.
 */
import type { AdminRole } from '@guia-ubs/cms/src/auth/permissions.js';

import { ROTAS_DA_SPA } from '../rotas.js';
import { useSessao } from '../sessao.js';

/**
 * Amarrado ao enum do servidor: um papel novo em `ADMIN_ROLES` deixa este
 * `Record` incompleto e reprova `tsc -p cms/web` no mesmo PR. E a versao barata
 * da cadeia de type safety da §3 do plano.
 */
const PAPEIS: Readonly<Record<AdminRole, { titulo: string; faz: string; naoFaz: string }>> = {
  editor: {
    titulo: 'Editor',
    faz: 'Escreve conteudo e regras, cria e submete releases para revisao.',
    naoFaz: 'Nao aprova o que escreve — quem aprova e o revisor clinico.',
  },
  clinical_reviewer: {
    titulo: 'Revisor clinico',
    faz: 'Le conteudo, simula regras e aprova ou rejeita releases.',
    naoFaz: 'Nao escreve conteudo — quem escreve e o editor.',
  },
  admin: {
    titulo: 'Administrador',
    faz: 'Gere operadores, reenfileira job travado e revoga pack publicado.',
    naoFaz:
      'Nao escreve conteudo nem aprova release. Nao e limitacao da tela: e a segregacao ' +
      'de funcoes, e concentrar os tres papeis num so a desfaria.',
  },
};

/**
 * O que a interface AINDA nao cobre, DERIVADO das rotas que existem.
 *
 * Uma casca com telas de entrada da a impressao de que o resto tambem existe. E
 * a mesma armadilha de um manual cheio de `curl` que parece um sistema operavel
 * — e a correcao e a mesma: declarar a lacuna onde ela seria sentida.
 *
 * A lista era literal ate a fase B, e mentiu no mesmo commit em que a tela de
 * releases nasceu: o painel continuava mandando o editor usar `curl` para uma
 * coisa que ele acabara de ganhar em botao. Agora cada area aponta para o
 * PREFIXO de rota que a cobriria, e a area some da lista quando a rota aparece.
 * O mesmo motivo de `PII_COLUMNS` e `APPEND_ONLY_TABLES` serem percorridas por
 * teste: lista redigida a parte envelhece e passa a mentir.
 */
const AREAS_DO_MANUAL: readonly { rotulo: string; prefixo: string }[] = [
  { rotulo: 'Conteudo (§4.1 e §4.2 do manual)', prefixo: '/conteudo' },
  { rotulo: 'Regras e simulacao (§4.3)', prefixo: '/regras' },
  { rotulo: 'Releases, submissao e aprovacao (§4.4 e §4.5)', prefixo: '/releases' },
];

function aindaNoCurl(): readonly string[] {
  return AREAS_DO_MANUAL.filter(
    (a) => !ROTAS_DA_SPA.some((r) => r.caminho === a.prefixo),
  ).map((a) => a.rotulo);
}

export function Painel() {
  const { operador, carregando } = useSessao();

  if (carregando) return <p>Carregando…</p>;
  if (!operador) return null;

  const papel = PAPEIS[operador.role as AdminRole] as (typeof PAPEIS)[AdminRole] | undefined;
  const pendentes = aindaNoCurl();

  return (
    <main>
      <h1>Painel</h1>

      <section className="cartao">
        <h2>{papel?.titulo ?? operador.role}</h2>
        <p>{papel?.faz}</p>
        <p className="nota">{papel?.naoFaz}</p>
      </section>

      {pendentes.length > 0 && (
        <section className="cartao">
          <h2>Ainda pela API</h2>
          <p>Estas partes do manual continuam sendo feitas por chamadas HTTP:</p>
          <ul>
            {pendentes.map((item) => (
              <li key={item}>{item}</li>
            ))}
          </ul>
          <p className="nota">
            Veja <code>docs/operacao.md</code>.
          </p>
        </section>
      )}
    </main>
  );
}
