# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Estado do repositório

Projeto em **fase de especificação** — ainda não há código-fonte, build ou testes. Todo o conteúdo vive em `docs/` (em **português**; mantenha novos documentos em pt-BR). O produto especificado: **Guia UBS**, app Android offline-only (Flutter + SLM local via llama.cpp) com interface 100% iconográfica para orientar populações rurais, imigrantes e pessoas de baixo letramento sobre serviços do SUS, mais um plano de controle de conteúdo (TypeScript/Hono) que compila e assina pacotes SQLite distribuídos via arquivos estáticos.

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

Semântica de cor fixa: **verde = UBS/rotina, vermelho = emergência, azul = informação**. Alvos de toque ≥ 64 dp, máx. 8 elementos por tela, navegação linear com voltar/casa sempre visíveis, zero texto obrigatório (todo conteúdo essencial tem ícone + áudio pt/es). O padrão de referência está implementado em `docs/design.html` (tokens de tema claro/escuro incluídos).

## Comandos

Ainda não há build/teste/lint — o scaffolding (app Flutter, `cms/`, `packer/`) será criado nos milestones M3–M4. Quando existir, o ponto de partida é o compose de stack.md §7 (`docker compose up -d` para o plano de controle; `docker compose run --rm packer` para gerar packs).
