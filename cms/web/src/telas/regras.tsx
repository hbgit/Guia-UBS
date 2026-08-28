/**
 * O editor de regras e a simulacao clinica.
 *
 * ## Por que a simulacao e o coracao desta tela
 *
 * Uma regra de roteamento decide se o aplicativo manda alguem para a UBS ou para
 * a emergencia. A simulacao roda a regra proposta contra os casos golden e diz
 * **quais vereditos mudam** — e poe isso na frente de quem decide enquanto ainda
 * da para desistir.
 *
 * `FALSO_NEGATIVO` e classe a parte, e nao um item de lista: e o caso em que o
 * app mandaria para casa alguem que precisava de emergencia. `ESCALADA` e
 * revisao clinica; falso negativo e evento de seguranca do paciente
 * (`operacao.md` §4.3).
 *
 * ## `Simular` esta sempre disponivel; `Salvar`, nao
 *
 * `POST /api/rules/simular` exige apenas `content:read` — deliberadamente aberto
 * ao revisor clinico, que precisa poder perguntar "o que esta regra faria?" sem
 * ter permissao de escreve-la. E aqui que a segregacao vira algo que se ve.
 */
import { useCallback, useEffect, useState, type FormEvent } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';

import type { Simulacao } from '@guia-ubs/cms/src/services/rule-simulation.js';
import type { ProblemaDeRegra } from '@guia-ubs/cms/src/services/rule-validation.js';

import { ErroApi, acionar, buscar, criar, gravar, ler } from '../api/api.js';
import { COMO_RESOLVER, semDesfecho } from '../regras/problemas.js';
import { useSessao } from '../sessao.js';

interface Termo {
  groupNo: number;
  tokenId: string;
  negated: boolean;
}

interface Regra {
  id: string;
  priority: number;
  outcomeId: string;
  status: string;
  rationale?: string | null;
}

interface RespostaDaSimulacao {
  problemas: ProblemaDeRegra[];
  simulacao: Simulacao | null;
}

// ---------------------------------------------------------------------------

