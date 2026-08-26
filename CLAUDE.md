# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Estado do repositório

Projeto **em implementação**. A documentação está dividida em dois lugares com papéis distintos, e confundi-los é erro de categoria (tudo em **português**; mantenha novos documentos em pt-BR):

- **`spec/`** — o que o sistema **deve** ser. Normativo, ordenado por precedência, o PRD governa. Foi renomeado de `docs/`, e mensagens de commit anteriores ainda citam o nome antigo.
- **`docs/`** — como operar o que **existe**. Derivado do código; em conflito com `spec/`, é o `docs/` que está errado. Hoje contém [`docs/operacao.md`](docs/operacao.md), cujas rotas, variáveis de ambiente e comandos são conferidos contra o código por `cms/test/doc-operacao.test.ts`.

O código já existe em `app/` (Flutter), `contract/` + `packer/` (TypeScript), `native/llama_shim/` (C) e `infra/`. O andamento por item está em `spec/arquitetura.md` §Roadmap; as medições e decisões de cada item entregue ficam nas subseções §5.x do mesmo arquivo. O produto especificado: **Guia UBS**, app Android offline-only (Flutter + SLM local via llama.cpp) com interface 100% iconográfica para orientar populações rurais, imigrantes e pessoas de baixo letramento sobre serviços do SUS, mais um plano de controle de conteúdo (TypeScript/Hono) que compila e assina pacotes SQLite distribuídos via arquivos estáticos.

## Hierarquia documental (ordem de precedência)

1. **`spec/PRD.md`** — fonte única da verdade; consolida e governa os demais. Em conflito, vale o PRD.
2. **`spec/espec.md`** — normativo para comportamento: matrizes FSM completas (FSM-A triagem, FSM-B ciclo do pack), invariantes INV-1…8, requisitos RF/RNF com critérios de aceitação.
3. **`spec/stack.md`** — decisões de tecnologia com trade-offs, auditoria open source (§9) e **ADRs arquiteturais (§10)**; §11 é a explicação não técnica para sponsors.
4. **`spec/lgpd.md`** — requisitos de conformidade LGPD (LGPD-RF01…17, RT01…11).
5. **`spec/brainstorm.md`** — visão de produto, milestones M1–M7, definição do MVP.
6. **`spec/design.html`** — protótipo interativo autocontido (abrir no navegador); publicado como Artifact. `spec/design_selo_procedencia.html` é o companheiro para o selo de procedência (RF-15).

Ao alterar uma decisão em um documento, propague a consistência nos demais (eles se citam por links relativos).

## Invariantes que nenhum código futuro pode violar

Estas regras são de segurança clínica/legal, não preferências (detalhes em espec.md §5.1):

- **Red flag ⇒ EMERGENCY, sempre.** O gate determinístico roda ANTES do LLM e `severity_final = max(gate, llm)` — o LLM nunca rebaixa severidade. Exceção no gate = fail-closed para EMERGENCY.
- **Zero dado pessoal do usuário final** em disco, log ou rede. A sequência de sintomas morre em memória; telemetria só agregada por coorte com k-anonimato ≥ 20.
- **Offline-only em runtime:** toda funcionalidade do usuário opera com rádio desligado. O app faz exatamente duas chamadas de rede, ambas fora do caminho do usuário: download de manifest/pack pelo WorkManager e, desde o [ADR-003](spec/stack.md), download do modelo SLM no 1º acesso (700 MB–1,2 GB). Ambas retomáveis por HTTP Range, com SHA-256 conferido antes de aceitar, e **falha em qualquer uma nunca bloqueia o app** — sem modelo, a triagem roda via `RuleOnlyEngine`.
- **Nenhum conteúdo sem assinatura Ed25519 válida e dual review clínico** chega ao usuário; versão de pack é monotônica (downgrade rejeitado mesmo assinado).
- **Falha de LLM/TTS/sync nunca bloqueia** navegação de conteúdo estático (degradação em escada: llama.cpp → MediaPipe → regras puras → conteúdo estático).
- `RuleOnlyEngine` e `RedFlagGate` consomem a **mesma tabela** do pack — lógica de regras duplicada em código é proibida.

## Decisões de stack já tomadas (não reabrir sem ADR)

