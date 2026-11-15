/*
 * tour: hello plus a tour of the main functions, one page at a time --
 * shapes, text (Japanese too), a picture, sound and the system side (the
 * app's information, clocks, memory, a file, the last input). Every SDK
 * language has this same app with the same screen (tinygo/examples/tour is
 * the TinyGo one), so the languages can be compared line by line; the common
 * specification is in docs/tour.md.
 *
 *   click or 1-5   change page
 *   q              quit
 *   the page's own keys are listed at its bottom
 *
 * It calls the boundary's flat functions (fmrb_boundary.h) directly, with no
 * libc: freestanding wasm, built by c/build.rb (or its Makefile) with zig cc.
 */
#include <stdint.h>
#include "fmrb_boundary.h"
#include "fmrb_sdk_version.h"

/* Once in the app: the place the firmware writes on_event's record into,
   and the SDK version (the custom section "fmrb.sdk"). */
FMRB_EVENT_BUFFER();
FMRB_SDK_VERSION_SECTION();

/* The compiler may call these for copies and clears; with no libc the app
   brings its own (an import of env.memcpy would be refused at load). */
void *memcpy(void *d, const void *s, unsigned long n)
{
    uint8_t *dp = d;
    const uint8_t *sp = s;
    while (n--) *dp++ = *sp++;
    return d;
}
void *memset(void *d, int c, unsigned long n)
{
    uint8_t *dp = d;
    while (n--) *dp++ = (uint8_t)c;
    return d;
}

/* The page is white and the palette is picked for contrast against it
   (RGB332, RRRGGGBB). 0x01 would be the transparent key: not used. */
enum {
    PAPER = 0xFF, INK = 0x00, INK_SUB = 0x49,
    C_RED = 0xC0, C_GREEN = 0x0C, C_BLUE = 0x02, C_ORANGE = 0xE8,
    C_TEAL = 0x0F, C_PURPLE = 0x82, C_PANEL = 0xB6,
};
#define WINDOW 0 /* the window's drawer */

static const char PICTURE[] = "/usr/share/asterism/icon.png";
static const char CACHED[] = "/cache/app/tour/icon.png";
static const char DATA_FILE[] = "/home/tour.txt";
/* konnichiwa ABC nihongo, in UTF-8 */
static const char SAMPLE_JA[] = "\xe3\x81\x93\xe3\x82\x93\xe3\x81\xab\xe3\x81\xa1\xe3\x81\xaf ABC "
                                "\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e";

static const char *const PAGES[] = { "Shapes", "Text", "Image", "Sound", "System" };
static const char *const KEYS[] = {
    "click or 1-5: pages  q: quit",
    "T: font",
    "I: show / hide the picture",
    "1 scale  3 beep  0 stop",
    "W: write a file",
};
static const int32_t SCALE[] = { 262, 294, 330, 349, 392, 440, 494, 523 };
#define SCALE_N ((int32_t)(sizeof(SCALE) / sizeof(SCALE[0])))

static int32_t page, font_mode, scale_i = -1;
static int64_t started, scale_at, note_off_at[2];
static int32_t blink;
static int32_t img_tried, img_ok, img_shown = 1;
static fmrb_gfx_image_info_t img;
static char file_text[24] = "-";
static char input[32] = "-";

/* ---- strings, without libc */

static int32_t len(const char *s)
{
    int32_t n = 0;
    while (s[n]) n++;
    return n;
}

/* A small text buffer: put appends and keeps it NUL-terminated. */
typedef struct { char s[64]; int32_t n; } buf_t;

static void put(buf_t *b, const char *s)
{
    while (*s && b->n < (int32_t)sizeof(b->s) - 1) b->s[b->n++] = *s++;
    b->s[b->n] = '\0';
}

static void put_int(buf_t *b, int64_t v)
{
    char tmp[21];
    int32_t t = 0;
    uint64_t u = v < 0 ? (uint64_t)(-v) : (uint64_t)v;
    do { tmp[t++] = (char)('0' + u % 10); u /= 10; } while (u);
    if (v < 0) put(b, "-");
    while (t) { char c[2] = { tmp[--t], 0 }; put(b, c); }
}

static void put2(buf_t *b, int32_t v)
{
    if (v < 10) put(b, "0");
    put_int(b, v);
}

static void text(int32_t x, int32_t y, const char *s, int32_t color)
{
    fmrb_gfx_draw_text_raw(WINDOW, x, y, s, len(s), color, PAPER, 0);
}

