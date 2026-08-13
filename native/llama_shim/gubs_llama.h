/* Fronteira nativa mínima entre o app e o llama.cpp.
 *
 * ===========================================================================
 * POR QUE ESTE SHIM EXISTE
 * ===========================================================================
 *
 * O Dart poderia falar direto com `llama.h` via ffigen. Não fazemos isso por
 * duas razões concretas:
 *
 * 1. SUPERFÍCIE. `llama.h` expõe ~200 símbolos e muda a cada release. Um
 *    binding gerado transforma cada mudança de ABI em um crash em tempo de
 *    execução, no device, em campo. Aqui a superfície são 4 funções, e uma
 *    quebra do upstream vira erro de COMPILAÇÃO em C — encontrada no CI.
 *
 * 2. DETERMINISMO E TIMEOUT. RF-05 exige inferência reprodutível com teto duro
 *    de 5 s. Ambos são propriedades do laço de geração: se o laço morar no
 *    Dart, cada chamada FFI é um bloqueio que o Dart não consegue interromper,
 *    e um `Future.timeout` apenas ABANDONA a espera enquanto a CPU do device
 *    segue gerando tokens que ninguém vai ler. Com o laço aqui, o prazo entra
 *    no `abort_callback` do próprio llama.cpp e a geração PARA.
 *
 * Versão do llama.cpp fixada em CMakeLists.txt (tag b6100).
 */

#ifndef GUBS_LLAMA_H
#define GUBS_LLAMA_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Incrementar SEMPRE que a assinatura de qualquer função abaixo mudar.
 * O lado Dart confere no boot: divergência desqualifica o motor (isAvailable
 * = false) em vez de arriscar uma chamada com layout errado. */
#define GUBS_LLAMA_ABI_VERSION 1

/* Códigos de erro de gubs_llama_generate. Todos negativos; >= 0 é o número de
 * bytes escritos em `out`. */
#define GUBS_ERR_ARGS      (-1) /* argumento inválido */
#define GUBS_ERR_TOKENIZE  (-2) /* prompt não tokenizável / maior que o contexto */
#define GUBS_ERR_DECODE    (-3) /* falha de inferência (inclui OOM do backend) */
#define GUBS_ERR_TIMEOUT   (-4) /* prazo estourou; geração abortada */
#define GUBS_ERR_OVERFLOW  (-5) /* saída não coube em `out` */

typedef struct gubs_llama_ctx gubs_llama_ctx;

/* Versão da ABI compilada. Primeira chamada feita pelo Dart. */
int32_t gubs_llama_abi_version(void);

/* Carrega modelo e cria contexto. Retorna NULL em qualquer falha — modelo
 * ausente, corrompido, ou RAM insuficiente. NULL é esperado e tratado: o app
 * degrada para o RuleOnlyEngine (RF-12), não quebra. */
gubs_llama_ctx *gubs_llama_open(const char *model_path,
                                int32_t n_ctx,
                                int32_t n_threads);

/* Gera texto de forma gulosa (greedy) a partir de `prompt`.
 *
 * Greedy = temperatura 0 e nenhuma fonte de aleatoriedade no laço. É isso que
 * satisfaz RF-05: a mesma entrada produz a mesma saída em qualquer execução,
 * sem depender de seed. (Seed só teria efeito com amostragem estocástica, que
 * deliberadamente não usamos.)
 *
 * `timeout_ms` <= 0 desliga o prazo — use apenas em bench offline.
 *
 * Retorna bytes escritos em `out` (sem terminador), ou um GUBS_ERR_*. */
int32_t gubs_llama_generate(gubs_llama_ctx *h,
                            const char *prompt,
                            int32_t max_tokens,
                            int64_t timeout_ms,
                            char *out,
                            int32_t out_cap);

/* Libera contexto e modelo. Aceita NULL. */
void gubs_llama_close(gubs_llama_ctx *h);

#ifdef __cplusplus
}
#endif

#endif /* GUBS_LLAMA_H */
