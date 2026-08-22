# Guia UBS

Aplicativo Android **offline-only** que orienta populações rurais, imigrantes e
pessoas de baixo letramento sobre os serviços da Atenção Básica do SUS. A
interface é **100% iconográfica** — sem texto obrigatório — e a triagem roda no
próprio aparelho, com um SLM local (llama.cpp) atrás de um gate determinístico
de red flags.

O conteúdo clínico não vive no binário: ele chega em pacotes SQLite assinados
(Ed25519), produzidos por um plano de controle em TypeScript e distribuídos como
arquivos estáticos.

> **Aviso.** As regras clínicas e os ícones do pacote semente são *placeholders*
> explicitamente marcados (`clinical_source: "revisão clínica pendente"`, casos
> golden com `reviewed_by: ~`). O packer emite aviso a cada build. **Nada aqui
> deve chegar perto de um usuário real antes da dupla aprovação clínica.**

## Por que offline-only

Toda funcionalidade do usuário opera com o rádio desligado. O app faz **duas**
chamadas de rede, ambas fora do caminho do usuário e ambas retomáveis com
SHA-256 conferido antes de aceitar:

1. manifest + pacote de conteúdo, pelo WorkManager;
2. o modelo SLM, no primeiro acesso (~800 MB — [ADR-003](docs/stack.md)).

Falha em qualquer uma **nunca bloqueia o app**: sem modelo, a triagem roda pelo
`RuleOnlyEngine`; sem pacote, o app continua navegável.

## Invariantes

Estas regras são de segurança clínica e legal, não preferências. Detalhes em
[`docs/espec.md` §5.1](docs/espec.md):

| # | Invariante |
|---|---|
| INV-1 | Red flag ⇒ EMERGENCY, sempre. O gate roda **antes** do LLM e `severity_final = max(gate, llm)` — o modelo só escala, nunca rebaixa. Exceção no gate = fail-closed para emergência |
| INV-2 | Zero dado pessoal em disco, log ou rede. A sequência de sintomas morre em memória |
| INV-3/4 | Nenhum conteúdo sem assinatura Ed25519 válida e dual review chega ao usuário; versão de pacote é monotônica |
| INV-8 | Falha de LLM, TTS ou sync nunca impede a navegação de conteúdo estático |

## Estrutura

```
app/        Flutter — o aplicativo
  lib/triage/     gate determinístico, motores, FSM-A (orquestrador)
  lib/sync/       FSM-B (ciclo do pacote), verificação Ed25519, downloads
  lib/content/    leitura somente-leitura do content.db
  lib/prefs/      user.db (Drift) — a superfície auditável da LGPD
  lib/telemetry/  allowlist fechada de métricas agregadas
  lib/ui/         casca, triagem, conteúdo estático, privacidade
contract/   TypeScript — schemas Drizzle/Zod e o contrato do manifest
packer/     TypeScript — constrói, valida, assina e publica os pacotes
seed/       SQL e suíte golden clínica que alimentam o pacote semente
native/     shim C de 4 funções sobre o llama.cpp (ADR-002)
infra/      Compose com sqld + MinIO + Caddy
docs/       fonte de verdade (ver hierarquia abaixo)
```

## Pré-requisitos

| Ferramenta | Versão | Para quê |
|---|---|---|
| Flutter | 3.44.8 | app |
| Node | ≥ 22 | contrato e packer |
| Android SDK | compileSdk 36, minSdk 26 | build do APK |
| CMake + Ninja | — | shim nativo (o primeiro build baixa o llama.cpp) |
| Docker | — | `infra/` |
| librsvg + ImageMagick | — | só para regenerar o ícone do launcher |

## Build e testes

### App Flutter

Rodar de dentro de `app/`:

```sh
flutter pub get                 # também GERA as classes de i18n de lib/l10n/*.arb
dart run build_runner build     # GERA os *.g.dart do Drift (user.db)
flutter analyze --fatal-infos   # o CI usa --fatal-infos: info vira erro
flutter test                    # suíte completa
flutter build apk --release --target-platform=android-arm64

tool/gen_launcher_icon.sh           # regenera o ícone do launcher a partir do SVG
tool/gen_launcher_icon.sh --check   # confere que os PNGs no disco batem com o SVG
```

**Código gerado não é versionado.** `lib/l10n/app_localizations*.dart` e
`**/*.g.dart` estão no `.gitignore`. O i18n sai do próprio `flutter pub get`; o
Drift exige `build_runner`. Em checkout limpo, pular esse comando produz ~35
erros de análise sem relação com o código escrito.

Os 15 PNGs do ícone **são** versionados — o build do Android os consome direto —
mas a receita que os produz fica ao lado deles. `app/tool/icon/icone_app.svg` é a
arte como foi entregue; o script inverte as cores, enquadra para a máscara do
ícone adaptativo e escreve as três camadas em cada densidade. Precisa de
`rsvg-convert`, `magick` e `python3`, e não roda no CI: é ferramenta de quem
edita o ícone. As regras de enquadramento estão no cabeçalho do script.

