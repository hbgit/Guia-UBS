# Logger

## Fase 1:

Três decisões que vale destacar
1. Maior severidade vence, prioridade só desempata. Escolhi isso em vez de "primeira regra por prioridade" porque torna a INV-1 estrutural: nenhum erro de autoria — nem uma regra de rotina com prioridade 1 — consegue rebaixar uma red flag. Há um teste dedicado a esse cenário exato.

2. O DDL saiu do packer. Em vez de escrever CREATE TABLE à mão, restaurei as FKs no contrato e gero o DDL com drizzle-kit — 28 FKs a partir da mesma fonte que alimenta o codegen. Eliminei a fonte de verdade duplicada que o próprio blueprint alertava (atualizei a nota da §4 que dizia o contrário).

3. O manifest é publicado por último. Uma publicação interrompida na metade nunca aponta para artefato ausente, porque o device só enxerga a versão nova quando o manifest existe.

Verificação por execução
O quê	Resultado
Suite golden	24/24
Testes (contrato + packer)	23/23, autocontidos — rodam em CI limpo sem artefatos
Cadeia de assinatura	Válida; adulterar hash do pack, versão ou hash de asset invalida
Simulação do device pela borda	Manifest 200 + assinatura válida + anti-downgrade rejeitando v1 ≤ v5 + download em 2 pedaços via Range (206+206) + SHA-256 confere
Publicação SigV4	49 objetos no MinIO

Ressalvas honestas
As regras clínicas e os ícones são placeholders explicitamente marcados: clinical_source diz "revisão clínica pendente" em cada regra, os 24 casos golden têm reviewed_by: ~, e o packer emite aviso a cada build — "bloqueia o piloto, não a Fase 1". Nada aqui deve chegar perto de um usuário real antes da dupla aprovação clínica.

Item 8
* O externalNativeBuild compila o shim e o empacota no APK. Verifiquei o fecho de dependências dentro do APK: libgubs_llama.so → libllama.so → libggml{,-base,-cpu}.so + libc++_shared.so, todas presentes, nenhuma ausente. Foi para isso que forcei ANDROID_STL=c++_shared — com o padrão c++_static, as duas libs C++ carregariam cópias separadas da STL.

* Fixei também minSdk = 26 — o Flutter herdava 24, mas o RNF-09 e o ANDROID_PLATFORM do shim são 26. Sem isso, a Play Store instalaria em aparelhos onde o .so não carrega.

* Os 2549 ms são má notícia, não boa. O orçamento é 3000 ms e isso foi medido em núcleos Alder Lake. Um Cortex-A53/A55 roda inferência CPU do llama.cpp a uma fração disso — o p95 no aparelho alvo deve passar não só dos 3 s do RF-05 como provavelmente do teto duro de 5 s, disparando o RuleOnlyEngine na maioria das triagens.

* [TODO] O que continua sem verificação: o job do WorkManager disparando de fato — confirmei o registro e as restrições, mas não esperei uma janela periódica real (frequência de 6 h). E o picker OTG não foi testado com um pendrive físico.

* [TODO] O `PackStore` reconfere o SHA-256 do pack ativo a cada abertura. Hoje custa nada (160 KB), mas se o pack crescer com áudio embarcado isso tem de sair do caminho crítico do boot — é o mesmo erro que o marcador `.verificado` do modelo corrigiu.

## Fase 2

Pendente do item 9, ainda não verificado: o WorkManager agendando o sync de pack (item 15) e o download dos assets do manifest — o PoC baixa e ativa o content.db, que é o que a triagem consome.

Item 10 [FEITO]
* A casca segue a mesma tática do item 9: mapa de rotas como DADO, e o roteador só dobra a lista. Assim "profundidade ≤ 4", "zero dead-ends" e "quais telas a exceção da INV-8 alcança" viram travessia de lista em vez de leitura de builders.

* Reduzi a exceção da INV-8 ao tamanho que o ADR-003 realmente autorizou. Estava travando o app inteiro até o modelo baixar; o ADR fala em travar "a tela principal de atendimento clínico". Agora só as rotas com `requiresModel` fecham — a triagem. Onde ir, Documentos, o fluxo e principalmente a tela de EMERGÊNCIA seguem abertos sem modelo. Quem chega em emergência pode estar tendo um infarto, e aquela tela é conteúdo estático assinado que não precisa de inferência nenhuma.

