# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Estado do repositório

Projeto **em implementação**. A documentação vive em `docs/` (em **português**; mantenha novos documentos em pt-BR) e continua sendo a fonte de verdade. O código já existe em `app/` (Flutter), `contract/` + `packer/` (TypeScript), `native/llama_shim/` (C) e `infra/`. O andamento por item está em `docs/arquitetura.md` §Roadmap; as medições e decisões de cada item entregue ficam nas subseções §5.x do mesmo arquivo. O produto especificado: **Guia UBS**, app Android offline-only (Flutter + SLM local via llama.cpp) com interface 100% iconográfica para orientar populações rurais, imigrantes e pessoas de baixo letramento sobre serviços do SUS, mais um plano de controle de conteúdo (TypeScript/Hono) que compila e assina pacotes SQLite distribuídos via arquivos estáticos.

## Hierarquia documental (ordem de precedência)

1. **`docs/PRD.md`** — fonte única da verdade; consolida e governa os demais. Em conflito, vale o PRD.
2. **`docs/espec.md`** — normativo para comportamento: matrizes FSM completas (FSM-A triagem, FSM-B ciclo do pack), invariantes INV-1…8, requisitos RF/RNF com critérios de aceitação.
3. **`docs/stack.md`** — decisões de tecnologia com trade-offs, auditoria open source (§9) e **ADRs arquiteturais (§10)**; §11 é a explicação não técnica para sponsors.
4. **`docs/lgpd.md`** — requisitos de conformidade LGPD (LGPD-RF01…17, RT01…11).
5. **`docs/brainstorm.md`** — visão de produto, milestones M1–M7, definição do MVP.
6. **`docs/design.html`** — protótipo interativo autocontido (abrir no navegador); publicado como Artifact.

Ao alterar uma decisão em um documento, propague a consistência nos demais (eles se citam por links relativos).

## Invariantes que nenhum código futuro pode violar

Estas regras são de segurança clínica/legal, não preferências (detalhes em espec.md §5.1):

- **Red flag ⇒ EMERGENCY, sempre.** O gate determinístico roda ANTES do LLM e `severity_final = max(gate, llm)` — o LLM nunca rebaixa severidade. Exceção no gate = fail-closed para EMERGENCY.
- **Zero dado pessoal do usuário final** em disco, log ou rede. A sequência de sintomas morre em memória; telemetria só agregada por coorte com k-anonimato ≥ 20.
- **Offline-only em runtime:** toda funcionalidade do usuário opera com rádio desligado. O app faz exatamente duas chamadas de rede, ambas fora do caminho do usuário: download de manifest/pack pelo WorkManager e, desde o [ADR-003](docs/stack.md), download do modelo SLM no 1º acesso (700 MB–1,2 GB). Ambas retomáveis por HTTP Range, com SHA-256 conferido antes de aceitar, e **falha em qualquer uma nunca bloqueia o app** — sem modelo, a triagem roda via `RuleOnlyEngine`.
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

Semântica de cor fixa: **verde = UBS/rotina, vermelho = emergência, azul = informação**. Alvos de toque ≥ 64 dp, máx. 8 elementos por tela, navegação linear com voltar/casa sempre visíveis, zero texto obrigatório (todo conteúdo essencial tem ícone + áudio pt/es). O protótipo visual está em `docs/design.html`; a implementação normativa é `app/lib/ui/theme/`.

- **A escala de `severity_level` pertence ao PACK, não ao binário.** O pacote semente usa 10 (rotina) e 100 (emergência); outro município pode publicar outra escala. Use `severityFor(level, model)`, que deriva os extremos dos desfechos do próprio pack. Limiares fixos em Dart já causaram o pior defeito visual do projeto: todo resultado de rotina pintado de vermelho com "Ligue 192" embaixo.
- **Peça a cor pela SEVERIDADE, não pelo nome.** `GubsColors.forSeverity(...)` devolve o par certo; escolher entre `green` e `red` na hora do layout é o caminho para um cartão de emergência pintado de verde.
- **Dentro de botão colorido, informe a cor do texto explicitamente** (`onGreen`/`onRed`/`onAmber`). Os estilos de `Theme.of(context).textTheme` já vêm coloridos com `onSurface`, e essa cor vence o `foregroundColor` do botão — armadilha documentada em `app/lib/ui/theme/gubs_theme.dart`.
- **O mapa de rotas é dado** (`app/lib/ui/app_routes.dart`): profundidade, dead-ends e o alcance da exceção da INV-8 são verificados percorrendo a lista, não lendo builders.
- Strings de casca vivem em `app/lib/l10n/*.arb`; **conteúdo clínico vem do `content.db` assinado**, nunca de ARB.