export function ListaDeRegras() {
  const [itens, setItens] = useState<Regra[]>();
  const [erro, setErro] = useState<string>();
  const { operador } = useSessao();

  useEffect(() => {
    buscar<{ items: Regra[] }>('/api/rules')
      .then((r) => setItens(r.items))
      .catch(() => setErro('Nao foi possivel carregar as regras.'));
  }, []);

  if (erro)
    return (
      <main>
        <p className="erro" role="alert">
          {erro}
        </p>
      </main>
    );
  if (!itens) return <main>Carregando…</main>;

  return (
    <main>
      <h1>Regras de roteamento</h1>
      {operador?.permissions.includes('content:write') && <Link to="/regras/nova">Nova regra</Link>}

      {itens.length === 0 ? (
        <p className="nota">Nenhuma regra ainda.</p>
      ) : (
        <table>
          <thead>
            <tr>
              <th>Regra</th>
              <th>Prioridade</th>
              <th>Desfecho</th>
              <th>Situacao</th>
            </tr>
          </thead>
          <tbody>
            {itens.map((r) => (
              <tr key={r.id}>
                <td>
                  <Link to={`/regras/${r.id}`}>{r.id}</Link>
                </td>
                <td>{r.priority}</td>
                <td>{r.outcomeId}</td>
                <td>{r.status === 'approved' ? 'aprovada' : 'rascunho'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </main>
  );
}

// ---------------------------------------------------------------------------

function PainelDeSimulacao({
  problemas,
  simulacao,
}: {
  problemas: readonly ProblemaDeRegra[];
  simulacao: Simulacao | null;
}) {
  if (problemas.length === 0 && !simulacao) return null;

  const falsos = simulacao?.muda.filter((m) => m.classe === 'FALSO_NEGATIVO') ?? [];
  const outras = simulacao?.muda.filter((m) => m.classe !== 'FALSO_NEGATIVO') ?? [];

  return (
    <section className="cartao">
      <h2>Simulacao</h2>

      {/*
        TODOS os problemas de uma vez. "Corrigir um por requisicao faria qualquer
        revisor desistir na terceira" — e o servidor ja os devolve juntos, no 422
        e na simulacao.
      */}
      {problemas.length > 0 && (
        <ul className="problemas">
          {problemas.map((p) => (
            <li key={p.codigo + p.mensagem}>
              <strong>{p.mensagem}</strong>
              <br />
              <span className="nota">{COMO_RESOLVER[p.codigo]}</span>
            </li>
          ))}
        </ul>
      )}

      {simulacao === null && semDesfecho(problemas) && (
        <p className="nota">
          Sem desfecho cadastrado nao ha o que comparar: a simulacao precisa dos desfechos
          existentes para saber o que mudaria. Cadastre em <Link to="/conteudo">Conteudo</Link>.
        </p>
      )}

      {simulacao && (
        <>
          {/*
            O bloco que interrompe o trabalho. Vem primeiro, e numa regiao de
            alerta: e o caso em que o app mandaria para casa alguem que precisava
            de emergencia.
          */}
          {falsos.length > 0 && (
            <div className="falso-negativo" role="alert">
              <h3>{simulacao.falsosNegativos} caso(s) deixariam de ir para a emergencia</h3>
              <p>Isto e evento de seguranca do paciente, nao divergencia de opiniao clinica.</p>
              <ul>
                {falsos.map((m) => (
                  <li key={m.casoId}>
                    <code>{m.casoId}</code> [{m.tokens.join(' + ')}]: {m.de} → {m.para}
                  </li>
                ))}
              </ul>
            </div>
          )}

          {outras.length > 0 && (
            <>
              <h3>Outras mudancas</h3>
              <ul>
                {outras.map((m) => (
                  <li key={m.casoId}>
                    <code>{m.casoId}</code> [{m.tokens.join(' + ')}]: {m.de} → {m.para} (
                    {m.classe === 'ESCALADA' ? 'escalada' : 'outra'})
                  </li>
                ))}
              </ul>
            </>
          )}

          {/*
            O tamanho da amostra. `jaVermelhos` existe para uma regra inofensiva
            nao parecer inofensiva: se metade dos casos ja diverge do esperado
            ANTES da regra, "nada mudou" nao quer dizer "esta tudo bem".
          */}
          <p className="nota">
            {simulacao.inalterados} de {simulacao.total} casos inalterados.{' '}
            {simulacao.jaVermelhos > 0 && (
              <>
                <strong>{simulacao.jaVermelhos}</strong> ja divergiam do esperado antes desta
                regra.
              </>
            )}
          </p>
        </>
      )}
    </section>
  );
}

// ---------------------------------------------------------------------------

export function EditorDeRegra() {
  const { id } = useParams();
  const navegar = useNavigate();
  const { operador } = useSessao();
  const podeEscrever = operador?.permissions.includes('content:write') ?? false;

  const [regra, setRegra] = useState<Regra>({
    // Um id de rascunho: `simular` exige `id` e `priority`, entao uma regra nova
    // precisa de ambos ANTES de poder ser simulada. Editavel, e nao imposto.
    id: id ?? 'regra-nova',
    priority: 100,
    outcomeId: '',
    status: 'draft',
    rationale: '',
  });
  const [termos, setTermos] = useState<Termo[]>([{ groupNo: 0, tokenId: '', negated: false }]);
  const [versao, setVersao] = useState<{ dados: unknown; versao: number }>();
  const [resultado, setResultado] = useState<RespostaDaSimulacao>();
  const [erro, setErro] = useState<string>();
  const [ok, setOk] = useState<string>();
  const [ocupado, setOcupado] = useState(false);
  const [cientePerigo, setCientePerigo] = useState(false);

  const aprovada = regra.status === 'approved';
  const falsosNegativos = resultado?.simulacao?.falsosNegativos ?? 0;

  const carregar = useCallback(async () => {
    if (!id) return;
    const lido = await ler<{ regra: Regra; termos: Termo[] }>(`/api/rules/${id}`);
    setRegra(lido.dados.regra);
    setTermos(
      lido.dados.termos.length > 0 ? lido.dados.termos : [{ groupNo: 0, tokenId: '', negated: false }],
    );
    setVersao({ dados: lido.dados, versao: lido.versao });
  }, [id]);

  useEffect(() => {
    carregar().catch(() => setErro('Nao foi possivel carregar a regra.'));
  }, [carregar]);

  function corpoDaRegra() {
    return {
      id: regra.id,
      priority: Number(regra.priority),
      outcomeId: regra.outcomeId,
      rationale: regra.rationale ?? '',
      terms: termos.filter((t) => t.tokenId.trim() !== ''),
    };
  }

  async function simular() {
    setErro(undefined);
    setOk(undefined);
    setOcupado(true);
    try {
      setResultado(await acionar<RespostaDaSimulacao>('/api/rules/simular', corpoDaRegra()));
    } catch {
      setErro('Nao foi possivel simular.');
    } finally {
      setOcupado(false);
    }
  }

  async function salvar(e: FormEvent) {
    e.preventDefault();
    setErro(undefined);
    setOk(undefined);
    setOcupado(true);
    try {
      if (versao) {
        await gravar(versao, `/api/rules/${regra.id}`, corpoDaRegra());
        setOk('Regra gravada.');
        await carregar();
      } else {
        await criar('/api/rules', corpoDaRegra());
        setOk('Regra criada.');
        navegar(`/regras/${regra.id}`);
      }
    } catch (e) {
      if (e instanceof ErroApi && e.falha.tipo === 'regra_invalida') {
        // O 422 alimenta o MESMO painel da simulacao: uma peca, duas fontes.
        setResultado({ problemas: [...e.falha.problemas], simulacao: null });
      } else if (e instanceof ErroApi && e.falha.tipo === 'conflito_estado' && e.falha.next) {
        setErro('Regra aprovada nao e editada. Crie uma revisao para trabalhar sobre ela.');
      } else if (e instanceof ErroApi && e.falha.tipo === 'conflito_versao') {
        setErro(
          `Alguem gravou antes de voce (versao ${e.falha.versaoAtual}). Recarregue e refaca a alteracao.`,
        );
      } else {
        setErro('Nao foi possivel gravar.');
      }
    } finally {
      setOcupado(false);
    }
  }

  async function abrirRevisao() {
    const novoId = `${regra.id}-rev`;
    try {
      await criar(`/api/rules/${regra.id}/revisao`, { id: novoId });
      navegar(`/regras/${novoId}`);
    } catch {
      setErro('Nao foi possivel criar a revisao.');
    }
  }

  const grupos = [...new Set(termos.map((t) => t.groupNo))].sort((a, b) => a - b);

  return (
    <main>
      <h1>{id ? `Regra ${regra.id}` : 'Nova regra'}</h1>

      {erro && (
        <p className="erro" role="alert">
          {erro}
        </p>
      )}
      {ok && (
        <p className="sucesso" role="alert">
          {ok}
        </p>
      )}

      {aprovada && (
        <div className="aviso">
          <p>
            Regra aprovada nao e editada — trabalhe sobre uma revisao, que nasce como rascunho e
            deixa a original intacta.
          </p>
          {podeEscrever && (
            <button type="button" onClick={() => void abrirRevisao()}>
              Criar revisao
            </button>
          )}
          {/*
            A lacuna, dita na propria tela. Nao ha rota que mova uma regra de
            rascunho para aprovada — nem o POST, nem o PUT, nem `/revisao`. Como
            o extrator filtra por `approved`, regra escrita aqui ainda nao chega
            ao pack. Esconder isso faria alguem editar por horas sem efeito.
          */}
          <p className="nota">
            O CMS ainda nao tem rota que mova uma regra de rascunho para aprovada — ver §6 do
            manual de operacao.
          </p>
        </div>
      )}

      <form onSubmit={salvar}>
        <section className="cartao">
          <h2>Identificacao</h2>

          <label htmlFor="regra-id">Identificador</label>
          <input
            id="regra-id"
            required
            disabled={Boolean(id)}
            value={regra.id}
            onChange={(e) => setRegra((r) => ({ ...r, id: e.target.value }))}
          />

          <label htmlFor="prioridade">Prioridade</label>
          <input
            id="prioridade"
            type="number"
            required
            value={regra.priority}
            onChange={(e) => setRegra((r) => ({ ...r, priority: Number(e.target.value) }))}
          />
          <p className="nota">Define a ordem de avaliacao. Duas regras nao podem repeti-la.</p>

          <label htmlFor="desfecho">Desfecho</label>
          <input
            id="desfecho"
            required
            value={regra.outcomeId}
            onChange={(e) => setRegra((r) => ({ ...r, outcomeId: e.target.value }))}
          />

          <label htmlFor="rationale">Justificativa clinica</label>
          <textarea
            id="rationale"
            rows={2}
            value={regra.rationale ?? ''}
            onChange={(e) => setRegra((r) => ({ ...r, rationale: e.target.value }))}
          />
        </section>

        <section className="cartao">
          <h2>Condicao</h2>
          {/*
            Forma normal disjuntiva: E dentro do grupo, OU entre grupos. O mesmo
            avaliador (`contract/src/rules.ts`) roda aqui, no packer e no gate do
            aplicativo — nao ha copia local.
          */}
          <p className="nota">
            A regra dispara quando <strong>qualquer grupo</strong> casar por inteiro. Dentro de um
            grupo, todos os termos precisam casar.
          </p>

          {grupos.map((g) => (
            <fieldset key={g}>
              <legend>Grupo {g + 1}</legend>
              {termos
                .map((t, i) => ({ t, i }))
                .filter(({ t }) => t.groupNo === g)
                .map(({ t, i }) => (
                  <div key={i} className="acao">
                    <input
                      aria-label={`Token do grupo ${g + 1}`}
                      value={t.tokenId}
                      onChange={(e) =>
                        setTermos((ts) =>
                          ts.map((x, j) => (j === i ? { ...x, tokenId: e.target.value } : x)),
                        )
                      }
                    />
                    <label>
                      <input
                        type="checkbox"
                        checked={t.negated}
                        onChange={(e) =>
                          setTermos((ts) =>
                            ts.map((x, j) => (j === i ? { ...x, negated: e.target.checked } : x)),
                          )
                        }
                      />{' '}
                      negado
                    </label>
                    <button
                      type="button"
                      onClick={() => setTermos((ts) => ts.filter((_, j) => j !== i))}
                    >
                      Remover
                    </button>
                  </div>
                ))}
              <button
                type="button"
                onClick={() =>
                  setTermos((ts) => [...ts, { groupNo: g, tokenId: '', negated: false }])
                }
              >
                Acrescentar termo
              </button>
            </fieldset>
          ))}

          <button
            type="button"
            onClick={() =>
              setTermos((ts) => [
                ...ts,
                { groupNo: Math.max(...ts.map((t) => t.groupNo)) + 1, tokenId: '', negated: false },
              ])
            }
          >
            Acrescentar grupo (OU)
          </button>
        </section>

        <div className="acao">
          {/*
            Sempre habilitado: `simular` exige so `content:read`. E o que permite
            ao revisor clinico perguntar "o que esta regra faria?" sem poder
            escreve-la.
          */}
          <button type="button" disabled={ocupado} onClick={() => void simular()}>
            Simular
          </button>

          {podeEscrever && !aprovada && (
            <button type="submit" disabled={ocupado || (falsosNegativos > 0 && !cientePerigo)}>
              Salvar
            </button>
          )}
        </div>

        {/*
          Guarda de INTERFACE, nao autorizacao: o servidor nao bloqueia salvar com
          falso negativo. Ela existe para que a decisao seja deliberada, e nao um
          clique a mais — e o texto diz isso, para ninguem confundir com garantia.
        */}
        {podeEscrever && falsosNegativos > 0 && (
          <label className="aviso">
            <input
              type="checkbox"
              checked={cientePerigo}
              onChange={(e) => setCientePerigo(e.target.checked)}
            />{' '}
            Estou ciente de que esta regra retira {falsosNegativos} caso(s) da emergencia, e
            justifiquei acima. (Esta trava e da interface; o servidor nao a impoe.)
          </label>
        )}
      </form>

      {resultado && (
        <PainelDeSimulacao problemas={resultado.problemas} simulacao={resultado.simulacao} />
      )}

      <Link to="/regras">Voltar para a lista</Link>
    </main>
  );
}
