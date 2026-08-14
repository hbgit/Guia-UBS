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
* [Verificar para Alteração] O app responde por 2,7% do total. Nenhuma quantização salva: o piso é 681 MB (IQ4_XS), porque a tabela de embeddings de 256k tokens não quantiza. Ou o orçamento sobe para ~1 GB, ou o modelo muda — e o 270M, único que cabe, produziu identificador válido em 1 de 20 casos, ou seja, rodaria sempre em modo degradado. Não alterei os números da espec: mudar critério de aceite é decisão de produto.

* [DOING] O caminho crítico agora não é código: é um aparelho arm64 de entrada, e a decisão sobre orçamento × modelo. Sigo para o item 9 (sync_service) enquanto isso?
    - p95 = 4731 ms num aparelho intermediário. O RF-05 exige < 3000 ms
    - O RF-05 reprova por 58% — e num Motorola Edge 40 Neo, aparelho intermediário (Dimensity 7030, 7,6 GB de RAM), não no "≤ 4 GB de entrada" que o critério nomeia. O aparelho-alvo real será pior.
    - Pior ainda: 4731 ms encosta no teto duro de 5 s. Já neste hardware, uma fração das triagens estouraria o timeout e cairia no RuleOnlyEngine. No aparelho de entrada, isso seria a regra, não a exceção — o SLM estaria embarcado, ocupando 768 MB, e quase nunca respondendo a tempo.
    - A boa notícia isolada: pico de RAM de 832 MB, bem dentro do 1,5 GB do RNF-03 (no host eram 1136 MB — o Android devolve páginas do mmap sob pressão). E 20/20 respostas válidas: o Gemma 3 1B funciona para a tarefa. O problema é exclusivamente velocidade e tamanho.
    - [TODO] As opções reais, na minha ordem de preferência: (1) adiar o SLM para pós-MVP e liberar com gate + regras, (2) subir o orçamento para ~1 GB e aceitar p95 na casa dos 5–10 s com degradação frequente, ou (3) buscar um modelo de 300–500 M com vocabulário menor e avaliá-lo com a mesma suite. >> prefere avaliar antes um modelo intermediário?



