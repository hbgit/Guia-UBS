# Guia UBS — Minimum Viable Tech Stack (MVTS)

> Premissa arquitetural: este sistema tem **duas metades assimétricas**. O produto real roda 100% no device (Flutter + SLM local + SQLite). A "nuvem" é apenas um **plano de controle de conteúdo**: um CMS mínimo que compila e assina pacotes de conteúdo versionados, servidos como arquivos estáticos via CDN. Não existe caminho de request usuário→servidor em runtime. Toda decisão abaixo deriva dessa assimetria — e é ela que garante o TTM e a escalabilidade quase gratuita.

---

## 1. Stack Core & Runtime

### 1.1 Cliente (o produto) — Flutter / Dart 3

| Camada | Escolha | Justificativa (trade-off) |
|---|---|---|
| Framework | **Flutter (Android-first, minSdk 26)** | Único runtime que entrega UI iconográfica custom + FFI para inferência nativa + um só codebase para o futuro iOS. Alternativa React Native descartada: bridge JS penaliza FFI de inferência e TTS; Kotlin puro descartado: perde iOS e o time já tem Dart como pré-requisito. |
| Estado | **Riverpod (codegen) + freezed** | Sealed classes + exhaustive switch eliminam estados impossíveis na triagem (crítico: um estado inconsistente aqui é risco clínico). Menos boilerplate que BLoC para um app sem eventos complexos. |
| Navegação | **GoRouter** | Declarativo, deep-link-ready (v2: abrir direto no calendário vacinal via QR na UBS). |
| Inferência local | **llama.cpp via FFI (`llama_cpp_dart`) + Gemma 3 1B QAT int4 (GGUF)** | GGUF é o formato com maior liquidez de modelos e roda em qualquer SoC ARM sem depender de delegates. MediaPipe LLM Inference fica como *fallback* se o custo de manutenção do FFI apertar — API mais estável, porém formato `.task` proprietário e churn de versões do Google. |
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
│         │ packer (CI)                  │ CDN  │  swap atômico no sync        │
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

- **Ansible (GPL-3.0)** provisiona o VPS de forma reprodutível: Docker, firewall, volume criptografado (LUKS), usuário de deploy, unit systemd que roda `docker compose up -d`. Um playbook versionado no repo substitui todo o papel do SST/Railway.
- **O `docker-compose.yaml` do §7 é o artefato de deploy** — não existe distinção dev/prod além do arquivo de override com o Caddy (TLS) e os segredos reais.
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
- **Admin/CMS: Better Auth** (self-hosted, TS, roda em qualquer runtime incl. edge, sessões no próprio Turso via adapter Drizzle). Clerk/Auth0 descartados: vendor lock-in e custo por MAU para um sistema com ~dezenas de admins municipais é comprar problema. 2FA TOTP nativo — suficiente para editores de conteúdo de saúde.

### 4.2 Cache & Entrega na Edge

- **A borda atende duas superfícies, com regimes opostos** (desde o item 24): o
domínio de conteúdo entrega packs ao aparelho e recusa tudo que não seja
`GET`/`HEAD`; o domínio do CMS serve o plano de controle, que é autenticado e
escreve. Blocos separados de propósito — herdar a guarda de somente-leitura no
CMS quebraria login e aprovação.

