/**
 * O CRUD de conteudo: indice, lista, formulario e traducoes.
 *
 * ## O indice existe por causa de uma frase do manual
 *
 * "A ordem nao e livre — as chaves estrangeiras a impoem. Fora de ordem, a
 * resposta e `409 "violaria uma referencia"`, **que diz o que aconteceu mas nao
 * o que faltava**" (`operacao.md` §4.1). O indice mostra a ordem e, para cada
 * entidade cujo pre-requisito esta vazio, **nomeia o que falta** — que e
 * exatamente a informacao que o 409 nao carrega.
 *
 * ## Nada de campo de autoria no formulario
 *
 * `version`, `updatedBy` e `updatedAt` voltam no GET e sao removidas na escrita.
 * Os formularios sao construidos de `CAMPOS`, que e tipado contra o modelo de
 * INSERCAO — e ha teste afirmando que nenhum campo de autoria entrou ali.
 */
import { useCallback, useEffect, useState, type FormEvent } from 'react';
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom';

import type { NomeDeEntidade } from '@guia-ubs/cms/src/content/tipos.js';
import { LANGS } from '@guia-ubs/contract';

import { ErroApi, buscar, criar, gravar, ler, remover } from '../api/api.js';
import {
  CAMPOS,
  CAMPOS_DE_TRADUCAO,
  META,
  OPCOES,
  ORDEM_DE_CRIACAO,
  caminhoDaLinha,
} from '../conteudo/campos.js';
import { useSessao } from '../sessao.js';

type Linha = Record<string, unknown>;

interface CampoRenderizavel {
  nome: string;
  rotulo: string;
  tipo: string;
  referencia?: NomeDeEntidade;
  dica?: string;
}

function campos(nome: NomeDeEntidade): readonly CampoRenderizavel[] {
  return CAMPOS[nome] as readonly CampoRenderizavel[];
}

function ehEntidade(v: string | undefined): v is NomeDeEntidade {
  return v !== undefined && v in CAMPOS;
}

/** `?municipalityId=m1&id=x` — a chave da linha, na ordem declarada. */
function consultaDaChave(nome: NomeDeEntidade, linha: Linha): string {
  return META[nome].chave
    .map((k) => `${k}=${encodeURIComponent(String(linha[k] ?? ''))}`)
    .join('&');
}

function Aviso({ erro, ok }: { erro?: string; ok?: string }) {
  return (
    <>
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
    </>
  );
}

// ---------------------------------------------------------------------------

export function IndiceDeConteudo() {
  const [contagem, setContagem] = useState<Partial<Record<NomeDeEntidade, number>>>({});

  useEffect(() => {
    // As municipais exigem `?municipalityId=`, entao nao da para conta-las sem
    // escolher um municipio. So as globais entram na checagem de pre-requisito.
    for (const nome of ORDEM_DE_CRIACAO) {
      if (META[nome].escopo !== 'global') continue;
      buscar<{ items: unknown[] }>(`/api/content/${nome}`)
        .then((r) => setContagem((c) => ({ ...c, [nome]: r.items.length })))
        .catch(() => undefined);
    }
  }, []);

  /** O que precisa existir antes desta entidade, e ainda nao existe. */
  function faltando(nome: NomeDeEntidade): NomeDeEntidade[] {
    const referencias = new Set(
      campos(nome)
        .map((c) => c.referencia)
        .filter((r): r is NomeDeEntidade => r !== undefined && r !== nome),
    );
    return [...referencias].filter((r) => META[r].escopo === 'global' && contagem[r] === 0);
  }

  return (
    <main>
      <h1>Conteudo</h1>
      <p className="nota">
        A ordem abaixo nao e sugestao: as chaves estrangeiras a impoem. Fora dela, o servidor
        responde <code>409 &quot;violaria uma referencia&quot;</code> — que diz o que aconteceu,
        mas nao o que faltava.
      </p>

      <ol>
        {ORDEM_DE_CRIACAO.map((nome) => {
          const pendencias = faltando(nome);
          return (
            <li key={nome}>
              <Link to={`/conteudo/${nome}`}>{nome}</Link>{' '}
              {META[nome].escopo === 'municipal' && <span className="nota">(municipal)</span>}
              {contagem[nome] !== undefined && (
                <span className="nota"> · {contagem[nome]} item(ns)</span>
              )}
              {pendencias.length > 0 && (
                <p className="aviso">
                  Falta cadastrar antes: <strong>{pendencias.join(', ')}</strong>.
                </p>
              )}
            </li>
          );
        })}
      </ol>
    </main>
  );
}

