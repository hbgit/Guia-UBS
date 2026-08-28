# Guia UBS — Operação do plano de controle

> **Este documento é DERIVADO, não normativo.** Ele descreve como operar o que
> existe. Em conflito com [`spec/PRD.md`](../spec/PRD.md) ou
> [`spec/espec.md`](../spec/espec.md), vale o normativo — e é este manual que
> está errado.
>
> Para **por que** cada coisa é assim, leia
> [`spec/arquitetura.md`](../spec/arquitetura.md) §5.10–5.12. Aqui só se diz **o
> que fazer**.

As rotas, variáveis de ambiente e comandos citados abaixo são conferidos contra
o código por `cms/test/doc-operacao.test.ts`. Uma rota que mude sem esta página
mudar junto reprova o CI.

---

## 1. Antes de começar

### A topologia

```
                   ┌─────────────────────────────────────┐
  navegador  ──────▶  cms        :8787   sessão + 2FA     │
  (operador)       │  Hono, RBAC, CRUD, dual review       │
                   └───────────────┬─────────────────────┘
                                   │ mesmo banco
                   ┌───────────────▼─────────────────────┐
                   │  db          :8080   sqld (libSQL)  │
                   └───────────────┬─────────────────────┘
                                   │
                   ┌───────────────▼─────────────────────┐
                   │  packer      SEM PORTA              │
                   │  extrai → constrói → assina →       │
                   │  publica.  Lê a chave privada.      │
                   └───────────────┬─────────────────────┘
                                   │
  aparelho   ◀───── edge :443 ◀──── storage :9000  MinIO
  (offline)         Caddy           packs assinados
```

**O `packer` não tem porta publicada, e isso é a garantia de segurança do
sistema, não uma configuração.** Ele lê a chave privada Ed25519; o `cms` atende
HTTP. Juntar os dois faria uma falha de execução remota no serviço web virar
conteúdo clínico assinado chegando a aparelhos offline. Se alguém propuser
"simplificar" publicando pelo CMS, é isto que se perde.

### Conferir se está no ar

```sh
curl -s http://127.0.0.1:8787/health      # {"status":"ok"}
```

| Rota | Método | Acesso |
|---|---|---|
| `/health` | `GET` | **público** — é o healthcheck do compose |
| `/api/telemetry` | `POST` | **público** — ver §6 |

Estas são as **duas únicas** rotas sem autenticação, e as duas são exceções
declaradas: `/health` responde uma constante e não toca no banco de identidade;
`/api/telemetry` não pode autenticar porque exigiria identidade de dispositivo,
que a INV-2 proíbe. Qualquer outra rota sem sessão é defeito.

### O que o aparelho toca

Só `edge`. O aplicativo nunca fala com o `cms` — ele baixa `manifest.json` e o
pack como arquivos estáticos, confere a assinatura, e só então troca o conteúdo.
Um CMS fora do ar não afeta nenhum usuário final.

---

## 2. Implantar

### 2.1 Gerar os segredos

Três valores, todos aleatórios e nenhum versionado:

```sh
openssl rand -base64 48      # BETTER_AUTH_SECRET
openssl rand -base64 48      # IP_HASH_SALT
openssl rand -base64 24      # MINIO_ROOT_PASSWORD
```

| Variável | Para quê | Se faltar |
|---|---|---|
| `BETTER_AUTH_SECRET` | cifra o segredo TOTP e os códigos de recuperação em repouso | o processo **não sobe** |
| `IP_HASH_SALT` | pseudonimiza o IP na trilha e o e-mail na trava de login | o processo **não sobe** |
| `BETTER_AUTH_URL` | validação de origem (CSRF) | o compose recusa subir |
| `MINIO_ROOT_USER` | credencial do storage | o compose recusa subir |
| `MINIO_ROOT_PASSWORD` | idem | o compose recusa subir |
| `CONTENT_DOMAIN` | domínio público servido pela borda | o compose recusa subir |
| `ACME_EMAIL` | contato do certificado TLS | o compose recusa subir |
| `PACK_SIGNING_KEY_HOST_PATH` | chave privada no host, montada só-leitura no `packer` | o compose recusa subir |
| `PACK_SIGNING_KEY_ID` | qual chave de `signing_key` está em uso | assume `k1` |
| `PACK_SIGNING_KEY_PATH` | caminho da chave para o CLI do packer (build a partir de `seed/`) | o comando falha |
| `S3_BUCKET` | bucket dos packs | assume `content-packs` |
| `SOURCE_DATE_EPOCH` | build reproduzível | duas builds do mesmo conteúdo geram hashes diferentes, e a frota re-baixa o pack à toa |

