# Guia UBS — Diretrizes de Implantação

> **Natureza deste documento.** É **normativo**: diz o que precisa existir para publicar o APK e operar o plano de controle, em que ordem, e como se verifica que existe. Fica **abaixo do [stack.md](stack.md)** na hierarquia documental ([PRD.md](PRD.md) > [espec.md](espec.md) > [stack.md](stack.md) > este documento). Ele **não toma decisão nova**: transforma em diretriz operacional as decisões do [ADR-001](stack.md#10-registro-de-decisões-arquiteturais-adr) (com a Revisão 2026-11-02) e dos [ADR-005 a ADR-009](stack.md#10-registro-de-decisões-arquiteturais-adr). Cada seção cita o ADR de origem. **Em conflito, vale o ADR**, e este documento é que está errado.
>
> **Normativo, não procedimento.** O pipeline de release (`app-release.yml`), o `signingConfig` de release, o playbook Ansible, o backup e o monitoramento **ainda não existem**. Quando o código de cada um existir, o procedimento operacional (comandos que rodam de fato) vai para [docs/operacao.md](../docs/operacao.md), que é derivado do código. Até lá, nenhum comando daqui deve ser lido como "já funciona".
>
> **Marcadores.** `[a definir — F-n]` aponta pergunta aberta de classe M (bloqueia só o item de implementação; respostas operacionais ficam no registro de decisões fora do repositório). **(P)** marca decisão provisória, com data de revisão no ADR citado. Regra do Google Play é sempre de terceiro e se confere **no Play Console na data da publicação**. Nenhuma base legal da LGPD é decidida aqui: remete-se a [lgpd.md](lgpd.md) e à revisão jurídica (T7-R do [plano de realinhamento](../docs/superpowers/plans/2026-11-02-realinhamento-institucional-implantacao.md)).

---

## 1. Princípios

| # | Princípio | Origem |
|---|---|---|
| P1 | O app é um **projeto educativo aberto** do Grupo de Pesquisa PRISM (UFRR) em cooperação com o PET-Saúde, **sem vínculo com unidades de saúde**, secretarias ou prefeituras. Nenhum passo de implantação depende de infraestrutura, aprovação ou operação delas, nem da UFRR como instituição. | [ADR-005](stack.md#10-registro-de-decisões-arquiteturais-adr), Decisões 1, 4 e 6 |
| P2 | **Dois canais oficiais**, GitHub Releases e Google Play, publicando o **mesmo build**. Repasse entre pessoas não é canal oficial. F-Droid é futuro e exige ADR próprio. | [ADR-006](stack.md#10-registro-de-decisões-arquiteturais-adr) |
| P3 | O plano de controle roda numa **VPS mantida pelo PRISM**, com `infra/compose.yaml` sem override, backup fora do host e provisionamento por Ansible. O app não depende do CMS em runtime. | [ADR-007](stack.md#10-registro-de-decisões-arquiteturais-adr) |
| P4 | Conteúdo é publicado por **edição** (`municipality` no contrato), pela equipe do projeto, sob o dual review de sempre. Não há curador municipal. | [ADR-008](stack.md#10-registro-de-decisões-arquiteturais-adr) |
| P5 | Identidade, versão e assinatura do app são fixadas **antes** da 1ª publicação na Play; o artefato testado é o artefato publicado (**promoção, não rebuild**). | [ADR-009](stack.md#10-registro-de-decisões-arquiteturais-adr) |
| P6 | A chave Ed25519 do pack **nunca** toca processo HTTP nem CI. Na VPS, só o job `packer` (sem `ports:`) a monta `:ro`; enquanto a VPS não existe, vale a exceção provisória de dois mantenedores. | [ADR-001](stack.md#10-registro-de-decisões-arquiteturais-adr), fundamento 4 e Revisão 2026-11-02 |
| P7 | Nada aqui afrouxa INV-1…INV-8, FSM-A/FSM-B, dual review clínico, Ed25519, zero PII e k ≥ 20 ([espec.md](espec.md) §5.1). | [espec.md](espec.md); [ADR-005](stack.md#10-registro-de-decisões-arquiteturais-adr), fundamento 2 |

---

## 2. APK Android

### 2.1 Identidade

- O `applicationId` definitivo é fixado **num lugar só**: o [ADR-009](stack.md#10-registro-de-decisões-arquiteturais-adr), item 1 (sufixo decidido, prefixo pendente do registro do domínio próprio do PRISM). Este documento **não o reescreve**; quem precisar do id lê o ADR.
- **Ordem obrigatória:** o id é fixado no ADR-009 **antes** da 1ª publicação na Play, porque depois dela não muda. Nenhum AAB é enviado à Play com o id de exemplo (`br.gov.exemplo.guia_ubs`).
- Mudam junto com o id, no **item 25** do roadmap: os nomes de tarefa do WorkManager (`pack_sync_scheduler.dart`, `model_sync_scheduler.dart`) e `app/tool/release_permissions.dart`.
- O título exibido é "Guia UBS" ([ADR-005](stack.md#10-registro-de-decisões-arquiteturais-adr), Decisão 5), sempre acompanhado do aviso do RF-16.

*Aceite:* o `applicationId` do `build.gradle` de release é igual ao do ADR-009, item 1, e não contém `gov` nem `exemplo`.

### 2.2 Versionamento (P — [ADR-009](stack.md#10-registro-de-decisões-arquiteturais-adr), itens 2 e 3; F-5)

- `pubspec.yaml` em SemVer `MAJOR.MINOR.PATCH`:
  - **MAJOR:** o app passa a rejeitar packs de um `schemaVersion` major antigo, ou muda o comportamento perceptível da orientação;
  - **MINOR:** funcionalidade nova;
  - **PATCH:** correção.
- **Fórmula:** `versionCode = MAJOR*10000 + MINOR*100 + PATCH`. Estritamente crescente e **único entre os canais** (o mesmo número no APK `arm64-v8a`, no APK `armeabi-v7a` e no AAB).
- **Limites:**
  - **MINOR ≤ 99** e **PATCH ≤ 99**;
  - **MAJOR ≤ 210**, porque a Play aceita `versionCode` até 2 100 000 000 (conferir no Play Console na data da publicação);
  - estourar MINOR ou PATCH exige um MAJOR novo ou a revisão da fórmula no ADR-009.
- Tag **anotada** `vX.Y.Z` em `main`. `CHANGELOG.md` na raiz, no formato Keep a Changelog.
- A versão do pack (INV-7) e o `schemaVersion` são **independentes** da versão do app.
- **`minAppBuild`** compara com esse `versionCode` único. A guarda é implementada no item 25, com teste. **Até ela existir, é proibido publicar pack que dependa de app novo**, porque nenhum aparelho o recusaria.

*Aceite:* o `versionCode` de cada artefato é igual a `MAJOR*10000 + MINOR*100 + PATCH` da tag; o build recusa MINOR ou PATCH > 99 e MAJOR > 210.

### 2.3 Modelo de promoção ([ADR-009](stack.md#10-registro-de-decisões-arquiteturais-adr), item 4; [ADR-006](stack.md#10-registro-de-decisões-arquiteturais-adr), Decisão 2)

- Uma tag produz **um** conjunto de artefatos. O que é testado é o que é publicado: mesma tag, mesmo `versionCode`, mesmo binário.
- **Play:** o AAB sobe para a faixa de teste (interno ou fechado), onde roda o estudo piloto, e é **promovido** para produção.
- **GitHub:** a release nasce marcada como ***pre-release***; na promoção, só a marca sai. APK e `SHA256SUMS` não mudam.
- **Não existe** sufixo `-rc`, PATCH reservado para pré-release nem rebuild da mesma versão. Defeito achado na faixa de teste vira um **PATCH novo** e uma nova rodada.
- Sem conta Play ([a definir — F-4]), o estudo piloto roda só pela *pre-release* do GitHub (ADR-006, Decisão 2).

*Aceite:* o SHA-256 do APK na release promovida é igual ao da *pre-release*; o AAB em produção na Play é o mesmo `versionCode` testado na faixa de teste.

### 2.4 ABIs e versão mínima (P — [ADR-009](stack.md#10-registro-de-decisões-arquiteturais-adr), item 5; F-17)

- Release com `arm64-v8a` **e** `armeabi-v7a`; `minSdk` 26.
- `armeabi-v7a` sai **sem o shim nativo** ([ADR-002](stack.md#10-registro-de-decisões-arquiteturais-adr)): a triagem roda pelo `RuleOnlyEngine` (INV-8). **Onde o shim não existe, o app não oferece nem inicia o download do modelo** — coberto por teste no item 25.
- **Um build por ABI, sem `--split-per-abi`.** Cada APK sai de um `flutter build apk --release` separado, com `--target-platform=android-arm64` ou `--target-platform=android-arm`. O `--split-per-abi` é proibido porque o plugin gradle do Flutter sobrescreve o `versionCode` (`abi*1000 + versionCode`), o que quebra o código único e colide com a fórmula da §2.2 (o motivo, com a referência ao SDK, está no ADR-009).
- O AAB usa o mesmo `versionCode` e entrega a ABI certa na Play.
- No GitHub, **dois APKs**, cada um com o seu SHA-256 em `SHA256SUMS`.
- Hoje `app/tool/build_apk.sh` fixa `android-arm64`; o item 25 o estende para as duas ABIs sem perder as guardas.

*Aceite (verificação exigida pelo ADR-009 antes de a decisão deixar de ser provisória):* cada APK contém só as `.so` da sua ABI; o `versionCode` lido por `aapt dump badging` e na tela "Sobre" é igual nos três artefatos. Se falhar, vale a alternativa registrada no ADR-009 (comparar `minAppBuild` com um número derivado do SemVer injetado por `--dart-define`).

### 2.5 Assinatura e custódia ([ADR-009](stack.md#10-registro-de-decisões-arquiteturais-adr), itens 7 e 8)

- **Keystore de release** (assina o APK do GitHub e o AAB enviado à Play): gerado **uma vez**, guardado em cofre offline com **duas custódias**, no mesmo regime da chave Ed25519.
- Nunca vai para o repositório (`app/android/.gitignore` já cobre `key.properties`, `*.keystore` e `*.jks`). O `signingConfig` de release lê `key.properties` de fora do repositório (item 25).
- No CI, entra **só** como segredo do *environment* `release`, que exige aprovação manual de um segundo mantenedor.
- **Play App Signing com chave gerada pela Google.** Consequência: o APK do GitHub e o da Play **não se atualizam um sobre o outro**. O aviso de canal (§2.8) é obrigatório na nota de release e na página do projeto.
- O keystore é uma chave **diferente** da Ed25519 do pack. A Ed25519 continua fora de CI (§3.7).

*Aceite:* nenhum arquivo de chave no histórico do repositório; o job de release só obtém o keystore depois da aprovação do *environment* `release`; a impressão SHA-256 do certificado publicada na release confere com a do APK (`apksigner verify --print-certs`).

### 2.6 Fluxo de release (item 31)

Deriva do [ADR-006](stack.md#10-registro-de-decisões-arquiteturais-adr) e do [ADR-009](stack.md#10-registro-de-decisões-arquiteturais-adr). Depende do item 25; a etapa da Play depende de [a definir — F-4].

1. **PR `develop` → `main`** com `CHANGELOG.md` atualizado e CI verde nos jobs `app`, `interop`, `shim`, `contract` e `cms`.
2. **Tag anotada `vX.Y.Z`** em `main`. O `app-release.yml` dispara e roda no *environment* `release`, que exige aprovação de um **segundo mantenedor** (diferente de quem criou a tag).
3. **Guarda de versão.** O job calcula o `versionCode` pela fórmula da §2.2, confere os limites e **reprova** se ele for ≤ o maior `versionCode` já publicado.
4. **Build**, com `config/defines.release.json` montado a partir de segredo:
   - `tool/build_apk.sh release` para cada ABI (guardas de `MODEL_URL` e `PACK_MANIFEST_URL` por `model_url_check.dart`);
   - `flutter build appbundle --release` com as mesmas guardas;
   - `dart run tool/check_release_permissions.dart` sobre o build.
5. **Artefatos:** um APK por ABI, `SHA256SUMS` e a impressão SHA-256 do certificado. **O job falha sem `SHA256SUMS`** (RF-17). O AAB **não** é anexado ao GitHub.
6. **Release no GitHub** criada como ***pre-release***, com a nota-modelo da §2.8 preenchida.
7. **AAB para a faixa de teste** (interno ou fechado) da Play. O estudo piloto roda aqui e na *pre-release*.
8. **Promoção manual**, condicionada ao checklist da §2.7 conferido e datado: o AAB passa da faixa de teste para produção na Play, e a marca *pre-release* sai no GitHub. **Sem rebuild.**
9. [docs/operacao.md](../docs/operacao.md) registra a versão publicada em cada canal.

### 2.7 Checklist da ficha no Google Play

Origem: [ADR-006](stack.md#10-registro-de-decisões-arquiteturais-adr), Decisão 6 e Custo aceito 2; [ADR-009](stack.md#10-registro-de-decisões-arquiteturais-adr), Custo aceito 4. Toda linha é regra de terceiro ou proposta, e a promoção para produção só ocorre com **todas** as datas preenchidas na mesma rodada de publicação.

- [ ] **Conta de desenvolvedor** [a definir — F-4]: tipo da conta (pessoal ou de organização, D-U-N-S) e exigência de teste fechado para conta pessoal nova (conferir no Play Console em ____-__-__).
- [ ] **`targetSdk`** dentro do mínimo vigente (conferir no Play Console em ____-__-__).
- [ ] **Tamanho do AAB** dentro do limite; o modelo SLM fica fora do pacote (conferir no Play Console em ____-__-__).
- [ ] **`versionCode`** abaixo do teto aceito pela Play, que sustenta o limite MAJOR ≤ 210 da §2.2 (conferir no Play Console em ____-__-__).
- [ ] **Política de privacidade** em URL pública [a definir — F-7], da mesma fonte e na mesma versão de `app/assets/legal/privacidade_*.md` (conferir no Play Console em ____-__-__).
- [ ] **Data safety:** proposta de declarar "nenhum dado coletado nem compartilhado pelo app", **sujeita** à revisão jurídica do tratamento de IP (T7-R; [lgpd.md](lgpd.md)). Não é decisão deste documento (conferir no Play Console em ____-__-__).
- [ ] **Declaração de app de saúde:** proposta "informação/educação em saúde, não dispositivo médico". O enquadramento RDC 657/2022 do ADR-004 é leitura a confirmar na T7-R (conferir no Play Console em ____-__-__).
- [ ] **Classificação e contato:** questionário IARC, público adulto, e-mail de contato de caixa do grupo (conferir no Play Console em ____-__-__).
- [ ] **Descrição da ficha:** segue R1–R3 do [ADR-004](stack.md#10-registro-de-decisões-arquiteturais-adr) (sem "triagem", "diagnóstico" ou "classificação de risco"), traz o aviso do RF-16 em pt e es e o link para fontes oficiais, contra a política de *Misrepresentation* (conferir no Play Console em ____-__-__).

### 2.8 Nota-modelo da release do GitHub

Modelo de **texto**, preenchido em cada release (passo 6 da §2.6). O texto do aviso educativo e de não afiliação deve ser o mesmo da chave ARB do RF-16 na versão publicada; o que vai abaixo é a forma, não a fonte. Termos proibidos por R1–R3 do ADR-004 também não entram aqui.

```markdown
# Guia UBS vX.Y.Z

## Novidades
<!-- Copiado da seção vX.Y.Z do CHANGELOG.md, em linguagem simples. -->
- ...

## Aviso
**pt:** O Guia UBS é um projeto educativo aberto do Grupo de Pesquisa PRISM
(UFRR)<, em cooperação com o PET-Saúde>. Não é serviço de saúde e não fala por
UBS, SUS, Secretaria ou Ministério. Em emergência, ligue 192.

**es:** Guia UBS es un proyecto educativo abierto del Grupo de Investigación
PRISM (UFRR)<, en cooperación con el PET-Saúde>. No es un servicio de salud y no
habla en nombre de UBS, SUS, Secretaría ni Ministerio. En emergencia, llame al 192.

## Política de privacidade
<URL pública da política, mesma versão de app/assets/legal/privacidade_*.md>

## Como conferir o arquivo
1. Baixe o APK da sua arquitetura e o `SHA256SUMS` desta página.
2. Rode `sha256sum -c SHA256SUMS --ignore-missing`; a linha do seu APK deve dizer `OK`.
3. Opcional: `apksigner verify --print-certs <apk>` deve mostrar a impressão
   SHA-256 do certificado: `<impressão>`.
APK recebido por Bluetooth, cartão ou mensagem não é canal oficial: confira o
SHA-256 contra esta página antes de instalar.

## Aviso de canal
O APK desta página e o do Google Play são assinados por chaves diferentes e não
se atualizam um sobre o outro. Troque de canal só desinstalando; seus ajustes se
perdem; nada de saúde é guardado.
```

- O trecho entre `< >` sobre o PET-Saúde só entra quando a citação ao usuário estiver liberada (F-13, ver [ADR-005](stack.md#10-registro-de-decisões-arquiteturais-adr), Revisão); até lá, sai sem ele.
- A URL da política depende do domínio do projeto ([a definir — F-7]).
- Na *pre-release*, acrescenta-se no topo que a versão está em teste no estudo piloto do projeto.

---

## 3. VPS do plano de controle

Origem: [ADR-007](stack.md#10-registro-de-decisões-arquiteturais-adr), salvo onde indicado.

### 3.1 Propriedade e requisitos mínimos (ADR-007, Decisões 1 e 2)

- A VPS é **contratada e administrada pelo PRISM**; não é da UFRR nem de unidade de saúde.
- Provedor, região, snapshot e LUKS: [a definir — F-1] (resposta no registro fora do repositório).
- **Requisitos mínimos:**
  - datacenter **no Brasil** ([ADR-001](stack.md#10-registro-de-decisões-arquiteturais-adr), fundamento 6; LGPD-RF06). Outro país só com transferência internacional registrada no RIPD e revisão do ADR-007;
  - ≥ 2 vCPU, 4 GB de RAM, disco ≥ 80 GB;
  - snapshot disponível.
- **Dois administradores**, designados por papel, para a VPS e para o domínio: [a definir — F-2].

*Aceite:* a VPS contratada atende a cada requisito acima, conferido no painel do provedor antes do item 27 ser dado como entregue.

### 3.2 Domínio e TLS (ADR-007, Decisão 4)

- Domínio próprio do PRISM, fora de `ufrr.br`, em conta do PRISM com os dois administradores da §3.1: [a definir — F-7]. O mesmo registro fecha o prefixo do `applicationId` (ADR-009, item 1).
- Dois nomes: `CONTENT_DOMAIN` (só GET/HEAD; `manifest.json` e packs) e `CMS_DOMAIN`.
- Caddy com ACME (TLS automático) e `ACME_EMAIL` de caixa do grupo, não pessoal. HSTS e CSP como hoje em `infra/Caddyfile`. `BETTER_AUTH_URL` em `https://`.
- **Só 80 e 443 públicas.** `sqld` e MinIO em `127.0.0.1`; `cms` e `packer` sem `ports:` ([stack.md](stack.md) §7).

### 3.3 Provisionamento (item 27; ADR-007, Decisões 3 e 5)

O playbook Ansible é a **fonte da verdade** da VPS (substitui a promessa de `infra/ansible/`). Ele configura, nesta ordem:

1. usuário de deploy com SSH **só por chave** e `PermitRootLogin no`;
2. firewall com 22, 80 e 443;
3. `unattended-upgrades` de segurança;
4. Docker em versão pinada;
5. LUKS, se o provedor permitir ([a definir — F-1]);
6. `infra/.env` na VPS com permissão `600`, e cópia cifrada no cofre;
7. unit systemd que sobe `docker compose -f compose.yaml up -d`, **sem** o `compose.override.yaml`, que é só de dev e tira o TLS do edge;
8. chave Ed25519 montada `:ro` **só** no `packer`.

*Aceite:* o playbook aplicado duas vezes seguidas sobre a mesma VPS não muda nada na segunda (idempotência); `ss -tlnp` na VPS mostra só 22/80/443 em interface pública; `docker compose -f compose.yaml config` na VPS não inclui o override.

**Risco residual registrado** (ADR-007, Custo aceito 1): chave Ed25519 numa VPS sem HSM. Mitigação: a segunda posição de chave já embarcada no app (rotação, `app/lib/sync/pack_signing_keys.dart`) e o runbook de revogação.

### 3.4 Atualização (ADR-007, Decisão 6)

- Imagens com **tag exata ou digest**. Hoje `caddy:2.9-alpine` (`infra/compose.yaml`) e `node:22-bookworm-slim` (`cms/Dockerfile`) são flutuantes e deixam de ser.
- Toda mudança entra por **PR com CI verde**; na VPS, `docker compose -f compose.yaml up -d --build`.
- Migração do banco master: **backup antes** (§3.5), depois `npm run cms:migrate`, depois conferência da trilha de auditoria.
- O app não depende do CMS em runtime: uma janela de manutenção atrasa a convergência da frota, nunca para o app.

### 3.5 Backup (item 28; ADR-007, Decisão 7)

- **O que é copiado, diariamente:**
  - `sqld` por dump consistente;
  - do MinIO, só o que for fonte primária;
  - o volume `caddydata`;
  - `infra/.env`.
- **Proteção:** tudo cifrado (restic ou age), com cópia **fora da VPS**. O destino é provisório (P, F-8): um segundo provedor de armazenamento de objetos, com conta do PRISM, a revisar na data do ADR-007.
- **Retenção (P, F-8):** 7 diárias, 4 semanais e 6 mensais. A retenção da trilha, dos logs e dos backups como tratamento de dado pessoal é tema da LGPD-RF07 em [lgpd.md](lgpd.md) e da T7-R; este documento não a decide.
- **Teste de restauração trimestral**, numa VPS descartável.
- **Prioridade:** banco master e trilha de auditoria, que não são reconstruíveis. Os packs são reconstruíveis pelo packer reprodutível (`SOURCE_DATE_EPOCH`).

### 3.6 Segurança e monitoramento (ADR-007, Decisão 8)

- 2FA obrigatória e rate limit do CMS como hoje.
- `fail2ban` no SSH.
- **Monitor externo** (fora da VPS) de `manifest.json` em `CONTENT_DOMAIN` e do CMS em `CMS_DOMAIN`, com alerta aos dois administradores.
- Alertas de expiração do certificado TLS e de disco acima de 80 %.
- Log do Caddy com retenção curta (P, F-10: 14 dias), sujeita também à T7-R.
- **Incidente:** o runbook da LGPD-RF12 ([lgpd.md](lgpd.md)) nomeia o PRISM como comunicante, sob o controlador ainda pendente de consulta institucional (ADR-005, Decisão 8).

### 3.7 Assinatura do pack enquanto a VPS não existe

A fonte é a **Revisão 2026-11-02 do [ADR-001](stack.md#10-registro-de-decisões-arquiteturais-adr)**; o ADR-007 (Decisão 9) aponta para ela. Em resumo:

- o pack sai pelo caminho `seed/`, sem CMS; dual review clínico, portão golden e Ed25519 continuam valendo (INV-4);
- a chave fica **fora de qualquer processo HTTP e fora de CI**;
- dois mantenedores partem da mesma tag: o **mantenedor B** (sem a chave) gera o pack sem assinar e publica o hash; o **mantenedor A** (custódia) assina com a chave trazida do cofre sem tocar disco persistente, só envia se o hash bater, e **B** confere a assinatura publicada;
- a exceção **sai** quando o item 27 entrar e o job `packer` do compose passar a assinar na VPS.

O procedimento completo, com os passos e as duas verificações prévias, **não é copiado aqui**: vale o texto do ADR-001.

---

## 4. Responsabilidades por papel

Papéis, nunca nomes. A atribuição de pessoas a papéis fica no registro de decisões fora do repositório. Uma mesma pessoa pode acumular papéis, **exceto** onde a coluna "Separação" proíbe.

| Responsabilidade | Papel | Separação obrigatória | Origem |
|---|---|---|---|
| Aprovar a release do app (*environment* `release`) | Mantenedor aprovador | Diferente de quem criou a tag | [ADR-009](stack.md#10-registro-de-decisões-arquiteturais-adr), item 8 |
| Conferir e datar o checklist da §2.7 e promover para produção | Mantenedor que publica, com a conta da Play ([a definir — F-4]) | — | [ADR-006](stack.md#10-registro-de-decisões-arquiteturais-adr), Decisão 6 |
| Criar a tag e a *pre-release* | Mantenedor que publica | — | [ADR-009](stack.md#10-registro-de-decisões-arquiteturais-adr), item 4 |
| Custodiar o keystore de release | Dois custodiantes (cofre offline) | Duas custódias distintas | [ADR-009](stack.md#10-registro-de-decisões-arquiteturais-adr), item 8 |
| Custodiar a chave Ed25519 do pack | Dois custodiantes (cofre offline), mesmo regime do keystore | Duas custódias distintas | [ADR-009](stack.md#10-registro-de-decisões-arquiteturais-adr), item 8; [ADR-001](stack.md#10-registro-de-decisões-arquiteturais-adr) |
| Assinar o pack durante a exceção da §3.7 | Mantenedor A (custódia) | Diferente do mantenedor B | [ADR-001](stack.md#10-registro-de-decisões-arquiteturais-adr), Revisão |
| Gerar o pack sem chave e conferir a assinatura publicada | Mantenedor B | Diferente do mantenedor A | [ADR-001](stack.md#10-registro-de-decisões-arquiteturais-adr), Revisão |
| Aprovar conteúdo clínico | Revisores clínicos, por dual review | Autor ≠ revisor (gatilho `approval_no_self_approval`) | [espec.md](espec.md) INV-4 |
| Operar a VPS e o domínio (provisionamento, atualização, backup, restauração, resposta a alerta) | Dois administradores da VPS ([a definir — F-2]) | Dois, para que a ausência de um não pare a operação | [ADR-007](stack.md#10-registro-de-decisões-arquiteturais-adr), Decisão 1 |
| Comunicar incidente | PRISM, sob o controlador pendente | — | [ADR-007](stack.md#10-registro-de-decisões-arquiteturais-adr), Decisão 8; [lgpd.md](lgpd.md) LGPD-RF12 |

---

## 5. Critérios de aceite de RNF-10 e RNF-11

Os critérios abaixo são copiados de [espec.md](espec.md) §1.2. A coluna "Como se verifica" detalha a prova exigida; ela não muda o critério.

### 5.1 RNF-10 — Release em pipeline

> APK e AAB saem do CI a partir de tag `vX.Y.Z` em `main`, com `versionCode` monotônico e chave de assinatura nunca versionada; as guardas `build_apk.sh`/`model_url_check` e `check_release_permissions` rodam no job. **Aceite:** uma tag gera os artefatos; `versionCode` ≤ o publicado reprova

| Critério | Como se verifica |
|---|---|
| Uma tag gera os artefatos | Uma tag `vX.Y.Z` de ensaio em `main` produz, sem passo manual além da aprovação do *environment*: um APK por ABI (§2.4), `SHA256SUMS`, a impressão do certificado, a *pre-release* no GitHub com a nota da §2.8 e o AAB na faixa de teste da Play (este último só com a conta da F-4). Tag fora de `main` não dispara o job. |
| `versionCode` ≤ o publicado reprova | Uma tag cujo `versionCode` seja igual ou menor que o maior já publicado faz o job falhar no passo 3 da §2.6, **antes** do build. O mesmo vale para MINOR ou PATCH > 99 e MAJOR > 210 (§2.2). |
| `versionCode` monotônico e único | `aapt dump badging` nos dois APKs e o `versionCode` do AAB dão o mesmo número, igual ao da fórmula (§2.2 e §2.4). |
| Chave nunca versionada | Nenhum `*.jks`, `*.keystore` ou `key.properties` no histórico; o job lê o keystore só do segredo do *environment* `release`. A Ed25519 não aparece em nenhum segredo de CI (§3.7). |
| As guardas rodam no job | O log do job mostra `model_url_check.dart` (via `build_apk.sh`) antes de cada build e `check_release_permissions.dart` depois dele; um `defines.release.json` com URL inválida ou uma permissão fora da lista fechada reprova o job. |
| RF-17 junto | O job falha sem `SHA256SUMS` ([espec.md](espec.md) RF-17). |

### 5.2 RNF-11 — Operação do plano de controle

> Backup diário cifrado fora do host, com restauração testada a cada trimestre; monitoramento externo de `manifest.json` e do CMS; imagens pinadas e atualizadas por PR; TLS automático. **Aceite:** conforme as diretrizes de operação do CMS na VPS do PRISM (`implantacao.md`)

| Critério | Como se verifica |
|---|---|
| Backup diário | O repositório de backup tem um snapshot de cada um dos últimos 7 dias, cobrindo os itens da §3.5; um alerta dispara se o mais recente tiver mais de 26 h. |
| Cifrado | O conteúdo no destino não é legível sem a chave do backup (restic/age); a chave não fica no destino. |
| Fora do host | O destino é outro provedor que não o da VPS (§3.5); apagar a VPS não apaga o backup. |
| Restauração trimestral | A cada trimestre, uma VPS descartável é restaurada a partir do backup e o CMS sobe com o banco master e a trilha íntegros; data e resultado ficam registrados em [docs/operacao.md](../docs/operacao.md) quando o item 28 existir. Trimestre sem registro reprova. |
| Monitoramento externo | Derrubar o `edge` em ensaio gera alerta aos dois administradores para `manifest.json` e para o CMS, vindo de fora da VPS (§3.6). |
| Imagens pinadas | Toda `image:` de `infra/compose.yaml` e todo `FROM` de Dockerfile do plano de controle usam tag exata ou digest; nenhuma tag flutuante (§3.4). |
| Atualizadas por PR | Nenhuma mudança de imagem ou de `infra/` chega à VPS sem PR mergeado com CI verde (§3.4). |
| TLS automático | O Caddy renova por ACME sem intervenção; o alerta de expiração (§3.6) existe e é testado. |

---

*Itens de roadmap citados: 25 (identidade, assinatura, ABIs, guarda de `minAppBuild`), 31 (workflow de release), 27 (playbook Ansible), 28 (backup e monitoramento); andamento em [arquitetura.md](arquitetura.md) §Roadmap.*
