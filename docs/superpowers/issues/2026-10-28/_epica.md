## Contexto
Índice ordenado do levantamento do estado do projeto feito em 2026-10-28 (plano: `docs/superpowers/plans/2026-10-28-levantamento-estado-projeto.md`, no branch `develop`). O plano contém a tabela feature → estado → evidência para RF-01…15, RNF-01…09, LGPD e dívidas transversais, mais as sete decisões do dono que moldaram esta lista.

Base medida: `flutter analyze --fatal-infos` limpo; 532 testes Flutter e 331 TypeScript verdes; APK release 25,6 MB; pack de referência 160 KB com golden 24/24 (24 sem revisor clínico).

**O registro oficial de progresso continua em `spec/arquitetura.md` §5.** Esta épica é um índice; `PROGRESS.md` na raiz aponta para cá.

## Ordem de execução
Dentro da mesma prioridade: desbloqueia outras → maior risco de retrabalho → menor esforço. Marco **Piloto** = P0 + P1. Marco **v1.1** = #25.

### P0 — bloqueia uso ou viola segurança/privacidade
| Código | Issue | Labels | Depende de |
|---|---|---|---|
| P0-1 | #1 | bug, app, P0 · marco **Piloto** | — |
| P0-2 | #2 | bug, backend, spec, P0 · marco **Piloto** | — |

### P1 — requisito obrigatório ainda não atendido (marco Piloto)
| Código | Issue | Labels | Depende de |
|---|---|---|---|
| P1-1 | #3 | feature, llm, spec, P1 · marco **Piloto** | #1 |
| P1-2 | #4 | test, ci, app, P1 · marco **Piloto** | #3, #5 |
| P1-3 | #5 | bug, app, P1 · marco **Piloto** | #1 |
| P1-4 | #6 | feature, app, backend, spec, P1 · marco **Piloto** | — |
| P1-5 | #7 | spike, llm, P1 · marco **Piloto** | — |
| P1-6 | #8 | test, app, P1 · marco **Piloto** | #6 |
| P1-7 | #9 | test, llm, app, P1 · marco **Piloto** | — |
| P1-8 | #10 | feature, backend, P1 · marco **Piloto** | — |
| P1-9 | #11 | documentation, P1 · marco **Piloto** | — |
| P1-10 | #12 | documentation, P1 · marco **Piloto** | #11 |
| P1-11 | #13 | test, app, P1 · marco **Piloto** | #1, #8 |

### P2 — parcial ou melhoria com impacto claro
| Código | Issue | Labels | Depende de |
|---|---|---|---|
| P2-1 | #14 | ci, infra, P2 | #1 |
| P2-2 | #15 | ci, P2 | — |
| P2-3 | #16 | bug, backend, P2 | — |
| P2-4 | #17 | feature, backend, P2 | — |
| P2-5 | #18 | spike, llm, P2 | — |
| P2-6 | #19 | feature, app, P2 | — |
| P2-7 | #20 | spike, spec, backend, P2 | — |
| P2-8 | #21 | feature, backend, P2 | #11 |
| P2-9 | #22 | test, app, P2 | — |
| P2-10 | #23 | test, app, P2 | — |
| P2-11 | #24 | infra, documentation, P2 | #11 |
| P2-12 | #25 | feature, app, backend, P2 · marco **v1.1** | — |

### P3 — dívida técnica e documentação
| Código | Issue | Labels | Depende de |
|---|---|---|---|
| P3-1 | #26 | documentation, spec, P3 | — |
| P3-2 | #27 | tech-debt, spec, backend, P3 | — |
| P3-3 | #28 | documentation, app, P3 | #1 |

## Decisões do dono (2026-10-28)
1. Gemma fica no piloto, com a Política de Uso Proibido analisada no ADR de #3; leitura desfavorável torna a troca de modelo P0; #18 é a contingência.
2. Controlador = prefeitura (Secretaria de Saúde), que nomeia o encarregado (#11); #21 leva proposta de retenção por classe.
3. Delta packs em v1.1 (#25); a espec RF-10 repete a condição do PRD (#27).
4. Telemetria desligada no piloto; North Star medido à mão (#20); sai da tela de privacidade enquanto desligada (#19).
5. Comprar um ou dois aparelhos de 4 GB da faixa mais comum em campo (#7); revisor clínico com registro, idealmente dois (#2).
6. Pack de referência embutido no APK, registrado no PRD (#6).
7. Itens documentais da LGPD como issues no marco Piloto com dono fora da equipe (#11, #12); runbook de incidente em #24.