* O teste de contraste reprovou a paleta do próprio protótipo em três pontos, sendo um sério: verde e vermelho do tema claro tinham razão de contraste de 1,01 ENTRE SI. Mesma luminância. Para os ~5% de homens com deficiência de visão de cores vermelho-verde, cartão de rotina e cartão de emergência eram literalmente a mesma cor — e a distinção rotina/emergência é a coisa mais importante que este app comunica. Escureci o vermelho para #9E2626 (razão 1,55) e o âmbar para #8F651A. Propaguei para o design.html.

* Depois disso o aparelho ainda achou um quarto: o rótulo do botão principal saiu com 1,94:1 no tema escuro. Causa: todo estilo do `textTheme` já vem colorido com `onSurface`, e cor explícita no TextStyle vence o `foregroundColor` do botão. O teste de paleta não tinha como pegar — `ink`×`green` não é um par que a paleta preveja, foi o widget que inventou. Virou um segundo teste que lê a cor do texto JÁ PINTADO (RenderParagraph). Verificar a paleta prova que as cores escolhidas são boas; só verificar o renderizado prova que são elas que chegam à tela.

* Dead-end que só o aparelho mostrou: a tela de triagem sem botão voltar. `canPop()` responde "existe algo empilhado", que não é "existe para onde voltar" — os ladrilhos navegam com `go`, que substitui. Meu teste passava porque usava `push`, ou seja, exercitava um caminho que o app não percorre. Agora o destino do voltar vem do manifesto (`parentPath`) e o teste chega por deep link, que é o pior caso.

* Dois estouros de layout com a fonte em 2×: os ladrilhos tinham proporção fixa e o nome do idioma saía pela borda. Ampliar a fonte é a primeira coisa que faz quem tem presbiopia sem óculos. Cobertos agora em 1×, 1,3×, 1,6× e 2×, nos dois temas.

* Sabotagem: 6 proteções desligadas, 5 pegas. A que NÃO foi pega é a mais interessante — baixar `minTouchTarget` de 64 para 48 não quebrou nada, porque o teste comparava o widget renderizado contra a mesma constante que eu tinha alterado. Teste circular. Ancorei as constantes nos números da RNF-06.

* Riverpod fixado no 2.x de propósito: o 3.x só resolve subindo 31 pacotes. Trocar de major na casca, antes de existir tela que use o estado, pagaria a migração duas vezes. O codegen + freezed que a stack.md nomeia entra no item 12, onde os estados de união exaustiva pagam pelo gerador.

* Atualizei o CLAUDE.md, que ainda dizia "não há build/teste/lint" desde antes do item 8.

* 153 → 256 testes. APK release arm64 de 21,1 → 23,8 MB (orçamento do ADR-003 é 50–80 MB).

* [TODO] As telas de triagem (item 12) e de conteúdo estático (item 13) são placeholders — mas os caminhos já existem, senão a estrutura não seria testável. O `LocaleStore` é um JSON simples; o item 11 reimplementa sobre Drift.

* [TODO] Não verifiquei o TTS falando de verdade no aparelho: o `speech/` está testado contra engine de mentira (incluindo ROM sem engine e engine que não responde), mas nenhuma tela ainda tem botão de áudio para acionar. Isso vem com o item 12.

Item 11 [FEITO]
* Duas camadas de dados com regras opostas, e é a oposição que importa. `content/` SÓ LÊ um arquivo que chega assinado de fora; `prefs/` é o único lugar do aparelho onde o app escreve — e por isso é a superfície que a LGPD audita.

* O `content.db` abre em `OpenMode.readOnly` e tem teste que confirma que um UPDATE lança. Não é convenção: a INV-4 diz que conteúdo clínico só entra por pack assinado com dupla revisão, e um caminho de escrita no device seria um caminho para orientação não revisada chegar ao usuário sem passar pela assinatura.

