/**
 * As telas de release: lista, criacao e o detalhe onde se decide.
 *
 * ## Os botoes vem do SERVIDOR
 *
 * `GET /api/releases/<id>` devolve `transicoes` — o que e possivel a partir do
 * estado atual —, e a tela renderiza um botao por entrada. Nao ha `if` sobre
 * estado nesta tela, e nao deve haver: seria a segunda copia da FSM que a
 * `operacao.md` §4.4 proibe, e a copia que ficasse para tras ofereceria uma acao
 * que o servidor recusa (ou esconderia uma que ele permite).
 *
 * `acoes.ts` traduz `(de, para)` na chamada HTTP. Isso e transporte, nao regra.
 *
 * ## `transicionou: false` e SUCESSO
 *
 * Quando o quorum ainda nao fechou, o servidor responde `200` com
 * `{ transicionou: false, faltam: N }`. Pintar isso de vermelho faria o revisor
 * achar que o voto se perdeu — e o comentario do proprio servidor diz que essa
 * era a razao de nao devolver erro.
 */
import { useCallback, useEffect, useState, type ChangeEvent, type FormEvent, type ReactNode } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';

import type {
  Ator,
  ReleaseStatus,
  Transicao,
} from '@guia-ubs/cms/src/services/approval-workflow.js';

import { ErroApi, acionar, buscar, criar } from '../api/api.js';
import { ROTULO_DO_ESTADO, acaoDe } from '../releases/acoes.js';
import { useSessao } from '../sessao.js';

interface Release {
  id: string;
  municipalityId: string;
  packVersion: number;
  schemaVersion: string;
  status: ReleaseStatus;
  claimedAt?: string | null;
  publishedAt?: string | null;
  createdBy?: string | null;
  createdAt?: string | null;
}

function Aviso({ tom, children }: { tom: 'erro' | 'ok'; children: ReactNode }) {
  return (
    <p className={tom === 'erro' ? 'erro' : 'sucesso'} role="alert">
      {children}
    </p>
  );
}

// ---------------------------------------------------------------------------