static void log_info(const char *s) { fmrb_log_info_raw(s, len(s)); }

static const char *platform(void)
{
    return fmrb_app_platform() == FMRB_APP_PLATFORM_ESP32 ? "esp32" : "linux";
}

static void language(buf_t *b)
{
    char l[8];
    int32_t n = fmrb_app_language(l, sizeof(l) - 1);
    if (n < 0 || n >= (int32_t)sizeof(l)) n = 0;
    l[n] = '\0';
    put(b, l);
}

/* ---- page 1: shapes */

static void draw_shapes(int32_t y0)
{
    fmrb_gfx_draw_round_rect(WINDOW, 6, y0 + 4, 56, 26, 6, C_TEAL);
    fmrb_gfx_fill_round_rect(WINDOW, 70, y0 + 4, 56, 26, 6, C_GREEN);
    fmrb_gfx_draw_ellipse(WINDOW, 34, y0 + 52, 26, 14, C_PURPLE);
    fmrb_gfx_fill_ellipse(WINDOW, 98, y0 + 52, 26, 14, C_RED);
    fmrb_gfx_draw_triangle(WINDOW, 8, y0 + 104, 60, y0 + 104, 34, y0 + 74, C_ORANGE);
    fmrb_gfx_fill_triangle(WINDOW, 72, y0 + 104, 124, y0 + 104, 98, y0 + 74, C_BLUE);
    static const int32_t colors[] = { C_RED, C_ORANGE, C_GREEN, C_TEAL };
    static const int32_t dxs[] = { -30, -10, 10, 30 };
    for (int32_t i = 0; i < 4; i++) {
        fmrb_gfx_draw_line(WINDOW, 160, y0 + 104, 160 + dxs[i], y0 + 8, colors[i]);
    }
    for (int32_t i = 0; i < 3; i++) {
        fmrb_gfx_draw_circle(WINDOW, 140 + i * 22, y0 + 40, 9, INK);
        fmrb_gfx_fill_circle(WINDOW, 140 + i * 22, y0 + 40, 4, C_PANEL);
    }
}

/* ---- page 2: text */

static void draw_text(int32_t y0)
{
    static const char *const modes[] = { "default font", "ja font", "mixed (ascii + ja)" };
    text(6, y0 + 6, modes[font_mode], INK_SUB);
    if (font_mode == 0) {
        text(6, y0 + 20, "ABC abc 123", C_BLUE);
    } else if (font_mode == 1) {
        fmrb_gfx_set_font_raw(WINDOW, FMRB_GFX_SET_FONT_RAW_FAMILY_JA, 12);
        text(6, y0 + 20, SAMPLE_JA, C_BLUE);
        fmrb_gfx_set_font_raw(WINDOW, FMRB_GFX_SET_FONT_RAW_FAMILY_DEFAULT, 0);
    } else {
        fmrb_gfx_draw_text_raw(WINDOW, 6, y0 + 20, SAMPLE_JA, len(SAMPLE_JA), C_BLUE, PAPER, 1);
    }
    int32_t sum = 0;
    for (int32_t i = 1; i <= 10; i++) sum += i;
    buf_t rows[5] = { 0 };
    put(&rows[0], "language "); language(&rows[0]);
    put(&rows[1], "sum(1..10) = "); put_int(&rows[1], sum);
    put(&rows[2], "2^16 = "); put_int(&rows[2], 1 << 16);
    put(&rows[3], "area "); put_int(&rows[3], fmrb_gfx_area_width(WINDOW));
    put(&rows[3], "x"); put_int(&rows[3], fmrb_gfx_area_height(WINDOW));
    put(&rows[4], "SDK " FMRB_SDK_VERSION);
    for (int32_t i = 0; i < 5; i++) text(6, y0 + 40 + i * 10, rows[i].s, INK);
}

/* ---- page 3: a picture */

static void draw_image(int32_t y0)
{
    if (!img_tried) {
        img_tried = 1;
        if (fmrb_gfx_sync_file_raw(WINDOW, PICTURE, len(PICTURE), CACHED, len(CACHED)) == 1) {
            img_ok = fmrb_gfx_create_image(WINDOW, CACHED, len(CACHED), &img) == 1;
        }
        if (!img_ok) log_info("tour: no picture from /usr/share/asterism/icon.png");
    }
    text(6, y0 + 6, PICTURE, INK_SUB);
    if (!img_ok) {
        text(6, y0 + 20, "no picture", C_RED);
        return;
    }
    if (img_shown) fmrb_gfx_draw_image_raw(WINDOW, img.id, 6, y0 + 20, 2.0, 0.0);
    buf_t a = { 0 }, b = { 0 };
    put(&a, "id "); put_int(&a, img.id);
    put_int(&b, img.width); put(&b, "x"); put_int(&b, img.height); put(&b, " px, x2");
    text(80, y0 + 20, a.s, INK);
    text(80, y0 + 32, b.s, INK);
}