- **100% open source** (stack.md §9): Turso→`sqld` self-host, R2/CDN→MinIO+Caddy, Railway→Compose+Ansible. Não reintroduzir SaaS pago sem registrar novo ADR em stack.md §10.
- **Vercel rejeitado** (ADR-001, stack.md §10) — só reavaliar se surgir superfície web dinâmica pública.
- O `docker-compose.yaml` de stack.md §7 **é** a topologia de produção planejada (paridade dev/prod literal).
- Type safety cruza TS→Dart por codegen: schema Drizzle → Zod → `pack-schema.json` → freezed; mudança de schema deve quebrar `flutter analyze` no mesmo PR (stack.md §3.3).
- **O Dart não fala com `llama.h`** (ADR-002, stack.md §10): a fronteira é o shim C de 4 funções em `native/llama_shim/`, com llama.cpp fixado na tag `b6100`. O laço de geração e o teto de 5 s moram no C — um `Future.timeout` no Dart abandonaria a espera sem parar a CPU do aparelho. Mudou assinatura no shim? Incremente `GUBS_LLAMA_ABI_VERSION` e `expectedAbiVersion` no mesmo commit.

## Convenções de design (UI)

Semântica de cor fixa: **verde = UBS/rotina, vermelho = emergência, azul = informação**, e **lilás = procedência/automação** — esta última existe só para o selo que diz de onde veio a orientação (`ui/triage/widgets/provenance_badge.dart`) e **nunca** aparece em cartão, botão ou ícone de conteúdo clínico; usá-la ali criaria um quarto significado clínico que ninguém especificou. Alvos de toque ≥ 64 dp, máx. 8 elementos por tela, navegação linear com voltar/casa sempre visíveis, zero texto obrigatório (todo conteúdo essencial tem ícone + áudio pt/es). O protótipo visual está em `spec/design.html`; a implementação normativa é `app/lib/ui/theme/`.

- **A escala de `severity_level` pertence ao PACK, não ao binário.** O pacote semente usa 10 (rotina) e 100 (emergência); outro município pode publicar outra escala. Use `severityFor(level, model)`, que deriva os extremos dos desfechos do próprio pack. Limiares fixos em Dart já causaram o pior defeito visual do projeto: todo resultado de rotina pintado de vermelho com "Ligue 192" embaixo.
- **Peça a cor pela SEVERIDADE, não pelo nome.** `GubsColors.forSeverity(...)` devolve o par certo; escolher entre `green` e `red` na hora do layout é o caminho para um cartão de emergência pintado de verde.
- **Dentro de botão colorido, informe a cor do texto explicitamente** (`onGreen`/`onRed`/`onAmber`). Os estilos de `Theme.of(context).textTheme` já vêm coloridos com `onSurface`, e essa cor vence o `foregroundColor` do botão — armadilha documentada em `app/lib/ui/theme/gubs_theme.dart`.
- **A procedência da orientação é DERIVADA, nunca guardada de novo.** `provenanceFor(result)` lê `source` e `degraded`, que já existem no `TriageResult`; um terceiro campo dizendo o mesmo criaria duas fontes de verdade para "quem produziu isto". Atenção a uma sutileza que só o teste revela: **modelo "sem opinião" também marca `degraded: true`** — então o estado "regras do posto" (não degradado) é alcançável apenas pela red flag, e "sem o assistente" cobre indisponível, com falha **e** sem opinião. As três dizem a mesma coisa a quem lê: o assistente não contribuiu.
- **O mapa de rotas é dado** (`app/lib/ui/app_routes.dart`): profundidade, dead-ends e o alcance da exceção da INV-8 são verificados percorrendo a lista, não lendo builders.
- Strings de casca vivem em `app/lib/l10n/*.arb`; **conteúdo clínico vem do `content.db` assinado**, nunca de ARB.

## Background e sync

- **Um único `callbackDispatcher`** (`app/lib/sync/background_sync.dart`). `Workmanager().initialize()` aceita uma função, que recebe TODAS as tarefas; dois dispatchers significam que só um roda e o outro é silenciosamente descartado.
- **Freio de sync é estado em disco, não em memória** (`app/lib/sync/sync_retry_state.dart`). O WorkManager cria um isolate por disparo — backoff e circuito guardados em campos de instância não existem em produção. O circuito é um *instante* ("fechado a partir de"), não um booleano.
- **Adiar a troca por triagem em curso não é falha.** Se contasse no circuito, o app pararia de sincronizar justamente por estar sendo usado.

## Dados no aparelho

