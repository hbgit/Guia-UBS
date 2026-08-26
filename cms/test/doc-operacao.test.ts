/**
 * `docs/operacao.md` nao pode envelhecer e passar a mentir.
 *
 * Um manual de operacao tem duas listas do tipo exato que este projeto trata
 * como perigoso: rotas e variaveis de ambiente. Escritas a parte, elas
 * envelhecem — e um manual desatualizado e pior que nenhum, porque alguem SEGUE
 * o passo que nao funciona mais e conclui que o sistema esta quebrado.
 *
 * E o mesmo motivo de `PII_COLUMNS` e `APPEND_ONLY_TABLES` serem constantes
 * percorridas por teste, e de `lgpd_surface_test.dart` enumerar colunas em vez
 * de conferir contra um texto escrito ao lado.
 *
 * ## Por que o CRUD e conferido por PADRAO, e nao linha a linha
 *
 * Sao ~48 rotas quase identicas (10 entidades x 4-5 verbos), geradas de
 * `content/registry.ts`. Uma tabela com 48 linhas seria uma tabela que ninguem
 * le e que quebra a cada entidade nova. O manual documenta o formato uma vez e
 * lista os NOMES das entidades; o teste confere que todo nome real esta listado.
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { after, before, test } from 'node:test';

import { CONTENT_ENTITIES } from '../src/content/registry.js';
import { freshApp, type Fixture } from './support/app.js';

const RAIZ = join(import.meta.dirname, '..', '..');
const MANUAL = readFileSync(join(RAIZ, 'docs', 'operacao.md'), 'utf8');

let f: Fixture;
before(async () => {
  f = await freshApp();
});
after(async () => f.close());

/**
 * Rotas reais do app, sem middleware e sem repeticao.
 *
 * O Hono registra uma entrada por camada: `requirePermission` aparece como
 * `ALL`, e a mesma rota surge duas vezes quando ha middleware antes do handler.
 * Filtrar `ALL` e deduplicar deixa a superficie de verdade.
 */
function rotasReais(): { metodo: string; caminho: string }[] {
  const vistas = new Set<string>();
  const saida: { metodo: string; caminho: string }[] = [];
  for (const rota of f.app.routes) {
    if (rota.method === 'ALL') continue;
    const chave = `${rota.method} ${rota.path}`;
    if (vistas.has(chave)) continue;
    vistas.add(chave);
    saida.push({ metodo: rota.method, caminho: rota.path });
  }
  return saida;
}

/** Rotas de conteudo — cobertas pelo padrao documentado, nao uma a uma. */
function ehRotaDeConteudo(caminho: string): boolean {
  return caminho.startsWith('/api/content/');
}

/**
 * Rotas que o manual nao precisa citar, cada uma com motivo.
 *
 * Nao ha "passa porque sim": excecao sem justificativa escrita e como a lista
 * volta a mentir.
 */
const FORA_DO_MANUAL: Readonly<Record<string, string>> = {
  'GET /api/auth/*':
    'superficie do Better Auth; o manual documenta o FLUXO (login, 2FA), nao o catalogo da biblioteca',
  'POST /api/auth/*': 'idem',
};

test('toda rota do app aparece no manual', () => {
  const faltando: string[] = [];
  for (const { metodo, caminho } of rotasReais()) {
    if (FORA_DO_MANUAL[`${metodo} ${caminho}`]) continue;
    if (ehRotaDeConteudo(caminho)) continue; // coberta pelo padrao, testado abaixo
    // O manual escreve parametros como `<id>`; o app, como `:id`.
    const forma = caminho.replace(/:([a-zA-Z]+)/g, '<$1>');
    if (!MANUAL.includes(caminho) && !MANUAL.includes(forma)) {
      faltando.push(`${metodo} ${caminho}`);
    }
  }
  assert.deepEqual(
    faltando,
    [],
    'rota sem linha em docs/operacao.md — quem seguir o manual nao vai saber que ela existe',
  );
});

test('o padrao de CRUD documentado cobre os verbos reais', () => {
  const verbos = new Set(
    rotasReais()
      .filter((r) => ehRotaDeConteudo(r.caminho))
      .map((r) => r.metodo),
  );
  for (const verbo of verbos) {
    assert.ok(
      MANUAL.includes(`\`${verbo}\``),
      `o CRUD de conteudo responde a ${verbo} e o manual nao menciona esse verbo`,
    );
  }
  assert.ok(MANUAL.includes('/api/content/<entidade>'), 'o manual perdeu o padrao de CRUD');
  assert.ok(MANUAL.includes('traducoes/<lang>'), 'o manual perdeu a rota de traducao');
});

test('as entidades de conteudo estao todas listadas', () => {
  // Entidade nova no registro sem linha no manual = conteudo que ninguem sabe
  // que da para editar.
  for (const entidade of CONTENT_ENTITIES) {
    assert.ok(
      MANUAL.includes(`\`${entidade.nome}\``),
      `a entidade "${entidade.nome}" existe e nao esta listada no manual`,
    );
  }
});

