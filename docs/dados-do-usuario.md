# Dados do usuário do aplicativo

> Levantamento feito em 2026-11-09 a partir do código do app: o esquema do `user.db`, a telemetria, as chamadas de rede, as dependências e o manifesto mesclado do release. Se o código mudar, este levantamento precisa ser refeito.

**O app não coleta nenhum dado pessoal.** Nada que identifique a pessoa sai do aparelho, e o app não tem conta, cadastro nem identificador de aparelho.

## 1. O que fica guardado no aparelho (`user.db`)

O app só guarda configurações, numa única linha da tabela `Preferences` (`app/lib/prefs/user_database.dart`, esquema v3):

| Coluna | O que guarda |
|---|---|
| `localeCode` | idioma escolhido, `pt` ou `es` |
| `telemetryEnabled` | se a telemetria agregada está ligada (vem ligada, com opção de desligar) |
| `allowMeteredDownload` | se o modelo pode ser baixado por dados móveis |
| `setupCompleted` | se a pessoa já passou pela configuração inicial |
| `themeMode` | tema: sistema, claro ou escuro |
| `fontScale` | tamanho da letra: 1.0, 1.3 ou 1.6 |
| `termsVersionAnswered` | qual versão dos termos a pessoa respondeu (uma data) |
| `termsAccepted` | se aceitou essa versão |

Nenhuma dessas colunas identifica a pessoa ou descreve a saúde dela. A lista é fechada por teste:
- `app/test/prefs/lgpd_surface_test.dart` reprova o build se aparecer uma coluna nova;
- o teste da tela de privacidade (`app/test/ui/privacy/`) confere que ela mostra exatamente essas colunas.

Os outros arquivos no armazenamento interno são técnicos: o pack de conteúdo, o manifest, o modelo e as travas de download.

## 2. O que o app não guarda nem envia

- **Sintomas e respostas da triagem** ficam só na memória e se perdem ao final (INV-2). Não vão para o disco, para o log nem para a rede.
- **Telemetria:** existem só 8 contadores (`app/lib/telemetry/metric_key.dart`), por exemplo triagens concluídas, quantas terminaram em emergência e falhas de sync. Eles ficam na memória, por dia, e **não são gravados nem enviados**. Hoje o app não tem como enviá-los.
- **Permissões:** o app não pede localização, câmera, microfone, contatos nem armazenamento externo. As permissões do release são: internet, estado da rede, notificações, iniciar no boot, wake lock e serviço em primeiro plano. Todas servem ao download em segundo plano.
- **Rastreamento:** o app não usa nenhum SDK de analytics, de anúncios ou de relatório de falhas.

## 3. O que um servidor vê quando o app baixa algo

São duas chamadas de rede, feitas em segundo plano: o manifest e o pack de conteúdo, e o modelo no primeiro acesso. Nelas, o servidor vê:
- o **endereço IP** do aparelho, o que é inevitável em qualquer conexão;
- o `User-Agent` padrão do Dart (`Dart/<versão> (dart:io)`), igual para todos os aparelhos;
- os cabeçalhos `Range` (para retomar o download) e `If-None-Match` (o ETag do manifest), que são técnicos e não identificam ninguém.

Quem recebe essas chamadas:
- **o Hugging Face**, no download do modelo;
- **o host de conteúdo do PRISM**, no download do pack, depois do plano B. Os logs de acesso desse servidor são uma questão de operação da VPS, não do app.

O site `guiasaude.prismrr.com.br` é hospedado pelo GitHub Pages. O GitHub também registra os IPs de quem o acessa, mas o site não tem nenhum script.

## 4. Pontos fora do controle do app

- **Voz (TTS):** o app usa o mecanismo de voz do Android. Dependendo do aparelho, esse mecanismo pode processar o texto na nuvem, fora do app. Vale citar isso na política quando a F-11 for resolvida.
- **Google Play:** se o app for distribuído pela Play, a loja coleta os próprios dados de instalação. Isso não vem do app, mas entra no formulário de segurança de dados da Play ([`spec/implantacao.md`](../spec/implantacao.md) §2.7). Os agregados do console podem ser insumo do estudo de impacto (§5).

## 5. Estudo de impacto: canal próprio, fora do app

O estudo de impacto ([ADR-010](../spec/stack.md#10-registro-de-decisões-arquiteturais-adr)) coleta os dados do estudo (observações de uso, respostas a entrevistas) por um canal próprio, definido no protocolo aprovado pelo CEP, como um formulário ou um caderno de campo. **Nunca pelo app.**

- O app é o mesmo para quem participa do estudo e para o público: não há versão do estudo, nem identificador, nem telemetria. Tudo o que as §§1 a 3 listam vale também para quem participa.
- Os dados do estudo seguem a [LGPD-RF02, RF04 e RF05](../spec/lgpd.md), a Lei 14.874/2024 e o protocolo do CEP. O TCLE e a base LGPD (consentimento ou termo de informação) ficam em documentos ou seções distintos (ADR-010, Decisão 6).
- Os dados agregados da loja (instalações, versões ativas) podem ser insumo do estudo. Eles vêm do console da Play, não do app.
- Telemetria no app seria uma decisão separada, com ADR próprio e revisão da INV-2 (ADR-010, Decisão 5). Se ela vier, este levantamento precisa ser refeito.
