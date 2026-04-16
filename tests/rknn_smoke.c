/*
 * Minimal RKNN inference smoke test. Loads a .rknn model, runs inference
 * N times against a uniform input, reports timing. No OpenCV — only libc
 * and librknnrt. See scripts/test-inference.sh for end-to-end orchestration
 * (download + compile + run + pre/post IRQ counters).
 *
 * Build: gcc rknn_smoke.c -I. -L. -lrknnrt -o rknn_smoke
 * Run:   LD_LIBRARY_PATH=. ./rknn_smoke model.rknn [iters] [core_mask]
 *
 * core_mask: auto | 0 | 1 | 2 | 0_1 | 0_1_2  (default: auto)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "rknn_api.h"

static unsigned char *load_file(const char *path, uint32_t *size_out) {
    FILE *f = fopen(path, "rb");
    if (!f) { perror(path); return NULL; }
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    unsigned char *buf = malloc(sz);
    if (!buf) { fclose(f); return NULL; }
    if (fread(buf, 1, sz, f) != (size_t)sz) {
        free(buf); fclose(f); return NULL;
    }
    fclose(f);
    *size_out = (uint32_t)sz;
    return buf;
}

static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

static rknn_core_mask parse_core_mask(const char *s) {
    if (!s || !*s || !strcmp(s, "auto")) return RKNN_NPU_CORE_AUTO;
    if (!strcmp(s, "0"))     return RKNN_NPU_CORE_0;
    if (!strcmp(s, "1"))     return RKNN_NPU_CORE_1;
    if (!strcmp(s, "2"))     return RKNN_NPU_CORE_2;
    if (!strcmp(s, "0_1"))   return RKNN_NPU_CORE_0_1;
    if (!strcmp(s, "0_1_2")) return RKNN_NPU_CORE_0_1_2;
    fprintf(stderr, "unknown core_mask '%s' — using auto\n", s);
    return RKNN_NPU_CORE_AUTO;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s model.rknn [iterations] [core_mask]\n", argv[0]);
        fprintf(stderr, "  core_mask: auto | 0 | 1 | 2 | 0_1 | 0_1_2  (default: auto)\n");
        return 1;
    }
    const char *model_path = argv[1];
    int iters = (argc >= 3) ? atoi(argv[2]) : 100;
    const char *mask_str = (argc >= 4) ? argv[3] : "auto";
    rknn_core_mask mask = parse_core_mask(mask_str);

    uint32_t model_size = 0;
    unsigned char *model = load_file(model_path, &model_size);
    if (!model) return 2;
    printf("loaded model: %s (%u bytes)\n", model_path, model_size);

    rknn_context ctx = 0;
    int rc = rknn_init(&ctx, model, model_size, 0, NULL);
    if (rc != RKNN_SUCC) {
        fprintf(stderr, "rknn_init failed: %d\n", rc);
        return 3;
    }
    printf("rknn_init ok, ctx=%lx\n", (unsigned long)ctx);

    if (mask != RKNN_NPU_CORE_AUTO) {
        rc = rknn_set_core_mask(ctx, mask);
        if (rc != RKNN_SUCC)
            fprintf(stderr, "warning: rknn_set_core_mask(%s) rc=%d\n", mask_str, rc);
        else
            printf("core mask : %s\n", mask_str);
    }

    rknn_sdk_version sdkv;
    memset(&sdkv, 0, sizeof(sdkv));
    rc = rknn_query(ctx, RKNN_QUERY_SDK_VERSION, &sdkv, sizeof(sdkv));
    if (rc == RKNN_SUCC)
        printf("SDK api=%s driver=%s\n", sdkv.api_version, sdkv.drv_version);

    rknn_input_output_num io;
    rc = rknn_query(ctx, RKNN_QUERY_IN_OUT_NUM, &io, sizeof(io));
    if (rc != RKNN_SUCC) {
        fprintf(stderr, "query IN_OUT_NUM failed: %d\n", rc);
        return 4;
    }
    printf("inputs=%u outputs=%u\n", io.n_input, io.n_output);

    rknn_tensor_attr in_attr[io.n_input];
    memset(in_attr, 0, sizeof(in_attr));
    for (uint32_t i = 0; i < io.n_input; i++) {
        in_attr[i].index = i;
        rc = rknn_query(ctx, RKNN_QUERY_INPUT_ATTR, &in_attr[i], sizeof(in_attr[i]));
        if (rc != RKNN_SUCC) { fprintf(stderr, "INPUT_ATTR[%u] rc=%d\n", i, rc); return 5; }
        printf("  in[%u] name=%s dims=[%u,%u,%u,%u] size=%u fmt=%s\n",
               i, in_attr[i].name,
               in_attr[i].dims[0], in_attr[i].dims[1],
               in_attr[i].dims[2], in_attr[i].dims[3],
               in_attr[i].size, get_format_string(in_attr[i].fmt));
    }

    /* Allocate + fill input buffers with a fixed byte so we exercise
     * the model uniformly. Actual classification accuracy isn't the
     * point here; only that rknn_run completes and the NPU acts. */
    rknn_input inputs[io.n_input];
    memset(inputs, 0, sizeof(inputs));
    for (uint32_t i = 0; i < io.n_input; i++) {
        inputs[i].index = i;
        inputs[i].buf = malloc(in_attr[i].size);
        if (!inputs[i].buf) { fprintf(stderr, "oom\n"); return 6; }
        memset(inputs[i].buf, 128, in_attr[i].size);  /* mid-gray */
        inputs[i].size = in_attr[i].size;
        inputs[i].pass_through = 0;
        inputs[i].type = RKNN_TENSOR_UINT8;
        inputs[i].fmt = RKNN_TENSOR_NHWC;
    }

    rc = rknn_inputs_set(ctx, io.n_input, inputs);
    if (rc != RKNN_SUCC) { fprintf(stderr, "inputs_set rc=%d\n", rc); return 7; }

    /* Warmup + timed loop. */
    printf("\nwarming up (5 iters)...\n");
    for (int i = 0; i < 5; i++) {
        rc = rknn_run(ctx, NULL);
        if (rc != RKNN_SUCC) { fprintf(stderr, "warmup run[%d] rc=%d\n", i, rc); return 8; }
        rknn_output outs[io.n_output];
        memset(outs, 0, sizeof(outs));
        for (uint32_t j = 0; j < io.n_output; j++) outs[j].want_float = 1;
        rknn_outputs_get(ctx, io.n_output, outs, NULL);
        rknn_outputs_release(ctx, io.n_output, outs);
    }

    printf("running %d timed iterations...\n", iters);
    double t0 = now_ms();
    for (int i = 0; i < iters; i++) {
        rc = rknn_run(ctx, NULL);
        if (rc != RKNN_SUCC) { fprintf(stderr, "run[%d] rc=%d\n", i, rc); return 9; }
        rknn_output outs[io.n_output];
        memset(outs, 0, sizeof(outs));
        for (uint32_t j = 0; j < io.n_output; j++) outs[j].want_float = 1;
        rknn_outputs_get(ctx, io.n_output, outs, NULL);
        rknn_outputs_release(ctx, io.n_output, outs);
    }
    double elapsed = now_ms() - t0;
    printf("\n=== RESULTS ===\n");
    printf("iterations  : %d\n", iters);
    printf("total time  : %.2f ms\n", elapsed);
    printf("per-inference: %.3f ms\n", elapsed / iters);
    printf("throughput  : %.1f inf/s\n", (iters * 1000.0) / elapsed);

    for (uint32_t i = 0; i < io.n_input; i++) free(inputs[i].buf);
    rknn_destroy(ctx);
    free(model);
    return 0;
}
