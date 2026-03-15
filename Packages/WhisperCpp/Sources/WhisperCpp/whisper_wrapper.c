#include "include/whisper_wrapper.h"
#include "whisper.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

// Audio loading helper — reads WAV 16kHz mono PCM
// Note: Assumes standard 44-byte PCM WAV header produced by AudioConverter.
static bool load_wav_file(const char *path, float **data, int *n_samples) {
    FILE *f = fopen(path, "rb");
    if (!f) return false;

    fseek(f, 0, SEEK_END);
    long file_size = ftell(f);
    fseek(f, 44, SEEK_SET);

    long data_size = file_size - 44;
    int n = (int)(data_size / sizeof(int16_t));

    int16_t *pcm = (int16_t *)malloc(data_size);
    if (!pcm) { fclose(f); return false; }

    fread(pcm, sizeof(int16_t), n, f);
    fclose(f);

    float *float_data = (float *)malloc(n * sizeof(float));
    if (!float_data) { free(pcm); return false; }

    for (int i = 0; i < n; i++) {
        float_data[i] = (float)pcm[i] / 32768.0f;
    }

    free(pcm);
    *data = float_data;
    *n_samples = n;
    return true;
}

struct progress_user_data {
    whisper_progress_callback cb;
    void *user_data;
};

static void internal_progress_cb(struct whisper_context *ctx, struct whisper_state *state, int progress, void *user_data) {
    struct progress_user_data *pud = (struct progress_user_data *)user_data;
    if (pud && pud->cb) {
        pud->cb((float)progress / 100.0f, pud->user_data);
    }
}

whisper_context *wrapper_init(const char *model_path) {
    struct whisper_context_params cparams = whisper_context_default_params();
    return whisper_init_from_file_with_params(model_path, cparams);
}

void wrapper_free(whisper_context *ctx) {
    if (ctx) whisper_free(ctx);
}

int wrapper_transcribe(
    whisper_context *ctx,
    const char *audio_path,
    const char *language,
    bool translate,
    whisper_progress_callback progress_cb,
    void *user_data
) {
    float *audio_data = NULL;
    int n_samples = 0;

    if (!load_wav_file(audio_path, &audio_data, &n_samples)) {
        return -1;
    }

    struct whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.language = language;
    params.translate = translate;
    params.print_progress = false;
    params.print_timestamps = false;

    struct progress_user_data pud = { progress_cb, user_data };
    params.progress_callback = internal_progress_cb;
    params.progress_callback_user_data = &pud;

    int result = whisper_full(ctx, params, audio_data, n_samples);
    free(audio_data);
    return result;
}

int wrapper_get_segment_count(whisper_context *ctx) {
    return whisper_full_n_segments(ctx);
}

whisper_segment_result wrapper_get_segment(whisper_context *ctx, int index) {
    whisper_segment_result seg;
    seg.start_ms = whisper_full_get_segment_t0(ctx, index) * 10;
    seg.end_ms = whisper_full_get_segment_t1(ctx, index) * 10;
    seg.text = whisper_full_get_segment_text(ctx, index);
    return seg;
}
