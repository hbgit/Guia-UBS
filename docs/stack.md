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
┌─ Turso/libSQL (master DB, serverless) ─┐      ┌─ Device ─────────────────────┐
│  CMS escreve via Drizzle               │      │  content.db (SQLite, RO)     │
│         │ packer (CI)                  │ CDN  │  swap atômico no sync        │
│         ▼                              │─────▶│  user.db (Drift, RW local)   │
│  content-pack vX.Y (SQLite file +      │      │  rules.json + modelo GGUF    │
│  áudios Opus + manifest assinado)      │      └──────────────────────────────┘
└────────────────────────────────────────┘
```

- **Servidor: Turso (libSQL serverless)** — free tier estável, réplicas de leitura, e o mesmo dialeto SQLite do device: o *packer* materializa o content pack sem camada de tradução de dialeto. Alternativa Neon (Postgres) descartada na v1: introduz um segundo dialeto e um ETL packer→SQLite que é puro custo.
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

### 3.2 IaC — SST v3 (engine Pulumi) sobre Cloudflare + Railway

- **SST v3** em TS: mesma linguagem do backend, tipado, e abstrai sem esconder — qualquer recurso desce para o provider Pulumi bruto quando necessário. Gerencia: bucket R2, DNS/CDN, secrets.
- **Railway** para o container do CMS: deploy direto do `Dockerfile`, sem YAML de orquestração. O CMS é interno e de baixo tráfego — Kubernetes aqui seria autoflagelo.
- Escape hatch comprovado localmente: o `docker-compose` (§7) sobe a stack inteira com `sqld` + MinIO — a paridade dev/prod é estrutural, não aspiracional.

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

- **Cloudflare R2 + CDN** para os content packs. Egress zero do R2 é decisivo: o produto é 99% download de arquivos.
- Estratégia de cache em duas classes:
  - **Packs e áudios**: nomeados por hash de conteúdo (`pack-a1b2c3.db`), `Cache-Control: public, max-age=31536000, immutable` — cache infinito, invalidação impossível por construção.
  - **`manifest.json`**: `max-age=60` + ETag — único objeto mutável; o device faz um GET condicional barato e só baixa o resto se a versão mudou.
- Assinatura **Ed25519 do manifest + hash dos artefatos** (chave pública embarcada no app): a CDN é infraestrutura não-confiável; o device verifica tudo. Isso também habilita distribuição sneakernet (APK + pack via Bluetooth/SD) com a mesma garantia de integridade.

---

## 5. Escalabilidade (10x–50x sem rearquitetura)

| Componente | Carga 50x | Ação necessária |
|---|---|---|
| Entrega de packs (R2+CDN) | Estático + cache imutável | Nenhuma — CDN absorve por design |
| Inferência | Roda no device do usuário | Nenhuma — escala com a base instalada (custo marginal ~0) |
| CMS (Railway) | Tráfego interno (admins) | Upgrade vertical do container; irrelevante para usuários finais |
| Turso | Leitura só pelo packer/CMS | Réplicas de leitura no plano pago; ou self-host `sqld` |

O único caminho quente (download de pack em campanha de vacinação nacional) já nasce no componente mais escalável da internet: arquivo estático atrás de CDN.

---

## 6. Análise de Risco — O Elo Mais Fraco

**`llama_cpp_dart` (binding FFI de inferência no device).** Não é um vendor SaaS, e é exatamente por isso que é o risco subestimado:

- **Vendor lock-in (invertido):** o risco não é aprisionamento comercial, é **abandono de manutenção** — binding FFI de nicho, mantido por poucos, acoplado ao ritmo agressivo de breaking changes do llama.cpp upstream e ao NDK/ABI do Android. Um `pub upgrade` pode quebrar inferência em produção num device que você não tem no lab.
- **Custo de longo prazo:** não é fatura de cloud — é **custo de engenharia recorrente**: recompilar `.so` para arm64/armv7, testar em matriz de SoCs de entrada, perseguir regressões de quantização. É o único componente da stack sem free tier de manutenção alheia.
- **Migração futura:** média-alta. A mitigação está desenhada desde o dia 1: **isolar a inferência atrás de uma interface Dart única (`TriageEngine`)** com três implementações possíveis — llama.cpp FFI (default), MediaPipe LLM (fallback Google-supported), e **regras puras sem LLM** (kill switch: o app degrada para triagem 100% determinística e continua clinicamente seguro). O modelo em GGUF preserva liquidez de formato.

Menção honrosa: **Turso** pós-free-tier — mas o lock-in real é baixo (é SQLite; `sqld` é self-hostável no mesmo compose abaixo; Drizzle abstrai o driver). Sair custa uma tarde, não um trimestre.

---

## 7. `docker-compose.yaml` de Síntese

Reproduz o plano de controle completo local: master DB (`sqld` = Turso self-host), CMS, storage S3-compatível (stand-in do R2) e o job de empacotamento. O app Flutter roda no host/emulador apontando para o MinIO; o CI de build do APK usa a imagem `ghcr.io/cirruslabs/flutter` (mesmo princípio Docker-first, pipeline separado).

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

  storage:                              # stand-in local do Cloudflare R2
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
| DB master | Turso/libSQL + Drizzle | Fonte de verdade; mesmo dialeto do device |
| API/CMS | Hono + Zod + React SPA, Node 22 | Plano de controle de conteúdo |
| Type safety | Drizzle → Zod → JSON Schema → Dart (freezed) em CI | Schema muda ⇒ build Flutter quebra |
| Auth | Better Auth (admins only); usuário final sem auth | Sem PII, sem lock-in |
| Entrega | Cloudflare R2 + CDN, packs imutáveis + manifest ETag, Ed25519 | Egress zero, sneakernet-safe |
| IaC/Deploy | SST v3 (Cloudflare) + Railway (container CMS) | TS de ponta a ponta, Docker-first |