> **Trocar o `BETTER_AUTH_SECRET` invalida o segundo fator de todo mundo.** Não
> é rotação: é reset. Todos os operadores precisam cadastrar o TOTP de novo.

Copie o modelo e preencha:

```sh
cp infra/.env.example infra/.env
$EDITOR infra/.env
```

### 2.2 Subir a topologia

```sh
cd infra && docker compose up -d db storage && cd ..
```

Espere `docker compose ps` mostrar `healthy` antes de migrar.

### 2.3 Aplicar o schema

```sh
export CMS_DATABASE_URL=http://127.0.0.1:8080
npm run cms:migrate
```

Saída esperada: `migrado  tabelas em dia, N gatilhos aplicados`.

Os gatilhos são reaplicados a **cada** migração, de propósito: gatilho que sumiu
— por restauração de backup antigo, por `DROP` manual — volta sozinho.

### 2.4 Criar o primeiro operador

Não existe autocadastro. Este script é o único caminho que não exige um operador
já existente, e ele exige acesso ao banco — que é a credencial.

```sh
npm run cms:create-admin -- --email admin@exemplo.invalid --name "Nome" --role admin
```

A senha é **sorteada e mostrada uma única vez**. Sem `--password`, é assim de
propósito: senha em linha de comando fica no histórico do shell e na lista de
processos da máquina.

Crie ao menos **dois** operadores com papéis diferentes. Um só não publica nada
— ver §3.

### 2.5 Ativar o segundo fator

**A conta recém-criada não alcança rota protegida nenhuma até isto ser feito.**
Não é um aviso: é o middleware recusando.

```sh
B=http://127.0.0.1:8787
J='Content-Type: application/json'; O="Origin: $B"

# 1. senha
curl -s -c ck.txt -X POST $B/api/auth/sign-in/email -H "$J" -H "$O" \
  -d '{"email":"admin@exemplo.invalid","password":"<a senha sorteada>"}'

# 2. pedir o segredo TOTP — devolve `totpURI`, que o autenticador lê como QR
curl -s -b ck.txt -X POST $B/api/auth/two-factor/enable -H "$J" -H "$O" \
  -d '{"password":"<a senha sorteada>"}'
```

Cadastre o `totpURI` no aplicativo autenticador. **A chamada acima não liga a
2FA** — ela entrega o segredo e revoga a sessão. A ativação acontece na primeira
verificação bem-sucedida, num login novo:

```sh
# 3. logar de novo e verificar o código de seis dígitos
curl -s -c ck.txt -X POST $B/api/auth/sign-in/email -H "$J" -H "$O" \
  -d '{"email":"admin@exemplo.invalid","password":"<a senha sorteada>"}'
curl -s -b ck.txt -c ck.txt -X POST $B/api/auth/two-factor/verify-totp \
  -H "$J" -H "$O" -d '{"code":"123456"}'

curl -s -b ck.txt $B/api/me     # 200 = pronto
```

> **Pela interface:** abra `` `/entrar` ``, informe e-mail e senha. Na primeira entrada
> a resposta manda para `` `/entrar/cadastrar-2fa` ``, que mostra o QR **e** a chave
> em base32 para digitação manual. Cadastre no autenticador e **entre de novo** —
> o cadastro só é ativado na primeira verificação bem-sucedida, num login novo, e
> é por isso que a tela pede para entrar outra vez em vez de aceitar o código ali.
> O `curl` acima continua valendo como descrição do que a tela faz por baixo.
> Concluído o segundo fator, a entrada leva ao painel em `` `/` ``, que diz o que
> o seu papel faz — e o que ele deliberadamente **não** faz.

> **Um `403` com dois significados.** Depois do `enable`, `two_factor_enabled`
> continua **falso** até a primeira verificação bem-sucedida — então `GET /api/me`
> responde o mesmo `403 "segundo fator obrigatorio"` para quem **nunca cadastrou**
> e para quem **já cadastrou e ainda não verificou**. O cliente não tem como
> distinguir os dois, e adivinhar erraria metade das vezes: mandar quem já tem a
> chave gerar outra invalidaria a que ele acabou de guardar no autenticador. Por
> isso a tela `` `/entrar/cadastrar-2fa` `` **pergunta**, oferecendo o atalho para
> `` `/entrar/codigo` ``. A ativação em si é o `verify-totp` sobre a sessão do
> login — não é preciso um cookie de 2FA pendente.

**Todo `POST` autenticado exige o cabeçalho `Origin`.** É proteção contra CSRF;
sem ele a resposta é `403` e a mensagem não diz por quê.