// ---------------------------------------------------------------------------

export function ListaDeEntidade() {
  const { entidade } = useParams();
  const [params, setParams] = useSearchParams();
  const municipio = params.get('municipalityId') ?? '';
  const [itens, setItens] = useState<Linha[]>();
  const [erro, setErro] = useState<string>();
  const { operador } = useSessao();

  const nome = ehEntidade(entidade) ? entidade : undefined;
  const precisaMunicipio = nome !== undefined && META[nome].escopo === 'municipal';

  useEffect(() => {
    if (!nome) return;
    // A rota responde 400 sem `municipalityId` nas municipais. Pedir a escolha
    // ANTES evita que a tela pisque um erro que a pessoa nao causou.
    if (precisaMunicipio && !municipio) {
      setItens([]);
      return;
    }
    const consulta = precisaMunicipio ? `?municipalityId=${encodeURIComponent(municipio)}` : '';
    setErro(undefined);
    buscar<{ items: Linha[] }>(`/api/content/${nome}${consulta}`)
      .then((r) => setItens(r.items))
      .catch(() => setErro('Nao foi possivel carregar.'));
  }, [nome, precisaMunicipio, municipio]);

  if (!nome) return <main>Entidade desconhecida.</main>;

  return (
    <main>
      <h1>{nome}</h1>
      {operador?.permissions.includes('content:write') && (
        <Link to={`/conteudo/${nome}/nova`}>Novo item</Link>
      )}

      {precisaMunicipio && (
        <>
          <label htmlFor="municipio">Municipio</label>
          <input
            id="municipio"
            value={municipio}
            onChange={(e) => setParams(e.target.value ? { municipalityId: e.target.value } : {})}
          />
          {!municipio && (
            <p className="nota">Escolha um municipio para listar — esta entidade e municipal.</p>
          )}
        </>
      )}

      <Aviso erro={erro} />

      {itens && itens.length > 0 && (
        <table>
          <thead>
            <tr>
              {campos(nome).map((c) => (
                <th key={c.nome}>{c.rotulo}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {itens.map((linha, i) => (
              <tr key={i}>
                {campos(nome).map((c, j) => (
                  <td key={c.nome}>
                    {j === 0 ? (
                      <Link to={`/conteudo/${nome}/editar?${consultaDaChave(nome, linha)}`}>
                        {String(linha[c.nome] ?? '')}
                      </Link>
                    ) : (
                      String(linha[c.nome] ?? '')
                    )}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      )}
      {itens && itens.length === 0 && !erro && <p className="nota">Nenhum item.</p>}

      <Link to="/conteudo">Voltar ao indice</Link>
    </main>
  );
}

// ---------------------------------------------------------------------------

export function FormularioDeConteudo() {
  const { entidade } = useParams();
  const [params] = useSearchParams();
  const navegar = useNavigate();
  const { operador } = useSessao();
  const podeEscrever = operador?.permissions.includes('content:write') ?? false;

  const nome = ehEntidade(entidade) ? entidade : undefined;
  const editando = [...params.keys()].length > 0;

  const [valores, setValores] = useState<Linha>({});
  const [lido, setLido] = useState<{ dados: unknown; versao: number }>();
  const [erro, setErro] = useState<string>();
  const [ok, setOk] = useState<string>();
  const [ocupado, setOcupado] = useState(false);

  const carregar = useCallback(async () => {
    if (!nome || !editando) return;
    const chave = Object.fromEntries(params.entries());
    const r = await ler<Linha>(caminhoDaLinha(nome, chave));
    setValores(r.dados);
    setLido({ dados: r.dados, versao: r.versao });
  }, [nome, editando, params]);

  useEffect(() => {
    carregar().catch(() => setErro('Nao foi possivel carregar o item.'));
  }, [carregar]);

  if (!nome) return <main>Entidade desconhecida.</main>;

  function corpo(): Linha {
    // So os campos declarados: nunca `version`/`updatedBy`/`updatedAt`, que o
    // servidor descarta e que apareceriam como uma edicao que nao salvou.
    const saida: Linha = {};
    for (const c of campos(nome!)) {
      const v = valores[c.nome];
      if (v === undefined || v === '') continue;
      saida[c.nome] = c.tipo === 'numero' ? Number(v) : c.tipo === 'booleano' ? (v ? 1 : 0) : v;
    }
    return saida;
  }

  async function enviar(e: FormEvent) {
    e.preventDefault();
    setErro(undefined);
    setOk(undefined);
    setOcupado(true);
    try {
      if (lido) {
        await gravar(lido, caminhoDaLinha(nome!, valores), corpo());
        setOk('Gravado.');
        // O PATCH responde `{ok, versao}` — nao a linha. Reler e o que garante
        // que a tela mostra o estado do banco, e nao o que ela achava que era.
        await carregar();
      } else {
        await criar(`/api/content/${nome!}`, corpo());
        setOk('Criado.');
        // O POST responde `{...corpo, version: 1}` — tambem nao a linha, entao
        // colunas com default do banco viriam ausentes. Navegar para a edicao
        // forca um GET, que traz a linha de verdade.
        navegar(`/conteudo/${nome!}/editar?${consultaDaChave(nome!, valores)}`);
      }
    } catch (e) {
      if (e instanceof ErroApi && e.falha.tipo === 'conflito_versao') {
        setErro(
          `Alguem gravou antes de voce (versao ${e.falha.versaoAtual}). Recarregue e refaca a alteracao — nada foi sobrescrito.`,
        );
      } else if (e instanceof ErroApi && e.falha.tipo === 'integridade') {
        setErro(`${e.falha.mensagem}. Confira o indice: alguma referencia ainda nao existe.`);
      } else if (e instanceof ErroApi && 'mensagem' in e.falha) {
        setErro(String(e.falha.mensagem));
      } else {
        setErro('Nao foi possivel gravar.');
      }
    } finally {
      setOcupado(false);
    }
  }

  async function apagar() {
    try {
      await remover(caminhoDaLinha(nome!, valores));
      navegar(`/conteudo/${nome!}`);
    } catch {
      setErro('Nao foi possivel apagar.');
    }
  }

  return (
    <main>
      <h1>
        {editando ? 'Editar' : 'Novo'} — {nome}
      </h1>

      <Aviso erro={erro} ok={ok} />

      <form onSubmit={enviar}>
        {campos(nome).map((c) => {
          const id = `campo-${c.nome}`;
          const valor = valores[c.nome];
          const opcoes =
            c.tipo === 'cor' ? OPCOES.cor : c.tipo === 'local' ? OPCOES.local : undefined;

          return (
            <div key={c.nome}>
              <label htmlFor={id}>{c.rotulo}</label>
              {opcoes ? (
                <select
                  id={id}
                  value={String(valor ?? '')}
                  onChange={(e) => setValores((v) => ({ ...v, [c.nome]: e.target.value }))}
                >
                  <option value="">—</option>
                  {opcoes.map((o) => (
                    <option key={o} value={o}>
                      {o}
                    </option>
                  ))}
                </select>
              ) : c.tipo === 'booleano' ? (
                <input
                  id={id}
                  type="checkbox"
                  checked={Boolean(valor)}
                  onChange={(e) => setValores((v) => ({ ...v, [c.nome]: e.target.checked }))}
                />
              ) : (
                <input
                  id={id}
                  type={c.tipo === 'numero' ? 'number' : 'text'}
                  // A chave nao muda depois de criada: alterar identificador e
                  // criar outra linha, nao editar esta.
                  disabled={editando && META[nome].chave.includes(c.nome)}
                  value={String(valor ?? '')}
                  onChange={(e) => setValores((v) => ({ ...v, [c.nome]: e.target.value }))}
                />
              )}
              {c.dica && <p className="nota">{c.dica}</p>}
            </div>
          );
        })}

        {podeEscrever && (
          <button type="submit" disabled={ocupado}>
            {ocupado ? 'Gravando…' : 'Gravar'}
          </button>
        )}
      </form>

      {/*
        Botao de apagar so onde a rota existe. `crud.ts` so registra `DELETE` para
        as entidades `apagavel`, e oferecer um botao que sempre falha ensina o
        editor a ignorar mensagem de erro.
      */}
      {editando && podeEscrever && META[nome].apagavel && (
        <button type="button" onClick={() => void apagar()}>
          Apagar
        </button>
      )}

      {editando && META[nome].temTraducao && (
        <Traducoes entidade={nome} chave={Object.fromEntries(params.entries())} />
      )}

      <Link to={`/conteudo/${nome}`}>Voltar para a lista</Link>
    </main>
  );
}

// ---------------------------------------------------------------------------

function Traducoes({
  entidade,
  chave,
}: {
  entidade: NomeDeEntidade;
  chave: Record<string, string>;
}) {
  const [lang, setLang] = useState<string>(LANGS[0]);
  const [texto, setTexto] = useState<Record<string, string>>({});
  const [ok, setOk] = useState<string>();
  const [erro, setErro] = useState<string>();

  // Declarados em `campos.ts` e conferidos contra as colunas de `*_translation`
  // por `web-conformance.test.ts` — campo a menos aqui vira pack que o packer
  // recusa publicar, longe de quem causou.
  const campos = CAMPOS_DE_TRADUCAO[entidade] ?? [];

  async function enviar(e: FormEvent) {
    e.preventDefault();
    setOk(undefined);
    setErro(undefined);
    try {
      await criar(`${caminhoDaLinha(entidade, chave)}/traducoes/${lang}`, texto);
      setOk('Traducao gravada.');
    } catch {
      setErro('Nao foi possivel gravar a traducao.');
    }
  }

  return (
    <section className="cartao">
      <h2>Traducoes</h2>
      {/*
        Sem travamento otimista: a rota e upsert sem `If-Match` e responde sem
        `ETag`. Dois editores traduzindo o mesmo item se sobrescrevem em silencio,
        e a interface nao tem como corrigir isso do lado dela — so avisar.
        Declarado no §6 do manual.
      */}
      <p className="aviso">
        Esta gravacao nao tem travamento: se duas pessoas traduzirem o mesmo item, vence a ultima.
      </p>

      <form onSubmit={enviar}>
        <label htmlFor="lang">Idioma</label>
        <select id="lang" value={lang} onChange={(e) => setLang(e.target.value)}>
          {LANGS.map((l) => (
            <option key={l} value={l}>
              {l}
            </option>
          ))}
        </select>

        {campos.map((c) => (
          <div key={c}>
            <label htmlFor={`t-${c}`}>{c}</label>
            <textarea
              id={`t-${c}`}
              rows={2}
              value={texto[c] ?? ''}
              onChange={(e) => setTexto((t) => ({ ...t, [c]: e.target.value }))}
            />
          </div>
        ))}

        <Aviso erro={erro} ok={ok} />

        <button type="submit">Gravar traducao</button>
      </form>
    </section>
  );
}
