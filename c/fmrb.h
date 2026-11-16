/*
 * fmrb.h: the hand-written C layer of the Family mruby SDK, on top of the
 * generated fmrb_boundary.h (every function, record and hook) and
 * fmrb_sdk_version.h. Header-only and optional: an app that includes it
 * gets the conveniences the other languages' thin layers give (C strings
 * instead of a pointer and a length, a small text buffer for numbers and
 * lines, the window and sound receivers, colours, the event record), and
 * can still call every generated function directly.
 *
 *   #include "fmrb.h"
 *   FMRB_APP_SETUP();   // once in the app: event buffer, SDK version,
 *                       // memcpy and memset (there is no libc)
 *
 * Every function here is static (FMRB_HELPER), so what an app does not use
 * costs nothing; they are not marked inline, which lets the compiler keep
 * one copy of each at -Os (inline made the tour a third larger). Names
 * ending in _s take NUL-terminated C strings; the rest follow the generated
 * names.
 */
#ifndef FMRB_H
#define FMRB_H

#include <stdint.h>
#include "fmrb_boundary.h"
#include "fmrb_sdk_version.h"

/* A helper: static, and no warning for the ones an app does not call. */
#define FMRB_HELPER static __attribute__((unused))

/* Once in one file of the app: the place for on_event's record, the SDK
   version (the custom section "fmrb.sdk"), and memcpy and memset, which
   the compiler may call for copies and clears (with no libc the app
   brings its own: an import of env.memcpy would be refused at load). */
#define FMRB_APP_SETUP()                                          \
    FMRB_EVENT_BUFFER();                                          \
    FMRB_SDK_VERSION_SECTION();                                   \
    void *memcpy(void *d, const void *s, unsigned long n)         \
    {                                                             \
        uint8_t *dp = d;                                          \
        const uint8_t *sp = s;                                    \
        while (n--) *dp++ = *sp++;                                \
        return d;                                                 \
    }                                                             \
    void *memset(void *d, int c, unsigned long n)                 \
    {                                                             \
        uint8_t *dp = d;                                          \
        while (n--) *dp++ = (uint8_t)c;                           \
        return d;                                                 \
    }                                                             \
    typedef int fmrb_app_setup_done_t

/* ---- receivers and constants */

#define FMRB_WINDOW 0       /* the app window's drawer, open before on_create */
#define FMRB_AUDIO 0        /* the app's sound */
#define FMRB_TRANSPARENT -1 /* as a text background: leaves what is under it */
/* The two APU instances that play a tune (play_slot's instance): a long
   tune on MAIN and short effects on SUB, so an effect never cuts the tune. */
#define FMRB_AUDIO_MAIN 0
#define FMRB_AUDIO_SUB 1

/* Colours are RGB332 (RRRGGGBB). 0x01 is the desktop's transparent key:
   never draw with it. FMRB_RGB is the conversion at compile time (the top
   3/3/2 bits); fmrb_rgb asks the firmware, which rounds to the nearest. */
#define FMRB_RGB(r, g, b) ((((r) >> 5) << 5) | (((g) >> 5) << 2) | ((b) >> 6))
FMRB_HELPER int32_t fmrb_rgb(int32_t r, int32_t g, int32_t b) { return fmrb_gfx_rgb_to_332(r, g, b); }

/* ---- C strings */

FMRB_HELPER int32_t fmrb_len(const char *s)
{
    int32_t n = 0;
    while (s[n]) n++;
    return n;
}

FMRB_HELPER int32_t fmrb_streq(const char *a, const char *b)
{
    while (*a && *a == *b) { a++; b++; }
    return *a == *b;
}

/* A line of text built in place: what is appended past its size is cut
   off, and it is always NUL-terminated. */
typedef struct {
    char s[64];
    int32_t n;
} fmrb_text_t;

FMRB_HELPER fmrb_text_t *fmrb_text_clear(fmrb_text_t *t)
{
    t->n = 0;
    t->s[0] = '\0';
    return t;
}

/* Appends n bytes of s (a String from the boundary, not NUL-terminated). */
FMRB_HELPER fmrb_text_t *fmrb_put_n(fmrb_text_t *t, const char *s, int32_t n)
{
    for (int32_t i = 0; i < n && t->n < (int32_t)sizeof(t->s) - 1; i++) t->s[t->n++] = s[i];
    t->s[t->n] = '\0';
    return t;
}