Testes por diretório ou por nome:

```sh
flutter test test/triage/
flutter test --plain-name "trecho do nome do teste"
```

### Plano de controle

Rodar da raiz:

```sh
npm test                        # contract + packer
npm run contract:check          # codegen fora de sincronia = build vermelho
npm run pack:check              # constrói e valida sem assinar
docker compose -f infra/compose.yaml config --quiet
```

Construir um pacote assinado:

```sh
SOURCE_DATE_EPOCH=1787097600 \
PACK_SIGNING_KEY_PATH=contract/keys/dev-k1.pem \
PACK_VERSION=1 npm run pack:build     # gera packer/out/{content.db,manifest.json}
```

`SOURCE_DATE_EPOCH` **não é opcional quando o hash importa**: sem ele o
`built_at` recebe o relógio de parede, duas builds do mesmo conteúdo produzem
`content.db` diferentes, e a frota re-baixaria o pacote a cada republicação.

### Infraestrutura local

```sh
cd infra && docker compose up -d
```

Sobe `sqld` (banco master), MinIO (artefatos) e Caddy (borda). É a mesma
topologia planejada para produção — paridade dev/prod literal
([stack.md §7](docs/stack.md)).

### Verificação em aparelho

Vários defeitos deste projeto só apareceram no aparelho — estouro de layout em
paisagem, re-hash de 806 MB a cada boot, contraste de 1,94:1 no botão principal,
tela de triagem sem botão voltar, um job de background que nunca seria chamado.
**Sempre que a mudança for de UI ou de I/O, instale e olhe.**

```sh
flutter build apk --release --target-platform=android-arm64
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Há também `integration_test/` (carga do `.so` dentro do APK) e um bench nativo
em `native/llama_shim/bench_main.c`, que roda de `/data/local/tmp` e é a única
forma de fixar núcleos com `taskset`.

> **Armadilha:** `flutter build apk --release` logo após um build debug falha com
> *"package dev.flutter.plugins.integration_test does not exist"*. Apagar
> `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java`
> resolve — ele é regerado.

## CI

| Job | O que guarda |
|---|---|
| `app` | `flutter analyze --fatal-infos` + suíte completa, incluindo a golden clínica: falso negativo reprova o PR |
| `interop` | Assina um pacote com chave Ed25519 efêmera e o verifica em Dart — pega divergência entre a serialização canônica em TS e em Dart, que de outra forma só apareceria como frota parando de receber conteúdo |
| `shim` | Compila o shim nativo e confere os símbolos exportados: mudança de ABI no llama.cpp falha aqui, não no aparelho do usuário |
| `contract` | `npm test` + `contract:check` — codegen fora de sincronia reprova |

## Estado atual

Fases 0, 1 e 2 concluídas. Verificação da última execução completa:

| Suíte | Resultado |
|---|---|
| Testes Dart | 438 |
| Testes TypeScript (contract + packer) | 24 |
| Golden clínica | 24/24 |
| APK release arm64 | 24,8 MB |

Medições do SLM em aparelho real (Motorola Edge 40 Neo), Gemma 3 1B Q4_K_M:
p95 de 4731 ms com o agendador livre e 13130 ms no proxy de aparelho de entrada
(Cortex-A55), pico de 832 MB de RAM. As decisões que essas medições forçaram
estão no [ADR-003](docs/stack.md); os números completos, em
[arquitetura.md §5.1](docs/arquitetura.md).

**Próximo:** Fase 3 — plano de controle (schema completo, autenticação, CRUD de
conteúdo com dual review e orquestração de release).

## Documentação

Ordem de precedência — em conflito, vale o documento mais acima:

1. [`docs/PRD.md`](docs/PRD.md) — fonte única da verdade
2. [`docs/espec.md`](docs/espec.md) — normativo de comportamento: FSM-A, FSM-B, invariantes, RF/RNF
3. [`docs/stack.md`](docs/stack.md) — decisões de tecnologia, auditoria open source e ADRs
4. [`docs/lgpd.md`](docs/lgpd.md) — conformidade LGPD
5. [`docs/brainstorm.md`](docs/brainstorm.md) — visão de produto e milestones
6. [`docs/arquitetura.md`](docs/arquitetura.md) — roadmap e o resultado medido de cada item entregue
7. [`docs/design.html`](docs/design.html) — protótipo interativo (abrir no navegador)

[`CLAUDE.md`](CLAUDE.md) reúne as armadilhas já pagas — leia antes de mexer em
tema, sync ou dados no aparelho.

## Licença

MIT — ver [LICENSE](LICENSE). Toda a stack é open source por decisão registrada
([stack.md §9](docs/stack.md)); o modelo Gemma 3 1B é *open weights* sob termos
Google, com alternativas OSI documentadas.