Errar a senha várias vezes trava a **conta**, progressivamente: duas tentativas
de folga, depois 30 s dobrando até o teto de 15 minutos. Travada, ela recusa até
a senha certa. A resposta não diz quanto falta — seria um oráculo sobre conta
alheia.

### 2.6 Semear a suíte golden

Os casos clínicos do repositório vão para a tabela `golden_case` uma vez. Dali em
diante o revisor acrescenta casos pelo CMS.

```sh
npm run cms:import-golden -- --autor <id do operador>
```

É idempotente: reimportar não duplica nem sobrescreve caso já editado.

> O script avisa quantos casos estão **sem revisor clínico nomeado**. Isso não
> bloqueia o build, mas bloqueia o piloto.

### 2.7 Registrar a chave de assinatura

O `packer` recusa assinar com chave que não esteja na tabela `signing_key`.
Registre a pública correspondente à privada que o job vai usar, com o mesmo
`key_id` de `PACK_SIGNING_KEY_ID`:

```sh
npm run cms:register-key -- --key-path contract/keys/dev-k1.pem
```

A **pública é derivada da privada**, nunca informada à parte — registrar uma que
não corresponde à privada em uso é exatamente o incidente que a guarda previne.
Rodar duas vezes com a mesma chave não faz nada; com uma chave diferente sob o
mesmo `key_id`, o script **recusa** e manda usar outro `--key-id`, porque trocar
a chave que a frota reconhece é rotação (§5), não efeito colateral de um comando
repetido.

**Pule este passo e a implantação parece pronta até o último comando**, onde o
job morre com *"A chave k1 não está em signing_key"*.

**Por que a guarda existe:** assinar com chave desconhecida produz um pack que
**toda a frota rejeita em silêncio** — o sync tenta, a assinatura não confere, o
pack é descartado, e nada no servidor acusa. A guarda transforma um incidente
mudo de frota inteira numa falha de build com nome.

---

### 2.8 Construir a interface

```sh
npm run web:build
```

Escreve `cms/web/dist/`, que **não é versionado** (`dist/` está no `.gitignore`):
um clone novo precisa construir antes de a interface responder. Sem o build, a
API continua atendendo normalmente e as telas devolvem `503` com
*"interface nao construida"* — `503` e não `404` de propósito, porque `404`
mandaria procurar erro de digitação no caminho quando o que faltou foi o build.
O aviso também sai no log do servidor, no boot.

Na imagem do Docker isso já acontece: o estágio `web` do `cms/Dockerfile` roda
este mesmo comando.

### 2.9 Desenvolver a interface

São dois modos, e a diferença entre eles é a **origem** que o navegador usa —
que é o que o Better Auth confere para barrar CSRF.

**Modo 1 — com recarregamento automático:**

```sh
BETTER_AUTH_URL=http://localhost:5173 npm run cms:dev   # terminal 1
npm run web:dev                                          # terminal 2
```

O Vite serve em `localhost:5173` e repassa `/api` e `/health` para o `:8787` sem
reescrever cabeçalho nenhum. Por isso o `BETTER_AUTH_URL` precisa ser **a porta
do Vite**: é ela que o navegador informa como origem.

**Modo 2 — como em produção, sem proxy:**

```sh
npm run web:build
BETTER_AUTH_URL=http://127.0.0.1:8787 npm run cms:dev
```

É o único modo que exercita o caminho de servir estáticos do Hono. **Confira
neste modo antes de dar merge** — o Modo 1 nunca passa por ele.

> ⚠️ **`localhost` e `127.0.0.1` são origens diferentes.** Abrir o Modo 2 em
> `http://localhost:8787` com o `BETTER_AUTH_URL` apontando para `127.0.0.1`
> devolve `403` em todo `POST`, e a mensagem não diz por quê.


## 3. Os três papéis

| Papel | Pode | **Não pode** |
|---|---|---|
| `editor` | ler e escrever conteúdo, criar e submeter release | **aprovar** |
| `clinical_reviewer` | ler conteúdo, simular regra, aprovar ou rejeitar release | **escrever conteúdo** |
| `admin` | ler conteúdo, gerir operadores, revogar e reenfileirar release | **escrever conteúdo** e **aprovar** |

A coluna da direita é a que importa. **Quem escreve não aprova, e quem aprova não
escreve** — é a segregação de funções da LGPD-RF11, e é o que impede uma pessoa
sozinha levar conteúdo clínico ao aparelho.

### As três metades do dual review