FMRB_HELPER fmrb_text_t *fmrb_put(fmrb_text_t *t, const char *s) { return fmrb_put_n(t, s, fmrb_len(s)); }

FMRB_HELPER fmrb_text_t *fmrb_put_char(fmrb_text_t *t, char c) { return fmrb_put_n(t, &c, 1); }

/* Appends an integer in decimal. */
FMRB_HELPER fmrb_text_t *fmrb_put_int(fmrb_text_t *t, int64_t v)
{
    char d[20];
    int32_t i = 0;
    uint64_t u = v < 0 ? 0 - (uint64_t)v : (uint64_t)v;
    do { d[i++] = (char)('0' + u % 10); u /= 10; } while (u);
    if (v < 0) fmrb_put_char(t, '-');
    while (i) fmrb_put_char(t, d[--i]);
    return t;
}

/* Appends an integer with a 0 before it below 10 (clocks). */
FMRB_HELPER fmrb_text_t *fmrb_put_int2(fmrb_text_t *t, int64_t v)
{
    if (v >= 0 && v < 10) fmrb_put_char(t, '0');
    return fmrb_put_int(t, v);
}

/* Ends a String a boundary function wrote into buf (of size bytes) and
   whose full length it returned as n: the length that is really there,
   never past size - 1, with buf NUL-terminated. Negative n (none) is 0. */
FMRB_HELPER int32_t fmrb_terminate(char *buf, int32_t size, int32_t n)
{
    if (n < 0) n = 0;
    if (n > size - 1) n = size - 1;
    buf[n] = '\0';
    return n;
}

/* ---- FmrbApp */

/* The app's name, language and script path into buf (NUL-terminated); the
   length. */
FMRB_HELPER int32_t fmrb_app_name_s(char *buf, int32_t size)
{
    return fmrb_terminate(buf, size, fmrb_app_name(buf, size - 1));
}
FMRB_HELPER int32_t fmrb_app_language_s(char *buf, int32_t size)
{
    return fmrb_terminate(buf, size, fmrb_app_language(buf, size - 1));
}
FMRB_HELPER int32_t fmrb_app_script_path_s(char *buf, int32_t size)
{
    return fmrb_terminate(buf, size, fmrb_app_script_path(buf, size - 1));
}
/* The clipboard (at most limit bytes, 0: all that fits) into buf. */
FMRB_HELPER int32_t fmrb_app_clipboard_s(int32_t limit, char *buf, int32_t size)
{
    return fmrb_terminate(buf, size, fmrb_app_clipboard_raw(limit, buf, size - 1));
}
FMRB_HELPER int32_t fmrb_app_set_clipboard_s(const char *text)
{
    return fmrb_app_set_clipboard(text, fmrb_len(text)) == 1;
}

/* ---- the event record */

/* The printable character of a key event (0x21 to 0x7E), 0 for another. */
FMRB_HELPER char fmrb_event_char(const fmrb_app_event_t *ev)
{
    return ev->character > ' ' && ev->character < 127 ? (char)ev->character : 0;
}

/* ---- FmrbGfx */

FMRB_HELPER void fmrb_draw_text_s(int32_t gfx, int32_t x, int32_t y, const char *s, int32_t color, int32_t bg)
{
    fmrb_gfx_draw_text_raw(gfx, x, y, s, fmrb_len(s), color, bg, 0);
}
/* Text that mixes ASCII (the default font) and Japanese (the ja font). */
FMRB_HELPER void fmrb_draw_text_mixed_s(int32_t gfx, int32_t x, int32_t y, const char *s, int32_t color, int32_t bg)
{
    fmrb_gfx_draw_text_raw(gfx, x, y, s, fmrb_len(s), color, bg, 1);
}
FMRB_HELPER void fmrb_present(int32_t gfx) { fmrb_gfx_present_raw(gfx, 0, 0, 0); }