export function ListaDeReleases() {
  const [itens, setItens] = useState<Release[]>();
  const [erro, setErro] = useState<string>();
  const { operador } = useSessao();

  useEffect(() => {
    buscar<{ items: Release[] }>('/api/releases')
      .then((r) => setItens(r.items))
      .catch(() => setErro('Nao foi possivel carregar as releases.'));
  }, []);

  if (erro) return <main>{<Aviso tom="erro">{erro}</Aviso>}</main>;
  if (!itens) return <main>Carregando…</main>;

  return (
    <main>
      <h1>Releases</h1>
      {/*
        `content:write` desenha o botao; quem autoriza e o `requirePermission` da
        rota. Um `admin` nao ve "Nova release" — e isso e a segregacao aparecendo,
        nao uma limitacao da tela.
      */}
      {operador?.permissions.includes('content:write') && (
        <Link to="/releases/nova">Nova release</Link>
      )}

      {itens.length === 0 ? (
        <p className="nota">Nenhuma release ainda.</p>
      ) : (
        <table>
          <thead>
            <tr>
              <th>Release</th>
              <th>Municipio</th>
              <th>Versao</th>
              <th>Estado</th>
            </tr>
          </thead>
          <tbody>
            {itens.map((r) => (
              <tr key={r.id}>
                <td>
                  <Link to={`/releases/${r.id}`}>{r.id}</Link>
                </td>
                <td>{r.municipalityId}</td>
                <td>{r.packVersion}</td>
                <td>{ROTULO_DO_ESTADO[r.status]}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </main>
  );
}

// ---------------------------------------------------------------------------

export function NovaRelease() {
  const navegar = useNavigate();
  const [campos, setCampos] = useState({
    id: '',
    municipalityId: '',
    packVersion: '',
    schemaVersion: '',
  });
  const [erro, setErro] = useState<string>();
  const [enviando, setEnviando] = useState(false);

  function ao(nome: keyof typeof campos) {
    return (e: ChangeEvent<HTMLInputElement>) => setCampos((c) => ({ ...c, [nome]: e.target.value }));
  }

  async function enviar(e: FormEvent) {
    e.preventDefault();
    setErro(undefined);
    setEnviando(true);
    try {
      await criar('/api/releases', { ...campos, packVersion: Number(campos.packVersion) });
      navegar(`/releases/${campos.id}`);
    } catch (e) {
      // O 409 de versao repetida e o anti-downgrade da INV-7 ancorado no banco
      // (`UNIQUE(municipality_id, pack_version)`), e a mensagem do servidor ja
      // explica. Reescrever aqui perderia a distincao entre ele e um 409 de FK.
      setErro(
        e instanceof ErroApi && 'mensagem' in e.falha
          ? String(e.falha.mensagem)
          : 'Nao foi possivel criar a release.',
      );
    } finally {
      setEnviando(false);
    }
  }

  return (
    <main className="cartao">
      <h1>Nova release</h1>
      <form onSubmit={enviar}>
        <label htmlFor="id">Identificador</label>
        <input id="id" required value={campos.id} onChange={ao('id')} />

        <label htmlFor="municipalityId">Municipio</label>
        <input
          id="municipalityId"
          required
          value={campos.municipalityId}
          onChange={ao('municipalityId')}
        />

        <label htmlFor="packVersion">Versao do pack</label>
        {/*
          A versao e monotonica e o banco recusa repeticao: reemitir um numero
          faria metade da frota parar de atualizar sem erro nenhum (INV-7).
        */}
        <input
          id="packVersion"
          type="number"
          min={1}
          required
          value={campos.packVersion}
          onChange={ao('packVersion')}
        />

        <label htmlFor="schemaVersion">Versao do schema</label>
        <input
          id="schemaVersion"
          required
          value={campos.schemaVersion}
          onChange={ao('schemaVersion')}
        />

        {erro && <Aviso tom="erro">{erro}</Aviso>}

        <button type="submit" disabled={enviando}>
          {enviando ? 'Criando…' : 'Criar'}
        </button>
      </form>
    </main>
  );
}

// ---------------------------------------------------------------------------

export function TelaDaRelease() {
  const { id = '' } = useParams();
  const { operador } = useSessao();
  const [release, setRelease] = useState<Release>();
  const [transicoes, setTransicoes] = useState<readonly Transicao[]>([]);
  const [comentario, setComentario] = useState('');
  const [erro, setErro] = useState<string>();
  const [ok, setOk] = useState<string>();
  const [ocupado, setOcupado] = useState(false);

  const carregar = useCallback(async () => {
    const r = await buscar<{ release: Release; transicoes: readonly Transicao[] }>(
      `/api/releases/${id}`,
    );
    setRelease(r.release);
    setTransicoes(r.transicoes);
  }, [id]);

  useEffect(() => {
    carregar().catch(() => setErro('Nao foi possivel carregar a release.'));
  }, [carregar]);

  async function executar(t: Transicao) {
    const acao = acaoDe(t.de, t.para);
    // Uma transicao sem acao mapeada e do `job`, e nao vira botao — mas se
    // chegar aqui, e melhor nao fazer nada que inventar uma chamada.
    if (!acao) return;

    setErro(undefined);
    setOk(undefined);
    setOcupado(true);
    try {
      const resposta = await acionar<{ transicionou?: boolean; faltam?: number; para?: string }>(
        acao.caminho(id),
        acao.corpo?.(id, comentario),
      );
      if (resposta.transicionou === false) {
        // 200, e nao erro. A decisao FOI registrada e conta para o quorum.
        setOk(`Decisao registrada. Faltam ${resposta.faltam} para fechar o quorum.`);
      } else {
        const destino = resposta.para as ReleaseStatus | undefined;
        setOk(`Release agora esta ${destino ? ROTULO_DO_ESTADO[destino] : 'atualizada'}.`);
      }
      setComentario('');
      await carregar();
    } catch (e) {
      if (e instanceof ErroApi && e.falha.tipo === 'conflito_estado') {
        // O servidor devolve `atual` e `permitidas`: em vez de insistir com um
        // botao que nao vale mais, redesenha a partir do que ele acabou de dizer.
        setErro(`${e.falha.mensagem} (estado atual: ${e.falha.atual ?? '?'})`);
        if (e.falha.permitidas) setTransicoes(e.falha.permitidas as readonly Transicao[]);
      } else if (e instanceof ErroApi && e.falha.tipo === 'sem_permissao') {
        // Nao deveria acontecer — o botao so aparece para quem esta em `t.por`.
        // Mas se acontecer, "erro" nao ajuda ninguem: o servidor recusou por
        // papel, e e isso que a tela diz.
        setErro('Seu papel nao permite esta acao.');
      } else if (e instanceof ErroApi && e.falha.tipo === 'proibido') {
        // Auto-aprovacao barrada pelo gatilho. A mensagem do servidor ja e escrita
        // para humanos — reescrever perderia o motivo.
        setErro(e.falha.mensagem);
      } else {
        setErro('Nao foi possivel concluir a acao.');
      }
    } finally {
      setOcupado(false);
    }
  }

  if (erro && !release) return <main>{<Aviso tom="erro">{erro}</Aviso>}</main>;
  if (!release) return <main>Carregando…</main>;

  /**
   * `t.por` diz QUEM pode; `acaoDe` diz COMO. Sao perguntas diferentes, e usar
   * so a segunda oferece o botao a quem vai levar 403.
   *
   * Nao e uma segunda copia da FSM: `por` vem do servidor, na MESMA resposta que
   * `de` e `para`. Ignora-lo era usar a resposta pela metade — e o sintoma era o
   * editor, que acabara de submeter, enxergando "Aprovar" logo abaixo.
   */
  const podeAgir = (t: Transicao) =>
    operador !== undefined && t.por.includes(operador.role as Ator);

  const acionaveis = transicoes.filter((t) => acaoDe(t.de, t.para) && podeAgir(t));
  const deOutroPapel = transicoes.filter((t) => acaoDe(t.de, t.para) && !podeAgir(t));
  const doJob = transicoes.filter((t) => !acaoDe(t.de, t.para));
  const pedeComentario = acionaveis.some((t) => acaoDe(t.de, t.para)?.pedeComentario);

  return (
    <main>
      <h1>{release.id}</h1>
      <p>
        Estado: <strong>{ROTULO_DO_ESTADO[release.status]}</strong> · municipio{' '}
        {release.municipalityId} · pack v{release.packVersion} · schema {release.schemaVersion}
      </p>

      {erro && <Aviso tom="erro">{erro}</Aviso>}
      {ok && <Aviso tom="ok">{ok}</Aviso>}

      <section className="cartao">
        <h2>O que da para fazer agora</h2>
        {acionaveis.length === 0 && deOutroPapel.length === 0 && doJob.length === 0 && (
          <p className="nota">Nada — este e um estado final.</p>
        )}

        {pedeComentario && (
          <>
            <label htmlFor="comentario">Comentario da revisao</label>
            <textarea
              id="comentario"
              rows={3}
              maxLength={2000}
              value={comentario}
              onChange={(e) => setComentario(e.target.value)}
            />
            <p className="nota">
              Retratar-se e inserir uma decisao nova, nao apagar a anterior: a tabela e append-only
              e as duas ficam visiveis.
            </p>
          </>
        )}

        {acionaveis.map((t) => (
          <div key={`${t.de}-${t.para}`} className="acao">
            <button type="button" disabled={ocupado} onClick={() => void executar(t)}>
              {acaoDe(t.de, t.para)?.rotulo}
            </button>
            <span className="nota">{t.motivo}</span>
          </div>
        ))}

        {/*
          Transicao que existe mas nao e SUA vira texto dizendo de quem e. Isso e
          a segregacao da LGPD-RF11 ficando visivel: o editor ve que a release
          esta esperando o revisor clinico, em vez de um botao que da 403.
        */}
        {deOutroPapel.map((t) => (
          <p key={`${t.de}-${t.para}`} className="nota">
            {acaoDe(t.de, t.para)?.rotulo}: cabe a {t.por.join(' ou ')} — {t.motivo}
          </p>
        ))}

        {/*
          Transicoes do `job` viram TEXTO, nao botao: ninguem as aciona pela
          interface, e um botao desabilitado sugeriria que falta permissao.
        */}
        {doJob.map((t) => (
          <p key={`${t.de}-${t.para}`} className="nota">
            Automatico: {t.motivo} (vira <strong>{ROTULO_DO_ESTADO[t.para]}</strong>, feito pelo
            job)
          </p>
        ))}
      </section>

      <Link to="/releases">Voltar para a lista</Link>
    </main>
  );
}