* Decisão sobre idioma faltando: RECUAR para pt, não sumir com o item. O packer já bloqueia publicação com tradução faltando, então recuo no aparelho é defeito — mas sumir com "Onde ir" de quem precisa é pior que mostrá-lo em português para um hispanofalante. O ícone continua certo e as duas línguas são próximas. O recuo fica sinalizado em `Localized.isFallback` para telemetria agregada contar o defeito, nunca para a tela.

* O esquema do `user.db` usa colunas TIPADAS e não chave-valor, de propósito. Uma tabela (chave, valor) aceitaria qualquer coisa que qualquer código futuro gravasse, e "o que este app guarda sobre a pessoa?" deixaria de ter resposta estática. Com colunas declaradas, as colunas SÃO a resposta, e um teste as enumera: coluna nova reprova o build até ser justificada contra a INV-2 e a LGPD-RF13. Custa uma migração por preferência; compra a capacidade de PROVAR o que não guardamos. São quatro, todas escolha de operação do app: idioma, telemetria agregada, override de dados móveis, setup concluído.

* Ganhei uma segunda barreira contra a corrida S1 sem escrever código para isso. O desenho do item 9 (packs nomeados pelo hash, commit por rename do manifest) significa que remover o arquivo antigo não invalida descritor já aberto no POSIX — uma leitura em voo termina no pack anterior íntegro em vez de ver arquivo trocado por baixo. Tem teste que abre o v1, instala o v2, remove o v1 e confirma que a leitura antiga ainda responde v1. O guard de quiescência continua valendo; agora são duas barreiras independentes.

* Paguei a dívida do item 10: `setupCompleted` e o override de dados móveis viviam na memória do processo. Quem escolhia "usar sem a IA assistente" revia a apresentação de valor a cada abertura, e um posto sem Wi-Fi voltava a recusar o download depois de o administrador já ter autorizado.

* Migração do `locale.json` do item 10 para o banco, com regra de não sobrescrever escolha mais recente e apagar o arquivo ao terminar. Verificada no aparelho: instalei por cima do app anterior e ele abriu direto em espanhol, sem repetir a tela de idioma. Cold start 1149 ms.

* Sabotagem: 6 proteções desligadas, 6 pegas. Mas a sabotagem revelou um risco que eu mesmo tinha criado: o teste que prova "escrever no pack é impossível" rodava contra a fixture VERSIONADA. Quando removi o `readOnly`, o UPDATE passou e corrompeu o arquivo compartilhado, derrubando 10 testes de sync sem relação com o assunto. Um teste que prova "isto não pode acontecer" precisa ser inofensivo no dia em que acontecer — agora ele opera sobre cópia descartável.

* Codegen do Drift entrou no build. Os .g.dart não são versionados, e em checkout limpo pular `dart run build_runner build` produz ~35 erros de análise sem relação com o código escrito. Passo adicionado ao CI antes do analyze, e verificado apagando os gerados e refazendo o caminho.

* 302 testes. APK 23,8 → 24,3 MB.

* [TODO] A tela de privacidade (CAP-13 / LGPD-RF03) ainda não existe — o `wipe()` está implementado e testado, mas nenhuma tela o aciona. É o item 14. Também não há tela lendo os repositórios de conteúdo ainda; isso são os itens 12 e 13.

* [TODO] Não verifiquei o `user.db` em disco no aparelho: build release não permite `run-as`. O que verifiquei foi o comportamento — idioma migrado, persistido e relido entre reinícios.

Item 12 [FEITO]
* FSM-A pela mesma tática dos itens 9 e 10: matriz pura, driver separado. Aqui isso vale mais, porque as propriedades que precisam ser verdadeiras são clínicas — e "nenhum caminho leva red flag à inferência" é afirmação sobre o GRAFO. Seis propriedades desse tipo viraram testes que percorrem todos os pares (estado, evento).

* O pior defeito do projeto até agora, e o teste de widget que o pegou: a conversão de `severity_level` para cor tinha limiares fixos em Dart (`<=1` rotina, `2` atenção, resto emergência). O pack real usa 10 e 100. Resultado: TODO cartão de rotina saía VERMELHO, com "Ligue 192" embaixo. Para quem depende da cor por não ler o texto, é a mensagem oposta à correta, na tela mais crítica do app.