- **`content.db` é somente leitura, e isso é estrutural** (`app/lib/content/`). O app nunca escreve conteúdo: ele troca o arquivo inteiro quando o sync commita (FSM-B). Um caminho de escrita ali seria um caminho para orientação não revisada chegar ao usuário sem assinatura (INV-4). O pack é aberto em `OpenMode.readOnly` e há teste que confirma que o `UPDATE` falha.
- **Falta de tradução recua para `pt`, não some com o item.** O packer bloqueia publicação com tradução faltando, então recuo no aparelho é defeito — mas sumir com "Onde ir" de quem precisa é pior que mostrá-lo em português para um hispanofalante. O recuo é sinalizado em `Localized.isFallback`.
- **A tela de privacidade lista o que o `user.db` guarda, e há teste que compara as duas listas** (`app/test/ui/privacy/`). Preferência nova sem entrada na tela reprova: uma lista redigida à parte envelhece e passa a mentir para o titular.
- **Telemetria: a allowlist é uma enum, nunca uma `String`** (`app/lib/telemetry/metric_key.dart`), conferida contra `contract/telemetry-schema.json`. O módulo **não envia e não persiste** — enviar seria uma terceira chamada de rede (exige ADR) e persistir viraria coluna nova no `user.db`. O opt-out zera a COLETA, não só o envio.
- **O esquema do `user.db` é a superfície auditável da LGPD** (`app/lib/prefs/user_database.dart`). Colunas **tipadas**, nunca chave-valor: as colunas são a resposta a "o que este app guarda sobre a pessoa", e `test/prefs/lgpd_surface_test.dart` as enumera. Coluna nova reprova o build até ser justificada contra a INV-2 e a LGPD-RF13. Sintoma é dado sensível de saúde e **não** é persistido — a sequência morre em memória.

## Banco master do CMS (`cms/`)

- **A lista append-only é uma constante, nunca um literal** (`cms/src/db/schema/index.ts`). `APPEND_ONLY_TABLES` alimenta o gerador de gatilhos **e** é percorrida pelo teste; `VERSIONED_TABLES` e `PII_COLUMNS` funcionam igual. É o mesmo motivo de `lgpd_surface_test.dart` enumerar colunas: lista redigida à parte envelhece e passa a mentir. Tabela acrescentada à constante sem linha de exemplo em `test/support/db.ts` **reprova** — senão o teste rodaria zero asserções e ficaria verde.
- **Gatilho mora em `triggers.sql` idempotente, não no journal do drizzle.** `drizzle-kit generate --custom` criaria arquivo numerado e imutável, e uma tabela versionada nova daqui a meses exigiria migração só para os gatilhos dela — o conjunto acabaria espalhado por N arquivos históricos. `triggers.sql` carrega o conjunto **completo**, cada `CREATE` precedido de `DROP ... IF EXISTS`, reaplicado a cada `runMigrations()`. Efeito colateral bom: gatilho que sumiu volta sozinho.
- **Tabela de conteúdo nova exige par em `contract/src/content-schema.ts` no mesmo PR.** `test/schema-conformance.test.ts` compara coluna a coluna **nos dois sentidos**; a única folga é `AUTHORING_ONLY_COLUMNS`. Coluna do pack sem par na autoria = o CMS não consegue produzir a linha; coluna da autoria sem par no pack = alguém preenche um campo que nunca chega ao aparelho.
- **O corte global × municipal é imposto pelas FKs, não escolhido.** `asset` e `venue` são globais porque `symptom_token.icon_ref` e `routing_outcome.venue_id` apontam para eles a partir do lado global, e FK global→municipal não fecha. As **regras** ficam globais de propósito: red flag corrigida alcança toda a rede por construção.
- **`enum` do Drizzle não é restrição — use `check()`.** `text(..., { enum })` é tipagem só de TypeScript e não emite `CHECK` nenhum no DDL (o DDL do pack comprova). Aqui um `role` inválido é escalada de privilégio.
- **`git diff --exit-code` ignora arquivo não rastreado**, e migração nova nasce assim. Por isso `cms:check` faz `git add --intent-to-add` antes do diff. Ao acrescentar guarda desse tipo em outro workspace, lembre da armadilha.

## Autenticacao do CMS (`cms/src/auth/`)