## Dados no aparelho

- **`content.db` é somente leitura, e isso é estrutural** (`app/lib/content/`). O app nunca escreve conteúdo: ele troca o arquivo inteiro quando o sync commita (FSM-B). Um caminho de escrita ali seria um caminho para orientação não revisada chegar ao usuário sem assinatura (INV-4). O pack é aberto em `OpenMode.readOnly` e há teste que confirma que o `UPDATE` falha.
- **Falta de tradução recua para `pt`, não some com o item.** O packer bloqueia publicação com tradução faltando, então recuo no aparelho é defeito — mas sumir com "Onde ir" de quem precisa é pior que mostrá-lo em português para um hispanofalante. O recuo é sinalizado em `Localized.isFallback`.
- **A tela de privacidade lista o que o `user.db` guarda, e há teste que compara as duas listas** (`app/test/ui/privacy/`). Preferência nova sem entrada na tela reprova: uma lista redigida à parte envelhece e passa a mentir para o titular.
- **Telemetria: a allowlist é uma enum, nunca uma `String`** (`app/lib/telemetry/metric_key.dart`), conferida contra `contract/telemetry-schema.json`. O módulo **não envia e não persiste** — enviar seria uma terceira chamada de rede (exige ADR) e persistir viraria coluna nova no `user.db`. O opt-out zera a COLETA, não só o envio.
- **O esquema do `user.db` é a superfície auditável da LGPD** (`app/lib/prefs/user_database.dart`). Colunas **tipadas**, nunca chave-valor: as colunas são a resposta a "o que este app guarda sobre a pessoa", e `test/prefs/lgpd_surface_test.dart` as enumera. Coluna nova reprova o build até ser justificada contra a INV-2 e a LGPD-RF13. Sintoma é dado sensível de saúde e **não** é persistido — a sequência morre em memória.

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

# Plano de controle (rodar da raiz)
npm test                        # contract + packer
SOURCE_DATE_EPOCH=1787097600 PACK_SIGNING_KEY_PATH=contract/keys/dev-k1.pem \
  PACK_VERSION=1 npm run pack:build     # gera packer/out/{content.db,manifest.json}
npm run contract:check          # codegen fora de sincronia = build vermelho
docker compose -f infra/compose.yaml config --quiet
```

**Código gerado não é versionado.** `lib/l10n/app_localizations*.dart` (i18n) e `**/*.g.dart` (Drift) estão no `.gitignore`. O i18n sai do próprio `flutter pub get`; o Drift exige `dart run build_runner build`. Em checkout limpo, pular esse comando produz ~35 erros de análise que não têm nada a ver com o código escrito.

**`SOURCE_DATE_EPOCH` no packer não é opcional quando o hash importa.** Sem ele o `built_at` recebe o relógio de parede e duas builds do mesmo conteúdo produzem `content.db` diferentes — o que invalida as fixtures de teste e, em produção, faria a frota re-baixar o pack a cada republicação.

**Armadilha do `flutter build apk --release` logo após um build debug:** falha com *"package dev.flutter.plugins.integration_test does not exist"*. Apagar `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java` resolve; ele é regerado.

**Verificação em aparelho** (o `adb` vive em `~/Android/Sdk/platform-tools`): vários defeitos deste projeto só apareceram no aparelho — estouro de layout em paisagem, re-hash de 806 MB a cada boot, contraste de 1,94:1 no botão principal, tela sem botão voltar. Sempre que a mudança for de UI ou de I/O, instale e olhe.
