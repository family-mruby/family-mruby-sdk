/*
 * hello: the app docs/getting_started.md builds in C. A line of text and a
 * counter that goes up by itself; a key shows its character and space sets
 * the counter back to 0, q ends the app.
 *
 * Freestanding wasm (no libc): the boundary's flat functions from
 * fmrb_boundary.h, strings as a pointer and a length. Build it with the
 * Makefile next to this file, or with the one line in the guide.
 */
#include <stdint.h>
#include "fmrb_boundary.h"
#include "fmrb_sdk_version.h"

/* Once in the app: the place for on_event's record, and the SDK version
   (the custom section "fmrb.sdk"). */
FMRB_EVENT_BUFFER();
FMRB_SDK_VERSION_SECTION();

#define WINDOW 0          /* drawer 0 is the app's window */
#define TRANSPARENT (-1)  /* no background behind text */

static int64_t count;
static char key[8] = "-";
static int32_t bg, fg;

static int32_t len(const char *s)
{
    int32_t n = 0;
    while (s[n]) n++;
    return n;
}

/* s followed by v in decimal, into out (32 bytes). */
static const char *with_int(char *out, const char *s, int64_t v)
{
    int32_t n = 0;
    while (*s) out[n++] = *s++;
    char tmp[21];
    int32_t t = 0;
    uint64_t u = v < 0 ? (uint64_t)(-v) : (uint64_t)v;
    do { tmp[t++] = (char)('0' + u % 10); u /= 10; } while (u);
    if (v < 0) out[n++] = '-';
    while (t) out[n++] = tmp[--t];
    out[n] = '\0';
    return out;
}

static void text(int32_t x, int32_t y, const char *s)
{
    fmrb_gfx_draw_text_raw(WINDOW, x, y, s, len(s), fg, TRANSPARENT, 0);
}

static void log_info(const char *s) { fmrb_log_info_raw(s, len(s)); }

void on_create(void)
{
    /* White paper (never 0x01: the transparent key), black ink. */
    bg = fmrb_gfx_rgb_to_332(255, 255, 255);
    fg = fmrb_gfx_rgb_to_332(0, 0, 0);
    log_info("hello: started");
}

int32_t on_update(void)
{
    char line[32];
    count++;
    fmrb_gfx_fill_rect(WINDOW, 0, 0, fmrb_gfx_area_width(WINDOW), fmrb_gfx_area_height(WINDOW), bg);
    text(4, 4, "Hello, Family mruby!");
    text(4, 16, with_int(line, "count ", count));
    char k[16] = "key   ";
    for (int i = 0; key[i]; i++) { k[6 + i] = key[i]; k[7 + i] = '\0'; }
    text(4, 28, k);
    fmrb_gfx_present_raw(WINDOW, 0, 0, 0);
    return 100; /* call me again in 100 ms */
}

void on_event(const fmrb_app_event_t *ev)
{
    if (ev->type != FMRB_APP_EVENT_TYPE_KEY_DOWN || ev->character == 0) return;
    if (ev->character == 'q') {
        fmrb_app_stop();
    } else if (ev->character == ' ') {
        count = 0;
        const char *s = "space";
        for (int i = 0; i < 6; i++) key[i] = s[i];
    } else if (ev->character < 0x80) {
        key[0] = (char)ev->character;
        key[1] = '\0';
    }
}

void on_destroy(void)
{
    char line[32];
    log_info(with_int(line, "hello: bye at count ", count));
}
