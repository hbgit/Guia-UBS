# Regulamentação e aprovações do estudo piloto

> Levantamento de 2026-11-09. É um quadro de situação: as exigências vêm do `spec/` (que prevalece em conflito) e o estado de cada uma, das issues e das perguntas abertas na data. Atualize o estado quando uma exigência for cumprida.

A especificação divide o piloto em **dois portões** ([`spec/brainstorm.md`](../spec/brainstorm.md); [ADR-005](../spec/stack.md), Decisão 7), e cada um exige aprovações diferentes. Nenhum deles passa por unidade de saúde.

## Portão 1: dogfooding interno, só a equipe

Não exige aprovação externa. Basta a equipe saber que os textos legais podem estar incompletos. O canal é a pre-release do GitHub ou a faixa interna da Play.

**Falta:** a primeira tag, que depende do plano B e da configuração do repositório ([`spec/implantacao.md`](../spec/implantacao.md) §2).

## Portão 2: participantes externos, voluntários da comunidade (20 a 30 pessoas)

| Exigência | Base | Estado em 2026-11-09 |
|---|---|---|
| Controlador LGPD identificado na política de privacidade | LGPD, art. 9º | aberta (**F-11**) |
| Encarregado (DPO) designado | [`spec/PRD.md`](../spec/PRD.md), aprovações | depende da F-11 |
| RIPD, o relatório de impacto | LGPD, art. 38; [`spec/lgpd.md`](../spec/lgpd.md) | não escrito |
| TCLE e parecer do Comitê de Ética em Pesquisa (CEP), **se** o estudo coletar dados dos participantes | `spec/lgpd.md`, RF02 | aberta (**F-9**) |
| Revisão clínica do conteúdo, com profissionais de registro ativo | ADR-004, R3; [#2](https://github.com/hbgit/Guia-UBS/issues/2) | os 24 casos golden ainda não foram revisados |
| Enquadramento educacional no conteúdo (sem "triagem", sem "não é emergência") | ADR-004, R1 e R2; [#48](https://github.com/hbgit/Guia-UBS/issues/48) | aberta |
| O modelo só sinaliza escalada; o desfecho exibido vem da regra do pack | ADR-004; [#47](https://github.com/hbgit/Guia-UBS/issues/47) | aberta |
| Aparelhos do estudo provisionados do zero a partir do storage próprio, não do Hugging Face | ADR-004 | depende do plano B |

**Critério de saída do estudo:** nenhuma orientação clinicamente incorreta registrada, mais a aprovação da coordenação clínica do projeto.

## Anvisa

O ADR-004 sustenta que o app fica fora da **RDC 657/2022** pela exclusão de software "de bem-estar" (art. 1º, § 2º, I), mas com uma ressalva registrada: orientar a partir de sintomas fica perto da borda dessa definição. A exclusão só se sustenta se produto, textos, onboarding e página da loja forem coerentes com o rótulo educacional.

Por isso as issues #47 e #48 importam do ponto de vista regulatório, não só do de produto. O plano de realinhamento trata essa leitura como **proposta**, a confirmar por revisão jurídica (T7-R).

## Pontos de atenção (leitura não normativa, fora do `spec/`)

- **F-9 e CEP.** O `spec/` só exige CEP "se houver coleta". Mas observar o uso de 20 a 30 pessoas como estudo do grupo de pesquisa costuma ser enquadrado como pesquisa com seres humanos (Resoluções CNS 466/2012 e 510/2016), mesmo sem dado pessoal no app: entrevista, questionário ou anotação de observação já contam como coleta. Vale consultar o CEP da UFRR cedo, porque a tramitação na Plataforma Brasil leva semanas.
- **Google Play.** A declaração de app de saúde na Play é a mesma "informação/educação em saúde, não dispositivo médico" ([`spec/implantacao.md`](../spec/implantacao.md) §2.7) e precisa estar coerente com o enquadramento da Anvisa.

Nada disso é parecer jurídico. As bases legais e o enquadramento regulatório estão marcados como proposta até a revisão (T7-R).

## Caminho crítico do portão 2

**F-11 → RIPD → decisão sobre o CEP (F-9) → revisão clínica (#2) → #47 e #48.**
