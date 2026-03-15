#ifndef WHISPER_WRAPPER_H
#define WHISPER_WRAPPER_H

#include <stdbool.h>
#include <stdint.h>

typedef struct whisper_context whisper_context;

typedef struct {
    int64_t start_ms;
    int64_t end_ms;
    const char *text;
} whisper_segment_result;

typedef void (*whisper_progress_callback)(float progress, void *user_data);

whisper_context *wrapper_init(const char *model_path);
void wrapper_free(whisper_context *ctx);

int wrapper_transcribe(
    whisper_context *ctx,
    const char *audio_path,
    const char *language,
    bool translate,
    whisper_progress_callback progress_cb,
    void *user_data
);

int wrapper_get_segment_count(whisper_context *ctx);
whisper_segment_result wrapper_get_segment(whisper_context *ctx, int index);

#endif
