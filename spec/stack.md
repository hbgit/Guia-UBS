# Guia UBS — Minimum Viable Tech Stack (MVTS)

> Premissa arquitetural: este sistema tem **duas metades assimétricas**. O produto real roda 100% no device (Flutter + SLM local + SQLite). A "nuvem" é apenas um **plano de controle de conteúdo**: um CMS mínimo que compila e assina pacotes de conteúdo versionados, servidos como arquivos estáticos via CDN. Não existe caminho de request usuário→servidor em runtime. Toda decisão abaixo deriva dessa assimetria — e é ela que garante o TTM e a escalabilidade quase gratuita.

---

## 1. Stack Core & Runtime

### 1.1 Cliente (o produto) — Flutter / Dart 3

| Camada | Escolha | Justificativa (trade-off) |
|---|---|---|
| Framework | **Flutter (Android-first, minSdk 26)** | Único runtime que entrega UI iconográfica custom + FFI para inferência nativa + um só codebase para o futuro iOS. Alternativa React Native descartada: bridge JS penaliza FFI de inferência e TTS; Kotlin puro descartado: perde iOS e o time já tem Dart como pré-requisito. |
| Estado | **Riverpod (codegen) + freezed** | Sealed classes + exhaustive switch eliminam estados impossíveis na triagem (crítico: um estado inconsistente aqui é risco clínico). Menos boilerplate que BLoC para um app sem eventos complexos. |
| Navegação | **GoRouter** | Declarativo, deep-link-ready (v2: abrir direto num módulo educativo, como o calendário vacinal, por QR impresso no material do projeto). |
| Inferência local | **llama.cpp via FFI (`llama_cpp_dart`) + Gemma 3 1B Q4_K_M (GGUF, `ggml-org`)**, origem por `--dart-define=MODEL_URL`: o storage próprio, ou a exceção do Hugging Face enquanto ele não existe — ver [ADR-004](#10-registro-de-decisões-arquiteturais-adr) | GGUF é o formato com maior liquidez de modelos e roda em qualquer SoC ARM sem depender de delegates. MediaPipe LLM Inference fica como *fallback* se o custo de manutenção do FFI apertar — API mais estável, porém formato `.task` proprietário e churn de versões do Google. |
| Camada de segurança | **Motor de regras determinístico em Dart puro** (tabela de red flags versionada no content pack) | Red flags NUNCA passam pelo LLM. Regras são dados, não código → atualizáveis via sync sem release. |
| TTS | **`flutter_tts` (engine do sistema)** pt/es; áudios gravados (Opus) para línguas indígenas | Zero MB no bundle vs. TTS neural embarcado (~80 MB/voz). Trade-off aceito: qualidade de voz varia por device. |
| Background sync | **WorkManager (`workmanager`)** com constraint `NetworkType.connected` | O SO acorda o app na janela de conectividade — é exatamente a semântica da "sincronização de oportunidade", de graça. |

**Nota sobre tipagem:** Dart 3 é nominal, não estrutural — o requisito de "tipagem estrutural" é atendido onde importa: no backend TS (structural typing nativo) e na fronteira entre os dois via codegen de schema (§3.3).

### 1.2 Backend (plano de controle) — TypeScript / Node 22

| Camada | Escolha | Justificativa |
|---|---|---|
| Runtime | **Node 22 LTS** (Bun como upgrade opt-in) | Bun acelera DX, mas Node LTS elimina uma classe inteira de incompatibilidade de libs — em stack lean, previsibilidade > velocidade de cold start. |
| Framework | **Hono + Zod (`@hono/zod-openapi`)** | "Batteries-included" aqui significa: validação + OpenAPI + RPC client tipado (`hono/client`) no core, portável para qualquer runtime (Node, Workers, Lambda) sem reescrita — mantém a porta da edge aberta sem pagar por ela agora. Next.js descartado para a API: o admin não precisa de SSR; NestJS descartado: boilerplate de DI para um serviço de ~15 endpoints. |
| Admin UI | **Vite + React SPA** servida pelo próprio Hono | Um container só. Sem SSR, sem framework meta. |

---

## 2. Persistência & Estado

### 2.1 Decisão Relacional vs. Documentos

**Relacional (SQLite em ambas as pontas).** O domínio é um catálogo normalizado com integridade referencial real (`Sintoma ⇄ RegraTriagem ⇄ Encaminhamento`, `Serviço ⇄ Documento`, `Vacina ⇄ PerfilEtário`) e multilíngue (`entidade ⇄ traduções pt/es/indígena`). Documentos forçariam a duplicar traduções e validar referências na aplicação — exatamente o tipo de bug silencioso que num app de saúde vira incidente.

### 2.2 Topologia: um dialeto, três encarnações

```
┌─ libSQL/sqld self-host (master DB) ────┐      ┌─ Device ─────────────────────┐
│  CMS escreve via Drizzle               │      │  content.db (SQLite, RO)     │
│         │ packer (job, sem porta)      │ CDN  │  swap atômico no sync        │
│         ▼                              │─────▶│  user.db (Drift, RW local)   │
│  content-pack vX.Y (SQLite file +      │      │  rules.json + modelo GGUF    │
│  áudios Opus + manifest assinado)      │      └──────────────────────────────┘
└────────────────────────────────────────┘
```

- **Servidor: libSQL/`sqld` self-hosted (MIT)** — mesmo dialeto SQLite do device: o *packer* materializa o content pack sem camada de tradução de dialeto. Roda como um container no próprio VPS — o compose do §7 **é** a topologia de produção (paridade dev/prod literal). Turso (SaaS gerenciado sobre o mesmo libSQL) descartado: serviço comercial que não agrega nada aqui, pois `sqld` entrega o mesmo dialeto sem fornecedor. Neon (Postgres) descartada na v1: segundo dialeto + ETL packer→SQLite que é puro custo.
- **Device: Drift** (type-safe SQLite para Dart) para o `user.db` (preferências, cache de estado); o `content.db` chega **pronto e read-only** do pipeline — o app nunca roda migração de conteúdo, só troca o arquivo (swap atômico: download → verificação de assinatura → rename). Rollback = manter o pack anterior até o novo validar.
- **Migrações rápidas:** `drizzle-kit` (SQL puro, diff automático) no master. No device, Drift migra apenas o `user.db` (esquema minúsculo).

### 2.3 Capacidade Offline (offline-first de verdade)

- O app é **offline-only em runtime**; rede é usada exclusivamente pelo WorkManager para baixar `manifest.json` → comparar versão/hash → baixar delta do pack → verificar Ed25519 → swap.
- Downloads retomáveis (HTTP Range) — janelas de conectividade de 30s são o caso nominal, não a exceção.
- Sem estado de servidor por usuário ⇒ sem sync bidirecional, sem CRDT, sem conflito. Essa renúncia é a maior economia de complexidade da stack inteira.

---

## 3. DX, ORM & IaC

### 3.1 ORM — Drizzle

- **Drizzle + drizzle-kit** no backend: schema-as-code TS, introspecção real (`drizzle-kit pull`), migrações SQL legíveis, e dialeto SQLite nativo (Prisma trata SQLite como cidadão de segunda classe e seu engine engorda o container; SQLx é Rust — fora do ecossistema escolhido).
- O schema Drizzle é a **fonte única de verdade** de onde deriva todo o resto (§3.3).

### 3.2 IaC — Docker Compose + Ansible (100% open source)

- **Ansible (GPL-3.0)** provisiona o VPS de forma reprodutível: Docker, firewall, volume criptografado (LUKS), usuário de deploy, unit systemd que roda `docker compose -f compose.yaml up -d`. Um playbook versionado no repo substitui todo o papel do SST/Railway.
- **O compose do §7 (`infra/compose.yaml`) é o artefato de deploy** — não existe distinção dev/prod além dos segredos reais e do `compose.override.yaml`, que é **só de dev** (edge sem TLS) e não entra na VPS ([ADR-007](#10-registro-de-decisões-arquiteturais-adr)).
- **Coolify (Apache-2.0)** como opção de PaaS self-hosted se a equipe quiser DX de deploy por git push — mesma máquina, zero SaaS.
- SST v3 e Railway removidos: eram conveniência sobre nuvens comerciais; com a infra inteira num VPS, viram custo e dependência sem contrapartida. Kubernetes segue sendo autoflagelo nesta escala.

### 3.3 Cadeia de Type Safety de Ponta a Ponta

Requisito: *mudança no schema do banco quebra o build do frontend.* A cadeia cruza a fronteira TS→Dart via codegen em CI:

```
schema.ts (Drizzle)
  ├─▶ drizzle-zod ─▶ Zod schemas ─▶ API Hono tipada + hono/client (admin SPA quebra em compile-time)
  └─▶ zod-to-json-schema ─▶ contract/pack-schema.json  ← versionado no repo
                                    │
                                    ▼  (CI: quicktype/json_schema codegen)
                              lib/generated/pack_models.dart (freezed)
                                    │
                                    ▼
                              flutter analyze + testes de contrato ─▶ ❌ build quebra
```

Renomeou uma coluna no Drizzle → o JSON Schema muda → o Dart gerado muda → `flutter analyze` falha no mesmo PR. O `pack-schema.json` commitado também funciona como contrato versionado entre packs antigos e apps antigos (campo `schemaVersion` no manifest; app rejeita pack de major incompatível).

---

## 4. Auth & Edge

### 4.1 Autenticação

- **Usuário final: zero auth, por design.** Nenhum cadastro, nenhum PII — isso é feature de produto (LGPD/confiança), não corte de escopo.
- **Admin/CMS: Better Auth** (self-hosted, TS, roda em qualquer runtime incl. edge, sessões no próprio `sqld` via adapter Drizzle). Clerk/Auth0 descartados: vendor lock-in e custo por MAU para um sistema com poucos operadores da equipe do projeto é comprar problema. 2FA TOTP nativo — suficiente para editores de conteúdo de saúde.

### 4.2 Cache & Entrega na Edge

- **A borda atende duas superfícies, com regimes opostos** (desde o item 24): o
domínio de conteúdo entrega packs ao aparelho e recusa tudo que não seja
`GET`/`HEAD`; o domínio do CMS serve o plano de controle, que é autenticado e
escreve. Blocos separados de propósito — herdar a guarda de somente-leitura no
CMS quebraria login e aprovação.

**MinIO (AGPL-3.0) atrás de Caddy (Apache-2.0)**, self-hosted no VPS, para os content packs. Caddy dá TLS automático (Let's Encrypt, gratuito) e cache de estáticos; MinIO dá a API S3 que o packer consome. Trade-off assumido ao remover a CDN comercial: perde-se capilaridade global — aceitável porque manifest e deltas são KB-scale e **qualquer servidor estático vira espelho** (nginx/Caddy + rsync, inclusive de terceiros, que não precisam ser confiáveis), sem nenhuma mudança no app.
- Estratégia de cache em duas classes:
  - **Packs e áudios**: nomeados por hash de conteúdo (`pack-a1b2c3.db`), `Cache-Control: public, max-age=31536000, immutable` — cache infinito, invalidação impossível por construção.
  - **`manifest.json`**: `max-age=60` + ETag — único objeto mutável; o device faz um GET condicional barato e só baixa o resto se a versão mudou.
- Assinatura **Ed25519 do manifest + hash dos artefatos** (chave pública embarcada no app): o servidor de conteúdo e qualquer espelho são infraestrutura não-confiável; o device verifica tudo. Isso torna os espelhos triviais de operar (não precisam ser confiáveis) e mantém a garantia de integridade do **pack** mesmo quando ele chega por repasse (Bluetooth/SD). O repasse do APK entre pessoas, por sua vez, não é canal oficial ([ADR-006](#10-registro-de-decisões-arquiteturais-adr)): o binário se confere pelo SHA-256 publicado (RF-17).

---

## 5. Escalabilidade (10x–50x sem rearquitetura)

| Componente | Carga 50x | Ação necessária |
|---|---|---|
| Entrega de packs (MinIO+Caddy) | Estático + cache imutável | Adicionar espelhos estáticos (rsync) quando a banda do VPS saturar |
| Inferência | Roda no device do usuário | Nenhuma — escala com a base instalada (custo marginal ~0) |
| CMS (VPS/compose) | Tráfego interno (admins) | Upgrade vertical do VPS; irrelevante para usuários finais |
| `sqld` (self-host) | Leitura só pelo packer/CMS | Já é self-host; réplica de leitura opcional em segundo container |

O único caminho quente (download de pack numa ação educativa de grande alcance, como uma campanha de vacinação nacional) é arquivo estático cacheável e assinado — espelhável em qualquer servidor estático, sem que o espelho precise ser confiável.

---

## 6. Análise de Risco — O Elo Mais Fraco

**`llama_cpp_dart` (binding FFI de inferência no device).** Não é um vendor SaaS, e é exatamente por isso que é o risco subestimado:

- **Vendor lock-in (invertido):** o risco não é aprisionamento comercial, é **abandono de manutenção** — binding FFI de nicho, mantido por poucos, acoplado ao ritmo agressivo de breaking changes do llama.cpp upstream e ao NDK/ABI do Android. Um `pub upgrade` pode quebrar inferência em produção num device que você não tem no lab.
- **Custo de longo prazo:** não é fatura de cloud — é **custo de engenharia recorrente**: recompilar `.so` para arm64/armv7, testar em matriz de SoCs de entrada, perseguir regressões de quantização. É o único componente da stack sem free tier de manutenção alheia.
- **Migração futura:** média-alta. A mitigação está desenhada desde o dia 1: **isolar a inferência atrás de uma interface Dart única (`TriageEngine`)** com três implementações possíveis — llama.cpp FFI (default), MediaPipe LLM (fallback Google-supported), e **regras puras sem LLM** (kill switch: o app degrada para triagem 100% determinística e continua clinicamente seguro). O modelo em GGUF preserva liquidez de formato.

Menção honrosa: **banda e disponibilidade do VPS único** — sem CDN comercial, o servidor de conteúdo é o gargalo de distribuição e um ponto único de indisponibilidade. Mitigação barata e já desenhada: espelhos estáticos por rsync (operáveis por terceiros — a assinatura Ed25519 dispensa confiança no espelho), e o app tolera indisponibilidade por design (BASE: a frota apenas converge mais devagar, nunca para de funcionar).

---

## 7. `docker-compose.yaml` de Síntese

Este compose **é** a topologia de produção (não um stand-in): master DB `sqld`, CMS, MinIO como storage de packs, Caddy como edge TLS/cache e o job de empacotamento. A fonte é [`infra/compose.yaml`](../infra/compose.yaml); o bloco abaixo é uma síntese dele, sem os comentários e com os `healthcheck` abreviados — em divergência, vale o arquivo. Em dev, `infra/compose.override.yaml` é sobreposto automaticamente (edge sem TLS, em `127.0.0.1:8081`/`8082`) e o app Flutter roda no host/emulador apontando para ele; **na VPS o override não entra** (`docker compose -f compose.yaml`, [ADR-007](#10-registro-de-decisões-arquiteturais-adr)). O CI do app instala o Flutter fixado por versão (`subosito/flutter-action`, `.github/workflows/app.yml`), em pipeline separado.

Duas linhas de segurança aparecem pela **ausência**: `cms` e `packer` não têm `ports:`. A única porta publicada é a do `edge`; `db` e `storage` só escutam em `127.0.0.1`. A chave privada Ed25519 entra **só** no `packer`, montada `:ro` a partir do cofre, e nunca no `cms`, que atende HTTP — juntar os dois faria uma execução remota no serviço web virar conteúdo clínico assinado (INV-4). `cms/test/infra-topologia.test.ts` afirma essa topologia.

```yaml
services:
  db:                                   # banco master; mesmo dialeto SQLite do device
    image: ghcr.io/tursodatabase/libsql-server:v0.24.32
    restart: unless-stopped
    environment:
      SQLD_NODE: primary
    ports:
      - "127.0.0.1:8080:8080"
    volumes:
      - dbdata:/var/lib/sqld
    healthcheck: { test: ["CMD", "/bin/sqld", "--version"] }

  storage:                              # S3-compatível: packs assinados e assets
    image: minio/minio:RELEASE.2025-04-22T22-12-26Z
    restart: unless-stopped
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER:?defina em infra/.env}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD:?defina em infra/.env}
    ports:
      - "127.0.0.1:9000:9000"
      - "127.0.0.1:9001:9001"
    volumes:
      - s3data:/data
    healthcheck: { test: ["CMD", "mc", "ready", "local"] }

  cms:                                  # plano de controle: auth com 2FA, RBAC, trilha
    build: { context: .., dockerfile: cms/Dockerfile }
    restart: unless-stopped
    environment:
      CMS_DATABASE_URL: http://db:8080
      BETTER_AUTH_SECRET: ${BETTER_AUTH_SECRET:?defina em infra/.env}
      IP_HASH_SALT: ${IP_HASH_SALT:?defina em infra/.env}
      BETTER_AUTH_URL: ${BETTER_AUTH_URL:?defina em infra/.env}
    # SEM `ports:` de propósito: só o edge alcança o CMS. Sem chave de assinatura.
    depends_on:
      db: { condition: service_healthy }
    healthcheck: { test: ["CMD", "node", "-e", "fetch('http://127.0.0.1:8787/health')…"] }
    security_opt: [no-new-privileges:true]

  packer:                               # job: constrói, valida, assina e publica releases aprovadas
    build: { context: .., dockerfile: cms/Dockerfile }
    restart: unless-stopped
    command: ["node", "--import", "tsx", "packer/src/worker.ts", "--interval", "60"]
    environment:
      CMS_DATABASE_URL: http://db:8080
      S3_ENDPOINT: http://storage:9000
      S3_BUCKET: ${S3_BUCKET:-content-packs}
      MINIO_ROOT_USER: ${MINIO_ROOT_USER:?defina em infra/.env}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD:?defina em infra/.env}
      PACK_SIGNING_KEY_PATH: /run/secrets/pack_signing_key   # montada, nunca copiada para a imagem
      PACK_SIGNING_KEY_ID: ${PACK_SIGNING_KEY_ID:-k1}
      SOURCE_DATE_EPOCH: ${SOURCE_DATE_EPOCH:-}
    volumes:
      - ${PACK_SIGNING_KEY_HOST_PATH:?defina em infra/.env}:/run/secrets/pack_signing_key:ro
    # SEM `ports:` de propósito: lê a chave privada Ed25519.
    depends_on:
      db: { condition: service_healthy }
      storage: { condition: service_healthy }
      cms: { condition: service_healthy }
    security_opt: [no-new-privileges:true]

  edge:                                 # borda pública: TLS automático e política de cache
    image: caddy:2.9-alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    environment:
      CONTENT_DOMAIN: ${CONTENT_DOMAIN:?defina em infra/.env}   # só GET/HEAD
      CMS_DOMAIN: ${CMS_DOMAIN:?defina em infra/.env}
      ACME_EMAIL: ${ACME_EMAIL:?defina em infra/.env}
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddydata:/data
      - caddyconfig:/config
    depends_on:
      storage: { condition: service_healthy }
      cms: { condition: service_healthy }

volumes:
  dbdata:
  s3data:
  caddydata:
  caddyconfig:
```

`db`, `storage` e `edge` também levam `security_opt: no-new-privileges:true` no arquivo. Em produção, `caddy:2.9-alpine` e a base `node:22-bookworm-slim` do `cms/Dockerfile` ainda são tags flutuantes; fixá-las por tag exata ou digest é diretriz de implantação do item 27 ([ADR-007](#10-registro-de-decisões-arquiteturais-adr); `spec/implantacao.md`, estágio E3).

```bash
cd infra
docker compose -f compose.yaml up -d      # VPS: sobe o plano de controle, sem o override de dev
docker compose up -d                      # dev: o override entra automaticamente
npm run pack:worker -- --once             # (raiz) uma rodada do job fora do laço: constrói, assina e publica
```

**Enquanto a VPS não existe** (item 27), o pack é assinado fora dela, pelo procedimento de dois mantenedores da Revisão do [ADR-001](#10-registro-de-decisões-arquiteturais-adr); a chave continua fora de qualquer processo HTTP e fora de CI.

---

## 8. Resumo Executivo da Stack

| Domínio | Tecnologia | Papel |
|---|---|---|
| App | Flutter + Riverpod + freezed + GoRouter | Produto offline-first iconográfico |
| Edge AI | llama.cpp (FFI) + Gemma 3 1B GGUF, atrás de `TriageEngine` | Chatbot local com kill switch determinístico |
| DB device | SQLite: `content.db` (RO, distribuído) + Drift `user.db` | Zero migração de conteúdo no device |
| DB master | libSQL/`sqld` self-host + Drizzle | Fonte de verdade; mesmo dialeto do device |
| API/CMS | Hono + Zod + React SPA, Node 22 | Plano de controle de conteúdo |
| Type safety | Drizzle → Zod → JSON Schema → Dart (freezed) em CI | Schema muda ⇒ build Flutter quebra |
| Auth | Better Auth (admins only); usuário final sem auth | Sem PII, sem lock-in |
| Entrega | MinIO + Caddy (self-host), packs imutáveis + manifest ETag, Ed25519 | 100% OSS, espelhável, sneakernet-safe |
| IaC/Deploy | Docker Compose + Ansible (Coolify opcional) | 100% OSS, um VPS, Docker-first |

---

## 9. Auditoria Open Source (revisão de 2026-08)

Substituições aplicadas — todo componente pago ou SaaS comercial foi trocado por equivalente open source:

| Antes (pago/SaaS) | Depois (OSS) | Licença | O que muda |
|---|---|---|---|
| Turso (libSQL gerenciado) | `sqld`/libSQL self-host | MIT | Nada funcional — mesmo dialeto, mesmo driver; sai o fornecedor |
| Cloudflare R2 + CDN | MinIO + Caddy no VPS | AGPL-3.0 / Apache-2.0 | Perde CDN global; ganha espelhos federáveis (Ed25519 dispensa confiança no espelho) |
| Railway (PaaS) | Compose + systemd (Coolify opcional) | — / Apache-2.0 | Deploy = `docker compose up -d` via Ansible |
| SST v3 (sobre nuvens pagas) | Ansible playbook | GPL-3.0 | IaC vira provisionamento de 1 VPS |

**Dependências novas do app:**

| Pacote | Uso | Licença | Item |
|---|---|---|---|
| `cryptography` (Dart) | **Só `verify`** da assinatura Ed25519 do manifest no device | Apache-2.0 | 9 |
| `go_router` | Navegação declarativa; a árvore de rotas é o que torna CAP-02 verificável | BSD-3 | 10 |
| `flutter_riverpod` | Estado da UI (decisão da §1). Fixado no 2.x — ver nota abaixo | MIT | 10 |
| `flutter_localizations` + `intl` | i18n pt/es (RF-01) via `gen-l10n` | BSD-3 | 10 |
| `flutter_tts` | TTS pelo engine do SO (RF-06). Módulo folha: falha não propaga | MIT | 10 |
| `package_info_plus` | Versão e build reais do APK na tela "Sobre" (CAP-19). Uma constante gerada mentiria no dia em que alguém publicasse sem rodar o gerador. **Fixado em `^10`:** as versões 4.0.1–9.x exigem `win32 <6` e conflitam com `file_picker ^12` | BSD-3 | 10 |

`cryptography` é Dart puro, sem biblioteca nativa adicional no APK: o mesmo
código roda no host e no aparelho, e a suíte que confere a interoperabilidade
com o assinador em Node executa em CI sem emulador. O app **nunca assina** — a
chave privada não existe do lado do dispositivo, por construção.

**Riverpod fixado no 2.x.** O 3.x resolve, mas só subindo 31 pacotes junto por
causa das restrições atuais. Trocar de major na casca — antes de existir tela
que use o estado — pagaria a migração duas vezes; a hora de reavaliar é no item
12, quando a triagem for escrita. O sabor com `riverpod_generator` + `freezed`
que a §1 nomeia também entra ali, onde os estados de união exaustiva pagam pelo
gerador; na casca, providers escritos à mão bastam para um enum e um objeto de voz.

**Custo medido no APK.** A casca (item 10) levou o release arm64-v8a de
**21,1 MB para 23,8 MB**, com `libllama` e o shim nativo dentro. O orçamento do
[ADR-003](#10-registro-de-decisões-arquiteturais-adr) é de 50–80 MB para o APK base — sobra
folga confortável.

**Notas de licenciamento e opções (sem mudança de default):**

- **Modelo (Gemma 3 1B):** gratuito, mas *open weights* sob termos Google — **não é OSI**. Redistribuí-lo obriga a §3.1 dos Gemma Terms of Use (Notice, cópia dos termos, cláusula nos termos do app), e a Política de Uso Proibido restringe o uso; o enquadramento, a exceção do download direto do Hugging Face e o Gemma 4 (Apache 2.0, mas o E2B tem 2,84 GB e não cabe no ADR-003; não perseguido) estão no [ADR-004](#10-registro-de-decisões-arquiteturais-adr). Alternativas OSI-licenciadas de tamanho equivalente, compatíveis com o mesmo pipeline GGUF: **Qwen2.5 0.5B/1.5B (Apache-2.0)** e **Phi-3.5-mini (MIT)**. A troca é um arquivo — a interface `TriageEngine` e o eval harness clínico decidem por benchmark, não por ideologia.
- **TTS:** o engine do sistema (Google TTS) é proprietário, embora gratuito e on-device. Opção 100% OSS que também mitiga o risco R7 (ROMs sem engine): **Piper (MIT) via sherpa-onnx**, com vozes pt-BR/es embarcadas (~20 MB/voz). Default continua `flutter_tts` (zero MB); Piper entra como fallback empacotável.
- **CI:** GitHub Actions é serviço (gratuito para repositório público). Alternativas self-host quando desejado: **Woodpecker CI (Apache-2.0)** ou **Forgejo Actions (MIT)** no mesmo VPS.
- **Distribuição** ([ADR-006](#10-registro-de-decisões-arquiteturais-adr)): os canais oficiais do APK são **GitHub Releases** (gratuito, com o SHA-256 de cada APK e a impressão do certificado, RF-17) e **Google Play** (taxa única de registro da conta de desenvolvedor). O **F-Droid** fica como canal futuro, não previsto para o lançamento ([ADR-010](#10-registro-de-decisões-arquiteturais-adr)): é gratuito e exige build reprodutível — bônus de transparência para um app de saúde pública —, mas em regra assina com chave própria, o que soma mais um canal incompatível com os outros dois (ADR-009). Repasse do APK entre pessoas (Bluetooth/SD) não é canal oficial. O **packer** já é reprodutível sob `SOURCE_DATE_EPOCH` (a convenção de builds reprodutíveis): duas builds do mesmo conteúdo produzem `content.db` byte-idêntico, o que além da transparência evita que a frota re-baixe o pack a cada republicação sem mudança.

**Custo remanescente honesto:** open source elimina licenças e SaaS, não hardware — resta a **VPS mantida pelo PRISM** ([ADR-007](#10-registro-de-decisões-arquiteturais-adr); único item de fatura recorrente da stack inteira), o destino do backup fora dela e a taxa única da conta do Google Play. Tudo o mais roda com custo marginal zero.

---

## 10. Registro de Decisões Arquiteturais (ADR)

### ADR-001 — Vercel como plataforma de deploy: **REJEITADO** (2026-08-13)

**Contexto:** avaliou-se o Vercel como alternativa de deploy para o plano de controle e/ou a entrega de conteúdo.

**Decisão:** manter o deploy self-hosted (Compose + Ansible numa VPS mantida pelo PRISM, §3.2/§7 e [ADR-007](#10-registro-de-decisões-arquiteturais-adr)). Vercel rejeitado.

**Fundamentos (vinculados aos requisitos deste projeto):**

1. **Perfil de carga invertido:** o Vercel otimiza frontend serverless com requisições dinâmicas na edge; este projeto tem zero requisição dinâmica de usuário — o caminho quente é download de binário estático assinado (HTTP Range para retomada), caso de uso de object storage, não de plataforma de frontend.
2. **Docker-first violado:** requisito desta MVTS ("stack reprodutível via Dockerfile/Compose"); Vercel não executa containers arbitrários — o compose do §7, que é a topologia de produção, seria descartado.
3. **Fragmentação da stack:** o CMS depende de `sqld` e MinIO, que o Vercel não hospeda — migrar exigiria recontratar banco gerenciado e storage externos, revertendo a auditoria do §9.
4. **Segurança (SPOF R4):** o packer assina packs com a chave Ed25519; executá-lo em functions de terceiro colocaria o segredo mais crítico do modelo de ameaças sob custódia de SaaS. A política é a do §7: a assinatura é feita pelo **job `packer` do compose, sem porta, com a chave trazida do cofre e montada `:ro`** — nunca no processo que atende HTTP, nunca em CI de terceiro. A exceção provisória, enquanto a VPS não existe, está na **Revisão** deste ADR. Timeout de 60 s em functions também é inadequado ao job.

   *Correção de 2026-11-02:* o texto original dizia "cofre offline/HSM, assinatura só no CI", o que contradizia a topologia implementada (o `packer` assina no compose desde o item 19). O fundamento — segredo fora de SaaS — não muda.
5. **Custo/termos:** o tier Hobby proíbe uso comercial/institucional — a operação de um projeto institucional de pesquisa e extensão ([ADR-005](#10-registro-de-decisões-arquiteturais-adr)) exigiria plano pago, conflitando com a decisão de stack 100% OSS (§9); banda de 100 GB/mês é insuficiente para ações educativas de grande alcance, como campanhas de vacinação (milhares de devices × packs de MB).

   *Correção de 2026-11-02:* o texto original dizia "operação para prefeituras", premissa retirada pelo ADR-005 (Decisão 4).
6. **LGPD:** reintroduziria operador estrangeiro e transferência internacional (arts. 33–36), revertendo a postura do [lgpd.md](lgpd.md) RF06 (datacenter no Brasil).

**Exceção reconhecida:** hospedar um eventual site institucional estático — mesmo assim, o Caddy do VPS já cobre sem novo operador.

**Revisão:** reavaliar somente se o projeto ganhar superfície web dinâmica voltada ao público (o que hoje contraria a arquitetura offline-first).

**Revisão 2026-11-02 — exceção provisória: assinatura do pack fora da VPS.** Quem procura "quem assina o pack hoje" acha a resposta aqui. Enquanto a VPS do PRISM não está provisionada (item 27, [ADR-007](#10-registro-de-decisões-arquiteturais-adr)), o job `packer` do compose não existe em produção, e o pack é assinado na máquina de um mantenedor, sem perder o segundo par de olhos.

- **O CMS não é necessário nesse período.** O app só lê arquivos estáticos, e o pack sai pelo **caminho `seed/`** (`npm run pack:build`, suíte golden por YAML e atestados de revisão clínica). Dual review clínico, portão golden e Ed25519 continuam valendo (INV-4).
- **A chave continua fora de qualquer processo HTTP e fora de CI.** Pôr a chave privada num segredo do GitHub Actions a exporia a um terceiro e a qualquer workflow que alguém com escrita no repositório edite — seria reabrir, por outro caminho, a contradição corrigida no fundamento 4.
- **Procedimento de dois mantenedores.** O dual review do compose garantia que ninguém assina sozinho; o packer reprodutível (`SOURCE_DATE_EPOCH`) permite manter isso com um comando.
  1. Os dois mantenedores partem do **mesmo commit** (tag), com o mesmo `SOURCE_DATE_EPOCH` e o mesmo `PACK_VERSION`.
  2. **Mantenedor B** (sem a chave) roda `npm run pack:check` (`--dry-run`: portões verdes, sem assinatura) e o `sha256sum` do `content.db` gerado, e publica o hash por um canal que fique registrado (comentário no PR da release de conteúdo).
  3. **Mantenedor A** (custódia) traz a chave do cofre **sem tocar disco persistente**: arquivo em `tmpfs` (`/dev/shm`, `umask 077`, com swap desligado ou cifrado, porque página de tmpfs pode ir para o swap) ou um descritor (`PACK_SIGNING_KEY_PATH=/dev/fd/3 … 3< <(comando-do-cofre)`). Roda `npm run pack:build` e remove o arquivo do tmpfs no fim, em `trap`, mesmo se falhar.
  4. **A** confere que o hash do `content.db` assinado (e o `packHash` do `manifest.json`) é **igual** ao publicado por **B**. Se diferir, nada é enviado.
  5. **A** envia ao host estático. **B** baixa o manifest publicado e confere a assinatura com a chave pública embarcada e o hash (a mesma verificação do job `interop`).
- **Antes do 1º pack por este caminho**, verifica-se que `pack:check` deixa o `content.db` no mesmo caminho e com o mesmo hash que `pack:build` (isto é, que a assinatura só toca o manifest) e que `resolveFromRepo` aceita um caminho absoluto como `/dev/fd/3`. Se qualquer um falhar, o procedimento é ajustado antes.
- **Saída.** A exceção **sai** quando o item 27 entrar e o job `packer` do compose passar a assinar na VPS. Ela não volta a citar CI em lugar nenhum, inclusive em `infra/.env.example`.
- **Custo aceito:** a chave passa, durante a exceção, pela máquina de uma pessoa, e não por um container sem porta. A mitigação é o procedimento acima, a segunda posição de chave que o binário já aceita (`app/lib/sync/pack_signing_keys.dart`, para rotação) e o runbook de revogação.

### ADR-002 — Fronteira com o llama.cpp: **shim C de 4 funções** (2026-08-13)

**Contexto:** o app precisa chamar o llama.cpp a partir do Dart. O caminho usual é gerar bindings com `ffigen` direto sobre `llama.h` e escrever o laço de geração em Dart.

**Decisão:** interpor `native/llama_shim/` — quatro funções C (`open`, `generate`, `close`, `abi_version`) — e ligar o Dart apenas a elas. `llama.h` não é exposto ao Dart. Versão do llama.cpp fixada por tag (**b6100**) via `FetchContent`.

**Fundamentos:**

1. **Superfície e detecção de quebra.** `llama.h` expõe ~200 símbolos e muda a cada release; bindings gerados transformam mudança de ABI em *crash em campo*. Com o shim, uma quebra do upstream é erro de compilação C, encontrada no CI.
2. **O teto de 5 s do RF-05 precisa abortar, não desistir.** Com o laço de geração no Dart, cada chamada FFI bloqueia o isolate e `Future.timeout` apenas abandona a espera — a CPU do aparelho continua gerando tokens que ninguém vai ler, num device que já é o gargalo. Com o laço em C, o prazo entra no `abort_callback` do llama.cpp e a geração **para**. Medido: prazos de 1/5/50 ms respeitados em 2/5/49 ms, com o motor permanecendo utilizável após o aborto.
3. **Determinismo em um lugar só.** Decodificação gulosa (temperatura 0, sem amostragem estocástica) é imposta na criação da cadeia de sampling em C. Não há como um chamador Dart reintroduzir aleatoriedade.
4. **Sem log fora da memória.** O shim instala um *log sink* vazio: o diagnóstico do llama.cpp — que carrega conteúdo de prompt — nunca chega a stderr (INV-2 / LGPD-RF13).
5. **Tag fixa.** O pacote de conteúdo é assinado e auditável; a biblioteca que o interpreta precisa da mesma propriedade. `master` tornaria o build não reprodutível.

**Custo aceito:** ~200 linhas de C sob nossa manutenção, e um passo de build nativo no CI. Em troca, a superfície FFI cai de ~200 símbolos para 4, com verificação de `GUBS_LLAMA_ABI_VERSION` no boot.

**Verificado:** compila e linka para host x86-64 e para `arm64-v8a` / Android 26 (NDK r30), com inferência ponta a ponta exercitada.

**Revisão:** reabrir se o llama.cpp passar a oferecer uma API C estável e versionada, ou se surgir necessidade de backend de GPU (o `abort_callback` só vale para execução em CPU).

### ADR-003 — Orçamentos de footprint e latência: **ELEVADOS** para viabilizar o SLM (2026-08-17)

**Contexto.** A Fase 1 mediu oito configurações de modelo em aparelho arm64 real (Motorola Edge 40 Neo) e em host, com a bancada de [arquitetura.md §5.1](arquitetura.md). O resultado foi inequívoco: **nenhum modelo satisfazia simultaneamente** o RNF-03 original (APK + modelo + pack ≤ 400 MB) e o RF-05 original (p95 < 3 s). Acerto clínico acompanha o tamanho do modelo, e o orçamento de 400 MB cortava exatamente onde o modelo começava a ser útil — os que cabiam pontuavam ≤ 10/20 na suite de identificadores; os que acertavam pesavam ≥ 768 MB.

Havia duas saídas: cortar o SLM do MVP, ou elevar os orçamentos. **Decidiu-se elevar.**

**Decisão.** Os seguintes requisitos passam a valer, substituindo os originais:

| Requisito | Antes | **Agora** |
|---|---|---|
| Tamanho do APK base | (implícito no RNF-03) | **50–80 MB** |
| Peso do modelo SLM | (implícito) | **700 MB – 1,2 GB**, baixado no 1º acesso ou embarcado como asset |
| **RNF-03** — footprint total | APK + modelo + pack ≤ **400 MB** | APK + modelo + pack ≤ **1,2 GB** |
| Espaço livre em disco | — | **≥ 3 GB** (novo pré-requisito) |
| Contexto por atendimento | 512 tokens (padrão de código) | **512–1024 tokens**, máximo por atendimento |
| RAM do aparelho | "entrada, ≤ 4 GB" | **mínimo 4 GB; recomendado 6–8 GB** |
| **RF-05** — latência de inferência | p95 **< 3 s** | p95 **entre 3 e 5 s** |

RAM de pico da inferência permanece ≤ 1,5 GB — a medição em aparelho deu 832 MB para o Gemma 3 1B, com folga.

**Consequência imediata: vereditos medidos se invertem.** O Gemma 3 1B Q4_K_M passa a satisfazer os três critérios sem nenhuma alteração técnica, apenas pela mudança de régua:

| Critério | Medido | Antes | Agora |
|---|---|---|---|
| Footprint (768 MB modelo + 21 MB APK + pack) | ≈ 790 MB | ✗ (2,0× o teto) | ✓ (66% do teto) |
| p95 no aparelho, 4 threads | 4731 ms | ✗ | ✓ (dentro de 3–5 s) |
| RAM de pico | 832 MB | ✓ | ✓ |

**Risco aceito, explicitamente.** RAM mínima **não garante classe de CPU**. O proxy de aparelho de entrada — inferência fixada nos núcleos Cortex-A55 — mediu **p95 de 13.130 ms**, ainda 2,6× fora da nova janela e 2,6× acima do teto duro de 5 s. Aparelhos de 4 GB com SoC dominado por A55 (Snapdragon 4xx, Helio G) continuarão estourando o timeout e caindo no `RuleOnlyEngine` na maioria das triagens.

Isso é tolerável **porque a arquitetura já foi construída para esse desfecho**: o gate determinístico decide sozinho, o fallback é total, e a INV-1 garante que nada rebaixa uma emergência. O usuário desses aparelhos recebe orientação clínica correta, sem o refinamento do SLM. O que muda é que essa degradação deixa de ser exceção e passa a ser o modo esperado numa fatia do parque instalado — por isso `fallback_rate` **por coorte de aparelho** vira métrica de produto, não apenas de saúde técnica.

**Consequências de engenharia.**

1. **Segunda superfície de rede.** "Download no 1º acesso" acrescenta uma chamada de rede além de manifest/pack. Ela herda obrigatoriamente o mesmo tratamento: HTTP Range retomável, verificação de SHA-256 antes de aceitar, e **falha nunca bloqueia o app** — sem modelo, roda em modo degradado (RF-12). O invariante de runtime offline-only permanece intacto: nenhuma funcionalidade do usuário depende de rede.
2. **Verificação de espaço livre antes de baixar.** Iniciar um download de 1,2 GB num aparelho sem espaço deixa o usuário pior do que não baixar nada. O pré-requisito de 3 GB livres é checado *antes* de começar, e a falta de espaço resolve para degradação silenciosa (RuleOnly), não para erro na cara de quem usa.
3. **Contexto vira orçamento explícito.** 512–1024 tokens por atendimento é teto de produto, não detalhe de implementação: inflar o prompt é o caminho mais fácil de estourar o p95, e o CI de eval deve tratá-lo como orçamento (já implementado como `promptCharBudget` em `prompt_builder.dart`, que falha alto ao ser excedido).
4. **RNF-09 mantém minSdk 26**, mas o piso de RAM sobe para 4 GB — o que exclui parte do parque que a versão anterior contemplava.

**Revisão.** Reabrir se (a) a telemetria de campo mostrar `fallback_rate` alto o bastante para tornar o SLM decorativo, caso em que cortá-lo economiza 1,2 GB sem perda funcional; ou (b) surgir modelo de vocabulário pequeno que atinja ≥ 15/20 na suite abaixo de 400 MB, permitindo voltar ao orçamento original.

### ADR-004 — Gemma 3 1B no caso de uso do Guia UBS e redistribuição pelo storage próprio: **ACEITO** (2026-10-29)

**Aprovação.** Aceito pelo dono do projeto em 2026-10-29, sobre este texto, com a exceção do huggingface.co e sem parecer jurídico formal (ver "Gatilhos").

**Contexto.** O app baixava o modelo de `huggingface.co/ggml-org/gemma-3-1b-it-GGUF` fixo em `app/lib/sync/model_catalog.dart`, o que contraria três decisões: a §9 (100% self-host), o [PRD §4.1](PRD.md) e a [LGPD-RT11/RF17](lgpd.md) (lista fixa de endpoints). A exceção abaixo mantém essa divergência, de propósito e com prazo, até o projeto ter servidor. Servir o `.gguf` do storage próprio é *Distribution* pela §1.1(b) dos Gemma Terms of Use, e o Gemma 3 consta do Appendix desses termos, que valem *"regardless of the source that you obtained it from"* (§1.1(c)).

Textos lidos em **2026-10-29**, em duas cópias cada:

| Documento | URLs | "Last modified" |
|---|---|---|
| Gemma Terms of Use | `gemma.ai/resources/terms` e `ai.google.dev/gemma/terms` | April 1, 2026 (as duas) |
| Gemma Prohibited Use Policy | `gemma.ai/resources/prohibited-use/` e `ai.google.dev/gemma/prohibited_use_policy` | February 21, 2024 (as duas) |

As páginas de `ai.google.dev` exibem *"This documentation is deprecated. Please visit the new documentation at gemma.ai."*, e as duas versões dos termos pedem frases de Notice diferentes na §3.1(4) (ver D-A).

**Enquadramento do projeto** (revisto em 2026-11-02 pelo [ADR-005](#10-registro-de-decisões-arquiteturais-adr), que prevalece nesta parte). O Guia UBS é um projeto educativo open source de pesquisa e extensão do **Grupo de Pesquisa PRISM (UFRR)**, em cooperação com o **PET-Saúde: Inovação e Saúde Digital**, iniciativa do Núcleo de Telessaúde da UFRR; a cooperação está em andamento, com formalização pendente (ADR-005, Decisão 1). O ambiente de produção é do próprio grupo (VPS do PRISM, [ADR-007](#10-registro-de-decisões-arquiteturais-adr)), sem vínculo com unidades de saúde, e colaboradores do curso de Medicina apoiam a revisão clínica. *Texto original (2026-10-29):* "o ambiente de produção é do próprio grupo, não há vínculo formal com a UFRR" — a frase continua literalmente verdadeira enquanto a formalização estiver pendente, mas deixou de ser o enquadramento, porque calava a cooperação. Nesta fase **não há parecer jurídico formal**: a licença do modelo é cumprida por obrigação, e as perguntas que pediriam parecer viram regras de produto e implementação, com gatilhos para revisitar a parte formal.

**O que o modelo pode mudar no resultado (leitura do código).** A saída do SLM é entrada não confiável. `decodeSuggestion` (`app/lib/triage/engine/engine_decoder.dart`) só aceita o identificador de um `routing_outcome` que já existe no pack e passou por revisão clínica, e a severidade vem da tabela, nunca do texto gerado. `mergeVerdict` (`app/lib/triage/domain/severity.dart`) aplica `max(gate, llm)`: o modelo nunca rebaixa. Mas, quando a severidade do modelo é maior, o resultado exibido — cartão e local — passa a ser **o desfecho que o modelo nomeou**. O modelo só sobe e só escolhe entre desfechos revisados, mas escolhe. Nenhum texto gerado chega à tela, e nada sai do aparelho (INV-2).

**Leitura da Política de Uso Proibido contra o caso de uso.**

| Item | O caso de uso | O argumento arquitetural responde? | Onde não responde, e a resposta do projeto |
|---|---|---|---|
| **3.4** *"Making automated decisions in domains that affect material or individual rights or well-being"* (exemplos incluem *healthcare*) | O SLM pode nomear um desfecho revisado de severidade maior que a do gate. Nada é concedido ou negado: a pessoa recebe orientação e decide. | **Parcialmente.** `max(gate, llm)` elimina a falsa tranquilização, e o espaço de ação é um conjunto de desfechos com revisão clínica. | Hoje o modelo participa da escolha de para onde a pessoa vai, num domínio listado literalmente. "Só escala" limita a direção, não tira a natureza de decisão automatizada. **Resposta:** regras R1–R3 abaixo e a [#47](https://github.com/hbgit/Guia-UBS/issues/47), com a qual o modelo deixa de escolher desfecho. |
| **2.2 / 3.6** prática ilegal ou não licenciada de profissão, incluindo *"medical/health"* | O cartão diz onde ir, sem diagnóstico nem prescrição; regras e textos são autorados e revisados. | **Para diagnóstico e prescrição, sim.** | Classificar gravidade e encaminhar se parece com a classificação de risco, que a [Resolução Cofen nº 661/2021](https://www.cofen.gov.br/resolucao-cofen-no-661-2021/), art. 1º, declara *"privativa do Enfermeiro"* no âmbito da equipe de enfermagem. **Resposta:** o app não se apresenta nem funciona como classificação de risco (R1, R2), e o conteúdo é revisado clinicamente (R3). |
| **3.3** *"Misleading claims of expertise or capability made particularly in sensitive areas"* (exemplo: *health*) | Os textos dizem "não faz diagnóstico" e "revisão clínica pendente"; o selo de procedência (RF-15) diz quando o assistente contribuiu. | **Sim**, enquanto os textos forem assim. | Depende de texto, não de arquitetura. O guarda de não endosso e de linguagem ([#48](https://github.com/hbgit/Guia-UBS/issues/48)) mantém isso verificável. |
| **3.1** proveniência de conteúdo gerado | Não há texto gerado na tela; o selo informa a origem da orientação. | **Sim.** | — |
| **2.5** (dados pessoais; inferir dado sensível sem consentimento) | Sintomas são dado sensível, processados no aparelho, para a própria pessoa, sem persistência nem transmissão (INV-2, INV-5). | **Sim**, quanto à Política. | A base legal LGPD está em [lgpd.md](lgpd.md). |
| 1, 2.1, 2.3, 2.4, 3.2, 3.5, 4 | Direitos de terceiros, atividade ilegal, spam e fraude, burla de filtros, personificação, difamação, conteúdo sexual: o app não gera texto nem mídia e não tem entrada livre. | Não se aplicam. | — |

Três pontos dos termos, fora da Política: a **§3.2** reserva ao Google o direito de restringir o uso *"remotely or otherwise"* — o app offline não pode ser desligado à distância, mas a obrigação de parar existiria; a **§3.3** diz *"You and your users are solely responsible for Outputs"*, o que põe a responsabilidade pela saída em quem distribui o app: o projeto, para o build que ele distribui; e a **§3.1(3)** pede aviso em arquivo modificado — o `.gguf` foi convertido para GGUF e quantizado em Q4_K_M pela `ggml-org` a partir de `google/gemma-3-1b-it`, o README da `ggml-org` não traz esse aviso, e o arquivo não pode recebê-lo sem mudar o SHA-256 (ver D-B).

**Obrigatório × boa prática.**
- *Obrigatório, de qualquer jeito:* cumprir a licença do modelo que o projeto redistribui. É a condição para redistribuir o Gemma 3 e não depende de formalidade jurídica: Notice ao lado do arquivo e no app, cópia do Agreement, cláusula nos termos de uso do app e aviso de modificação.
- *Boa prática, que mantém o projeto honesto quanto ao que ele é:* as respostas abaixo.

**Respostas do projeto, sem parecer formal nesta fase.**
- **Exigibilidade da cláusula (J3) vira implementação.** O app pede "li e concordo" na primeira abertura e a cada versão nova dos termos, e guarda a resposta só no aparelho, sem identificar ninguém e sem que ela saia dele. Recusar desliga **só o assistente**: o Gemma não é baixado nem carregado, e a orientação continua pelo gate determinístico, pelo `RuleOnlyEngine` e pelo conteúdo estático (INV-1, INV-8). Não é registro de consentimento da LGPD-RF04, que pressupõe titular identificado. É cumprimento de boa-fé da §3.1(1) para um projeto educacional.
- **Decisão automatizada (J1) e exercício profissional (J2) viram regras de produto**, sustentadas pela revisão clínica:
  - **R1, linguagem:** o app explica sinais de alerta e onde procurar atendimento; não se apresenta como "triagem" nem "classificação de risco".
  - **R2, direção única:** o app diz "procure atendimento" ou "procure atendimento urgente", nunca "você não precisa procurar atendimento" nem que algo "não é emergência". O conteúdo semente ainda viola R2 (`card.routine`: *"Não é emergência."*), e a correção é a [#48](https://github.com/hbgit/Guia-UBS/issues/48), pelo portão de revisão clínica da #2.
  - **R3, revisão:** todo conteúdo exibido é autorado e revisado clinicamente; o portão da #2 já garante isso, e é onde entra a revisão pelos colaboradores do curso de Medicina.
- **Consequência regulatória, com a ressalva que ela merece.** A [RDC Anvisa nº 657/2022](https://anvisalegis.datalegis.net/action/ActionDatalegis.php?acao=abrirTextoAto&tipo=RDC&numeroAto=00000657&seqAto=000&valorAno=2022&orgao=RDC/DC/ANVISA/MS), art. 1º, § 2º, I, não se aplica a software *"para bem-estar"*, que o art. 2º, IX, define como o destinado a *"encorajar e manter o bem-estar"* e que *"não são destinados a prevenção, diagnóstico, tratamento, reabilitação ou anticoncepção"*. Um app que informa sinais de alerta e encaminha, sem diagnosticar nem decidir, é o caso mais próximo dessa exclusão — mas orientar a partir de sintomas fica perto da borda da definição, e a exclusão só se sustenta enquanto produto, textos, onboarding e página da loja forem coerentes com o rótulo educacional (R1–R3). É um dos motivos para os gatilhos abaixo.
- **O modelo só sinaliza escalada: decisão de design, não jurídica ([#47](https://github.com/hbgit/Guia-UBS/issues/47)).** Com o modelo pedindo "escalar" e a regra escolhendo o desfecho, tudo o que a pessoa vê passa a ser conteúdo revisado pela equipe clínica, o que torna "educacional" uma descrição verdadeira. Custos registrados na issue: perde-se a escolha fina entre desfechos de mesma severidade, a bancada de [arquitetura.md §5.1](arquitetura.md) é refeita, e o contrato de `decodeSuggestion`/`mergeVerdict` muda.
- **Resolvidas por escolha conservadora:**
  - frase do Notice → D-A usa as duas;
  - se a §3.1(3) obriga quem redistribui arquivo modificado por terceiro → D-B põe o aviso de qualquer forma;
  - aparelhos que baixaram do Hugging Face → são de desenvolvimento, e **todo aparelho do estudo piloto do projeto ([ADR-005](#10-registro-de-decisões-arquiteturais-adr), Decisão 7) é provisionado do zero a partir do storage próprio**;
  - repasse do `.gguf` por pendrive → tratado como distribuição: o Notice aparece no fluxo de importação do app, e o Notice e as cópias dos termos acompanham o arquivo.

**Responsável (decisão consciente).** Os termos de uso do app identificam o responsável como "Guia UBS, projeto de pesquisa e extensão desenvolvido pelo grupo de pesquisa PRISM", com o e-mail compartilhado do projeto (`prismufrr@gmail.com`). Um grupo de pesquisa não tem personalidade jurídica: a linha **identifica** quem mantém o app, mas não cria uma parte que assina contrato. Para uma iniciativa educacional open source nesta fase, é escolha razoável e comum. O projeto responde pelo app que ele distribui; quem compilar e distribuir a própria versão a partir do código responde por ela, inclusive pelos termos do modelo que embarcar (frase também no README).

**Logo do Telessaúde UFRR e e-mail com "ufrr" (ficam).** Papel do PET Telessaúde UFRR, nas palavras do dono do projeto: *"O PET Telessaúde UFRR atuou no diagnóstico da necessidade social e no desenvolvimento de uma solução direcionada à comunidade, articulando ações entre docentes e monitores discentes."* Daí, o logo na tela "Sobre" está sob "Realização", isto é, como crédito por essa participação, e não como aval nem como responsabilidade institucional pelo app distribuído. A participação de um programa não é vínculo formal da universidade com o app, que não existe. A mesma tela traz o aviso de que o conteúdo ainda não passou por revisão clínica, que existe para impedir a leitura de logotipo como endosso; nenhum texto do app ou dos termos afirma vínculo institucional, e um teste impede que algum passe a afirmar; o responsável declarado é o grupo PRISM. Se a UFRR ou o PET pedirem a retirada, ou se surgir vínculo formal, o logo e o e-mail são revistos.

**Decisões (2026-10-29).**
- **D-A — Notice com as duas frases.** O arquivo traz, literais e nesta ordem: *"Gemma is provided under and subject to the Gemma Terms of Use found at gemma.ai/resources/terms"* e *"Gemma is provided under and subject to the Gemma Terms of Use found at ai.google.dev/gemma/terms"*. As duas versões têm a mesma data e não há como saber qual o Google trata como canônica; repetir cumpre as duas.
- **D-B — aviso de modificação.** O Notice acrescenta, em inglês, que o arquivo não é o original do Google, que foi convertido e quantizado pela `ggml-org` a partir de `google/gemma-3-1b-it` (com a URL do repositório), que o Guia UBS o redistribui sem outra modificação, e o SHA-256.
- **D-C — notificação e aceite.** A cláusula com as restrições da §3.2 e a Política entra em `app/assets/legal/termos_{pt,es}.md` (nova versão datada). O "li e concordo" vale a cada versão; o Notice e o acesso aos termos aparecem também nos dois pontos de distribuição do onboarding (download e importação por pendrive) e na tela "Sobre".
- **Documentos.** Cópia integral e literal, em inglês, dos termos e da Política (a §3.1(2) pede *"a copy of this Agreement"*); tradução de cortesia só da Política, em pt e es; resumo em linguagem simples dos termos, em pt e es. Toda cortesia diz que prevalece o inglês. (Mudança de escopo registrada na #3.)
- **Origem e espelho.** **Durante a exceção** (abaixo), a origem é a URL fixada do Hugging Face. **Ao fim dela**, o bucket `content-packs`, chave `models/gemma-3-1b-it-Q4_K_M-<sha256>.gguf`, servida pelo site de conteúdo do edge (só GET/HEAD), com o Notice e as cópias ao lado. O SHA-256 continua versionado no app (`8ccc5cd1…a135`): a identidade do modelo no aparelho é o hash e o nome do arquivo, não a URL, e um modelo já verificado não é baixado de novo quando a URL muda. A URL entra no build por `--dart-define=MODEL_URL`, sem valor padrão. Quem operar espelho federado redistribui o Gemma e fica sujeito à §3.1; o script de publicação envia os arquivos juntos.

**Exceção: download direto do huggingface.co (decisão do dono, 2026-10-29).** Enquanto o projeto não tem domínio nem servidor, o app baixa o modelo **direto do Hugging Face**, e não do storage próprio.

- **A URL continua fora do código.** Ela entra pelo build (`--dart-define=MODEL_URL`, em `app/config/defines.<modo>.json`); `app/lib` não cita host nenhum, e o app não tem host padrão.
- **Revisão fixa, não `main`:** `https://huggingface.co/ggml-org/gemma-3-1b-it-GGUF/resolve/f9c28bcd85737ffc5aef028638d3341d49869c27/gemma-3-1b-it-Q4_K_M.gguf` — o commit `f9c28bc` do repositório da `ggml-org` (último em 2025-03-12). Com `resolve/main/`, um push da `ggml-org` poderia trocar o arquivo sob o mesmo nome: o SHA-256 do app recusaria, mas a frota ficaria sem modelo sem ninguém ter mudado nada aqui.
- **Uma URL, não um host.** O guarda de build (`app/tool/model_url_check.dart`) aceita `huggingface.co` só nessa URL exata, e só enquanto o catálogo for o Gemma 3 1B Q4_K_M (`8ccc5cd1…a135`). Outro repositório, `resolve/main/` ou outro modelo reprovam.
- **A integridade não muda:** o SHA-256 está no app, e o Hugging Face não consegue entregar outro arquivo como se fosse este.
- **Medido em 2026-10-29:** a URL responde `302` para `us.aws.cdn.hf.co` (CDN na AWS, EUA), que honra `Range` (`206`, `Content-Range: bytes 100-199/806058240`, `Content-Length: 100`); no emulador, a retomada com `206` por esse caminho já foi observada na issue 31 ([arquitetura.md](arquitetura.md)). São dois hosts no caminho, `huggingface.co` e o da CDN, e a allowlist da #4 precisa dos dois.

Custos aceitos:
1. **Diverge** da §9, do PRD §4.1 e da LGPD-RF17(d)/RT11, com prazo.
2. **Transferência internacional de dado pessoal.** Cada aparelho entrega ao Hugging Face e à CDN (AWS, EUA) o endereço IP e o `User-Agent` no momento do download. Não vai sintoma nem identificador do app, mas IP é dado pessoal, e a LGPD trata a transferência internacional nos arts. 33 a 36 — o mesmo motivo pelo qual o [ADR-001](#10-registro-de-decisões-arquiteturais-adr) rejeitou o Vercel. O aviso de privacidade passa a dizer isso, e o fornecedor entra no inventário de [lgpd.md](lgpd.md). **Validação do encarregado (DPO): pendente**, como as demais do documento.
3. **Disponibilidade de terceiro.** Se a `ggml-org` apagar o repositório, ou o Hugging Face mudar a URL, o download falha e o app segue pelo `RuleOnlyEngine` (INV-8). Nenhum aparelho recebe arquivo errado.
4. **Termos do Gemma.** Com o arquivo vindo do Hugging Face, quem o transmite é o Hugging Face, e fica em dúvida se o projeto "distribui" (§1.1(b)). As obrigações da §3.1 **são mantidas mesmo assim**: as restrições da §3.2 valem para o uso pelo projeto de qualquer forma, o repasse por pendrive continua sendo distribuição, e a saída da exceção volta a ser. Durante a exceção, o Notice e as cópias dos termos ficam no app, e não ao lado do arquivo, porque o projeto não controla aquele repositório.

**Fim da exceção**, com qualquer um destes: domínio e servidor do projeto definidos (então publicar com `npm run model:publish` e trocar o `MODEL_URL` — aparelhos já provisionados **não** baixam de novo, porque a identidade é o SHA-256); a `ggml-org` ou o Hugging Face tirarem o arquivo do ar; objeção do encarregado à transferência internacional; ou o app crescer além do piloto.

**Alternativa de licença: Gemma 4 (Apache 2.0) — registrada, não perseguida.** O Gemma 4 é distribuído sob Apache 2.0 (`gemma.ai/resources/apache-2/`) e não consta do Appendix dos Gemma Terms of Use; trocar eliminaria a Política, a cláusula e o Notice do Gemma (a §4 da Apache ainda pede cópia da licença e aviso em arquivo modificado, bem mais leves). Conferido em 2026-10-29: são cinco modelos (E2B, E4B, 12B, 26B-A4B e 31B), e o menor quantizado publicado do E2B tem **2,84 GB** (`gemma-4-E2B-it-Q4_0.gguf`, `ggml-org`; o QAT Q4_0 do Google tem 3,35 GB), 2,4 vezes o teto de 1,2 GB do ADR-003. Também exigiria subir o llama.cpp da tag `b6100` (ADR-002), anterior ao Gemma 4. **Decisão:** não reabrir o ADR-003 por isso; a #18 continua mirando modelos de ~1 B de parâmetros com licença OSI. Reavaliar se surgir quantizado do Gemma 4 dentro do orçamento.

**Desfecho desfavorável.** Se este ADR for rejeitado: ficam o `MODEL_URL` sem host no código, o estado "não configurado" e a infraestrutura de publicação e conferência do objeto (independentes de modelo), e o "li e concordo" por versão dos termos, que vale para qualquer mudança deles. Saem o Notice, as cópias, a cláusula do Gemma e a publicação do arquivo. Como a Política restringe **uso**, e não só distribuição, baixar o Gemma do Hugging Face também deixaria de ser opção: builds de piloto sairiam sem `MODEL_URL`, com orientação pelo `RuleOnlyEngine`, até a troca de modelo — que vira issue P0, com a #18 deixando de ser contingência. A infraestrutura de publicação no storage próprio continua sendo a saída da exceção, para qualquer modelo.

**Gatilhos para revisitar a parte formal** (qualquer um reabre este ADR, com parecer jurídico e entidade com personalidade jurídica como responsável): publicar o app em loja; parceria formal com Secretaria de Saúde ou UBS; crescer além do piloto; coletar dados de participantes para publicação — este último é ética em pesquisa: avaliar o uso com pessoas passa antes por Comitê de Ética em Pesquisa.

**Revisão.** Reabrir também se os termos ou a Política mudarem (a data de "Last modified" é conferida a cada troca de modelo), quando a #47 mudar o papel do modelo, ou se a alternativa Gemma 4 passar a caber no orçamento.

**Revisão 2026-11-02 ([ADR-005](#10-registro-de-decisões-arquiteturais-adr)).** Os parágrafos acima ficam como foram aceitos em 2026-10-29; esta revisão diz o que mudou neles. D-A, D-B, D-C, R1–R3 e a exceção do Hugging Face **não** mudam de mérito.

- **O gatilho "publicar o app em loja" disparou.** A distribuição pelo Google Play está decidida (ADR-005, Decisão 6; [ADR-006](#10-registro-de-decisões-arquiteturais-adr)). O gatilho reabre este ADR **agora**, e o que ele pede vira condição para a **promoção para produção** na Play e para o **estudo com participantes externos**: **parecer jurídico** sobre a parte formal (licença do modelo, Política de Uso Proibido, enquadramento RDC 657/2022) e um **responsável com personalidade jurídica**, que é o controlador ainda **pendente de consulta institucional** (F-11; ADR-005, Decisão 8). Este ADR não escolhe esse responsável. O dogfooding interno pela faixa de teste da Play ou pela *pre-release* do GitHub não espera por isso (ADR-005, Decisão 7).
- **"Parceria formal com Secretaria de Saúde ou UBS" sai dos gatilhos.** Passa a **fora de escopo**: o projeto não tem vínculo com unidades de saúde, secretarias ou prefeituras (ADR-005, Decisão 4), e uma proposta assim exige **ADR novo**, não reabertura deste.
- **"Crescer além do piloto" passa a ler-se** "iniciar o estudo com participantes externos ou publicar em produção no Google Play" (ADR-005, Decisão 7; ADR-006).
- **"Domínio e servidor do projeto definidos"**, no "Fim da exceção", passa a apontar para a **VPS do PRISM** ([ADR-007](#10-registro-de-decisões-arquiteturais-adr)) e para o domínio próprio do PRISM (F-7), cujo registro também fecha o prefixo do `applicationId` ([ADR-009](#10-registro-de-decisões-arquiteturais-adr)).
- **Gatilhos vigentes**, em consequência: publicar em produção no Google Play (disparado; exige o parecer e o responsável acima); estudo com participantes externos; coletar dados de participantes para publicação (Comitê de Ética em Pesquisa, como antes). A lista original, no parágrafo "Gatilhos", fica como registro histórico.
- **A exceção do Hugging Face continua, agora por decisão (2026-11-03), e não por herança.** O host de conteúdo serve **só** `manifest.json` e packs (ADR-007, Decisão 4). O modelo continua vindo de `ggml-org/gemma-3-1b-it-GGUF`, um espelho GGUF de terceiro e não o repositório oficial, fixado no commit `f9c28bc`. Quatro condições tornam isso uma escolha:
  1. **A URL do modelo sai do APK e vai para o manifest assinado** (plano B). Hoje o `MODEL_URL` entra pelo `defines.release.json`, e trocar de host exige release. No manifest, trocar o host vira uma edição assinada (Ed25519 e dual review). O SHA-256 e o tamanho também podem ir para o manifest, mas isso permite **trocar de modelo sem release**, e essa escolha fica para o plano B decidir explicitamente. Hoje a identidade do modelo é o SHA-256 versionado no app (`model_catalog.dart`).
  2. **O download continua opt-in explícito**, e a tela passa a dizer, **antes** do "Baixar agora", que o arquivo vem de um servidor fora do Brasil. A transferência de IP deixa de ser implícita e vira ato informado da pessoa. Hoje a tela já pede o "sim" ("Deseja iniciar agora?"), mas não fala do país e chama o modelo de "módulo de idiomas", o que não descreve o arquivo. O texto entra no E7, e a leitura na LGPD fica para a T7-R.
  3. **Três riscos do espelho, cada um com o seu controle.** Sem modelo, o app segue pelo `RuleOnlyEngine` (INV-8) em todos eles; os controles servem para que isso não vire o estado normal:
     - **o espelho troca o arquivo:** o **SHA-256** versionado no app reprova. O `ResumableDownloader` apaga o arquivo parcial e rejeita com `digestMismatch`. É o único dos três que o hash cobre;
     - **o espelho some, ou muda a URL:** o hash não ajuda. Quem cobre é a **condição 1**: com a URL no manifest assinado, trocar de origem é uma edição, não um release;
     - **o Hugging Face limita downloads anônimos**, e uma frota, mesmo pequena, pode esbarrar nisso: o hash também não ajuda. Quem cobre é **observar a taxa de falhas de download** no estudo piloto (plano B). Se ela aparecer, o arquivo vai para o provedor de objeto do backup (F-8), em São Paulo, pela mesma condição 1.
  4. **Gatilho de revisão mensurável, e não só uma data.** Quando o estudo piloto mostrar o volume real de downloads, calcular o custo de servir 806 MB por pessoa a partir do provedor de objeto do backup (F-8), em São Paulo. Para dezenas de pessoas é pouco; para milhares, é dinheiro, e a decisão de trazer o modelo para o Brasil passa a ser informada. A revisão também ocorre em 2027-05-01 ou no critério de saída do estudo piloto (ADR-005, Decisão 7), o que vier primeiro.
- **Enquadramento e logo.** O "Enquadramento do projeto" foi revisto acima. No "Logo do Telessaúde UFRR", a frase "a participação de um programa não é vínculo formal da universidade com o app" continua literalmente verdadeira enquanto a formalização estiver pendente, mas a cooperação com o PET-Saúde é declarada (ADR-005, Decisão 1, e suas condições para citar o PET-Saúde pelo nome).

**Revisão 2026-11-09 ([ADR-010](#10-registro-de-decisões-arquiteturais-adr)).** O "estudo com participantes externos" dos gatilhos passa a ser o **estudo de impacto**, e "crescer além do piloto" lê-se "promover para produção na Google Play ou iniciar o estudo de impacto"; "builds de piloto" lê-se "builds do lançamento". O parecer jurídico e o responsável (F-11) continuam como condição da promoção para produção. O CEP passa a ser condição só do estudo de impacto (ADR-010, Decisão 4). "Aparelho do estudo piloto" lê-se "aparelho do dogfooding ou do estudo de impacto". A taxa de falha de download é observada pela loja e pelos relatos de QA, nunca por telemetria (ADR-010, Decisão 5).

### ADR-005 — Enquadramento institucional: projeto educativo aberto, sem vínculo com unidades de saúde: **ACEITO** (2026-11-02)

**Aprovação.** Contexto institucional e decisões de implantação definidos pelo dono do projeto em 2026-11-02. O nome do app foi decidido na mesma data. O plano de execução está em [`docs/superpowers/plans/2026-11-02-realinhamento-institucional-implantacao.md`](../docs/superpowers/plans/2026-11-02-realinhamento-institucional-implantacao.md).

**Contexto.** A especificação foi escrita supondo que o produto seria adotado e operado por uma rede municipal de saúde. Essa suposição aparece em vários pontos:
- a Secretaria Municipal de Saúde como controladora e como quem indica os revisores clínicos ([lgpd.md](lgpd.md), [`docs/revisao-golden.md`](../docs/revisao-golden.md));
- o piloto "em 2 UBS", com aprovação dos gestores das unidades ([PRD](PRD.md) §1.3 e §6.2, [brainstorm](brainstorm.md) M6);
- um admin de conteúdo municipal ([espec](espec.md) §1.3);
- o selo "regras do posto" (RF-15);
- a triagem como "coração do produto".

Nenhuma dessas premissas corresponde ao projeto real. O [ADR-004](#10-registro-de-decisões-arquiteturais-adr) registra "não há vínculo formal com a UFRR". A frase continua literalmente verdadeira, porque a formalização está pendente (Decisão 1), mas ficou incompleta: ela cala a cooperação com o PET-Saúde, que existe.

**Decisão.**

1. **Quem faz.** O Guia UBS é desenvolvido pelo **Grupo de Pesquisa PRISM (UFRR)** em cooperação com o **Programa de Educação pelo Trabalho para a Saúde (PET-Saúde): Inovação e Saúde Digital**, iniciativa do **Núcleo de Telessaúde da UFRR**.
   - A cooperação está **em andamento, com formalização pendente**. Isto é provisório (ver Revisão).
   - Até haver instrumento formal, os textos ao usuário só citam o PET-Saúde pelo nome com autorização registrada. O crédito que já existe (logo do Telessaúde UFRR sob "Realização", na tela "Sobre"; ADR-004) fica como está.
   - A UFRR, como instituição, não responde pelo app distribuído enquanto a Decisão 8 não disser outra coisa.
2. **O que é, nesta ordem.** O foco primário é **educação social em saúde**: entender o SUS e a Atenção Primária, direitos, documentos e sinais de alerta. Dizer onde procurar atendimento é apoio **secundário**. Especificação, termos de uso, ficha das lojas e textos ao usuário seguem essa hierarquia.
   - As regras R1–R3 do ADR-004 já apontam nessa direção e passam a ser a regra geral, não só uma resposta à Política do Gemma.
3. **Aberto.** Código aberto, repositório público, sob a licença do repositório.
4. **Sem vínculo com unidades de saúde.** O projeto não tem vínculo com unidades de saúde públicas ou privadas, secretarias ou prefeituras. Nenhum requisito pode pressupor integração, dados, operação ou aprovação delas.
   - "UBS", "UPA" e "posto" continuam no vocabulário como **categorias de serviço do SUS**, que são conteúdo educativo. Nunca aparecem como unidade parceira.
   - O que fica proibido é **atribuir** regra, decisão ou configuração do app a uma unidade (exemplo: "regras do posto").
   - Parceria com unidade, secretaria ou prefeitura não é ajuste de texto: exige um ADR novo.
5. **Nome.** O app continua **"Guia UBS"**. Ele passa a carregar, no 1º uso, na tela "Sobre" e na ficha das lojas, um aviso de não afiliação e de caráter educativo (RF-16, a especificar no E2).
   - **Princípio do `applicationId`** (o id em si é fixado inteiro, e só, no ADR-009, no E2):
     - não codifica "UBS", para sobreviver a uma renomeação: renomear custa uma ficha nova, nunca um app novo;
     - é específico deste app, sem consumir um nome genérico que caberia a outro app do PRISM;
     - fica **fora de `ufrr.br`**: o PRISM não controla `prism.ufrr.br`, e o id é permanente, enquanto a relação com a UFRR está em formalização. O prefixo vem de um domínio próprio do PRISM, registrado junto com o domínio de conteúdo (ADR-007).
6. **Infraestrutura própria.** Implantação, hospedagem e operação não dependem de infraestrutura de unidades de saúde nem da UFRR. O plano de controle roda numa **VPS mantida pelo PRISM** (ADR-007, E2).
   - O APK é distribuído por **GitHub Releases e Google Play** (ADR-006, E2).
7. **"Piloto" passa a ser o estudo piloto do projeto.** É conduzido pelo PRISM/PET-Saúde com voluntários da comunidade, fora de unidades de saúde. Há dois portões:
   - **dogfooding interno**, só com a equipe;
   - **estudo com participantes externos**. Este exige a política de privacidade com o controlador identificado (LGPD, art. 9º), o RIPD e, se houver coleta de dados de participantes, TCLE e parecer de Comitê de Ética em Pesquisa.
   - **Critério de saída:** zero orientação clinicamente incorreta e aprovação da coordenação clínica do projeto.
   - Nenhum dos dois passa por unidade de saúde.
8. **Controlador LGPD: pendente de consulta institucional.** Um grupo de pesquisa não tem personalidade jurídica. A escolha entre a UFRR e uma pessoa física do PRISM como controladora depende de consulta ao encarregado ou à procuradoria e **não** é decidida aqui.
   - Até a resposta, nenhum texto aponta a Secretaria como controladora. Os textos ao usuário **passam a usar** o marcador "[a definir]" no estágio E5; hoje a política de privacidade ainda diz "A ser preenchido pelo responsável pelo tratamento".
   - A identificação de quem mantém o app ("grupo de pesquisa PRISM", `prismufrr@gmail.com`; ADR-004, "Responsável") continua valendo como **identificação**, não como controlador.

**Relação com o ADR-004.** Na parte institucional, este ADR prevalece sobre o "Enquadramento do projeto" e sobre o "Logo do Telessaúde UFRR" do ADR-004: a cooperação existe e é declarada. A frase "não há vínculo formal com a UFRR" deixa de ser o enquadramento do projeto, embora continue literalmente verdadeira enquanto a formalização estiver pendente. A revisão textual do ADR-004 foi feita no estágio E2 (ver "Revisão 2026-11-02 (ADR-005)" no fim do ADR-004), com o registro de que a publicação no Google Play **dispara** o gatilho "publicar o app em loja".

**Fundamentos.**

1. **A especificação precisa descrever o projeto que existe.** Requisito que pressupõe um parceiro inexistente não tem como ser cumprido, e o piloto ficaria esperando uma aprovação que ninguém tem autoridade para dar.
2. **Segurança clínica não depende de parceiro.** INV-1…8, dual review, assinatura Ed25519 e a suíte golden protegem o usuário independentemente de quem opera. Nada nesta decisão os afrouxa. Os revisores clínicos passam a ser colaboradores do projeto, com registro profissional ativo, sem representar unidade.
3. **Educação primeiro reduz a superfície regulatória.** O enquadramento "bem-estar" da RDC Anvisa nº 657/2022 (ADR-004) só se sustenta enquanto produto e textos forem coerentes com o rótulo educacional. Ordenar o produto pela educação torna essa leitura mais robusta. A leitura continua sujeita à revisão jurídica.
4. **Atribuir regra a um posto é afirmar vínculo.** Para quem lê pouco, "regras do posto" e "Guia UBS" sugerem canal oficial. O nome fica, por decisão consciente, e o aviso de não afiliação passa a ser requisito, não cortesia.

**Custos aceitos.**

1. **Nome "Guia UBS" mantido.**
   - Na revisão do Google Play, o nome pode ser lido como *misrepresentation* (aparência de canal oficial), com risco de rejeição ou suspensão da ficha.
   - Quem lê pouco pode ler "UBS" como "oficial", mesmo com o aviso.
   - Mitigação: o RF-16, o aviso na ficha e o `applicationId` neutro, que permite renomear sem app novo. O GitHub Releases continua como canal se a Play recusar.
2. **Perde-se o canal "a prefeitura distribui"** (antiga H4). O alcance passa a depender dos canais públicos e das ações do PET-Saúde.
3. **Todo texto ao usuário é revisto**, em pt e es. A versão nova dos termos reabre o "li e concordo", até duas vezes durante a transição: uma antes e outra depois da revisão jurídica.
4. **O estudo com participantes externos espera o controlador.** O dogfooding interno pode começar antes.

**Revisão.**
- Decisões provisórias, cada uma com data de revisão. A revisão acontece **na primeira destas datas** que chegar: a data fixa ou o evento.
  - **Cooperação "em andamento, formalização pendente"** (Decisão 1). Revisar até **2027-02-01**, ou quando houver instrumento formal, ou se o PET-Saúde pedir outra redação. **Se 2027-02-01 chegar sem instrumento formal:**
    - a cooperação continua registrada aqui como **informal**;
    - a citação do PET-Saúde pelo nome em texto ao usuário fica **suspensa** até a formalização: o que já tiver sido publicado sai na versão seguinte dos termos, e nada novo é acrescentado;
    - o logo do Telessaúde UFRR na tela "Sobre" continua sob as condições do ADR-004 (crédito, não aval; sai se a UFRR ou o PET pedirem);
    - a próxima revisão fica marcada para seis meses depois.
  - **Métrica-norte "módulos educativos concluídos sem mediação"** e meta de alcance do estudo, a fixar com o PET-Saúde. A meta precisa estar fixada **antes do 1º participante externo**; a métrica-norte é revisada até **2027-05-01** ou no fim do estudo piloto.
- **Reabrir** se:
  - a Play recusar ou suspender a ficha pelo nome;
  - o estudo piloto mostrar que o público lê o app como serviço oficial;
  - surgir proposta de vínculo com unidade de saúde, secretaria ou prefeitura (aí exige ADR novo, não emenda).
- **Emendar** quando a consulta institucional definir o controlador.

**Revisão 2026-11-09 ([ADR-010](#10-registro-de-decisões-arquiteturais-adr)).** A Decisão 7 foi dividida. O dogfooding interno e o portão de publicação formam o **lançamento**, e a exigência de TCLE e CEP sai dele para o **estudo de impacto**, que tem portão próprio. O critério de saída vira o critério de promoção para produção (ADR-010, Decisão 3g). O custo aceito 4 lê-se "a promoção para produção e o estudo de impacto esperam o controlador", e o estudo pode depender ainda da formalização da Decisão 1 (ADR-010, Decisão 4). A métrica-norte passa a ser do estudo de impacto. O gatilho de reabrir "se o estudo piloto mostrar que o público lê o app como serviço oficial" lê-se "se o estudo de impacto ou os relatos do lançamento mostrarem…".

### ADR-006 — Canais oficiais do APK: GitHub Releases e Google Play: **ACEITO** (2026-11-02)

**Contexto.** A **origem** desta decisão é o [ADR-005](#10-registro-de-decisões-arquiteturais-adr), Decisão 6: o APK é distribuído por **GitHub Releases e Google Play**, por pedido do dono do projeto, não por pergunta aberta. Este ADR só detalha. A especificação anterior previa Play + F-Droid + repasse por Bluetooth/SD, sem GitHub Releases, e um canal "a prefeitura distribui" que deixou de existir com o fim da premissa municipal (ADR-005, Custo aceito 2).

**Decisão.**

1. **Dois canais oficiais:**
   - **GitHub Releases**, no repositório público: um APK por ABI ([ADR-009](#10-registro-de-decisões-arquiteturais-adr)), `SHA256SUMS` e a impressão SHA-256 do certificado de assinatura. O AAB não é anexado.
   - **Google Play**, com o AAB, que já entrega a ABI certa a cada aparelho.
2. **Os dois canais publicam o mesmo build**: mesma tag `vX.Y.Z`, mesmo `versionCode` (modelo de promoção do ADR-009). O estudo piloto roda na faixa de teste da Play e na *pre-release* do GitHub. Sem conta Play (F-4), os dois portões do estudo rodam só pela *pre-release* do GitHub.
3. **Procedência verificável (RF-17).** A release no GitHub traz o SHA-256 do APK e a impressão do certificado, e a versão aparece na tela "Sobre". O job de release falha sem `SHA256SUMS`.
4. **F-Droid é canal futuro**, não previsto para o estudo piloto. Entrar nele exige ADR próprio: o F-Droid em regra assina com chave própria, o que cria um terceiro canal incompatível com os outros dois (ver ADR-009, Play App Signing).
5. **Repasse entre pessoas não é canal oficial.** Quem recebe o APK por Bluetooth, SD ou mensagem confere o SHA-256 contra a release do GitHub. O **pack** repassado continua seguro sem isso, porque o aparelho verifica a assinatura Ed25519 (§4.2). O repasse do `.gguf` continua tratado como distribuição (ADR-004).
6. **A ficha da Play e a nota de release** seguem as regras R1–R3 do ADR-004 e trazem o aviso de não afiliação e de caráter educativo (RF-16), a política de privacidade em URL pública (F-7) e o aviso de canal do ADR-009.

**Fundamentos.**

1. **O GitHub Releases é o canal que não depende de terceiro aprovar.** É gratuito, público, e a transparência do binário (hash + certificado) acompanha o código aberto (ADR-005, Decisão 3). Se a Play recusar a ficha — risco registrado no ADR-005 (nome "Guia UBS") —, o projeto continua distribuindo.
2. **A Play é onde o público instala.** Quem lê pouco não instala APK de fora da loja; a Play também entrega atualização sem gesto do usuário.
3. **Um build, dois canais.** O artefato testado no estudo é o artefato publicado; rebuild por canal criaria duas versões com o mesmo número.

**Custos aceitos.**

1. **Os dois canais não se atualizam um sobre o outro** (Play App Signing com chave da Google, ADR-009). Trocar de canal exige desinstalar; os ajustes do `user.db` se perdem. Nada de saúde é guardado (INV-2), então a perda é de preferências.
2. **Taxa única da conta de desenvolvedor da Play** e as exigências da conta (teste fechado para conta pessoal nova, `targetSdk` mínimo, Data safety, declaração de app de saúde) — todas **(conferir no Play Console na data da publicação)**.
3. **Sem F-Droid no estudo piloto**, perde-se o selo de build reprodutível de terceiro. O `SHA256SUMS` e o código aberto cobrem parte disso.

**Revisão.**
- Reabrir se a Play recusar ou suspender a ficha (aí o GitHub Releases segue sozinho, e o ADR-005 é reaberto pelo nome), se o projeto decidir entrar no F-Droid, ou se um canal novo for proposto.
- A declaração de Data safety e a de app de saúde são **propostas**, sujeitas à revisão jurídica (T7-R), e conferidas no Play Console na data da publicação. Nada aqui decide base legal.

**Revisão 2026-11-09 ([ADR-010](#10-registro-de-decisões-arquiteturais-adr)).** Na Decisão 2, a faixa de teste da Play e a *pre-release* do GitHub servem ao dogfooding e ao QA do lançamento, e "o estudo piloto roda na faixa de teste" lê-se assim. O estudo de impacto usa o app publicado. Na Decisão 4 e no custo 3, "estudo piloto" lê-se "lançamento".

### ADR-007 — Plano de controle numa VPS mantida pelo PRISM: **ACEITO** (2026-11-02)

**Contexto.** A **origem** desta decisão é o [ADR-005](#10-registro-de-decisões-arquiteturais-adr), Decisão 6: o plano de controle roda numa **VPS mantida pelo PRISM**, sem depender de infraestrutura de unidades de saúde nem da UFRR. Este ADR só detalha. O [ADR-001](#10-registro-de-decisões-arquiteturais-adr) e a §9 já fixavam "Compose + Ansible num VPS, 100% OSS", mas sem dono: o VPS aparecia como "provedor contratado" sem quem contrate, e o compose não dizia como sobe em produção.

**Decisão.**

1. **Dono e pessoas.** A VPS é contratada e administrada pelo PRISM; não é da UFRR nem de unidade de saúde. Os nomes, o provedor, a região, o snapshot e o LUKS (F-1, F-2) ficam no registro de decisões fora do repositório; o país do provedor só entra em texto público se a revisão jurídica exigir. São **duas pessoas** (F-2, decidida em 2026-11-03):
   - **o administrador da VPS**, que opera a VPS e o domínio no dia a dia;
   - **um segundo mantenedor**, que **não** opera a VPS, mas é: revisor obrigatório do *environment* `release` (*Prevent self-review*, ADR-009); segunda custódia do keystore e da chave Ed25519; o mantenedor B da assinatura provisória do pack (Revisão do ADR-001); quem tem a credencial de leitura do backup (Decisão 7); e quem pode criar tag `v*` pelo ruleset.
   - **Por quê: fator ônibus.** Com uma pessoa só, duas semanas sem acesso dela significam nenhuma correção publicada, nenhum backup restaurado e nenhum pack assinado. Um projeto de saúde distribuído na Play não pode ter esse ponto único. Pela mesma razão, o backup precisa poder ser **restaurado numa VPS nova sem o administrador**. Quem precisa saber restaurar é o **runbook escrito** (item 28), não a pessoa: o segundo mantenedor não precisa operar infraestrutura, porque o papel dele é aprovar, guardar, conferir hash e ler o backup. **O teste trimestral de restauração é executado pelo segundo mantenedor, seguindo o runbook.** Assim o teste treina a pessoa e valida o documento ao mesmo tempo, e qualquer passo que só o administrador saberia fazer aparece como defeito do runbook.
2. **Requisitos mínimos:** datacenter no Brasil, que é a postura do ADR-001 (fundamento 6) e da LGPD-RF06. Outro país só com transferência internacional registrada no RIPD e revisão deste ADR; ≥ 2 vCPU, 4 GB de RAM, disco ≥ 80 GB, snapshot disponível.
3. **Topologia = `infra/compose.yaml`, sem override.** Sobe com `docker compose -f compose.yaml up -d`, por unit systemd; o `compose.override.yaml` é só de dev (edge sem TLS) e não entra na VPS. Só 80/443 públicas; `sqld` e MinIO em `127.0.0.1`; `cms` e `packer` sem `ports:` (§7). A chave Ed25519 fica `:ro` **só** no `packer`.
4. **Domínio e TLS.** Domínio próprio do PRISM, **`prismrr.com.br`** (registrado em 2026-11-02; ADR-005, Decisão 5; ADR-009, item 1), com `ACME_EMAIL` de caixa do grupo e dois nomes **separados de propósito** (F-7, respondida em 2026-11-03):
   - **`guiasaude.conteudo.prismrr.com.br`** (`CONTENT_DOMAIN`): **só** `manifest.json` e packs, como arquivos estáticos (GET/HEAD). É este nome que vai embarcado no APK (`PACK_MANIFEST_URL`), e por isso ele não muda;
   - **`guiasaude.cms.prismrr.com.br`** (`CMS_DOMAIN`): o plano de controle, atrás de VPN ou de autenticação (o CMS já exige login e 2FA; a VPN é decisão do item 27). Ele **pode mudar de endereço** sem que o de conteúdo mude, porque nenhum aparelho fala com ele. O mesmo domínio dá o prefixo do `applicationId` ([ADR-009](#10-registro-de-decisões-arquiteturais-adr)).
5. **Provisionamento por Ansible** (item 27), fonte da verdade: usuário de deploy com SSH só por chave e `PermitRootLogin no`, firewall 22/80/443, `unattended-upgrades` de segurança, Docker pinado, LUKS se o provedor permitir. `infra/.env` só na VPS, com permissão 600, e cópia cifrada no cofre.
6. **Atualização.** Imagens com tag exata ou digest; toda mudança por PR com CI verde; migração do banco master só depois de backup.
7. **Backup fora do host** (item 28), **com o destino também no Brasil**, pela mesma regra da VPS do item 2: o backup carrega a trilha e os dados dos operadores, e cifrar não afasta a transferência internacional. **O destino é de outro provedor que não o da VPS** (F-8, respondida em 2026-11-03; o nome fica fora do repositório), para que uma suspensão de conta não leve a VPS e o backup juntos. Requisitos do destino:
   - **a VPS não consegue apagar o backup:** credencial de escrita sem permissão de apagar, ou bucket com imutabilidade por período. Uma VPS comprometida não leva o backup junto;
   - **a credencial de leitura fica com uma pessoa diferente do administrador da VPS;**
   - **teste de restauração trimestral, registrado com data** no registro operacional.

   Diário e cifrado (restic/age) — `sqld` (dump consistente), o que no MinIO for fonte primária, `caddydata` e `.env` —, com teste de restauração trimestral numa VPS descartável. Prioridade: banco master e trilha de auditoria, que não são reconstruíveis; os packs são, pelo packer reprodutível.
8. **Monitoramento:** monitor externo de `manifest.json` e do CMS, alertas de expiração do TLS e de disco acima de 80 %, `fail2ban` no SSH. Incidente: o runbook LGPD-RF12 nomeia o PRISM como comunicante, sob o controlador pendente (F-11).
9. **Assinatura do pack enquanto a VPS não existe:** ver a **Revisão do [ADR-001](#10-registro-de-decisões-arquiteturais-adr)** — procedimento provisório de dois mantenedores, que sai quando o item 27 entrar.

**Fundamentos.**

1. **Infraestrutura sem dono não tem quem responda por incidente** nem por backup. Nomear o PRISM e dois administradores fecha essa lacuna sem criar vínculo com unidade de saúde.
2. **O app não depende do CMS em runtime** (§2.3): a VPS cair atrasa a convergência da frota, nunca para o app. Por isso uma VPS única, com backup fora dela, é proporcional ao risco.
3. **Sem override em produção** porque o override de dev tira o TLS do edge; carregá-lo na VPS por um `docker compose up` sem `-f` é o erro mais barato de cometer.

**Custos aceitos.**

1. **Chave Ed25519 numa VPS sem HSM.** Mitigação: a segunda posição de chave que o binário já aceita (rotação) e o runbook de revogação.
2. **VPS única** como ponto de indisponibilidade da entrega de conteúdo (§6); mitigação por espelhos estáticos, que não precisam ser confiáveis.
3. **Fatura recorrente** da VPS e do destino do backup, pagas pelo PRISM.

**Revisão.**
- Decisões provisórias, revistas em **2027-05-01** ou quando o estudo piloto atingir o critério de saída da Decisão 7 do ADR-005 (zero orientação clinicamente incorreta e aprovação da coordenação clínica do projeto), **o que vier primeiro**:
  - **destino do backup fora da VPS** (F-8): um segundo provedor de armazenamento de objetos, com conta do PRISM; a retenção de 7 diárias, 4 semanais e 6 mensais também é provisória;
  - **retenção do log do Caddy em 14 dias** (F-10), sujeita também à revisão jurídica (T7-R).
- Reabrir se o PRISM deixar de manter a VPS, se a revisão jurídica exigir datacenter ou operador diferente, ou se o projeto ganhar superfície web dinâmica pública (ADR-001).
- **Se o domínio `prismrr.com.br` for perdido** (expiração, disputa, mudança de titular sem transferência):
  - **o `applicationId` fica.** Ele é só um identificador na Play, que não verifica posse de domínio (ADR-009);
  - **mudam de endereço** o domínio de conteúdo (`CONTENT_DOMAIN`, `PACK_MANIFEST_URL`, `MODEL_URL`), o CMS, a URL da política de privacidade da ficha da Play e qualquer e-mail de contato no domínio;
  - **exige release do app**, porque `PACK_MANIFEST_URL` e `MODEL_URL` entram embutidos no build (`--dart-define`). Até o app novo chegar, os aparelhos antigos procuram conteúdo no endereço perdido. Nada de errado chega a eles, porque a assinatura Ed25519 e o SHA-256 não dependem do domínio e quem tomar o domínio não consegue assinar pack. Mas param de receber conteúdo novo (INV-8: nada bloqueia);
  - **o modelo já instalado não é baixado de novo**, porque a identidade dele é o SHA-256, não a URL (ADR-004);
  - **mitigação:** renovação automática, alerta de expiração no monitoramento (`implantacao.md` §3.6), titular e plano de transferência no registro operacional fora do repositório (F-2).

**Revisão 2026-11-09 ([ADR-010](#10-registro-de-decisões-arquiteturais-adr)).** "Quando o estudo piloto atingir o critério de saída da Decisão 7 do ADR-005" lê-se "quando o lançamento for promovido para produção" (ADR-010, Decisão 3g).

### ADR-008 — Escopo de conteúdo: de "município" para "edição": **ACEITO** (2026-11-02)

**Contexto.** O contrato do pack e o banco master usam `municipality` (`municipalityCode` no manifest e em `contract/src/content-schema.ts`, as tabelas municipais do CMS, o campo `municipality` da telemetria, `contract/src/telemetry.ts`), desenhados para que cada município publicasse e curasse o próprio pack. O [ADR-005](#10-registro-de-decisões-arquiteturais-adr) (Decisão 4) retirou a premissa: não há prefeitura, secretaria nem curador municipal.

**Decisão.**

1. **`municipality` fica no contrato e no schema, reinterpretado como "edição"** do conteúdo: um recorte publicado pela equipe do projeto, nacional ou regional. Não há curador municipal; quem autora e revisa é a equipe do projeto, sob o dual review de sempre.
2. **Nenhum identificador é renomeado** por este ADR. Renomear `municipality` só com motivo de código (por exemplo, uma mudança de schema que já quebre a compatibilidade), num PR que siga a cadeia de type safety (§3.3) e a versão de `schemaVersion`.
3. **O corte global × edição continua imposto pelas FKs.** Regras de red flag seguem globais: correção alcança toda edição por construção.
4. **Texto novo** (spec, docs, CMS) diz "edição"; onde precisar citar o campo, diz "`municipality` (edição)".

**Fundamentos.**

1. **O mecanismo serve sem a premissa.** Separar conteúdo por recorte continua útil (ex.: uma edição de Roraima, com serviços e idiomas da região), e não exige parceiro.
2. **Renomear custa mais do que explica.** O nome atravessa contrato, codegen Dart, migrações imutáveis do CMS e packs já assinados; trocar por semântica, sem ganho funcional, seria churn com risco de quebra de compatibilidade de pack.

**Custos aceitos.**

1. **O nome no código diverge do sentido.** Quem lê `municipality` precisa deste ADR para não supor curadoria municipal.
2. **`municipality` na telemetria** continua sendo o nome da coorte de edição; o k-anonimato ≥ 20 não muda.

**Revisão.**
- **Pack único nacional** (F-16, provisório): uma edição nacional, com o mecanismo de edição preservado. Revisar em **2027-05-01** ou quando o estudo piloto atingir o critério de saída da Decisão 7 do ADR-005 (zero orientação clinicamente incorreta e aprovação da coordenação clínica do projeto), **o que vier primeiro**, ou antes se o estudo pedir uma edição regional.
- Reabrir se surgir motivo de código para renomear, ou se alguém propuser edição curada por terceiro (aí vale também o ADR-005: parceria exige ADR novo).

**Revisão 2026-11-09 ([ADR-010](#10-registro-de-decisões-arquiteturais-adr)).** "Quando o estudo piloto atingir o critério de saída da Decisão 7 do ADR-005" lê-se "quando o lançamento for promovido para produção" (ADR-010, Decisão 3g).

### ADR-009 — Identidade, versionamento, ABIs e assinatura do app: **ACEITO** (2026-11-02)

**Contexto.** Hoje o app sai como `0.1.0+1`, sem tags, só em `arm64-v8a`, com `minSdk 26`, e com o `applicationId` de exemplo `br.gov.exemplo.guia_ubs`, que leva `gov` e codifica o nome. Os canais do [ADR-006](#10-registro-de-decisões-arquiteturais-adr) exigem fixar identidade, versão e assinatura **antes** da 1ª publicação na Play, porque o id não muda depois dela. O [ADR-005](#10-registro-de-decisões-arquiteturais-adr) (Decisão 5) traz só o **princípio** do id; o id inteiro é fixado aqui, e só aqui. A implementação é o item 25 do roadmap.

**Decisão.**

1. **`applicationId`: `br.com.prismrr.guiasaude`.** Fixado em 2026-11-02 e permanente depois da 1ª publicação na Play.
   - O **sufixo `guiasaude` está decidido** (registro da T0, 2026-11-02): neutro quanto ao nome "Guia UBS", específico deste app — o PRISM tem outro app com o PET-Saúde.
   - O **prefixo** `br.com.prismrr` é o reverso de **`prismrr.com.br`**, domínio próprio do PRISM. Ele foi registrado no Registro.br em 2026-11-02 e escolhido pelo dono do projeto. Fica fora de `ufrr.br`, sem `gov` e sem "ufrr" no nome. O "rr" é Roraima. É o mesmo domínio da F-7 ([ADR-007](#10-registro-de-decisões-arquiteturais-adr)).
   - A titularidade do domínio (CPF ou CNPJ do titular no Registro.br), o plano de transferência e quem renova ficam no registro de decisões fora do repositório (F-2). Se o titular for pessoa física, o nome do domínio é dela até a transferência; se for a UFRR, isso precisa ser conciliado com a Decisão 1 do ADR-005.
   - O que acontece se o domínio for perdido está na Revisão do ADR-007: o id fica, e o conteúdo e a política migram com uma release do app.
   - Mudam junto, no item 25: os nomes de tarefa do WorkManager (`pack_sync_scheduler.dart`, `model_sync_scheduler.dart`) e `app/tool/release_permissions.dart`.
2. **Versionamento SemVer** no `pubspec.yaml`, `MAJOR.MINOR.PATCH`:
   - MAJOR: o app passa a rejeitar packs de um `schemaVersion` major antigo, ou muda o comportamento perceptível da orientação;
   - MINOR: funcionalidade nova;
   - PATCH: correção.
   - Tag anotada `vX.Y.Z` em `main`; `CHANGELOG.md` na raiz, no formato Keep a Changelog. A versão do pack (INV-7) e o `schemaVersion` seguem independentes da versão do app.
3. **`versionCode = MAJOR*10000 + MINOR*100 + PATCH`**, estritamente crescente e **único entre os canais**.
   - **Limites:** MINOR e PATCH ≤ 99; MAJOR ≤ 210, porque a Play aceita `versionCode` até 2 100 000 000 (conferir no Play Console na data da publicação).
   - Estourar MINOR ou PATCH exige um MAJOR novo ou a revisão desta fórmula.
4. **Modelo de promoção, não de rebuild.** O artefato testado é o publicado: mesma tag, mesmo `versionCode`, mesmo binário.
   - Na Play, o AAB sobe para a faixa de teste e é **promovido** para produção.
   - No GitHub, a release nasce marcada como ***pre-release***, e a marca sai na promoção; o APK e o `SHA256SUMS` não mudam.
   - Não há sufixo `-rc` nem PATCH reservado: defeito achado no estudo piloto vira um PATCH novo e uma nova rodada na faixa de teste.
5. **ABIs e versão mínima:**
   - `arm64-v8a` **e** `armeabi-v7a`; `minSdk` continua 26.
   - **`armeabi-v7a` sai sem o shim nativo** ([ADR-002](#10-registro-de-decisões-arquiteturais-adr)): nesses aparelhos a triagem roda pelo `RuleOnlyEngine`, degradação que a INV-8 já prevê. Um aparelho 32-bit dificilmente tem memória para o modelo de ~806 MB ([ADR-003](#10-registro-de-decisões-arquiteturais-adr)), então compilar o llama.cpp para ele não compensa.
   - **Onde o shim não existe, o app não oferece nem inicia o download do modelo.** Baixar 806 MB que nunca vão rodar desperdiça o plano de dados de quem menos pode pagar. O item 25 cobre isso com teste.
   - **Um build por ABI, sem `--split-per-abi`:** cada APK sai de um `flutter build apk --release --target-platform=android-arm64` (e `android-arm`) separado, e o AAB usa o mesmo `versionCode`. O motivo é verificado no SDK: com `--split-per-abi`, o plugin gradle do Flutter **sobrescreve** o código, `versionCodeOverride = abiVersionCode * 1000 + versionCode` (`packages/flutter_tools/gradle/src/main/kotlin/FlutterPlugin.kt:669-674`), com `armeabi-v7a`=1, `arm64-v8a`=2 e `x86_64`=4 (`FlutterPluginConstants.kt:39-45`). Isso quebraria as duas premissas acima: os três artefatos sairiam com códigos diferentes, e o deslocamento de 1000 cai **dentro** da fórmula, que anda de 100 em 100 por MINOR — o APK `arm64` de `0.1.0` (100 + 2000 = 2100) colidiria com o `0.21.0`.
6. **Guarda de `minAppBuild`.** Hoje o app lê `minAppBuild` do manifest (`app/lib/sync/pack_manifest.dart`), mas **nenhum código o compara com nada**, e o packer grava `1` por padrão. Passa a valer:
   - `minAppBuild` compara com o `versionCode` **único** do item 5;
   - a guarda é implementada no item 25, com teste;
   - **até lá, publicar pack que dependa de app novo é proibido**, porque nenhum aparelho o recusaria.
7. **Play App Signing com chave gerada pela Google** (F-6, respondida em 2026-11-02). Consequência entre canais: o APK do GitHub (assinado pela chave de release do projeto) e o da Play (assinado pela chave da Google) **não se atualizam um sobre o outro**. A nota de release e a página do projeto avisam: "troque de canal só desinstalando; seus ajustes se perdem; nada de saúde é guardado".
8. **Custódia do keystore de release** (o que assina o APK do GitHub e o AAB enviado à Play): gerado uma vez e guardado em cofre offline com **duas custódias**, no mesmo regime da chave Ed25519. Nunca vai para o repositório (o `.gitignore` já cobre). É uma chave **diferente** da Ed25519 do pack.
   - **Por que este keystore vai para o CI e a chave do pack não.** A Revisão do ADR-001 tira a chave do pack de CI porque qualquer workflow editável por quem tem escrita a expõe. O keystore tem **a mesma exposição**, e para quem instala pelo GitHub ele é a chave de distribuição, não uma chave recuperável.
     - A diferença está em como cada artefato é conferido. O pack é **reprodutível** (`SOURCE_DATE_EPOCH`): um segundo mantenedor reconstrói o mesmo hash, e a assinatura pode ficar fora do pipeline sem perder a verificação.
     - O APK **não é reprodutível** (build nativo, NDK, Gradle). Assinar fora do pipeline obrigaria a confiar no binário de uma máquina pessoal, que ninguém consegue reproduzir para conferir. Por isso o APK é assinado **no** pipeline, e a exposição é compensada pelos controles abaixo.
   - **Controles compensatórios** (configuração do repositório, feita pelo mantenedor; lista em `docs/operacao.md` §2.13):
     - (a) os segredos do keystore são do **environment `release`**, não do repositório. Só existem num job que referencia o environment, e só depois da aprovação;
     - (b) o environment exige **revisor** e ***Prevent self-review***: quem dispara não aprova;
     - (c) o environment só aceita **tags `v*`** (*deployment branches and tags*);
     - (d) um **ruleset de tags** restringe a criação de `v*` aos mantenedores. Sem ele, qualquer colaborador com escrita dispara o pipeline de assinatura com um `git push --tags`;
     - (e) o workflow confere o certificado de cada APK contra `vars.RELEASE_CERT_SHA256`. Uma chave trocada ou a debug reprova.

**Fundamentos.**

1. **O id é a única coisa que não muda depois da 1ª publicação.** Por isso ele não codifica o nome (que pode mudar, ADR-005) e só usa domínio que o PRISM controla.
2. **Um `versionCode` só, para todo artefato**, é o que permite o modelo de promoção, a comparação de `minAppBuild` e a rejeição de downgrade sem tabela por ABI.
3. **32-bit sem shim** amplia o público que mais precisa dos módulos educativos, sem prometer o assistente onde ele não roda.
4. **Chave gerada pela Google** tira do projeto o risco de perder a chave de assinatura da Play; a chave de upload perdida pode ser substituída pelo procedimento da Play (conferir no Play Console na data da publicação).

**Custos aceitos.**

1. **Canais incompatíveis** (item 7): trocar de canal custa desinstalar e perder preferências.
2. **Um build a mais no CI do app** (não do shim), para `armeabi-v7a`, e um segundo APK no GitHub, com o seu SHA-256.
3. **Domínio `.br`.** O `docs/operacao.md` recomendava domínio fora de `.br`, porque o Registro.br exige CPF ou CNPJ do titular e expõe dados dele. O dono do projeto escolheu `.com.br` assim mesmo. O custo aceito é que o id e o domínio de conteúdo passam a depender de um titular identificado no Registro.br. **A renovação do domínio é obrigação permanente:** se ele expirar, o id passa a apontar para um domínio que outra pessoa pode registrar, e a frota perde a origem de conteúdo.
4. **Regras da Play** citadas aqui — limite de `versionCode`, `targetSdk` mínimo, tamanho do AAB — mudam por decisão de terceiro; cada uma é conferida no Play Console na data da publicação.
5. **Keystore no CI** (item 8): mesmo com os controles (a)–(e), quem conseguir editar o workflow **e** obter a aprovação do environment alcança a chave.
   - **Se o keystore vazar, os dois canais não se recuperam igual.**
     - Na Play, a chave vazada é a de **upload**, e a Play App Signing a troca sem afetar quem já instalou.
     - No GitHub, a chave vazada **é a de distribuição**. Não há troca: um APK assinado por outra chave não atualiza o instalado, e **todo aparelho instalado pelo GitHub precisa desinstalar e instalar de novo**, perdendo os ajustes.
   - Por isso o vazamento entra no runbook de incidente (item 28), com aviso aos usuários do canal GitHub.

**Revisão.**
- Decisões provisórias, revistas em **2027-05-01** ou quando o estudo piloto atingir o critério de saída da Decisão 7 do ADR-005 (zero orientação clinicamente incorreta e aprovação da coordenação clínica do projeto), **o que vier primeiro**:
  - **política de versionamento e modelo de promoção** (F-5; itens 2 a 4);
  - **ABIs e `minSdk`** (F-17; item 5). Antes de virar definitiva, o item 25 verifica que cada APK contém só as `.so` da sua ABI e que o `versionCode` lido no aparelho (`aapt dump badging` e a tela "Sobre") é igual nos três artefatos. Se falhar, a alternativa é o `minAppBuild` comparar com um número derivado do SemVer injetado por `--dart-define`, e não com o `versionCode` do pacote. Ainda a medir: o tamanho do APK `armeabi-v7a` e o custo da configuração a mais no CI.
- Reabrir se o domínio `prismrr.com.br` for perdido ou mudar de titular (o id não muda, mas a origem de conteúdo e a verificação de posse sim).
- Reabrir se a Play mudar o limite de `versionCode` ou a política de assinatura, ou se o projeto passar a enviar chave própria à Play (o que tornaria os canais compatíveis, com a custódia inteira na equipe).

---

**Revisão 2026-11-09 ([ADR-010](#10-registro-de-decisões-arquiteturais-adr)).** "Quando o estudo piloto atingir o critério de saída da Decisão 7 do ADR-005" lê-se "quando o lançamento for promovido para produção" (ADR-010, Decisão 3g), e "defeito achado no estudo piloto" lê-se "defeito achado no dogfooding ou no teste fechado".

### ADR-010 — Lançamento do app separado do estudo de impacto: **ACEITO** (2026-11-09)

**Contexto.** Antes de 2026-11-09, o [ADR-005](#10-registro-de-decisões-arquiteturais-adr), Decisão 7, juntava a publicação do app e o estudo com usuários numa única etapa, o "estudo piloto do projeto", com dois portões. O segundo exigia TCLE e parecer de Comitê de Ética em Pesquisa "se houver coleta de dados de participantes", o que punha a ética em pesquisa no caminho crítico da publicação. O app não coleta dado pessoal ([INV-2](espec.md); [`docs/dados-do-usuario.md`](../docs/dados-do-usuario.md)). A coleta que existe é a do estudo: observação de uso e respostas a entrevistas ([LGPD-RF02](lgpd.md)). Decisão da coordenação do projeto em 2026-11-09.

**Decisão.**
1. **Duas etapas, cada uma com seu portão.**
   - **Lançamento (Parte A):** a publicação do app. É produto, não pesquisa: não coleta dados de usuários, não mede hipótese e não observa nem entrevista pessoas externas para fins de pesquisa. Não depende de CEP.
   - **Estudo de impacto (Parte B):** pesquisa com seres humanos sobre o app **já publicado**.
2. **"Piloto", nome usado antes de 2026-11-09, deixa de nomear etapa.** Onde se referia à publicação, passa a ser "lançamento". Onde se referia a observar pessoas, passa a ser "estudo de impacto". O dogfooding interno é uma fase do lançamento.
3. **Portão do lançamento.** Substitui o portão "estudo com participantes externos" do ADR-005, Decisão 7.
   a. Conteúdo de saúde validado por profissionais com registro ativo, com registro de revisão (quem, qual versão, quando): o portão golden ([#2](https://github.com/hbgit/Guia-UBS/issues/2)) e os atestados `AT-NNNN`. A revisão conta com o PET-Saúde/Telessaúde UFRR, em cooperação com a formalização pendente (ADR-005, Decisão 1), citado ao usuário conforme a F-13.
   b. Aviso de que o app não substitui atendimento ([RF-16](espec.md)) e encaminhamento explícito dos sinais de alarme para SAMU 192, UPA ou UBS (INV-1).
   c. Responsável institucional identificado (F-11). Continua no caminho crítico, junto com o parecer jurídico do ADR-004 (Revisão 2026-11-02).
   d. Política de privacidade e termos publicados em `guiasaude.prismrr.com.br` ([`implantacao.md`](implantacao.md) §2.9), mesmo sem coleta, e políticas da Google Play para apps de saúde conferidas (§2.7).
   e. Correção de conteúdo publicada em até 7 dias ([RNF-12](espec.md), a antiga H2 do PRD), pelo GitHub Releases e pela Google Play.
   f. Testes de usabilidade internos (equipe, bolsistas e alunos) são **QA**: não registram dado identificável, não medem hipótese e não são usados depois em publicação. O teste fechado da Play também é QA (DC-D). A ausência do público-alvo é compensada desde já por três mitigações: revisão de linguagem simples por profissionais do PET-Saúde que atendem essa população (ACS, enfermagem), com registro de quem revisou, qual versão e quando; índice de legibilidade em pt-BR como critério de aceite dos textos e roteiros de áudio (índice e limiar a definir); e escuta do TTS em pt e es no aparelho antes da promoção. **Se, e somente se**, o CEP/UFRR se manifestar por escrito de que o desenho não é pesquisa (F-20 d), soma-se a **validação de produto** com pessoas indicadas pelo PET-Saúde como representativas do público-alvo, cabendo a caracterização a quem indica. Antes da tarefa, a pessoa é informada oralmente de que é um teste do produto, voluntário e sem registro, e não assina nada. O teste não tem hipótese, registro identificável nem roteiro de entrevista; o resultado serve só para iterar e é descartado. Se o CEP entender que é pesquisa, a cláusula não se ativa, e o teste com o público-alvo fica no estudo de impacto.
   g. **Critério de promoção para produção:** nenhuma orientação clinicamente incorreta na revisão clínica, mais a aprovação da coordenação clínica do projeto (DC-B).
4. **Portão do estudo de impacto.**
   - **Pré-condição: instituição proponente.** A Plataforma Brasil recebe o protocolo de uma instituição proponente cadastrada, e o CEP é "vinculado à instituição que realiza a pesquisa" (Lei 14.874/2024, art. 2º, X). **Hipótese de trabalho, a confirmar na consulta prévia (F-20 b):** o pesquisador responsável é docente da UFRR, e o CEP/UFRR recebe protocolos de pesquisadores da casa tendo a UFRR como proponente. O "sem vínculo formal" do PRISM (ADR-005, Decisões 1 e 8) diz respeito à publicação do app, não à submissão de um estudo por um docente da UFRR. Se a hipótese não se confirmar, a Parte B passa a depender da formalização da cooperação (custo aceito 4).
   - **Base LGPD dos dados do estudo:** escolhida com o controlador (F-11). A hipótese de estudos por órgão de pesquisa (art. 7º, IV) só é usada se o controlador confirmar que se enquadra no art. 5º, XVIII. A proponente do estudo e o controlador dos dados do estudo podem ser respondidos juntos (F-11, F-20 b, F-21).
   - **TCLE e parecer do CEP/UFRR** (Plataforma Brasil) antes do primeiro participante externo. **Postura do projeto:** até manifestação escrita do CEP/UFRR, o projeto não se apoia em nenhuma hipótese de dispensa, porque a Lei 14.874/2024 (art. 6º) e a pendência do regulamento do art. 63, parágrafo único, tornam incerta a aplicação da Res. CNS 510/2016, art. 1º, parágrafo único. O entendimento de que uma atividade não é pesquisa também só vale com manifestação escrita do CEP/UFRR (F-20 c e d).
   - **Hipóteses:** H1, H1b e H4 do [PRD](PRD.md) §1.3.2.
   - **Método:** observação de uso e respostas a entrevistas, por canal próprio, fora do app ([LGPD-RF02](lgpd.md)). Os dados agregados da loja (instalações, versões ativas) podem ser insumo.
   - **Antes do primeiro participante, também:** a base LGPD dos dados do estudo escolhida com o controlador (consentimento, ou termo de informação se a base for o art. 7º, IV), o RIPD (DC-A) e o controlador (F-11).
5. **Regras de fronteira.**
   - Nada observado no lançamento vira dado de resultado no estudo de impacto. O CEP não aprova retroativamente.
   - TCC e relatório do PET-Saúde com dados de participantes só existem dentro do estudo de impacto. Relato de experiência de desenvolvimento, sem dados de pessoas, não entra no CEP. Da Parte A, o PET-Saúde pode reportar o produto, o alcance agregado da loja e o relato de experiência, mas nenhum dado de pessoa.
   - Telemetria futura é decisão separada, com ADR próprio, LGPD e revisão da INV-2. Não é consequência desta divisão.
6. **TCLE e consentimento LGPD são exigências distintas.**
   - O TCLE responde à ética em pesquisa (Lei 14.874/2024, art. 18; Res. CNS 466/2012 e 510/2016) e é exigido pelo CEP.
   - A base LGPD responde ao tratamento de dados (arts. 7º e 11). Para dados de pesquisa, a LGPD se aplica de forma subsidiária à Lei 14.874/2024 (art. 61).
   - Podem estar no mesmo documento, nunca na mesma cláusula.
   - O "li e concordo" dos termos do app não é nenhum dos dois (ADR-004).
7. **Registro do software** como produção técnica (e, opcionalmente, no INPI) é entregável do lançamento, independente do estudo. A titularidade fica aberta (F-21).

**Decisões complementares (revisão de 2026-11-09).**
- **DC-A (Q-A).** O RIPD é exigido antes do estudo de impacto. No lançamento, a superfície de dados é o `docs/dados-do-usuario.md`, a confirmar com o encarregado (F-11).
- **DC-B (Q-B).** O antigo critério de saída vira o critério de promoção para produção (Decisão 3g). Os ADR-007, 008 e 009 recebem Revisões que apontam para ele.
- **DC-C (Q-C).** Variante **C1+C2**: QA interno e as mitigações de linguagem desde já, mais a validação de produto condicionada à manifestação escrita do CEP/UFRR (F-20 d). Decidida pelo dono do projeto em 2026-11-09, na revisão do plano de implementação.
- **DC-D (Q-D).** Os testadores do teste fechado da Play são QA do lançamento: equipe, bolsistas e alunos, sem coleta. O mínimo de testadores e de dias é lido no Play Console na data. Se faltar gente interna, a decisão volta à coordenação.
- **DC-E (Q-E).** A titularidade do registro do software fica aberta (F-21), e a resposta sobre o vínculo institucional (Decisão 4, pré-condição) deve resolvê-la junto.

**Alternativas descartadas.**
- **Manter publicação e estudo juntos.** O CEP ficaria no caminho da publicação de um app que não coleta nada: semanas a meses de tramitação sem nenhuma proteção a mais para quem usa o app. E o "se houver coleta" continuaria ambíguo, sugerindo que o app é a fonte dos dados.
- **Remover o CEP de vez.** O estudo observa e entrevista pessoas de populações vulneráveis expostas a orientação de saúde, e o projeto o trata como pesquisa com seres humanos: é a posição conservadora diante da definição da Lei 14.874/2024 (art. 2º, XXXIV), a confirmar na consulta prévia (F-20 a). Sem o parecer, os resultados não são publicáveis, e o CEP não aprova retroativamente.

**Custos aceitos.**
1. As mitigações da Decisão 3f medem a linguagem, não a compreensão. A validação de produto, se o CEP a aceitar, itera a interface, mas não produz evidência publicável. Em qualquer caso, a evidência de compreensão por quem tem baixo letramento (H1, H1b; risco R2, crítico) só vem do estudo de impacto, depois da publicação.
2. A fronteira exige disciplina: toda observação precisa de data e de origem (lançamento ou estudo).
3. Ficam duas listas de aprovação para manter ([`docs/aprovacoes.md`](../docs/aprovacoes.md)).
4. Se a hipótese de trabalho da Decisão 4 não se confirmar (a UFRR como proponente de um estudo de docente da casa), a Parte B passa a depender da formalização da cooperação (ADR-005, Decisão 1).

**Relação com outros ADRs.** Prevalece sobre o ADR-005, Decisão 7, sobre os gatilhos do ADR-004 e sobre as menções ao estudo nos ADR-006 a 009. Cada um recebe uma Revisão 2026-11-09 que aponta para cá.

**Revisão.** Reabrir se:
- a consulta prévia ao CEP/UFRR (F-20) entender que o lançamento também precisa de protocolo;
- a UFRR não puder ser a proponente e não houver outra instituição;
- a coordenação do PET-Saúde/Telessaúde não aceitar a regra de fronteira (Decisão 5) ou o cronograma da Parte B;
- sair o regulamento do art. 63 da Lei 14.874/2024;
- surgir proposta de telemetria.

## 11. Para o Sponsor — Por que um app "100% offline" ainda precisa de serviços web?

> Seção não técnica, para apresentação a patrocinadores, parceiros de pesquisa e à coordenação do projeto. Explica em linguagem simples o papel da infraestrutura dos §§1.2–7.

O Guia UBS é um projeto educativo de código aberto do Grupo de Pesquisa PRISM (UFRR), em cooperação com o PET-Saúde ([ADR-005](#10-registro-de-decisões-arquiteturais-adr)). Ele ensina, no próprio celular e sem internet, como funcionam o SUS e a Atenção Primária, quais são os direitos e documentos de quem procura atendimento e quais sinais de alerta pedem ajuda urgente — e, como apoio, diz que tipo de serviço procurar. O app não fala por nenhuma unidade de saúde, secretaria ou ministério. Então é justo perguntar: **para que pagar por qualquer coisa na internet?** A resposta curta: o celular não precisa dos serviços web para *funcionar*, mas o projeto precisa deles para o conteúdo **nascer, ser confiável e chegar até os celulares**. São três papéis:

### 11.1 A "redação" — onde o conteúdo educativo é escrito e revisado

O conteúdo é escrito pela equipe do projeto: o que é a Atenção Primária, quais documentos levar, como funciona o calendário vacinal, que sinais de alerta não podem esperar. Ele é melhorado aos poucos — uma explicação mais clara, uma tradução para o espanhol, um tema novo. Cada mudança precisa de um lugar para ser **editada e, antes de ir ao ar, aprovada por um profissional de saúde colaborador do projeto** — essa dupla checagem é uma trava de segurança: nenhuma orientação chega à população sem revisão clínica.

Esse lugar é o painel web (o CMS, §1.2). Sem ele, cada correção dependeria de lançar uma versão nova do app inteiro.

### 11.2 O "carimbo" — a garantia de que ninguém falsifica o conteúdo

Antes de ser distribuído, todo pacote de conteúdo recebe uma **assinatura digital** (§4.2) — pense num carimbo impossível de falsificar. O celular confere o carimbo e **recusa qualquer conteúdo que não tenha saído da revisão do projeto**. Isso protege a população contra alguém mal-intencionado tentando espalhar orientação de saúde falsa em nome do app.

### 11.3 O "correio" — a estante de onde os celulares pegam as atualizações

Quando um celular da zona rural passa perto de um Wi-Fi (da escola, do centro comunitário), ele aproveita aqueles segundos para baixar, sozinho e em silêncio, a atualização — poucos kilobytes. Do outro lado precisa existir uma "estante" na internet com esses arquivos disponíveis 24h (MinIO + Caddy, §4.2). É só isso que esse servidor faz: entregar arquivos prontos.

Detalhe importante: **se esse servidor cair, nenhum usuário percebe** — o app continua funcionando normalmente com o conteúdo que já tem; a atualização apenas chega um pouco depois. O servidor nunca é ponto de falha para quem está na ponta.

O app em si chega às pessoas pelo **Google Play** e pelo **GitHub Releases**, onde qualquer um pode conferir que o arquivo é o que o projeto publicou ([ADR-006](#10-registro-de-decisões-arquiteturais-adr)).

### 11.4 O que isso custa

Como o app não conversa com servidor durante o uso (a inteligência artificial roda no próprio celular), **o custo não cresce com o número de usuários**: atender 500 pessoas ou 50 mil custa praticamente o mesmo. Após a auditoria do §9, toda a infraestrutura roda em **um único servidor alugado (VPS), mantido pelo PRISM, com software 100% gratuito e de código aberto** ([ADR-007](#10-registro-de-decisões-arquiteturais-adr)) — essa é, com a cópia de segurança fora dele, a única fatura recorrente do projeto. Sem mensalidade por usuário, sem licenças, sem serviços de nuvem caros. Nada disso depende da infraestrutura de uma unidade de saúde ou da universidade.

De quebra, hospedando esse servidor em datacenter no Brasil, os dados administrativos ficam em território nacional — o que simplifica a conformidade com a LGPD ([lgpd.md](lgpd.md) RF06).

### 11.5 Resumo em uma frase

> O celular carrega a cartilha de saúde; os serviços web são a **redação que escreve, o carimbo que autentica e o correio que entrega** cada versão revisada — por um custo fixo pequeno, que não aumenta com o sucesso do projeto.