| Metade | Onde vive | O que barra |
|---|---|---|
| por **papel** | matriz de permissões | `editor` não tem `approval:decide` |
| por **linha** | gatilho no banco | quem criou **esta** release não a aprova |
| por **quórum** | serviço de workflow | exige ≥ 1 aprovação de `clinical_reviewer` |

**A do meio parece redundante e não é.** O cenário que ela cobre é a
**promoção**: um editor cria a release, é promovido a revisor, e passa a ter a
permissão de aprovar sem deixar de ser o autor. No instante da aprovação o papel
está correto — a matriz não vê nada de errado. Só a regra por linha barra.

Ela mora no **banco**, e não na rota, porque a ameaça nomeada no PRD é o insider:
uma checagem que vive só na rota protege apenas contra quem passa pela rota.

### Gestão de operadores

| Rota | Método | Quem |
|---|---|---|
| `/api/me` | `GET` | qualquer sessão — devolve papel e permissões resolvidas |
| `/api/users` | `GET` | `admin` |
| `/api/users` | `POST` | `admin` |
| `/api/users/<id>` | `PATCH` | `admin` |

```sh
curl -s -b ck.txt $B/api/users                          # listar
curl -s -b ck.txt -X POST $B/api/users -H "$J" -H "$O" \
  -d '{"email":"novo@exemplo.invalid","name":"Nome","role":"editor","password":"<senha>"}'
curl -s -b ck.txt -X PATCH $B/api/users/<id> -H "$J" -H "$O" \
  -d '{"role":"clinical_reviewer"}'                     # promover
curl -s -b ck.txt -X PATCH $B/api/users/<id> -H "$J" -H "$O" \
  -d '{"disabled":true}'                                # desligar
```

A listagem **nunca** devolve credencial. Gerir pessoas não é motivo para ver a
senha delas.

**Um operador não altera a própria conta** — nem papel, nem desligamento. Sem
isso, RBAC de três papéis seria decorativo: bastaria pedir `admin` para si.

---

## 4. O ciclo de uma release

```
  conteúdo ──▶ regra ──▶ simular ──▶ release ──▶ submeter
                                                    │
                            ┌───────────────────────┘
                            ▼
                     revisor aprova ──▶ approved ──▶ [job] ──▶ published
                            │                                      │
                        rejeita                                    ▼
                            ▼                                  aparelho
                          draft
```

### 4.1 Criar conteúdo

Todas as entidades seguem o mesmo formato — o CRUD é **gerado** de um registro, e
não escrito uma vez por entidade:

| Rota | Método | Para quê |
|---|---|---|
| `/api/content/<entidade>` | `GET` | listar (municipal exige `?municipalityId=`) |
| `/api/content/<entidade>` | `POST` | criar |
| `/api/content/<entidade>/<chave>` | `GET` | ler — devolve `ETag` com a versão |
| `/api/content/<entidade>/<chave>` | `PATCH` | editar — **exige `If-Match`** |
| `/api/content/<entidade>/<chave>` | `DELETE` | remover, quando permitido |
| `/api/content/<entidade>/<chave>/traducoes/<lang>` | `PUT` | gravar tradução |

As dez entidades: `municipalities`, `assets`, `symptom-tokens`,
`routing-outcomes`, `venues`, `cards`, `services`, `documents`,
`service-documents`, `flow-steps`.

**A chave é composta nas entidades municipais:**
`/api/content/services/<municipalityId>/<id>`.

**> **Pela interface:** `` `/conteudo` `` mostra as dez entidades na ordem que as
> FKs impõem e, para cada uma cujo pré-requisito está vazio, **nomeia o que
> falta** — que é exatamente a informação que o `409` não carrega. As telas são
> `` `/conteudo/:entidade` ``, `` `/conteudo/:entidade/nova` `` e
> `` `/conteudo/:entidade/editar` ``. Entidades municipais pedem o município
> antes de listar, porque a rota responde `400` sem ele.

A ordem não é livre — as chaves estrangeiras a impõem.** Um CMS recém-migrado
começa vazio, e cada entidade abaixo é alvo da seguinte. Fora de ordem, a
resposta é `409 "violaria uma referência"`, que diz o que aconteceu mas não o que
faltava:

```
asset ──┬─→ symptom_token ─────────────┐
        ├─→ card ──┐                   ├─→ routing_rule (§4.3)
        └─→ venue ─┴─→ routing_outcome ┘
municipality ─→ (service, document, flow_step — só as municipais)
```

Esta é a cadeia mínima até conseguir escrever **uma** regra:

```sh
# 1. o ícone, que todo o resto referencia por `iconRef`
#    `storageKey` é coluna de autoria: onde o binário está no MinIO. Ela não
#    atravessa para o pack — ver §6, "sem upload de asset".
curl -s -b ck.txt -X POST $B/api/content/assets -H "$J" -H "$O" \
  -d '{"ref":"icon.head","kind":"icon","path":"icons/head.svg",
       "sha256":"<sha256 do arquivo>","bytes":1024,
       "storageKey":"assets/icons/head.svg"}'

# 2. os sintomas que a regra vai combinar
curl -s -b ck.txt -X POST $B/api/content/symptom-tokens -H "$J" -H "$O" \
  -d '{"id":"chest","kind":"body_part","iconRef":"icon.head","sortOrder":0,"deprecated":0}'
curl -s -b ck.txt -X PUT $B/api/content/symptom-tokens/chest/traducoes/pt \
  -H "$J" -H "$O" -d '{"label":"Peito"}'
curl -s -b ck.txt -X POST $B/api/content/symptom-tokens -H "$J" -H "$O" \
  -d '{"id":"pain","kind":"symptom","iconRef":"icon.head","sortOrder":1,"deprecated":0}'

# 3. os cartões de resultado e o local — o que a pessoa vê no fim
curl -s -b ck.txt -X POST $B/api/content/cards -H "$J" -H "$O" \
  -d '{"id":"card.rotina","kind":"result","iconRef":"icon.head","colorToken":"green","sortOrder":0}'
curl -s -b ck.txt -X POST $B/api/content/cards -H "$J" -H "$O" \
  -d '{"id":"card.emerg","kind":"result","iconRef":"icon.head","colorToken":"red","sortOrder":1}'
curl -s -b ck.txt -X POST $B/api/content/venues -H "$J" -H "$O" \
  -d '{"id":"UBS","iconRef":"icon.head","colorToken":"green","sortOrder":0}'

# 4. os desfechos — SEM ao menos um, §4.3 não simula nada
curl -s -b ck.txt -X POST $B/api/content/routing-outcomes -H "$J" -H "$O" \
  -d '{"id":"ROUTINE_UBS","severityLevel":10,"cardId":"card.rotina","venueId":"UBS"}'
curl -s -b ck.txt -X POST $B/api/content/routing-outcomes -H "$J" -H "$O" \
  -d '{"id":"EMERGENCY","severityLevel":100,"cardId":"card.emerg","venueId":"UBS"}'
```

**`severityLevel` é escala do pack, não do binário.** O app deriva os extremos
dos desfechos que encontrar — 10 e 100 acima são o que o pacote semente usa, e
outro município pode publicar outra escala. O desfecho padrão da triagem é
**derivado da menor severidade**; não existe coluna para configurá-lo.

Para as entidades municipais (`services`, `documents`, `flow-steps`), crie antes
o município — a chave delas é composta, e `code` é o código IBGE de 7 dígitos:

```sh
curl -s -b ck.txt -X POST $B/api/content/municipalities -H "$J" -H "$O" \
  -d '{"id":"m1","code":"<código IBGE>","name":"<nome do município>","active":1}'
```

**Nem toda entidade pode ser apagada.** `municipalities`, `assets`,
`symptom-tokens`, `routing-outcomes`, `venues` e `cards` não têm rota de
`DELETE` — são alvo de regra clínica ou de chave estrangeira estrutural. Um token
sai de circulação por `deprecated`, e as regras que o citam continuam válidas até
serem reescritas.

### 4.2 Editar sem perder o trabalho de outra pessoa

Toda escrita usa travamento otimista. **Leia, edite, devolva a versão que leu:**

```sh
# 1. ler — o ETag é a versão
curl -s -b ck.txt -D- -o /dev/null $B/api/content/symptom-tokens/chest | grep -i etag
#    ETag: "1"

# 2. editar mandando de volta o que leu
curl -s -b ck.txt -X PATCH $B/api/content/symptom-tokens/chest \
  -H "$J" -H "$O" -H 'If-Match: "1"' -d '{"sortOrder":5}'
```

| Resposta | Significa |
|---|---|
| `200` + `ETag: "2"` | gravado; a versão subiu |
| `428` | faltou o `If-Match` — a pré-condição é exigida antes de olhar o corpo |
| `409` + `versaoAtual` | **alguém escreveu antes de você.** Releia e refaça sobre a versão nova |
| `404` | a linha sumiu — outra coisa que um `409` |
| `409` "violaria uma referência" | a FK recusou: algo depende desta linha, ou a referência informada não existe |

O `409` de conflito carrega a versão atual porque um conflito que não diz contra
o que se perdeu obriga a pessoa a recarregar a tela para descobrir.