* A causa não foi um número errado — foi a UI ter inventado uma escala. `severity_level` é definido pelo conteúdo, que passa por revisão clínica e pode mudar de pack para pack. Agora `severityFor(level, model)` deriva os extremos dos desfechos do próprio pack, os mesmos que o gate lê. Zero limiar clínico em Dart. Anotei a armadilha no CLAUDE.md.

* De quebra, movi o enum `GubsSeverity` do tema para o domínio da triagem. A regra de dependência da espec §2.2 é `ui → triage`, e eu tinha invertido; além disso, severidade morando dentro da paleta convida a decidir severidade a partir de cor, que é o contrário do que a INV-1 quer.

* Composição em três passos (`body_part` → `symptom` → `modifier`), mas UMA rota só. A FSM permanece em S1_COMPOSING nos três: compor é um estado só, e passo é apresentação. Dar rota a cada passo criaria estados de navegação que a máquina clínica não reconhece — o voltar do Android pularia para um passo sem a composição correspondente.

* Seleção comunicada por quatro canais ao mesmo tempo: fundo, borda grossa, marca de conferido e negrito. Cor sozinha exclui quem tem deficiência de visão de cores; texto sozinho exclui quem não lê. Este app não pode escolher um dos dois.

* Acrescentei `removeToken`, que não está na matriz da espec. A matriz descreve a máquina, não a edição da composição: retirar um ícone tocado por engano mantém o estado em S1 e nenhuma guarda muda. Sem isso, errar um toque obrigaria a recomeçar — e recomeçar é caro para quem não lê.

* Sabotagem: 7 proteções desligadas, 6 pegas de primeira. A que escapou: nada cobria o mapeamento `icon_ref` → ícone. Numa interface iconográfica, ícone que some remove a opção inteira. Agora tem teste exigindo que todo token do pack tenha ícone próprio E que ícones da mesma família sejam distintos entre si — dois sintomas com o mesmo desenho são, para esse usuário, o mesmo botão.

* Verificado no aparelho com o pack real empurrado para o sandbox (build debug, porque release não permite `run-as`): `peito+dor+muito forte` → cartão VERMELHO com "Llama al 192", sem aviso de degradação (red flag não é degradação, é o caminho previsto); `garganta+dor` → cartão VERDE com o aviso. E o TTS FALOU — "Utterance ID has started" no logcat. Fecha o TODO que ficou do item 10.

* [PENDENTE — decisão de conteúdo] A convenção de "máx. 8 elementos por tela" casa com `body_part` (8) e `modifier` (6), mas `symptom` tem 12 e a grade rola. Resolver exige ou um subconjunto de sintomas por parte do corpo (precisa de tabela de associação no pack, que não existe) ou reduzir a ontologia. As duas são decisão clínica com dupla revisão, não coisa que eu deva escolher no código. Fica para a revisão do piloto.

* [TODO] O `triageEngineProvider` está fixo em `null`, então a triagem roda sempre pelo `RuleOnlyEngine`. Ligar o `LlamaEngine` ao modelo provisionado é o que falta para o caminho S3 existir em produção — S3 está testado com motor de mentira, incluindo timeout, exceção e travamento.

* 302 → 370 testes.

Item 13 [FEITO]
* Quatro telas alimentadas 100% pelo content.db: Onde ir, O que levar, Como funciona e emergência. São o piso da escada de degradação, e verifiquei no aparelho exatamente na condição em que elas importam — rádios DESLIGADOS e sem modelo provisionado.

* Duas falhas que só o aparelho mostrou, ambas na tela mais usada. A primeira: todo serviço aparecia com um "?" porque o mapa `icon_ref → ícone` cobria só tokens de sintoma. O teste que escrevi no item 12 percorria `symptomTokens`, então passava tranquilo. A pergunta certa não era "os tokens têm ícone?", era "tudo que o pack manda desenhar tem ícone?" — agora ele percorre a tabela `asset` inteira.

* A segunda: a tela liderava com HOSPITAL. `venue` não tinha `sort_order`, então ordenava por id, alfabeticamente. A tela cujo propósito é encaminhar para a atenção básica quem não precisa de pronto-socorro abria com o hospital no topo.