**MinIO (AGPL-3.0) atrás de Caddy (Apache-2.0)**, self-hosted no VPS, para os content packs. Caddy dá TLS automático (Let's Encrypt, gratuito) e cache de estáticos; MinIO dá a API S3 que o packer consome. Trade-off assumido ao remover a CDN comercial: perde-se capilaridade global — aceitável porque manifest e deltas são KB-scale e **qualquer servidor estático vira espelho** (nginx/Caddy + rsync, inclusive servidores municipais federados), sem nenhuma mudança no app.
- Estratégia de cache em duas classes:
  - **Packs e áudios**: nomeados por hash de conteúdo (`pack-a1b2c3.db`), `Cache-Control: public, max-age=31536000, immutable` — cache infinito, invalidação impossível por construção.
  - **`manifest.json`**: `max-age=60` + ETag — único objeto mutável; o device faz um GET condicional barato e só baixa o resto se a versão mudou.
- Assinatura **Ed25519 do manifest + hash dos artefatos** (chave pública embarcada no app): o servidor de conteúdo e qualquer espelho são infraestrutura não-confiável; o device verifica tudo. Isso torna os espelhos triviais de operar (não precisam ser confiáveis) e habilita distribuição sneakernet (APK + pack via Bluetooth/SD) com a mesma garantia de integridade.

---

## 5. Escalabilidade (10x–50x sem rearquitetura)

| Componente | Carga 50x | Ação necessária |
|---|---|---|
| Entrega de packs (MinIO+Caddy) | Estático + cache imutável | Adicionar espelhos estáticos (rsync) quando a banda do VPS saturar |
| Inferência | Roda no device do usuário | Nenhuma — escala com a base instalada (custo marginal ~0) |
| CMS (VPS/compose) | Tráfego interno (admins) | Upgrade vertical do VPS; irrelevante para usuários finais |
| `sqld` (self-host) | Leitura só pelo packer/CMS | Já é self-host; réplica de leitura opcional em segundo container |

O único caminho quente (download de pack em campanha de vacinação nacional) é arquivo estático cacheável e assinado — espelhável em qualquer servidor, de VPS comercial a máquina de secretaria municipal.

---

## 6. Análise de Risco — O Elo Mais Fraco

**`llama_cpp_dart` (binding FFI de inferência no device).** Não é um vendor SaaS, e é exatamente por isso que é o risco subestimado:

- **Vendor lock-in (invertido):** o risco não é aprisionamento comercial, é **abandono de manutenção** — binding FFI de nicho, mantido por poucos, acoplado ao ritmo agressivo de breaking changes do llama.cpp upstream e ao NDK/ABI do Android. Um `pub upgrade` pode quebrar inferência em produção num device que você não tem no lab.
- **Custo de longo prazo:** não é fatura de cloud — é **custo de engenharia recorrente**: recompilar `.so` para arm64/armv7, testar em matriz de SoCs de entrada, perseguir regressões de quantização. É o único componente da stack sem free tier de manutenção alheia.
- **Migração futura:** média-alta. A mitigação está desenhada desde o dia 1: **isolar a inferência atrás de uma interface Dart única (`TriageEngine`)** com três implementações possíveis — llama.cpp FFI (default), MediaPipe LLM (fallback Google-supported), e **regras puras sem LLM** (kill switch: o app degrada para triagem 100% determinística e continua clinicamente seguro). O modelo em GGUF preserva liquidez de formato.

Menção honrosa: **banda e disponibilidade do VPS único** — sem CDN comercial, o servidor de conteúdo é o gargalo de distribuição e um ponto único de indisponibilidade. Mitigação barata e já desenhada: espelhos estáticos por rsync (federáveis com servidores municipais — a assinatura Ed25519 dispensa confiança no espelho), e o app tolera indisponibilidade por design (BASE: a frota apenas converge mais devagar, nunca para de funcionar).

---

## 7. `docker-compose.yaml` de Síntese

Este compose **é** a topologia de produção (não um stand-in): master DB `sqld`, CMS, MinIO como storage de packs, Caddy como edge TLS/cache e o job de empacotamento. Em dev, o app Flutter roda no host/emulador apontando para o MinIO local; o CI de build do APK usa a imagem `ghcr.io/cirruslabs/flutter` (mesmo princípio Docker-first, pipeline separado).

```yaml
services:
  db:
    image: ghcr.io/tursodatabase/libsql-server:latest
    ports:
      - "127.0.0.1:8080:8080"          # http (driver libsql)
    volumes:
      - dbdata:/var/lib/sqld
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:8080/health || exit 1"]
      interval: 5s
      timeout: 3s
      retries: 5

  cms:
    build:
      context: ./cms
      target: dev                       # multi-stage: deps → dev → build → production
    ports:
      - "3000:3000"
    environment:
      - DATABASE_URL=http://db:8080
      - S3_ENDPOINT=http://storage:9000
      - S3_BUCKET=content-packs
      - BETTER_AUTH_SECRET=${BETTER_AUTH_SECRET:?set in .env}
      - PACK_SIGNING_KEY=${PACK_SIGNING_KEY:?set in .env}   # Ed25519 privada (dev key)
    volumes:
      - ./cms:/app
      - /app/node_modules
    depends_on:
      db:
        condition: service_healthy
      storage:
        condition: service_started
    security_opt:
      - no-new-privileges:true

  storage:                              # storage de packs (dev e produção)
    image: minio/minio:RELEASE.2025-06-13T11-33-47Z
    command: server /data --console-address ":9001"
    ports:
      - "127.0.0.1:9000:9000"
      - "127.0.0.1:9001:9001"
    environment:
      MINIO_ROOT_USER: dev
      MINIO_ROOT_PASSWORD: dev-secret
    volumes:
      - s3data:/data

  edge:                                 # produção: TLS automático + cache de estáticos
    image: caddy:2.8-alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddydata:/data
    depends_on:
      - storage
      - cms

  packer:                               # one-shot: compila e assina o content pack
    build:
      context: ./packer
    profiles: ["tools"]                 # roda sob demanda: docker compose run --rm packer
    environment:
      - DATABASE_URL=http://db:8080
      - S3_ENDPOINT=http://storage:9000
      - PACK_SIGNING_KEY=${PACK_SIGNING_KEY:?set in .env}
    depends_on:
      db:
        condition: service_healthy

volumes:
  dbdata:
  s3data:
  caddydata:
```

```bash
docker compose up -d                      # sobe plano de controle
docker compose run --rm packer            # gera + assina + publica content-pack
```

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

- **Modelo (Gemma 3 1B):** gratuito, mas *open weights* sob termos Google — **não é OSI**. Alternativas OSI-licenciadas de tamanho equivalente, compatíveis com o mesmo pipeline GGUF: **Qwen2.5 0.5B/1.5B (Apache-2.0)** e **Phi-3.5-mini (MIT)**. A troca é um arquivo — a interface `TriageEngine` e o eval harness clínico decidem por benchmark, não por ideologia.
- **TTS:** o engine do sistema (Google TTS) é proprietário, embora gratuito e on-device. Opção 100% OSS que também mitiga o risco R7 (ROMs sem engine): **Piper (MIT) via sherpa-onnx**, com vozes pt-BR/es embarcadas (~20 MB/voz). Default continua `flutter_tts` (zero MB); Piper entra como fallback empacotável.
- **CI:** GitHub Actions é serviço (gratuito para repositório público). Alternativas self-host quando desejado: **Woodpecker CI (Apache-2.0)** ou **Forgejo Actions (MIT)** no mesmo VPS.
- **Distribuição:** Play Store cobra taxa única de publicação. Canais OSS-friendly já previstos: **F-Droid** (gratuito, exige build reprodutível — bônus de transparência para um app de saúde pública) e APK direto via sneakernet. O **packer** já é reprodutível sob `SOURCE_DATE_EPOCH` (mesma convenção do F-Droid): duas builds do mesmo conteúdo produzem `content.db` byte-idêntico, o que além da transparência evita que a frota re-baixe o pack a cada republicação sem mudança.

**Custo remanescente honesto:** open source elimina licenças e SaaS, não hardware — resta o VPS (único item de fatura recorrente da stack inteira) e, opcionalmente, a taxa única da Play Store. Tudo o mais roda com custo marginal zero.

---

## 10. Registro de Decisões Arquiteturais (ADR)

### ADR-001 — Vercel como plataforma de deploy: **REJEITADO** (2026-08-13)

**Contexto:** avaliou-se o Vercel como alternativa de deploy para o plano de controle e/ou a entrega de conteúdo.

**Decisão:** manter o deploy self-hosted (Compose + Ansible em VPS nacional, §3.2/§7). Vercel rejeitado.

**Fundamentos (vinculados aos requisitos deste projeto):**

1. **Perfil de carga invertido:** o Vercel otimiza frontend serverless com requisições dinâmicas na edge; este projeto tem zero requisição dinâmica de usuário — o caminho quente é download de binário estático assinado (HTTP Range para retomada), caso de uso de object storage, não de plataforma de frontend.
2. **Docker-first violado:** requisito desta MVTS ("stack reprodutível via Dockerfile/Compose"); Vercel não executa containers arbitrários — o compose do §7, que é a topologia de produção, seria descartado.
3. **Fragmentação da stack:** o CMS depende de `sqld` e MinIO, que o Vercel não hospeda — migrar exigiria recontratar banco gerenciado e storage externos, revertendo a auditoria do §9.
4. **Segurança (SPOF R4):** o packer assina packs com a chave Ed25519; executá-lo em functions de terceiro colocaria o segredo mais crítico do modelo de ameaças sob custódia de SaaS, contra a política "cofre offline/HSM, assinatura só no CI". Timeout de 60 s em functions também é inadequado ao job.
5. **Custo/termos:** o tier Hobby proíbe uso comercial/institucional — operação para prefeituras exigiria plano pago, conflitando com a decisão de stack 100% OSS (§9); banda de 100 GB/mês é insuficiente para campanhas de vacinação (milhares de devices × packs de MB).
6. **LGPD:** reintroduziria operador estrangeiro e transferência internacional (arts. 33–36), revertendo a postura do [lgpd.md](lgpd.md) RF06 (datacenter no Brasil).

**Exceção reconhecida:** hospedar um eventual site institucional estático — mesmo assim, o Caddy do VPS já cobre sem novo operador.

**Revisão:** reavaliar somente se o projeto ganhar superfície web dinâmica voltada ao público (o que hoje contraria a arquitetura offline-first).

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


### ADR-004 — Gemma 3 1B no caso de uso do Guia UBS e redistribuição pelo storage próprio: **PROPOSTO** (2026-10-29)

**Contexto.** O app baixa o modelo de `huggingface.co/ggml-org/gemma-3-1b-it-GGUF` (`app/lib/sync/model_catalog.dart`), o que contraria três decisões: a §9 (100% self-host), o [PRD §4.1](PRD.md) e a [LGPD-RT11/RF17](lgpd.md) (lista fixa de endpoints). Servir o `.gguf` do storage próprio é *Distribution* pela §1.1(b) dos Gemma Terms of Use, e o Gemma 3 consta do Appendix desses termos, que valem *"regardless of the source that you obtained it from"* (§1.1(c)).

Textos lidos em **2026-10-29**, em duas cópias cada:

| Documento | URLs | "Last modified" |
|---|---|---|
| Gemma Terms of Use | `gemma.ai/resources/terms` e `ai.google.dev/gemma/terms` | April 1, 2026 (as duas) |
| Gemma Prohibited Use Policy | `gemma.ai/resources/prohibited-use/` e `ai.google.dev/gemma/prohibited_use_policy` | February 21, 2024 (as duas) |

As páginas de `ai.google.dev` exibem *"This documentation is deprecated. Please visit the new documentation at gemma.ai."*, e as duas versões dos termos pedem frases de Notice diferentes na §3.1(4) (ver D-A).

**Enquadramento do projeto.** O Guia UBS é um projeto open source de pesquisa e extensão do grupo de pesquisa PRISM. O ambiente de produção é do próprio grupo, não há vínculo formal com a UFRR, e colaboradores do curso de Medicina apoiam a revisão clínica. Nesta fase **não há parecer jurídico formal**: a licença do modelo é cumprida por obrigação, e as perguntas que pediriam parecer viram regras de produto e implementação, com gatilhos para revisitar a parte formal.

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
  - aparelhos que baixaram do Hugging Face → são de desenvolvimento, e **todo aparelho do piloto é provisionado do zero a partir do storage próprio**;
  - repasse do `.gguf` por pendrive → tratado como distribuição: o Notice aparece no fluxo de importação do app, e o Notice e as cópias dos termos acompanham o arquivo.

**Responsável (decisão consciente).** Os termos de uso do app identificam o responsável como "Guia UBS, projeto de pesquisa e extensão desenvolvido pelo grupo de pesquisa PRISM", com o e-mail compartilhado do projeto (`prismufrr@gmail.com`). Um grupo de pesquisa não tem personalidade jurídica: a linha **identifica** quem mantém o app, mas não cria uma parte que assina contrato. Para uma iniciativa educacional open source nesta fase, é escolha razoável e comum. O projeto responde pelo app que ele distribui; quem compilar e distribuir a própria versão a partir do código responde por ela, inclusive pelos termos do modelo que embarcar (frase também no README).

**Logo do Telessaúde UFRR e e-mail com "ufrr" (ficam).** Papel do PET Telessaúde UFRR, nas palavras do dono do projeto: *"O PET Telessaúde UFRR atuou no diagnóstico da necessidade social e no desenvolvimento de uma solução direcionada à comunidade, articulando ações entre docentes e monitores discentes."* Daí, o logo na tela "Sobre" está sob "Realização", isto é, como crédito por essa participação, e não como aval nem como responsabilidade institucional pelo app distribuído. A participação de um programa não é vínculo formal da universidade com o app, que não existe. A mesma tela traz o aviso de que o conteúdo ainda não passou por revisão clínica, que existe para impedir a leitura de logotipo como endosso; nenhum texto do app ou dos termos afirma vínculo institucional, e um teste impede que algum passe a afirmar; o responsável declarado é o grupo PRISM. Se a UFRR ou o PET pedirem a retirada, ou se surgir vínculo formal, o logo e o e-mail são revistos.

**Decisões (2026-10-29).**
- **D-A — Notice com as duas frases.** O arquivo traz, literais e nesta ordem: *"Gemma is provided under and subject to the Gemma Terms of Use found at gemma.ai/resources/terms"* e *"Gemma is provided under and subject to the Gemma Terms of Use found at ai.google.dev/gemma/terms"*. As duas versões têm a mesma data e não há como saber qual o Google trata como canônica; repetir cumpre as duas.
- **D-B — aviso de modificação.** O Notice acrescenta, em inglês, que o arquivo não é o original do Google, que foi convertido e quantizado pela `ggml-org` a partir de `google/gemma-3-1b-it` (com a URL do repositório), que o Guia UBS o redistribui sem outra modificação, e o SHA-256.
- **D-C — notificação e aceite.** A cláusula com as restrições da §3.2 e a Política entra em `app/assets/legal/termos_{pt,es}.md` (nova versão datada). O "li e concordo" vale a cada versão; o Notice e o acesso aos termos aparecem também nos dois pontos de distribuição do onboarding (download e importação por pendrive) e na tela "Sobre".
- **Documentos.** Cópia integral e literal, em inglês, dos termos e da Política (a §3.1(2) pede *"a copy of this Agreement"*); tradução de cortesia só da Política, em pt e es; resumo em linguagem simples dos termos, em pt e es. Toda cortesia diz que prevalece o inglês. (Mudança de escopo registrada na #3.)
- **Origem e espelho.** Bucket `content-packs`, chave `models/gemma-3-1b-it-Q4_K_M-<sha256>.gguf`, servida pelo site de conteúdo do edge (só GET/HEAD), com o Notice e as cópias ao lado. O SHA-256 continua versionado no app (`8ccc5cd1…a135`): a identidade do modelo no aparelho é o hash e o nome do arquivo, não a URL, e um modelo já verificado não é baixado de novo quando a URL muda. A URL entra no build por `--dart-define=MODEL_URL`, sem valor padrão. Quem operar espelho federado redistribui o Gemma e fica sujeito à §3.1; o script de publicação envia os arquivos juntos.

**Alternativa de licença: Gemma 4 (Apache 2.0) — registrada, não perseguida.** O Gemma 4 é distribuído sob Apache 2.0 (`gemma.ai/resources/apache-2/`) e não consta do Appendix dos Gemma Terms of Use; trocar eliminaria a Política, a cláusula e o Notice do Gemma (a §4 da Apache ainda pede cópia da licença e aviso em arquivo modificado, bem mais leves). Conferido em 2026-10-29: são cinco modelos (E2B, E4B, 12B, 26B-A4B e 31B), e o menor quantizado publicado do E2B tem **2,84 GB** (`gemma-4-E2B-it-Q4_0.gguf`, `ggml-org`; o QAT Q4_0 do Google tem 3,35 GB), 2,4 vezes o teto de 1,2 GB do ADR-003. Também exigiria subir o llama.cpp da tag `b6100` (ADR-002), anterior ao Gemma 4. **Decisão:** não reabrir o ADR-003 por isso; a #18 continua mirando modelos de ~1 B de parâmetros com licença OSI. Reavaliar se surgir quantizado do Gemma 4 dentro do orçamento.

**Desfecho desfavorável.** Se este ADR for rejeitado: ficam o `MODEL_URL` sem host no código, o estado "não configurado" e a infraestrutura de publicação e conferência do objeto (independentes de modelo), e o "li e concordo" por versão dos termos, que vale para qualquer mudança deles. Saem o Notice, as cópias, a cláusula do Gemma e a publicação do arquivo. Como a Política restringe **uso**, e não só distribuição, baixar o Gemma do Hugging Face também deixaria de ser opção: builds de piloto sairiam sem `MODEL_URL`, com orientação pelo `RuleOnlyEngine`, até a troca de modelo — que vira issue P0, com a #18 deixando de ser contingência.

**Gatilhos para revisitar a parte formal** (qualquer um reabre este ADR, com parecer jurídico e entidade com personalidade jurídica como responsável): publicar o app em loja; parceria formal com Secretaria de Saúde ou UBS; crescer além do piloto; coletar dados de participantes para publicação — este último é ética em pesquisa: avaliar o uso com pessoas passa antes por Comitê de Ética em Pesquisa.

**Revisão.** Reabrir também se os termos ou a Política mudarem (a data de "Last modified" é conferida a cada troca de modelo), quando a #47 mudar o papel do modelo, ou se a alternativa Gemma 4 passar a caber no orçamento.

---

## 11. Para o Sponsor — Por que um app "100% offline" ainda precisa de serviços web?

> Seção não técnica, para apresentação a patrocinadores e gestores. Explica em linguagem simples o papel da infraestrutura dos §§1.2–7.

O Guia UBS funciona inteiro no celular, sem internet — a triagem, a voz, as orientações. Então é justo perguntar: **para que pagar por qualquer coisa na internet?** A resposta curta: o celular não precisa dos serviços web para *funcionar*, mas o projeto precisa deles para o conteúdo **nascer, ser confiável e chegar até os celulares**. São três papéis:

### 11.1 A "redação" — onde o conteúdo de saúde é escrito e aprovado

Horários da UBS mudam. Campanhas de vacinação começam e terminam. Remédios entram e saem da farmácia básica. Alguém da equipe de saúde precisa de um lugar para **editar essas informações, e um profissional de saúde precisa aprová-las antes de irem ao ar** — essa dupla checagem é uma trava de segurança do projeto: nenhuma orientação chega à população sem revisão clínica.

Esse lugar é o painel web (o CMS, §1.2). Sem ele, o app nasceria com informação congelada e estaria desatualizado — e, em saúde, desatualizado é perigoso.

### 11.2 O "carimbo oficial" — a garantia de que ninguém falsifica orientação de saúde

Antes de ser distribuído, todo pacote de conteúdo recebe uma **assinatura digital** (§4.2) — pense num carimbo impossível de falsificar. O celular confere o carimbo e **recusa qualquer conteúdo que não seja oficial**. Isso protege a população contra alguém mal-intencionado tentando espalhar orientação de saúde falsa pelo nosso canal.

### 11.3 O "correio" — a estante de onde os celulares pegam as atualizações

Quando um celular da zona rural passa perto de um Wi-Fi (da escola, do centro comunitário), ele aproveita aqueles segundos para baixar, sozinho e em silêncio, a atualização — poucos kilobytes. Do outro lado precisa existir uma "estante" na internet com esses arquivos disponíveis 24h (MinIO + Caddy, §4.2). É só isso que esse servidor faz: entregar arquivos prontos.

Detalhe importante: **se esse servidor cair, nenhum usuário percebe** — o app continua funcionando normalmente com o conteúdo que já tem; a atualização apenas chega um pouco depois. O servidor nunca é ponto de falha para quem está na ponta.

### 11.4 O que isso custa

Como o app não conversa com servidor durante o uso (a inteligência artificial roda no próprio celular), **o custo não cresce com o número de usuários**: atender 500 pessoas ou 50 mil custa praticamente o mesmo. Após a auditoria do §9, toda a infraestrutura roda em **um único servidor alugado (VPS), com software 100% gratuito e de código aberto** — essa é a única fatura recorrente do projeto. Sem mensalidade por usuário, sem licenças, sem serviços de nuvem caros.

De quebra, hospedando esse servidor em datacenter no Brasil, os dados administrativos ficam em território nacional — o que simplifica a conformidade com a LGPD ([lgpd.md](lgpd.md) RF06).

### 11.5 Resumo em uma frase

> O celular carrega o agente de saúde; os serviços web são a **redação que escreve, o carimbo que autentica e o correio que entrega** a cartilha atualizada — por um custo fixo pequeno, que não aumenta com o sucesso do projeto.
