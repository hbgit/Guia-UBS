# Changelog do contrato

Versionamento do `schemaVersion` do pack (`major.minor`), consumido pelo campo de mesmo
nome no `manifest.json`.

**Regra de compatibilidade:** o app compara apenas o **major**. Pack com major diferente
do binário é rejeitado e o dispositivo permanece no pack anterior — degradação segura,
nunca quebra ([espec.md](../docs/espec.md) INV-6). Portanto:

- **minor** — alteração **aditiva** (tabela ou coluna nova opcional). Apps antigos continuam
  lendo o pack novo. É o caminho normal, inclusive para as features v1.1.
- **major** — alteração **destrutiva** (remover/renomear coluna, mudar tipo ou semântica).
  Exige que a frota atualize o binário antes; o packer publica no menor major ainda ativo
  até a adoção cruzar o limiar (≥ 90%).

## 1.0 — 2026-08-13

Contrato inicial do MVP. 18 tabelas do `content.db`:

- **Metadados:** `pack_meta`
- **Ontologia:** `symptom_token`, `token_translation`
- **Encaminhamento:** `routing_outcome`, `routing_rule`, `routing_rule_term`
- **Locais e cartões:** `venue`, `venue_translation`, `card`, `card_translation`
- **Serviços e documentos:** `service`, `service_translation`, `document`,
  `document_translation`, `service_document`
- **Fluxo de atendimento:** `flow_step`, `flow_step_translation`
- **Assets:** `asset`

Reservado para 1.1 (aditivo): `vaccine`, `vaccine_schedule`, `health_profile`, `condition`,
`medication`, `condition_medication`.