- **O modelo `user` do Better Auth E a tabela `admin_user`** — mapeado, nao duplicado. Uma segunda tabela de identidade faria "quem e o autor disto?" ter duas respostas possiveis, que podem divergir. `role` e `disabled_at` entram como `additionalFields`.
- **Senha mora em `account.password`; segredo TOTP, em `two_factor.secret`.** Nao ha coluna de credencial em `admin_user` — o item 16 tinha duas, e as duas estavam no lugar errado. O plugin ja **cifra** o TOTP e os backup codes sob o `BETTER_AUTH_SECRET`.
- **`admin_user` usa `integer(timestamp_ms)`, nao ISO-8601 TEXT como o resto do banco.** Nao e descuido: o Better Auth passa objetos `Date` ao adapter e o Drizzle so converte `Date` em coluna INTEGER. Tabela nossa continua em TEXT.
- **O adapter resolve campos pelo nome da PROPRIEDADE Drizzle (camelCase), a coluna e snake_case.** `emailVerified` -> `email_verified` e o par correto; confundir os dois quebra na primeira leitura do modelo. Ha teste para os dois lados.
- **`auth-schema-conformance.test.ts` compara o schema com `getAuthTables()` em runtime.** Atualizacao da biblioteca que acrescente campo reprova no CI, e nao no primeiro login em producao. Ja pegou dois defeitos antes da primeira requisicao.
- **O plugin `admin` do Better Auth NAO entra** — traz impersonation, que num sistema com dual review deixaria um admin aprovar como se fosse o revisor. Nao adianta desligar por configuracao: seguranca que depende de opcao desligada e seguranca que uma atualizacao reverte.
- **2FA obrigatoria e middleware, nao configuracao**, com **uma** excecao nomeada: o proprio fluxo de cadastro do TOTP. Sem ela, ninguem consegue ativar o que e obrigatorio ter ativado.
- **`two-factor/enable` nao liga a 2FA** — entrega o segredo, deixa `verified = 0` e revoga a sessao. A ativacao acontece na primeira verificacao bem-sucedida, num login novo.
- **O `secret` do `totpURI` esta em base32; `createOTP` espera o bruto.** Passar direto produz codigo de seis digitos que nunca confere, e o sintoma e so "Invalid code".
- **A trilha nunca recebe o corpo da requisicao** (senha, codigo TOTP) e o IP vai **hasheado com sal** — `sha256(ip)` puro se inverte por forca bruta, porque IPv4 tem 2^32 enderecos. `loadEnv()` derruba o processo sem `IP_HASH_SALT`.
- **`audit_entry.actor_id` e nulavel**, e o nulo e informacao: login recusado nao tem ator. Rota de `/api/auth/*` nao passa por `requireSession`, entao o ator e resolvido explicitamente — sem isso, "quem ativou o segundo fator?" fica sem resposta.
- **Rate limit por endpoint e parametro com padrao LIGADO**; so o teste passa `false`, e ha asserção disso. Desligar nao desliga a trava progressiva por conta.

## CRUD e editor de regras (`cms/src/content/`, `cms/src/routes/rules.ts`)

- **O CRUD e GERADO de `content/registry.ts`, nao escrito por entidade.** Tres passos precisam acontecer em toda escrita — conferir a versao lida, gravar carimbando o autor, registrar na trilha — e a forma de falhar de dezessete copias e a ultima esquecer o terceiro. `test/crud-registry.test.ts` percorre o registro e exige os tres.
- **`version` chega por `If-Match`, nunca no corpo.** Aceitar no corpo convida o cliente a reenviar o que leu, que e exatamente o conflito a detectar. Ausente responde **428**, nao 400: 400 mandaria procurar o erro no corpo.
- **O 409 carrega a versao atual.** Conflito que nao diz contra o que se perdeu obriga a recarregar a tela para descobrir.
- **O Drizzle SUBSTITUI a mensagem do driver** por `Failed query: <sql>` e poe a original em `cause`. Ler so `error.message` faz toda violacao de integridade virar 500 — a protecao funcionando parece defeito do servidor. Use `db/errors.ts`; o defeito apareceu tres vezes antes de virar modulo.
- **Nao existe `DELETE` para entidade alvo de regra clinica.** A FK recusaria, mas oferecer rota que sempre falha ensina a ignorar mensagem de erro. Token sai de circulacao por `deprecated`.
- **O avaliador DNF mora em `contract/src/rules.ts`**, nao no packer. Packer e CMS o importam. Copiar faria a simulacao mostrar um veredito e o gate de publicacao produzir outro — pior que nao simular.
- **A simulacao considera so regras `approved` mais a proposta.** Rascunho alheio faria o resultado depender de trabalho inacabado de outra pessoa, e duas pessoas veriam respostas diferentes para a mesma regra.
- **Falso negativo e classe a parte na simulacao**, como no packer: e o caso em que o app manda para casa quem precisava de emergencia.
- **O desfecho padrao e DERIVADO da menor severidade**, nao configurado. Nao ha coluna para ele, e inventar uma decidiria por fora o que a semantica ja decide.
- **Regra aprovada responde 409 com `next: /revisao`.** O gatilho do item 16 e a defesa; a rota e quem diz o que fazer.
- **`:memory:` no libSQL da um banco POR CONEXAO.** Uma transacao abre conexao nova e cai num schema vazio — sintoma: `no such table` numa tabela recem-usada. O fixture de teste usa arquivo temporario.