* Corrigi atravessando a stack, e é esse o ponto: qual local aparece primeiro é CURADORIA DE CONTEÚDO, não `ORDER BY` do binário. Coluna `sort_order` no contrato Drizzle, migração 0001 gerada por drizzle-kit, valores no seed com o porquê escrito ali, repositório ordenando por ela. Agora um município republica a ordem sem tocar no app. Fixtures regeneradas e hashes atualizados nos testes de sync.

* Tradução de cor sem chute perigoso: o pack diz green/red/blue e o binário converte. Token desconhecido vira AZUL, nunca verde nem vermelho — chutar verde diria "pode esperar", chutar vermelho diria "corra", e azul diz "isto é informação", que é a única coisa verdadeira sobre um token que eu não entendo.

* Tirei a rolagem horizontal dos seletores. Na primeira versão o último atendimento ficava fora da tela, e para este público conteúdo fora da tela é conteúdo que não existe: ninguém arrasta de lado atrás de algo cuja existência não foi anunciada. Virou Wrap, com teste que reprova se qualquer opção passar da borda.

* Sabotagem: 7 proteções, 6 pegas. A sétima passou ilesa e o motivo é o melhor achado do item — meu teste do "192 não é botão" usava `find.byType(ButtonStyleButton)`, e `find.byType` compara tipo EXATO, então nunca casaria com um TextButton. O teste era estruturalmente incapaz de falhar. Troquei por `find.byWidgetPredicate` e a sabotagem passou a ser pega. Vale revisar outros `byType` com tipos-base em testes futuros.

* Escrevi "sem documento você ainda é atendido" num ARB e RETIREI. É afirmação sobre direito do usuário do SUS, não rótulo de casca — se aparecer, tem de vir do pack com dupla revisão (INV-4). Fica anotado como conteúdo que o pack deveria carregar: a tela de documentos ganharia muito, e quem mais precisa dessa informação é exatamente quem o app atende.

* [TODO] Os ícones ainda são do Material, mapeados por `icon_ref`. Os SVG reais viajam dentro do pack como assets, mas extrair e renderizar assets é Fase 4 — junto com os áudios Opus, que hoje são substituídos por TTS lendo o texto.

* 370 → 390 testes. APK 24,5 → 24,7 MB.

Item 14 [FEITO]
* A tela de privacidade NÃO escreve à mão o que o app guarda: ela lista uma entrada por preferência do user.db, e tem teste comparando as duas contagens. Pegou na primeira execução — `allow_metered_download` existia no banco e não aparecia na tela. Uma lista redigida à parte envelhece, e o resultado é uma tela que mente para o titular em português claro, com toda a cara de verdade.

* Opt-out zera a COLETA, não só o envio. A LGPD-RF03 fala em zerar envios; zerar a contagem é mais forte — quem desligou não tem nem número em memória a respeito de si. E desligar apaga o que já foi contado: um opt-out que só vale para o futuro deixa em memória exatamente o que a pessoa acabou de recusar.

* O pior defeito do item, e o teste pegou antes da sabotagem: eu tinha DOIS providers lendo o mesmo opt-out do user.db. A tela invalidava um, o contador escutava o outro. Ou seja: o botão desligava na tela e a coleta continuava. É o pior defeito possível numa opção de privacidade. Virou um estado síncrono único.

* A allowlist é fechada por construção — não existe API que aceite String, só a enum MetricKey. Campo novo passa obrigatoriamente pelo diff, que é onde a revisão do encarregado acontece. Teste confere a enum contra o telemetry-schema.json gerado, mesma técnica do manifest.

* O que o módulo de telemetria NÃO faz, de propósito: não transmite (seria uma TERCEIRA chamada de rede, e isso exige ADR — não decisão de passagem enquanto implemento um contador) e não persiste (contador em disco viraria tabela nova no user.db, e sem envio ninguém lê: risco sem benefício). Também não guarda série temporal — `observeMax` guarda o pior caso do dia, porque série por aparelho é justamente o que a LGPD-RF14 quer evitar.

