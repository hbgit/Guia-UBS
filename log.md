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
* Dívida do item 10 paga: setupCompleted e o override de dados móveis viviam na memória do processo. Quem escolhia "usar sem a IA assistente" revia a apresentação de valor a cada abertura; um posto sem Wi-Fi voltava a recusar o download depois de o administrador já ter autorizado.
* [TODO] Não verificado: a tela de privacidade (CAP-13/LGPD-RF03) não existe — wipe() está implementado e testado, mas nenhuma tela o aciona; é o item 14. Nenhuma tela lê os repositórios de conteúdo ainda (itens 12–13). E não inspecionei o user.db em disco no aparelho: build release não permite run-as — verifiquei o comportamento, não o arquivo.

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