/* ---- page 4: sound */

static void draw_sound(int32_t y0)
{
    static const char *const rows[] = {
        "1: a scale on pulse 1", "3: a beep on pulse 2", "0: stop", "", "notes end by the clock",
    };
    for (int32_t i = 0; i < 5; i++) text(6, y0 + 6 + i * 12, rows[i], i == 4 ? INK_SUB : INK);
}

/* A note sounds until it is switched off, so its end is booked by the clock
   (frames stretch when drawing is slow). */
static void note(int32_t ch, int32_t freq, int32_t ms, int32_t volume)
{
    fmrb_audio_note_on_raw(0, ch, freq, volume, 2, 0);
    note_off_at[ch] = fmrb_app_uptime_ms() + ms;
}

static void silence(void)
{
    for (int32_t ch = 0; ch < 2; ch++) {
        fmrb_audio_note_off(0, ch);
        note_off_at[ch] = 0;
    }
    scale_i = -1;
}

static void tick_sound(int64_t now)
{
    for (int32_t ch = 0; ch < 2; ch++) {
        if (note_off_at[ch] != 0 && note_off_at[ch] <= now) {
            fmrb_audio_note_off(0, ch);
            note_off_at[ch] = 0;
        }
    }
    if (scale_i >= 0 && now >= scale_at) {
        if (scale_i >= SCALE_N) {
            scale_i = -1;
            return;
        }
        note(0, SCALE[scale_i], 150, 12);
        scale_i++;
        scale_at = now + 200;
    }
}

/* ---- page 5: the system side */

static void read_data(void)
{
    uint8_t d[16];
    int32_t n = fmrb_file_read(DATA_FILE, len(DATA_FILE), d, sizeof(d));
    if (n < 0) {
        file_text[0] = '-'; file_text[1] = '\0';
        return;
    }
    if (n > (int32_t)sizeof(d)) n = sizeof(d);
    for (int32_t i = 0; i < n; i++) file_text[i] = (char)d[i];
    file_text[n] = '\0';
}

/* W: count the writes in a file of the app's own (under /home). */
static void write_data(void)
{
    uint8_t d[16];
    int64_t count = 0;
    int32_t n = fmrb_file_read(DATA_FILE, len(DATA_FILE), d, sizeof(d));
    for (int32_t i = 0; i < n && i < (int32_t)sizeof(d); i++) {
        if (d[i] >= '0' && d[i] <= '9') count = count * 10 + (d[i] - '0');
    }
    buf_t b = { 0 };
    put_int(&b, count + 1);
    if (fmrb_file_write(DATA_FILE, len(DATA_FILE), (const uint8_t *)b.s, b.n) != 1) {
        log_info("tour: cannot write /home/tour.txt");
    }
    read_data();
}

static void draw_system(int32_t y0)
{
    static const char *const labels[] = {
        "name", "pid", "platform", "language", "uptime", "clock", "memory", "toml", "file", "input",
    };
    buf_t v[10] = { 0 };
    char s[96];
    int32_t n = fmrb_app_name(s, sizeof(s) - 1);
    if (n < 0 || n >= (int32_t)sizeof(s)) n = 0;
    s[n] = '\0';
    put(&v[0], s);
    put_int(&v[1], fmrb_app_pid());
    put(&v[2], platform());
    language(&v[3]);
    put_int(&v[4], (fmrb_app_uptime_ms() - started) / 1000); put(&v[4], " s");
    fmrb_app_wallclock_t c;
    if (fmrb_app_wallclock(&c) == 1) {
        put2(&v[5], c.hour); put(&v[5], ":"); put2(&v[5], c.minute); put(&v[5], ":"); put2(&v[5], c.second);
    } else {
        put(&v[5], "-");
    }
    fmrb_app_sys_pool_info_t m;
    put_int(&v[6], fmrb_app_sys_pool_info(&m) == 1 ? m.free / 1024 : 0); put(&v[6], " KB free");
    /* the .app.toml next to the .app.wasm this app was started from */
    n = fmrb_app_script_path(s, sizeof(s) - 1);
    int64_t size = -1;
    if (n > 5 && n < (int32_t)sizeof(s) - 1) {
        s[n - 4] = 't'; s[n - 3] = 'o'; s[n - 2] = 'm'; s[n - 1] = 'l';
        size = fmrb_file_size(s, n);
    }
    if (size >= 0) { put_int(&v[7], size); put(&v[7], " B"); } else { put(&v[7], "-"); }
    put(&v[8], file_text);
    put(&v[9], input);
    for (int32_t i = 0; i < 10; i++) {
        int32_t y = y0 + 6 + i * 11;
        text(6, y, labels[i], INK_SUB);
        text(86, y, v[i].s, INK);
    }
    if (blink) fmrb_gfx_fill_circle(WINDOW, fmrb_gfx_area_width(WINDOW) - 10, y0 + 8, 3, C_GREEN);
}