## Publicacao: dual review e o job (`cms/src/services/approval-workflow.ts`, `packer/src/worker.ts`)

- **A chave privada Ed25519 nunca toca o processo que atende HTTP.** O CMS aprova; o job `packer` — servico do compose **sem `ports:`** — constroi, assina e publica. A topologia E a garantia, nao uma configuracao.
- **O dual review tem TRES metades**: por PAPEL (matriz do item 17), por LINHA (gatilho `approval_no_self_approval`) e por QUORUM (agregado, no servico). A do meio mora no banco porque a ameaca e o insider, e checagem so na rota protege so contra quem passa pela rota.
- **O cenario alcancavel de auto-aprovacao e a PROMOCAO**: editor cria a release, e promovido a revisor, e passa a poder aprovar sem deixar de ser o autor. A matriz de papeis nao ve; so a regra por linha barra.
- **A FSM e dado (`TRANSICOES`), percorrida pelo teste.** Nao existe `draft -> approved` nem `pending_review -> built`: publicar sem revisao clinica precisa ser impossivel de ESCREVER.
- **`approved -> building` e compare-and-set.** Sem estado de posse, dois jobs constroem a mesma release. Tomar posse tambem entra na trilha — senao "o job travou" e indistinguivel de "esta trabalhando".
- **Portao vermelho devolve a release para `approved`**, nao para um estado de erro: depois de corrigido o conteudo, a MESMA release deve poder ser construida. A corrida golden fica registrada mesmo falhando.
- **Toda transicao do job registra `actor_id` NULO.** O job nao tem operador; inventar um `system` criaria linha em `admin_user` que parece porta dos fundos numa auditoria.
- **`extract.ts` filtra por `status='approved'`.** Rascunho no pack e conteudo nao revisado chegando a aparelho sem internet (INV-4).
- **Assinar com chave fora de `signing_key` faz a frota inteira rejeitar EM SILENCIO.** A guarda deriva a publica da privada e confere antes do build.
- **Duas fontes de suite golden, sem sincronizacao**: YAML para o caminho `seed/` (CI, sem docker) e `golden_case` para o caminho do CMS. Cada caminho tem UMA; as duas desaguam na mesma `validateGolden`.
- **`POST /api/telemetry` e a SEGUNDA e ultima excecao a LGPD-RT01.** Autenticar exigiria identidade de dispositivo (INV-2 proibe). **Nao ha produtor**: o app nao envia, e o lote de um aparelho nao alcanca k>=20 — falta um agregador.

## Comandos