> **Pela interface:** o formulário lê a linha, guarda o `ETag` e o reenvia como
> `If-Match` — o `428` é **inalcançável** pela tela, porque a função de gravar só
> aceita uma leitura como parâmetro. No `409`, a tela mostra a versão atual e
> pede recarregar; ela **nunca reenvia sozinha**, que seria exatamente o atropelo
> silencioso que o travamento existe para impedir.

### 4.3 Escrever e simular uma regra

Uma regra é forma normal disjuntiva: **E** dentro do mesmo `groupNo`, **OU**
entre grupos.

| Rota | Método | Quem |
|---|---|---|
| `/api/rules` | `GET` | qualquer papel |
| `/api/rules/<id>` | `GET` | qualquer papel |
| `/api/rules/simular` | `POST` | qualquer papel — **não grava nada** |
| `/api/rules` | `POST` | `editor` |
| `/api/rules/<id>` | `PUT` | `editor` |
| `/api/rules/<id>/revisao` | `POST` | `editor` |

**Simule antes de gravar.** A simulação roda a suíte golden com e sem a regra
proposta e diz quais casos mudam de veredito:

```sh
curl -s -b ck.txt -X POST $B/api/rules/simular -H "$J" -H "$O" -d '{
  "id":"rf-toracica","priority":10,"outcomeId":"EMERGENCY",
  "terms":[{"groupNo":0,"tokenId":"chest","negated":false},
           {"groupNo":0,"tokenId":"pain","negated":false}]}'
```

```jsonc
{ "problemas": [],
  "simulacao": {
    "muda": [ { "casoId": "dor-toracica", "tokens": ["chest", "pain"],
                "de": "EMERGENCY", "para": "ROUTINE_UBS",
                "classe": "FALSO_NEGATIVO" } ],
    "inalterados": 23, "total": 24,
    "falsosNegativos": 1, "jaVermelhos": 11 } }
```

**`FALSO_NEGATIVO` é a linha que interrompe o trabalho.** É o caso em que o app
mandaria para casa alguém que precisava de emergência. `ESCALADA` é revisão
clínica; falso negativo é evento de segurança do paciente.

`inalterados` e `total` estão ali para você ver o **tamanho da amostra**: a
simulação só cobre os casos que alguém escreveu. `jaVermelhos` conta os casos que
já eram emergência antes da proposta — sem ele, uma regra que não muda nada
pareceria inofensiva quando na verdade estava sendo medida contra uma amostra em
que quase tudo já era vermelho.

Se **nenhum desfecho existir ainda**, a resposta vem com `simulacao: null` e o
problema `desfecho_inexistente` — não há o que comparar antes de §4.1 estar feito.

A simulação **não grava nada**, e está aberta a quem só lê conteúdo — o revisor
clínico precisa poder perguntar "o que esta regra faria?" sem ter permissão de
escrevê-la.

Gravar:

```sh
curl -s -b ck.txt -X POST $B/api/rules -H "$J" -H "$O" -d '{ … }'
```

Uma regra inválida responde `422` com **todos** os problemas de uma vez — sem
termos, token descontinuado, grupo contraditório, grupos duplicados, prioridade
repetida. Corrigir um por requisição faria qualquer revisor desistir na terceira.

**Regra aprovada não é editada.** O `PUT` responde `409` com
`next: /api/rules/<id>/revisao`, que clona a regra como rascunho novo e deixa a
original intacta — o pack já publicado com ela continua explicável.

> **Pela interface:** `` `/regras` `` lista, `` `/regras/nova` `` e
> `` `/regras/:id` `` editam. Os grupos são o OU e os termos dentro de cada grupo
> são o E. **`Simular` fica sempre disponível** — a rota exige apenas
> `content:read`, de propósito, para o revisor clínico poder perguntar "o que
> esta regra faria?" sem ter permissão de escrevê-la; `Salvar` some para ele.
>
> `FALSO_NEGATIVO` aparece em bloco vermelho, antes de tudo, com a contagem como
> manchete — e `Salvar` fica **bloqueado** até um reconhecimento explícito. Essa
> trava é da interface: o servidor não a impõe, e a tela diz isso.

### 4.4 Criar e submeter a release

| Rota | Método | Quem |
|---|---|---|
| `/api/releases` | `GET` | qualquer papel |
| `/api/releases` | `POST` | `editor` |
| `/api/releases/<id>` | `GET` | qualquer papel |
| `/api/releases/<id>/submeter` | `POST` | `editor` |
| `/api/releases/<id>/reenfileirar` | `POST` | `admin` — §5 |
| `/api/releases/<id>/revogar` | `POST` | `admin` — §5 |

