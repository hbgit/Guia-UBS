/* Bench autônomo do shim — mede latência de inferência direto no aparelho.
 *
 * ===========================================================================
 * POR QUE ESTE BINÁRIO EXISTE, SE JÁ HÁ DOIS BENCHES EM DART
 * ===========================================================================
 *
 * Os benches em Dart medem o caminho completo do app, que é o que o usuário
 * sente. Este mede a mesma inferência sem o app, e isso permite duas coisas
 * que aqueles não permitem:
 *
 * 1. FIXAR NÚCLEOS. Rodando sob `taskset`, dá para prender a inferência ao
 *    cluster pequeno (Cortex-A55) de um aparelho intermediário. Como um SoC de
 *    entrada é essencialmente um punhado de A55, isso PRODUZ uma medição de
 *    classe de entrada em hardware que não é de entrada — em vez de estimar um
 *    fator de conversão no papel.
 *
 * 2. RODAR SEM O CICLO DE VIDA DO APP. `flutter test` desinstala o aplicativo
 *    ao terminar, e desinstalar apaga o diretório onde o modelo de 768 MB foi
 *    colocado. Aqui o modelo mora em /data/local/tmp e sobrevive.
 *
 * Uso (no aparelho):
 *   gubs_bench <modelo.gguf> <prompts.txt> [iteracoes] [threads] [n_ctx]
 *
 * O arquivo de prompts traz um prompt por bloco, separados por uma linha
 * contendo apenas `%%`. Ele é GERADO pelo construtor de prompts em Dart, para
 * que o texto medido seja exatamente o que o app enviaria.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "gubs_llama.h"

#define MAX_PROMPTS 64
#define MAX_PROMPT_BYTES 4096
#define OUT_CAP 2048

static int64_t now_us(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000000 + ts.tv_nsec / 1000;
}

static int cmp_i64(const void *a, const void *b) {
    const int64_t x = *(const int64_t *)a;
    const int64_t y = *(const int64_t *)b;
    return (x > y) - (x < y);
}

/* Percentil por posto mais próximo — mesma definição do lado Dart. */
static int64_t percentile(const int64_t *sorted, int n, double p) {
    if (n <= 0) return 0;
    int rank = (int)(p * n + 0.999999);
    if (rank < 1) rank = 1;
    if (rank > n) rank = n;
    return sorted[rank - 1];
}

static long peak_rss_mb(void) {
    FILE *f = fopen("/proc/self/status", "r");
    if (!f) return -1;
    char line[256];
    long kb = -1;
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "VmHWM:", 6) == 0) {
            sscanf(line + 6, "%ld", &kb);
            break;
        }
    }
    fclose(f);
    return kb < 0 ? -1 : kb / 1024;
}

/* Carrega prompts separados por uma linha `%%`. Devolve a quantidade. */
static int load_prompts(const char *path, char prompts[][MAX_PROMPT_BYTES]) {
    FILE *f = fopen(path, "r");
    if (!f) return -1;

    int count = 0;
    size_t used = 0;
    prompts[0][0] = '\0';

    char line[1024];
    while (fgets(line, sizeof(line), f) && count < MAX_PROMPTS) {
        if (strcmp(line, "%%\n") == 0 || strcmp(line, "%%") == 0) {
            if (used > 0) {
                count++;
                used = 0;
                if (count < MAX_PROMPTS) prompts[count][0] = '\0';
            }
            continue;
        }
        const size_t len = strlen(line);
        if (used + len + 1 >= MAX_PROMPT_BYTES) continue;
        memcpy(prompts[count] + used, line, len + 1);
        used += len;
    }
    if (used > 0 && count < MAX_PROMPTS) count++;

    fclose(f);
    return count;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr,
                "uso: %s <modelo.gguf> <prompts.txt> [iteracoes] [threads] [n_ctx]\n",
                argv[0]);
        return 2;
    }

    const char *model_path = argv[1];
    const char *prompts_path = argv[2];
    const int iterations = argc > 3 ? atoi(argv[3]) : 20;
    const int threads = argc > 4 ? atoi(argv[4]) : 4;
    const int n_ctx = argc > 5 ? atoi(argv[5]) : 512;

    static char prompts[MAX_PROMPTS][MAX_PROMPT_BYTES];
    const int n_prompts = load_prompts(prompts_path, prompts);
    if (n_prompts <= 0) {
        fprintf(stderr, "nenhum prompt lido de %s\n", prompts_path);
        return 2;
    }

    printf("abi=%d modelo=%s prompts=%d iteracoes=%d threads=%d n_ctx=%d\n",
           gubs_llama_abi_version(), model_path, n_prompts, iterations, threads,
           n_ctx);

    const int64_t load_start = now_us();
    gubs_llama_ctx *h = gubs_llama_open(model_path, n_ctx, threads);
    if (!h) {
        fprintf(stderr, "FALHOU: modelo nao carregou\n");
        return 1;
    }
    printf("carga=%lldms\n", (long long)((now_us() - load_start) / 1000));

    char out[OUT_CAP + 1];

    /* Aquecimento: paga paginacao do mmap e alocacao de buffers. Contar esta
     * passada mascararia a latencia de regime, que e a que o usuario sente da
     * segunda triagem em diante. */
    gubs_llama_generate(h, prompts[0], 16, 0, out, OUT_CAP);

    int64_t *lat = (int64_t *)malloc(sizeof(int64_t) * (size_t)iterations);
    if (!lat) {
        gubs_llama_close(h);
        return 1;
    }

    int with_output = 0;
    for (int i = 0; i < iterations; i++) {
        const char *prompt = prompts[i % n_prompts];
        const int64_t t0 = now_us();
        /* timeout 0 = sem prazo: aqui queremos a latencia REAL, nao a truncada
         * pelo teto de 5 s. O teto e politica do app; o bench precisa mostrar
         * quanto o aparelho de fato leva, inclusive quando estoura. */
        const int32_t rc = gubs_llama_generate(h, prompt, 16, 0, out, OUT_CAP);
        lat[i] = now_us() - t0;
        if (rc > 0) with_output++;
    }

    qsort(lat, (size_t)iterations, sizeof(int64_t), cmp_i64);

    printf("p50=%.1fms p95=%.1fms max=%.1fms com_saida=%d/%d rss_pico=%ldMB\n",
           percentile(lat, iterations, 0.50) / 1000.0,
           percentile(lat, iterations, 0.95) / 1000.0,
           lat[iterations - 1] / 1000.0,
           with_output, iterations, peak_rss_mb());

    free(lat);
    gubs_llama_close(h);
    return 0;
}
