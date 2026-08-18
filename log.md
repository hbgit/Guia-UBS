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

[TODO] Resolver antes de ir para o item 9

* O que ainda não está ligado
Estas peças existem e funcionam, mas nada as chama ainda — falta o ModelArtifact real (URL do espelho + SHA-256 versionado no código) e a decisão de quando disparar o download: o ADR-003 diz "1º acesso", mas o gatilho concreto (WorkManager só em Wi-Fi? tela de boas-vindas?) é escolha de produto que ainda não foi feita. E o caminho de destino depende de path_provider, que ainda não é dependência.

Quer que eu siga para o item 9 (sync_service completo, FSM-B, que passa a usar este mesmo downloader), ou prefere fechar o wiring do modelo primeiro?


---

# Fluxo do SLM

toques em ícones  →  Set<String> de tokens  →  prompt (texto)
                                                    ↓  llama.cpp, greedy
                     identificador validado  ←  texto gerado
                              ↓
                     cartão + áudio (pt/es)

Na entrada (prompt_builder.dart): o usuário nunca digita. Ele toca em até 5 ícones, o que produz um conjunto de IDs simbólicos (chest, pain, sudden…). O construtor ordena esse conjunto e o serializa num template fixo — ordenar é o que garante que tocar "peito depois dor" e "dor depois peito" gere o mesmo prompt, byte a byte.

Na saída (engine_decoder.dart): o texto gerado não é lido como texto. Ele é varrido em busca de um identificador que já exista na tabela routing_outcome do pacote. Qualquer outra coisa — prosa, dois identificadores, alucinação — vira null, e o gate decide. A severidade vem do banco, nunca do texto: o modelo só consegue nomear um desfecho já revisado clinicamente.