```sh
curl -s -b ck.txt -X POST $B/api/releases -H "$J" -H "$O" \
  -d '{"id":"rel-2026-01","municipalityId":"m1","packVersion":1,"schemaVersion":"1.0"}'
curl -s -b ck.txt -X POST $B/api/releases/rel-2026-01/submeter -H "$O"
```

`GET /api/releases/<id>` devolve, junto da release, **as transições possíveis a
partir do estado atual** — é dali que uma interface monta os botões, em vez de
manter uma segunda cópia das regras. É exatamente o que a tela
`` `/releases/:id` `` faz: um botão por entrada de `transicoes`, e nenhum `if`
sobre estado. Há teste que reprova se um literal de estado aparecer em código
fora do mapa de transporte.

> **Pela interface:** `` `/releases` `` lista; `` `/releases/nova` `` cria (só
> quem tem `content:write` vê o atalho); `` `/releases/:id` `` mostra o estado e
> as ações. Transições do job aparecem como **texto**, não como botão
> desabilitado — ninguém deve clicar nelas, e um botão apagado sugeriria falta de
> permissão.

Versão repetida no mesmo município responde `409`. É o anti-downgrade ancorado no
banco: reemitir um número faria metade da frota parar de atualizar sem erro
nenhum, porque cada aparelho já teria "aquela versão".

### 4.5 Aprovar — com outra conta

| Rota | Método | Quem |
|---|---|---|
| `/api/approvals` | `POST` | **só** `clinical_reviewer` |

```sh
curl -s -b ck-revisor.txt -X POST $B/api/approvals -H "$J" -H "$O" \
  -d '{"releaseId":"rel-2026-01","decision":"approve"}'
```

| Resposta | Significa |
|---|---|
| `200` `{"para":"approved"}` | quórum fechado, release liberada para o job |
| `200` `{"transicionou":false}` | decisão registrada, quórum ainda não fechado |
| `403` | você não tem `approval:decide`, **ou** criou esta release |
| `409` | a release não está em revisão |

`decision: "reject"` devolve a release para `draft`. **Retratar-se é inserir uma
decisão nova**, não apagar a anterior: a tabela é append-only e as duas ficam
visíveis.

> **Pela interface:** os botões "Aprovar" e "Rejeitar" ficam em
> `` `/releases/:id` ``, com o campo de comentário ao lado — o revisor clínico já
> decide sem depender de quem opera a API. O `curl` acima continua valendo como
> descrição do que a tela faz por baixo.
>
> **`{"transicionou": false}` é verde, não vermelho.** A decisão foi registrada e
> conta para o quórum; o que não aconteceu foi a transição. A tela diz quantas
> faltam. Pintar de erro faria o revisor achar que o voto se perdeu.

### 4.6 O job publica

```sh
npm run pack:worker -- --once      # processa a fila e sai
```

Em produção o serviço `packer` do compose faz isso em laço.

O que ele faz, em ordem: toma posse (`approved → building`, compare-and-set),
**confere a chave** contra `signing_key`, extrai o conteúdo do município, monta o
`content.db`, roda integridade referencial e a suíte golden, assina o manifest
(`→ built`) e publica os artefatos (`→ published`) — **o manifest por último**,
para que uma publicação interrompida nunca aponte para artefato ausente.

Só regras `approved` entram no pack. Rascunho no pack seria conteúdo não revisado
chegando a um aparelho sem internet.

Conferir:

```sh
curl -s -b ck.txt $B/api/releases/rel-2026-01     # status: published
```

A trilha distingue quem é gente de quem é máquina: as transições do job entram
com `actor_id` **nulo**, porque o job não tem operador.

---

## 5. Runbooks

### O job travou — release parada em `building`

Um job que morreu no meio deixa a release com posse tomada. `claimed_at` diz há
quanto tempo — sem ele, "o job travou" seria indistinguível de "está
trabalhando".

```sh
curl -s -b ck-admin.txt -X POST $B/api/releases/<id>/reenfileirar -H "$O"
```

Volta para `approved` e limpa o carimbo. **Só `admin`**, e fica na trilha —
destravar sem registro é a saída que a auditoria não vê.

### Portão vermelho — a release voltou sozinha para `approved`

O job devolve a release quando integridade referencial ou suíte golden falham.
Isso é o desenho, não um erro: o problema está no conteúdo, e depois de corrigido
a **mesma** release deve poder ser construída.

A corrida fica registrada mesmo falhando, em `golden_run` — `passed`, `total` e
`failures_json` dizem qual caso quebrou.

Corrija o conteúdo ou a regra e deixe o job pegá-la de novo. **Nada foi
assinado** — nenhum aparelho viu nada.