test('o manual nao cita rota que nao existe mais', () => {
  // O sentido inverso, e o que mais engana: instrucao morta que alguem segue.
  const formas = new Set(rotasReais().map((r) => r.caminho.replace(/:[a-zA-Z]+/g, ':p')));

  // So o que esta em TABELA. Bloco `curl` usa id concreto de exemplo
  // (`/api/releases/rel-2026-01/submeter`) e nao e catalogo de rota — a tabela e.
  const linhasDeTabela = MANUAL.split('\n').filter((l) => l.trimStart().startsWith('|'));
  const citadas = linhasDeTabela
    .flatMap((l) => [...l.matchAll(/(\/api\/[a-z0-9/<>_-]+)/g)].map((m) => m[1]!))
    .filter((c) => !c.startsWith('/api/auth/'))
    // O padrao de CRUD usa `<entidade>`, que nao resolve para rota concreta;
    // quem o cobre e o teste do padrao.
    .filter((c) => !c.includes('<entidade>'));

  const mortas = [...new Set(citadas)].filter((c) => {
    const forma = c.replace(/<[^>]+>/g, ':p').replace(/:[a-zA-Z]+/g, ':p');
    return !formas.has(forma);
  });

  assert.deepEqual(mortas, [], 'o manual cita rota que o app nao serve mais');
});

test('toda variavel de ambiente citada existe em infra/.env.example', () => {
  const exemplo = readFileSync(join(RAIZ, 'infra', '.env.example'), 'utf8');
  const declaradas = new Set([...exemplo.matchAll(/^([A-Z][A-Z0-9_]*)=/gm)].map((m) => m[1]!));

  /**
   * Identificadores em MAIUSCULA que o manual cita e que NAO sao variavel de
   * ambiente. Cada um com motivo — excecao sem justificativa escrita e como a
   * lista volta a mentir.
   */
  const NAO_SAO_ENV: Readonly<Record<string, string>> = {
    CMS_DATABASE_URL: 'variavel de shell, definida na hora; nao mora no .env',
    FALSO_NEGATIVO: 'valor de resposta da simulacao de regra, nao configuracao',
  };

  // Exige `_` no nome: e o que separa `BETTER_AUTH_SECRET` de `PATCH`. Todas as
  // variaveis reais do projeto tem underscore; nenhum verbo HTTP tem.
  const citadas = [...MANUAL.matchAll(/`([A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+)`/g)].map((m) => m[1]!);
  const inexistentes = [...new Set(citadas)].filter(
    (v) => !declaradas.has(v) && !NAO_SAO_ENV[v],
  );
  assert.deepEqual(
    inexistentes,
    [],
    'o manual manda definir variavel que nao esta em infra/.env.example',
  );
});

test('infra/.env.example nao tem chave duplicada', () => {
  // Num arquivo `.env` a ultima ocorrencia vence, entao duplicata "funciona" —
  // ate alguem editar a de cima e nada mudar. E exatamente onde um manual de
  // implantacao faz perder uma tarde.
  const exemplo = readFileSync(join(RAIZ, 'infra', '.env.example'), 'utf8');
  const chaves = [...exemplo.matchAll(/^([A-Z][A-Z0-9_]*)=/gm)].map((m) => m[1]!);
  const repetidas = chaves.filter((c, i) => chaves.indexOf(c) !== i);
  assert.deepEqual([...new Set(repetidas)], []);
});

test('todo comando `npm run` citado existe', () => {
  const raiz = JSON.parse(readFileSync(join(RAIZ, 'package.json'), 'utf8')) as {
    scripts: Record<string, string>;
  };
  const disponiveis = new Set(Object.keys(raiz.scripts));

  const citados = [...MANUAL.matchAll(/npm run ([a-z:-]+)/g)].map((m) => m[1]!);
  const inexistentes = [...new Set(citados)].filter((c) => !disponiveis.has(c));
  assert.deepEqual(
    inexistentes,
    [],
    'o manual manda rodar um script que nao existe no package.json da raiz',
  );
});

test('o manual declara que NAO e normativo', () => {
  // Sem isto alguem o le como fonte de verdade e implementa contra ele, criando
  // uma segunda versao do sistema que so existe no texto.
  assert.match(MANUAL, /DERIVADO, n[aã]o normativo/i);
  assert.match(MANUAL, /vale o normativo/i);
});

test('o manual declara as lacunas, inclusive a ausencia de interface', () => {
  // A parte mais facil de esquecer numa revisao, e a que mais engana: um manual
  // cheio de `curl` da a impressao de que o sistema esta operavel por quem
  // deveria opera-lo.
  assert.match(MANUAL, /n[aã]o consegue trabalhar sozinho/i);
  assert.match(MANUAL, /cms\/web/);
});