/* ---- the page frame */

static void draw(void)
{
    int32_t w = fmrb_gfx_area_width(WINDOW), h = fmrb_gfx_area_height(WINDOW);
    fmrb_gfx_fill_rect(WINDOW, 0, 0, w, h, PAPER);
    buf_t head = { 0 };
    put_int(&head, page + 1); put(&head, "/5 "); put(&head, PAGES[page]);
    text(4, 2, head.s, INK);
    const int32_t y0 = 14;
    switch (page) {
    case 0: draw_shapes(y0); break;
    case 1: draw_text(y0); break;
    case 2: draw_image(y0); break;
    case 3: draw_sound(y0); break;
    default: draw_system(y0); break;
    }
    text(4, h - 10, KEYS[page], INK_SUB);
    fmrb_gfx_present_raw(WINDOW, 0, 0, 0);
}

static void set_page(int32_t p)
{
    page = p;
    buf_t b = { 0 };
    put(&b, "tour: page "); put(&b, PAGES[p]);
    log_info(b.s);
    draw();
}

/* ---- the hooks */

void on_create(void)
{
    started = fmrb_app_uptime_ms();
    read_data();
    buf_t b = { 0 };
    put(&b, "tour: started on "); put(&b, platform());
    log_info(b.s);
    draw();
}

void on_destroy(void)
{
    fmrb_audio_note_off(0, 0);
    fmrb_audio_note_off(0, 1);
    if (img_ok) fmrb_gfx_delete_image(WINDOW, img.id);
    log_info("tour: bye");
}

int32_t on_update(void)
{
    int64_t now = fmrb_app_uptime_ms();
    tick_sound(now);
    int32_t b = (now - started) / 500 % 2 == 0;
    if (b != blink) {
        blink = b;
        if (page == 4) draw();
    }
    return 100;
}

static void key(const fmrb_app_event_t *ev)
{
    int32_t sc = ev->scancode;
    if (ev->character == 'q') {
        fmrb_app_stop();
        return;
    }
    if (page == 3) {
        if (sc == 0x1E) { scale_i = 0; scale_at = fmrb_app_uptime_ms(); return; } /* 1 */
        if (sc == 0x20) { note(1, 988, 90, 14); return; }                         /* 3 */
        if (sc == 0x27) { silence(); return; }                                    /* 0 */
    }
    if (sc >= 0x1E && sc <= 0x22) {                       /* 1-5 */
        set_page(sc - 0x1E);
        return;
    }
    if (page == 1 && sc == 0x17) font_mode = (font_mode + 1) % 3;  /* T */
    else if (page == 2 && sc == 0x0C) img_shown = !img_shown;       /* I */
    else if (page == 4 && sc == 0x1A) write_data();                 /* W */
    draw();
}

void on_event(const fmrb_app_event_t *ev)
{
    if (ev->type == FMRB_APP_EVENT_TYPE_MOUSE_UP) {
        if (ev->button != 1) return;
        buf_t b = { 0 };
        put(&b, "click "); put_int(&b, ev->x); put(&b, ","); put_int(&b, ev->y);
        for (int32_t i = 0; i <= b.n; i++) input[i] = b.s[i];
        set_page((page + 1) % 5);
    } else if (ev->type == FMRB_APP_EVENT_TYPE_KEY_DOWN) {
        buf_t b = { 0 };
        if (ev->character > ' ' && ev->character < 127) {
            char c[2] = { (char)ev->character, 0 };
            put(&b, "key "); put(&b, c);
        } else {
            put(&b, "key code "); put_int(&b, ev->keycode);
        }
        for (int32_t i = 0; i <= b.n; i++) input[i] = b.s[i];
        key(ev);
    }
}