### Rotacionar a chave de assinatura

Duas chaves podem estar ativas ao mesmo tempo, e é isso que permite rotacionar
sem release do aplicativo: o aparelho já conhece `k2` antes de `k1` ser
aposentada.

1. Gere o novo par e registre a **pública** em `signing_key`.
2. Distribua a pública nova para a frota (release do app) e **espere a adoção**.
3. Aponte `PACK_SIGNING_KEY_ID` para a nova e reinicie o `packer`.
4. Só então carimbe `retired_at` na antiga.

**Aposentar antes de a frota adotar a nova deixa todo mundo sem conteúdo** — e em
silêncio, porque a rejeição de assinatura acontece no aparelho.

### Desligar um operador

```sh
curl -s -b ck-admin.txt -X PATCH $B/api/users/<id> -H "$J" -H "$O" \
  -d '{"disabled":true}'
```

Efeito **imediato**, inclusive em sessão já aberta. Nunca apague a linha: ela
sustenta toda a trilha que a pessoa assinou, e a trilha é append-only justamente
para não sumir.

### Revogar um pack publicado

```sh
curl -s -b ck-admin.txt -X POST $B/api/releases/<id>/revogar -H "$O"
```

Marca a release como `revoked` no banco. **Isto não remove o artefato do
storage** nem faz aparelho nenhum desinstalar o conteúdo: o app só troca de pack
quando encontra versão maior. Para tirar um pack de circulação de verdade,
publique uma versão nova e corrigida.

---

## 6. O que ainda não dá

| Lacuna | Efeito prático |
|---|---|
| **Sem upload de asset pela interface** | O formulário de `assets` grava metadado, mas o binário continua vindo de `seed/assets/`: `storageKey` aponta para um objeto que alguém precisa ter enviado por fora. **É a única parte do §4 que ainda não se faz pela tela** |
| **Sem aceite de Termo de Uso no primeiro login** | `legal_document` e `consent_record` existem no banco e são append-only, e **não há rota nem tela**. A LGPD-RF02/RF04 exige que o primeiro login do CMS bloqueie o acesso até o aceite, com registro da versão e do hash do documento. A interface torna a lacuna **visível**, não a fecha |
| **Tradução não tem travamento otimista** | `PUT /api/content/<entidade>/<chave>/traducoes/<lang>` é upsert sem `If-Match` e responde sem `ETag`. Dois editores traduzindo o mesmo item se sobrescrevem em silêncio — vence a última gravação, e nada acusa |
| **Regra escrita no CMS nunca chega ao pack** | Toda regra nasce `draft`, e **não existe rota que a mova para `approved`** — nem o `POST /api/rules`, nem o `PUT`, nem `/revisao`, que também clona como rascunho. Como `extract.ts` filtra `status='approved'`, o §4 inteiro roda até o fim e o portão golden reprova a release: a regra simplesmente não entrou. As regras que hoje chegam ao aparelho vêm do caminho `seed/`, não da autoria. **É o buraco que separa o CMS de ser usável em piloto** |
| **Telemetria sem produtor** | `POST /api/telemetry` existe e valida, mas nada envia: o app não faz a chamada, e o lote de um aparelho não alcança k≥20. Falta um agregador que nenhum documento especifica |
| **Sem importador de conteúdo** | `cms:import-golden` traz os casos clínicos, mas não há equivalente para o conteúdo de `seed/`. Um CMS recém-implantado começa vazio, e a primeira release é montada pela API, item a item |
| **Sem upload de asset** | `asset` guarda metadado; o binário continua vindo de `seed/assets/`. Publicar um ícone novo só pelo CMS não é possível |
| **Sem expurgo por retenção** | A LGPD-RF07 exige prazo de retenção com expurgo; o procedimento está desenhado mas não implementado — depende da tabela de retenção aprovada pelo encarregado |
| **Casos golden sem revisor nomeado** | Os casos semeados do repositório têm `reviewed_by` nulo. O packer avisa a cada build; bloqueia o piloto |

---

## Onde procurar o resto

| Pergunta | Onde |
|---|---|
| Por que a decisão é essa? | [`spec/arquitetura.md`](../spec/arquitetura.md) §5.10–5.12 |
| Qual é o comportamento normativo? | [`spec/espec.md`](../spec/espec.md) |
| O que a LGPD exige aqui? | [`spec/lgpd.md`](../spec/lgpd.md) |
| Quais armadilhas já foram pagas? | [`CLAUDE.md`](../CLAUDE.md) |
| Quais comandos existem? | [`README.md`](../README.md) |