```sh
# App Flutter (rodar de dentro de app/)
flutter pub get                 # tambem GERA as classes de i18n a partir de lib/l10n/*.arb
dart run build_runner build     # GERA os *.g.dart do Drift (user.db) — sem isso, analyze reprova
flutter analyze --fatal-infos   # o CI usa --fatal-infos; info vira erro
flutter test                    # suite completa
flutter test test/triage/       # so um diretorio
flutter test --plain-name "trecho do nome do teste"
flutter build apk --release --target-platform=android-arm64
tool/gen_launcher_icon.sh       # regenera os 15 PNGs do icone a partir do SVG
tool/gen_launcher_icon.sh --check   # confere que os PNGs no disco batem com o SVG
tool/gen_about_logos.sh         # rasteriza os logos institucionais da tela Sobre

# Plano de controle (rodar da raiz)
npm test                        # contract + cms + packer
SOURCE_DATE_EPOCH=1787097600 PACK_SIGNING_KEY_PATH=contract/keys/dev-k1.pem \
  PACK_VERSION=1 npm run pack:build     # gera packer/out/{content.db,manifest.json}
npm run contract:check          # codegen fora de sincronia = build vermelho
npm run cms:generate            # migracao do banco master (drizzle-kit)
npm run cms:triggers            # regenera cms/src/db/triggers.sql
npm run cms:check               # schema fora de sincronia = build vermelho
npm run typecheck               # tsc nos tres workspaces (o CI roda; tsx nao confere tipo)
npm run cms:migrate             # aplica no sqld (CMS_DATABASE_URL)
npm run cms:create-admin -- --email a@b.invalid --name "Nome"   # 1o operador
npm run cms:import-golden -- --autor <id>       # semeia golden_case do YAML (1x)
npm run pack:worker -- --once                   # job: constroi, assina e publica
npm --workspace @guia-ubs/cms run dev    # sobe o CMS (exige os segredos de infra/.env)
# Rota, variavel de ambiente ou script novo exige linha em docs/operacao.md —
# `doc-operacao.test.ts` reprova o CI se o manual ficar para tras.
docker compose -f infra/compose.yaml config --quiet
```

**Código gerado não é versionado.** `lib/l10n/app_localizations*.dart` (i18n) e `**/*.g.dart` (Drift) estão no `.gitignore`. O i18n sai do próprio `flutter pub get`; o Drift exige `dart run build_runner build`. Em checkout limpo, pular esse comando produz ~35 erros de análise que não têm nada a ver com o código escrito.

**`SOURCE_DATE_EPOCH` no packer não é opcional quando o hash importa.** Sem ele o `built_at` recebe o relógio de parede e duas builds do mesmo conteúdo produzem `content.db` diferentes — o que invalida as fixtures de teste e, em produção, faria a frota re-baixar o pack a cada republicação.

**O ícone do launcher é gerado, não desenhado à mão.** A fonte é `app/tool/icon/icone_app.svg` (a arte como foi entregue, pino verde sobre fundo claro); o script inverte as cores, enquadra e escreve os 15 PNGs. Duas regras moram no cabeçalho dele e não devem ser reinventadas no olho: a altura do pino ocupa **62 dp** dos 108 dp da tela adaptativa — não 66, porque a ponta afilada é o que uma máscara circular decepa primeiro — e a composição é centrada **no centro do pino**, não no da tela, que é assimétrica. A estrada sangrar pela borda mascarada é intencional. No monocromático, a cruz precisa ser **vazada** (`DstOut` no gerador): ela é um path desenhado por cima do pino, não um furo, e silhueta ingênua devolve uma mancha sólida sem nada que identifique o app.

**A barra tem TRÊS abas, e a terceira é "Mais" — "Documentos" saiu dela.** Não foi arbitrário: a inicial usa exatamente oito elementos acionáveis (cinco escolhas + três abas), que é o teto da RNF-06, e `test/ui/accessibility_test.dart` reprova em nove. Uma quarta aba obrigaria a mexer na tela clínica para abrir espaço a um menu utilitário. "Documentos" cedeu o lugar porque já tinha ladrilho próprio na inicial; de quebra ganhou botão voltar, que raiz de aba não tem. Antes de acrescentar destino à barra, resolva de onde sai o elemento.

**Coluna nova no `user.db` custa quatro coisas, no mesmo commit** — `theme_mode` e `font_scale` são o precedente: (1) `schemaVersion` + `onUpgrade` com teste de migração v1→v2, porque **sem ele todo aparelho já instalado quebra no boot** e instalação limpa não mostra isso; (2) a lista permitida de `test/prefs/lgpd_surface_test.dart`, com a justificativa escrita; (3) uma entrada na tela de privacidade em pt e es, que o teste conta contra as colunas; (4) a linha correspondente em `spec/lgpd.md`.

**Armadilha do `flutter build apk --release` logo após um build debug:** falha com *"package dev.flutter.plugins.integration_test does not exist"*. Apagar `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java` resolve; ele é regerado.

**Verificação em aparelho** (o `adb` vive em `~/Android/Sdk/platform-tools`): vários defeitos deste projeto só apareceram no aparelho — estouro de layout em paisagem, re-hash de 806 MB a cada boot, contraste de 1,94:1 no botão principal, tela sem botão voltar. Sempre que a mudança for de UI ou de I/O, instale e olhe.
