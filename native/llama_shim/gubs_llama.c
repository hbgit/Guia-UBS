/* Implementação do shim. Ver gubs_llama.h para o racional da fronteira.
 *
 * Contrato de uso: um `gubs_llama_ctx` NÃO é thread-safe. O app usa exatamente
 * um, dentro de um isolate dedicado (ver llama_engine.dart), e nunca emite duas
 * gerações concorrentes.
 */

#include "gubs_llama.h"

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "llama.h"

/* --------------------------------------------------------------------------
 * Prazo (deadline)
 * --------------------------------------------------------------------------
 * O ponteiro para esta struct é entregue ao llama.cpp na criação do contexto e
 * precisa sobreviver a ela — por isso mora DENTRO do handle, e não na pilha de
 * gubs_llama_generate. */

struct gubs_deadline {
    int64_t abort_at_ms; /* 0 = sem prazo */
};

struct gubs_llama_ctx {
    struct llama_model   *model;
    struct llama_context *ctx;
    struct llama_sampler *smpl;
    struct gubs_deadline  deadline;
};

static int64_t gubs_now_ms(void) {
    struct timespec ts;
    /* Relógio monotônico: o usuário pode mudar o fuso ou a hora do aparelho no
     * meio de uma triagem, e isso não pode virar um timeout de horas. */
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

/* Chamado pelo llama.cpp entre operações do grafo. `true` aborta o decode.
 * Só funciona em execução por CPU — mais um motivo para n_gpu_layers = 0. */
static bool gubs_should_abort(void *data) {
    const struct gubs_deadline *d = (const struct gubs_deadline *)data;
    if (d == NULL || d->abort_at_ms == 0) {
        return false;
    }
    return gubs_now_ms() >= d->abort_at_ms;
}

/* llama.cpp escreve diagnóstico em stderr por padrão. Silenciamos: o app não
 * tem console, e log de inferência é justamente onde conteúdo do usuário
 * vazaria para fora da memória (INV-2 / LGPD-RF13). */
static void gubs_log_sink(enum ggml_log_level level, const char *text, void *user_data) {
    (void)level;
    (void)text;
    (void)user_data;
}

static void gubs_backend_init_once(void) {
    static bool done = false;
    if (!done) {
        llama_log_set(gubs_log_sink, NULL);
        llama_backend_init();
        done = true;
    }
}

int32_t gubs_llama_abi_version(void) {
    return GUBS_LLAMA_ABI_VERSION;
}

gubs_llama_ctx *gubs_llama_open(const char *model_path, int32_t n_ctx, int32_t n_threads) {
    if (model_path == NULL || n_ctx <= 0 || n_threads <= 0) {
        return NULL;
    }

    gubs_backend_init_once();

    gubs_llama_ctx *h = (gubs_llama_ctx *)calloc(1, sizeof(gubs_llama_ctx));
    if (h == NULL) {
        return NULL;
    }

    struct llama_model_params mp = llama_model_default_params();
    /* CPU pura. Device de entrada (RNF-09) não tem backend de GPU confiável, e
     * o abort_callback — nosso teto de 5 s — só vale para CPU. */
    mp.n_gpu_layers = 0;
    /* mmap deixa o kernel paginar os pesos sob pressão de memória em vez de o
     * processo levar OOM kill com 4 GB de RAM. */
    mp.use_mmap  = true;
    mp.use_mlock = false;

    h->model = llama_model_load_from_file(model_path, mp);
    if (h->model == NULL) {
        free(h);
        return NULL;
    }

    struct llama_context_params cp = llama_context_default_params();
    cp.n_ctx           = (uint32_t)n_ctx;
    cp.n_batch         = (uint32_t)n_ctx;
    cp.n_threads       = n_threads;
    cp.n_threads_batch = n_threads;
    cp.no_perf         = true;
    cp.abort_callback      = gubs_should_abort;
    cp.abort_callback_data = &h->deadline;

    h->ctx = llama_init_from_model(h->model, cp);
    if (h->ctx == NULL) {
        llama_model_free(h->model);
        free(h);
        return NULL;
    }

    /* Cadeia de amostragem com um único elo: greedy. Sem top_k, sem top_p, sem
     * temperatura, sem dist — nada que introduza aleatoriedade. É a definição
     * operacional de "temperatura 0" do RF-05. */
    h->smpl = llama_sampler_chain_init(llama_sampler_chain_default_params());
    if (h->smpl == NULL) {
        llama_free(h->ctx);
        llama_model_free(h->model);
        free(h);
        return NULL;
    }
    llama_sampler_chain_add(h->smpl, llama_sampler_init_greedy());

    return h;
}

int32_t gubs_llama_generate(gubs_llama_ctx *h,
                            const char *prompt,
                            int32_t max_tokens,
                            int64_t timeout_ms,
                            char *out,
                            int32_t out_cap) {
    if (h == NULL || prompt == NULL || out == NULL || out_cap <= 0 || max_tokens <= 0) {
        return GUBS_ERR_ARGS;
    }

    h->deadline.abort_at_ms = timeout_ms > 0 ? gubs_now_ms() + timeout_ms : 0;

    /* Cada triagem começa do zero. Sem isto, a sessão anterior permaneceria no
     * cache KV e influenciaria a próxima — quebrando o determinismo E deixando
     * sintomas de um usuário residentes na memória do processo (INV-2). */
    llama_memory_clear(llama_get_memory(h->ctx), true);
    llama_sampler_reset(h->smpl);

    const struct llama_vocab *vocab = llama_model_get_vocab(h->model);
    const int32_t prompt_len = (int32_t)strlen(prompt);
    const int32_t n_ctx = (int32_t)llama_n_ctx(h->ctx);

    /* Um token nunca representa menos de um byte, então o comprimento em bytes
     * é um teto seguro para a contagem de tokens. */
    const int32_t cap_tokens = prompt_len + 8;
    llama_token *tokens = (llama_token *)malloc((size_t)cap_tokens * sizeof(llama_token));
    if (tokens == NULL) {
        return GUBS_ERR_DECODE;
    }

    const int32_t n_prompt =
        llama_tokenize(vocab, prompt, prompt_len, tokens, cap_tokens, true, false);
    if (n_prompt <= 0 || n_prompt >= n_ctx) {
        free(tokens);
        return GUBS_ERR_TOKENIZE;
    }

    int32_t rc = llama_decode(h->ctx, llama_batch_get_one(tokens, n_prompt));
    free(tokens);
    if (rc != 0) {
        return rc == 2 ? GUBS_ERR_TIMEOUT : GUBS_ERR_DECODE;
    }

    int32_t written = 0;
    int32_t n_generated = 0;

    while (n_generated < max_tokens && (n_prompt + n_generated) < n_ctx) {
        if (gubs_should_abort(&h->deadline)) {
            return GUBS_ERR_TIMEOUT;
        }

        llama_token id = llama_sampler_sample(h->smpl, h->ctx, -1);
        llama_sampler_accept(h->smpl, id);

        if (llama_vocab_is_eog(vocab, id)) {
            break;
        }

        /* `special = false`: tokens de controle do modelo não entram na saída.
         * O decodificador do lado Dart só procura identificadores de desfecho;
         * marcação de chat só serviria para confundi-lo. */
        const int32_t piece_len =
            llama_token_to_piece(vocab, id, out + written, out_cap - written, 0, false);
        if (piece_len < 0) {
            return GUBS_ERR_OVERFLOW;
        }
        written += piece_len;

        n_generated++;

        rc = llama_decode(h->ctx, llama_batch_get_one(&id, 1));
        if (rc != 0) {
            /* Abortado pelo prazo (2) é resultado normal sob carga, não defeito. */
            return rc == 2 ? GUBS_ERR_TIMEOUT : GUBS_ERR_DECODE;
        }
    }

    return written;
}

void gubs_llama_close(gubs_llama_ctx *h) {
    if (h == NULL) {
        return;
    }
    if (h->smpl != NULL) {
        llama_sampler_free(h->smpl);
    }
    if (h->ctx != NULL) {
        llama_free(h->ctx);
    }
    if (h->model != NULL) {
        llama_model_free(h->model);
    }
    free(h);
}