* `kAnonymityMin` está no código como DOCUMENTAÇÃO do contrato, não como regra que o aparelho aplique: k é propriedade do conjunto de aparelhos, e um aparelho sozinho não sabe quantos outros formam sua coorte. Quem recusa lote com k < 20 é o pipeline.

* Na ação destrutiva, a saída é o caminho fácil: "Não apagar" é o botão preenchido e vem primeiro; "Apagar mesmo assim" é texto discreto embaixo. Verificado no aparelho — apaga, confirma na tela, e na reabertura o app volta a perguntar o idioma, que é o sinal visível de que aconteceu.

* Esclareci (não afrouxei) o teto de oito elementos: ele conta ESCOLHAS, não moldura. Voltar, barra de abas e o escudo de privacidade não competem pelo escaneamento — e sem essa distinção a tela exigida pela LGPD-RF03 não teria onde caber na inicial, que já usava as oito posições. A regra está escrita no teste, não implícita.

* Sabotagem: 6 proteções, 6 pegas.

* Apaguei o `placeholder_screen.dart` — todas as rotas têm tela real agora.

* [TODO] O envio de telemetria não existe. Quando existir, precisa de ADR (terceira chamada de rede) e de decidir onde os contadores ficam entre aberturas do app. Hoje eles morrem com o processo, o que é correto enquanto não há consumidor.

* [TODO] Nenhum ponto do app chama o `TelemetryRecorder` ainda. A triagem, o sync e o boot deveriam alimentá-lo (`triage_completed_total`, `sync_success_total`, `session_total`) — é fiação simples, mas não fiz para não espalhar chamadas antes de existir consumidor.

* 390 → 417 testes. APK 24,7 → 24,8 MB.

Item 15 [FEITO]
* O item 9 entregou a FSM-B certa. Este item corrigiu o fato de que DOIS dos freios dela não existiam no aparelho — só no código.

* Circuito e backoff viviam em memória. O WorkManager executa num ISOLATE NOVO a cada disparo: um isolate recém-criado nasce com o circuito fechado e sem backoff pendente. O freio funcionava em teste e no app aberto, e nunca em produção. Uma frota sem rede voltaria a bater no servidor a cada janela, com o circuito "aberto" em memórias que já morreram.

* Agora o estado é disco, no mesmo arquivo do ETag e das blacklists — bookkeeping de sync, não dado do usuário, então longe do user.db. E o circuito deixou de ser booleano ("aberto até a próxima janela") para virar INSTANTE ("fechado a partir de"): um processo que acabou de nascer não sabe em que janela está, mas sabe que horas são.

* Persistir não bastou, e o teste mostrou: processo novo nasce em p0Steady, e a linha B1 só consulta o circuito — o backoff é guarda da B14, que sai de f1Retryable. Cada reinício pulava o backoff e ia direto à rede. Agora restauro também a POSIÇÃO da máquina: se há falhas registradas, ela estava em F1 quando o processo morreu.

* O guard de quiescência tinha o que proteger e não tinha o que consultar — era um callback que ninguém fornecia. Agora pergunta ao controlador de triagem se a FSM-A está em S0_IDLE. E adiar NÃO conta como falha: se contasse, cinco triagens seguidas abririam o circuito e o aparelho pararia de sincronizar justamente por estar sendo usado.

* O erro mais silencioso do item: `Workmanager().initialize()` aceita UMA função, que recebe todas as tarefas. Eu tinha dois dispatchers e só o do modelo era registrado. O do pack existia, compilava, tinha comentário explicando seu papel, e nunca seria chamado — a tarefa de conteúdo caía no `if (task != modelSyncTaskName) return true` do outro e era marcada como concluída. O sync estaria agendado e nunca aconteceria; nada falharia, nenhum log apareceria. Achei isso olhando o dumpsys do aparelho, não em teste.

* Política do pack ≠ do modelo: o modelo exige Wi-Fi, o pack não. São ~800 MB baixados uma vez contra centenas de KB que carregam correção clínica — um posto sem Wi-Fi não pode ficar meses com orientação velha porque a política de um arquivo mil vezes maior foi aplicada a ele.

