#ifndef AUDIOWRT_PLAYER_CORE_H
#define AUDIOWRT_PLAYER_CORE_H

#include <stddef.h>
#include <stdint.h>
#include <alsa/asoundlib.h>

int aw_http_stream_to_fd(const char *uri, int fd);
int aw_pcm_open(snd_pcm_t **pcm, unsigned int rate, unsigned int channels,
                snd_pcm_format_t format);
int aw_pcm_write(snd_pcm_t *pcm, const void *buffer, snd_pcm_uframes_t frames);
void aw_pcm_close(snd_pcm_t *pcm);
int aw_volume_percent(void);
void aw_scale_s16(int16_t *samples, size_t count);
void aw_scale_s32(int32_t *samples, size_t count);

#endif