/* Copies a file to where the graphics side reads it (dest, under /cache). */
FMRB_HELPER int32_t fmrb_sync_file_s(int32_t gfx, const char *path, const char *dest)
{
    return fmrb_gfx_sync_file_raw(gfx, path, fmrb_len(path), dest, fmrb_len(dest)) == 1;
}
FMRB_HELPER int32_t fmrb_create_image_s(int32_t gfx, const char *path, fmrb_gfx_image_info_t *img)
{
    return fmrb_gfx_create_image(gfx, path, fmrb_len(path), img) == 1;
}
/* A width x height sprite image with key see-through (use_key), read from
   a PNG on the graphics side: its id, 0 when it cannot be made. */
FMRB_HELPER int32_t fmrb_load_sprite_image_s(int32_t gfx, int32_t w, int32_t h, int32_t key, int32_t use_key,
                                               const char *path)
{
    int32_t id = fmrb_gfx_create_sprite_image(gfx, w, h, key, use_key);
    if (id <= 0) return 0;
    if (fmrb_gfx_load_sprite_image(gfx, id, path, fmrb_len(path)) < 0) {
        fmrb_gfx_delete_sprite_image(gfx, id);
        return 0;
    }
    return id;
}

/* ---- FmrbAudio */

FMRB_HELPER int32_t fmrb_audio_load_fmsq_file_s(int32_t audio, int32_t slot, const char *path)
{
    return fmrb_audio_load_fmsq_file(audio, slot, path, fmrb_len(path)) >= 0;
}
/* 1 when it plays, 0 where it cannot (Retro), below 0 on an error. */
FMRB_HELPER int32_t fmrb_audio_play_wav_s(int32_t audio, const char *path)
{
    return fmrb_audio_play_wav(audio, path, fmrb_len(path));
}

/* ---- FmrbFile (1 or 0 for done or not, as the generated ones) */

/* Reads a file into buf (NUL-terminated); its length, -1 when there is
   none. */
FMRB_HELPER int32_t fmrb_file_read_s(const char *path, char *buf, int32_t size)
{
    int32_t n = fmrb_file_read(path, fmrb_len(path), (uint8_t *)buf, size - 1);
    if (n < 0) {
        buf[0] = '\0';
        return -1;
    }
    return fmrb_terminate(buf, size, n);
}
FMRB_HELPER int32_t fmrb_file_write_s(const char *path, const char *text)
{
    return fmrb_file_write(path, fmrb_len(path), (const uint8_t *)text, fmrb_len(text)) == 1;
}
FMRB_HELPER int32_t fmrb_file_append_s(const char *path, const char *text)
{
    return fmrb_file_append(path, fmrb_len(path), (const uint8_t *)text, fmrb_len(text)) == 1;
}
FMRB_HELPER int32_t fmrb_file_exist_s(const char *path) { return fmrb_file_exist(path, fmrb_len(path)) == 1; }
FMRB_HELPER int64_t fmrb_file_size_s(const char *path) { return fmrb_file_size(path, fmrb_len(path)); }
FMRB_HELPER int32_t fmrb_file_delete_s(const char *path) { return fmrb_file_delete(path, fmrb_len(path)) == 1; }
FMRB_HELPER int32_t fmrb_file_mkdir_s(const char *path) { return fmrb_file_mkdir(path, fmrb_len(path)) == 1; }
FMRB_HELPER int64_t fmrb_file_free_bytes_s(const char *path) { return fmrb_file_free_bytes(path, fmrb_len(path)); }
/* The names in a directory, one per line, into buf (NUL-terminated); the
   length, -1 when it cannot be read. */
FMRB_HELPER int32_t fmrb_file_list_s(const char *dir, char *buf, int32_t size)
{
    int32_t n = fmrb_file_list_raw(dir, fmrb_len(dir), buf, size - 1);
    if (n < 0) {
        buf[0] = '\0';
        return -1;
    }
    return fmrb_terminate(buf, size, n);
}

/* ---- the log (the same log as a Ruby app's) */

FMRB_HELPER void fmrb_log_debug_s(const char *s) { fmrb_log_debug_raw(s, fmrb_len(s)); }
FMRB_HELPER void fmrb_log_info_s(const char *s) { fmrb_log_info_raw(s, fmrb_len(s)); }
FMRB_HELPER void fmrb_log_warn_s(const char *s) { fmrb_log_warn_raw(s, fmrb_len(s)); }
FMRB_HELPER void fmrb_log_error_s(const char *s) { fmrb_log_error_raw(s, fmrb_len(s)); }

#endif /* FMRB_H */