* Sabotagem: 7 proteções, 5 pegas de primeira. As duas que escaparam valem nota. Desligar o teto do backoff não quebrou nada porque, com orçamento de 5 falhas, `n` nunca passa de 4 e `2^4` são 16 segundos — o teto é código morto com os parâmetros de hoje. Mantive (2^11 já passa de meia hora; um freio que nunca solta é indistinguível de app que parou de sincronizar) mas virou função pura testada fora da faixa alcançável. E remover o jitter também passava, porque jitter é propriedade da FROTA, não de um aparelho — virou teste sobre a dispersão entre sementes.

* Também corrigi um comentário meu que exagerava: eu tinha escrito que `2^n` "vira dias por volta da décima falha". São 17 minutos. O teste me obrigou a olhar o número.

* Verificado no aparelho: os dois trabalhos periódicos coexistem com restrições distintas — NET BATNOTLOW STORENOTLOW (modelo) e NET BATNOTLOW (pack) —, período de 6h, zero erros de runtime.

* [TODO] Não esperei uma janela periódica real disparar (6h). O que verifiquei foi o REGISTRO e as restrições; a execução do ciclo em background continua sem prova de campo.

* [TODO] `packManifestUrl` aponta para o MinIO local por padrão. Precisa de `--dart-define` no build de produção, como as chaves de assinatura.

* 417 → 438 testes.


Item 12 [FEITO] << Checkout
* Dívida do item 10 paga: setupCompleted e o override de dados móveis viviam na memória do processo. Quem escolhia "usar sem a IA assistente" revia a apresentação de valor a cada abertura; um posto sem Wi-Fi voltava a recusar o download depois de o administrador já ter autorizado.
* [TODO] Não verificado: a tela de privacidade (CAP-13/LGPD-RF03) não existe — wipe() está implementado e testado, mas nenhuma tela o aciona; é o item 14. Nenhuma tela lê os repositórios de conteúdo ainda (itens 12–13). E não inspecionei o user.db em disco no aparelho: build release não permite run-as — verifiquei o comportamento, não o arquivo.

## FASE 3 [TODO]

---


Analisar:
* O pior defeito do projeto até agora, achado pelo teste de widget. A conversão de severity_level para cor tinha limiares fixos em Dart (<=1 rotina, 2 atenção, resto emergência). O pack real usa 10 e 100 — então todo cartão de rotina saía vermelho, com "Ligue 192" embaixo. Para quem depende da cor por não ler o texto, é a mensagem oposta à correta, na tela mais crítica do app.
* Pendente, e é decisão de conteúdo, não minha: a convenção de "máx. 8 elementos por tela" casa com body_part (8) e modifier (6), mas symptom tem 12 e a grade rola. Resolver exige subconjunto de sintomas por parte do corpo (precisa de tabela de associação que o pack não tem) ou redução da ontologia — ambas com dupla revisão clínica.
* triageEngineProvider está fixo em null, então a triagem roda sempre pelo RuleOnlyEngine. Ligar o LlamaEngine ao modelo provisionado é o que falta para o caminho S3 existir em produção; S3 está testado com motor de mentira (timeout, exceção, travamento), não com o real.

* Item 13 [TODO]


---

# Fluxo do SLM

toques em ícones  →  Set<String> de tokens  →  prompt (texto)
                                                    ↓  llama.cpp, greedy
                     identificador validado  ←  texto gerado
                              ↓
                     cartão + áudio (pt/es)

Na entrada (prompt_builder.dart): o usuário nunca digita. Ele toca em até 5 ícones, o que produz um conjunto de IDs simbólicos (chest, pain, sudden…). O construtor ordena esse conjunto e o serializa num template fixo — ordenar é o que garante que tocar "peito depois dor" e "dor depois peito" gere o mesmo prompt, byte a byte.

Na saída (engine_decoder.dart): o texto gerado não é lido como texto. Ele é varrido em busca de um identificador que já exista na tabela routing_outcome do pacote. Qualquer outra coisa — prosa, dois identificadores, alucinação — vira null, e o gate decide. A severidade vem do banco, nunca do texto: o modelo só consegue nomear um desfecho já revisado clinicamente.


