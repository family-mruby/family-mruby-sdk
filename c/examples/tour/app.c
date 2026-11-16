/*
 * tour: hello plus a tour of the main functions, one page at a time --
 * shapes, text (Japanese too), a picture, sprites, tiles, sound, a tune and
 * a voice, files, pointer and keys, and the system side (the app's
 * information, clocks, memory, the clipboard, its own wasm numbers). Every
 * SDK language has this same app with the same screen (tinygo/examples/tour
 * is the TinyGo one), so the languages can be compared line by line; the
 * common specification is in docs/tour.md.
 *
 *   click, arrows, 1-9, 0   change page
 *   q                       quit
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
    C_TEAL = 0x0F, C_PANEL = 0xB6, C_SKY = 0x9B,
};
#define WINDOW 0 /* the window's drawer */
#define AUDIO 0  /* the app's sound */
#define Y0 14    /* the top of a page's body */

#define CACHE "/cache/app/tour/"
#define PICTURE "/usr/share/asterism/icon.png"
#define SHEET_SRC "/usr/share/sprites/test/tilesheet.png"
#define TUNE_SRC "/usr/share/music/korobeiniki.fmsq"
#define VOICE "/usr/share/sounds/voice/mahjong/default/pon.wav"
#define DIR "/home/tour"
/* konnichiwa ABC nihongo, in UTF-8 */
static const char SAMPLE_JA[] = "\xe3\x81\x93\xe3\x82\x93\xe3\x81\xab\xe3\x81\xa1\xe3\x81\xaf ABC "
                                "\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e";

enum { P_SHAPES, P_TEXT, P_IMAGE, P_SPRITES, P_TILES, P_SOUND, P_SOUND_PLUS,
       P_FILES, P_INPUT, P_SYSTEM, P_SYSTEM_PLUS, N_PAGES };
static const char *const PAGES[N_PAGES] = {
    "Shapes", "Text", "Image", "Sprites", "Tiles", "Sound", "Sound+", "Files", "Input", "System", "System+",
};
static const char *const KEYS[N_PAGES] = {
    "click, arrows, 1-9, 0: pages  q: quit",
    "T: font",
    "I: show / hide the picture",
    "H: hide / show one  P: pause",
    "arrows: pages  q: quit",
    "S: scale  B: beep  X: stop",
    "M: tune on / off  V: voice",
    "W: append  D: delete count.txt",
    "drag: draw  type  BS: clear",
    "arrows: pages  q: quit",
    "C: copy to the clipboard",
};
static const int32_t SCALE[] = { 262, 294, 330, 349, 392, 440, 494, 523 };
#define SCALE_N ((int32_t)(sizeof(SCALE) / sizeof(SCALE[0])))
static const char *const SPRITE_FILES[4] = { "enemy1_a", "enemy1_b", "enemy2_a", "enemy2_b" };
static const char *const TILE_MAP[4] = {
    "............",
    "........33..",
    "..0.1...22..",
    "444455554444",
};
static const char *const TUNE_STATES[] = { "stopped", "playing", "cannot load" };
static const char *const VOICE_STATES[] = { "-", "played", "not on this machine", "failed" };
static const char *const FILE_STATES[] = { "-", "appended", "deleted count.txt", "no count.txt" };

#define MAX_POINTS 256

static int32_t page, font_mode, scale_i = -1;
static int64_t started, scale_at, note_off_at[2], second;
static int32_t blink;
static int32_t img_tried, img_ok, img_shown = 1;
static fmrb_gfx_image_info_t img;
static char input[32] = "-"; /* the last input */
/* sprites */
static int32_t spr_tried, spr_ok, sprites[4], sx[4], sy[4], step, paused, hidden0;
static int32_t dx[4] = { 2, -2, 3, -3 }, dy[4] = { 1, 2, -1, -2 };
/* tiles */
static int32_t sheet_tried, sheet; /* sheet: the sprite image, 0 for none */
/* a tune and a voice */
static int32_t tune_loaded, tune, voice;
/* files */
static int32_t file_last;
/* input */
static int32_t pen, n_pts;
static int16_t px[MAX_POINTS], py[MAX_POINTS];
static uint8_t p_start[MAX_POINTS]; /* the first point of a stroke */
static char typed[31];
static int32_t n_typed;

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

/* A label and its value on one row. */
static void row(int32_t x, int32_t vx, int32_t y, const char *label, const char *value)
{
    text(x, y, label, INK_SUB);
    text(vx, y, value, INK);
}

static void log_info(const char *s) { fmrb_log_info_raw(s, len(s)); }
static void log_warn(const char *s) { fmrb_log_warn_raw(s, len(s)); }

static int32_t sync_file(const char *src, const char *dest)
{
    return fmrb_gfx_sync_file_raw(WINDOW, src, len(src), dest, len(dest)) == 1;
}

static const char *platform(void)
{
    return fmrb_app_platform() == FMRB_APP_PLATFORM_ESP32 ? "esp32" : "linux";
}

/* A function that writes a String into the caller's buffer, into b. */
static void put_read(buf_t *b, int32_t n, const char *s)
{
    char c[2] = { 0, 0 };
    for (int32_t i = 0; i < n && i < (int32_t)sizeof(b->s) - 1; i++) { c[0] = s[i]; put(b, c); }
}

static void language(buf_t *b)
{
    char l[16];
    put_read(b, fmrb_app_language(l, sizeof(l)), l);
}

/* ---- page 1: shapes */

/* round to the nearest integer, halves away from zero */
static int32_t round_i(double v)
{
    return v >= 0 ? (int32_t)(v + 0.5) : -(int32_t)(-v + 0.5);
}

/* sin of an angle in degrees: folded into -90..90, then the Taylor series
   to x^13 (there is no libm). */
static double sin_deg(int32_t deg)
{
    int32_t d = (deg % 360 + 360) % 360; /* 0..359 */
    if (d > 180) d -= 360;               /* -179..180 */
    if (d > 90) d = 180 - d;
    else if (d < -90) d = -180 - d;
    double x = d * 3.141592653589793 / 180, term = x, sum = x;
    for (int32_t n = 1; n <= 6; n++) {
        term *= -x * x / ((2 * n) * (2 * n + 1));
        sum += term;
    }
    return sum;
}

static double cos_deg(int32_t deg) { return sin_deg(deg + 90); }

static void draw_shapes(void)
{
    /* left: the filled shapes, 57 x 25, 7 apart */
    fmrb_gfx_fill_rect(WINDOW, 10, 22, 57, 25, C_BLUE);
    fmrb_gfx_fill_round_rect(WINDOW, 10, 54, 57, 25, 6, C_TEAL);
    fmrb_gfx_fill_ellipse(WINDOW, 38, 98, 28, 12, C_ORANGE);
    fmrb_gfx_fill_triangle(WINDOW, 10, 142, 66, 142, 38, 118, C_RED);
    /* centre: concentric circles, 8 apart */
    static const int32_t rings[4] = { C_RED, C_ORANGE, C_TEAL, C_BLUE };
    for (int32_t i = 0; i < 4; i++) fmrb_gfx_draw_circle(WINDOW, 114, 82, (i + 1) * 8, rings[i]);
    fmrb_gfx_fill_circle(WINDOW, 114, 82, 3, C_RED);
    /* right: a regular hexagon around (190, 82), r 32, pointing up */
    enum { CX = 190, CY = 82, R = 32 };
    int32_t vx[6], vy[6];
    for (int32_t k = 0; k < 6; k++) {
        int32_t a = -90 + 60 * k;
        vx[k] = CX + round_i(R * cos_deg(a));
        vy[k] = CY + round_i(R * sin_deg(a));
    }
    for (int32_t k = 0; k < 3; k++) fmrb_gfx_draw_line(WINDOW, vx[k], vy[k], vx[k + 3], vy[k + 3], C_TEAL);
    fmrb_gfx_draw_circle(WINDOW, CX, CY, (int32_t)(R * cos_deg(30)) - 1, C_ORANGE); /* inside, 1 dot clear */
    for (int32_t k = 0; k < 6; k++) {
        fmrb_gfx_draw_line(WINDOW, vx[k], vy[k], vx[(k + 1) % 6], vy[(k + 1) % 6], C_BLUE);
    }
    fmrb_gfx_fill_circle(WINDOW, CX, CY, 3, C_RED);
}

/* ---- page 2: text */

static void draw_text(void)
{
    static const char *const modes[] = { "default font", "ja font", "mixed (ascii + ja)" };
    text(6, Y0 + 6, modes[font_mode], INK_SUB);
    if (font_mode == 0) {
        text(6, Y0 + 20, "ABC abc 123", C_BLUE);
    } else if (font_mode == 1) {
        fmrb_gfx_set_font_raw(WINDOW, FMRB_GFX_SET_FONT_RAW_FAMILY_JA, 12);
        text(6, Y0 + 20, SAMPLE_JA, C_BLUE);
        fmrb_gfx_set_font_raw(WINDOW, FMRB_GFX_SET_FONT_RAW_FAMILY_DEFAULT, 0);
    } else {
        fmrb_gfx_draw_text_raw(WINDOW, 6, Y0 + 20, SAMPLE_JA, len(SAMPLE_JA), C_BLUE, PAPER, 1);
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
    for (int32_t i = 0; i < 5; i++) text(6, Y0 + 40 + i * 10, rows[i].s, INK);
}

/* ---- page 3: a picture */

static void draw_image(void)
{
    if (!img_tried) {
        img_tried = 1;
        if (sync_file(PICTURE, CACHE "icon.png")) {
            img_ok = fmrb_gfx_create_image(WINDOW, CACHE "icon.png", len(CACHE "icon.png"), &img) == 1;
        }
        if (!img_ok) log_warn("tour: no picture from " PICTURE);
    }
    text(6, Y0 + 6, PICTURE, INK_SUB);
    if (!img_ok) {
        text(6, Y0 + 20, "no picture", C_RED);
        return;
    }
    if (img_shown) fmrb_gfx_draw_image_raw(WINDOW, img.id, 6, Y0 + 20, 2.0, 0.0);
    buf_t a = { 0 }, b = { 0 };
    put(&a, "id "); put_int(&a, img.id);
    put_int(&b, img.width); put(&b, "x"); put_int(&b, img.height); put(&b, " px, x2");
    text(80, Y0 + 20, a.s, INK);
    text(80, Y0 + 32, b.s, INK);
}

/* ---- page 4: sprites */

/* Syncs a picture and reads it into a new sprite image: its id, 0 for none. */
static int32_t load_sprite(const char *src, const char *name, int32_t w, int32_t h)
{
    buf_t dest = { 0 };
    put(&dest, CACHE); put(&dest, name);
    if (!sync_file(src, dest.s)) return 0;
    int32_t id = fmrb_gfx_create_sprite_image(WINDOW, w, h, 0x00, 1);
    if (id <= 0) return 0;
    return fmrb_gfx_load_sprite_image(WINDOW, id, dest.s, dest.n) >= 0 ? id : 0;
}

static void setup_sprites(void)
{
    spr_tried = 1;
    uint16_t imgs[4];
    for (int32_t i = 0; i < 4; i++) {
        buf_t src = { 0 }, name = { 0 };
        put(&src, "/usr/share/sprites/shooter/"); put(&src, SPRITE_FILES[i]); put(&src, ".png");
        put(&name, SPRITE_FILES[i]); put(&name, ".png");
        int32_t id = load_sprite(src.s, name.s, 16, 12);
        if (!id) {
            buf_t b = { 0 };
            put(&b, "tour: no sprite "); put(&b, SPRITE_FILES[i]);
            log_warn(b.s);
            return;
        }
        imgs[i] = (uint16_t)id;
    }
    for (int32_t k = 0; k < 4; k++) {
        sx[k] = 16 + 52 * k;
        sy[k] = Y0 + 24 + 20 * k;
        sprites[k] = fmrb_gfx_create_sprite_instance(WINDOW, &imgs[k % 2 ? 2 : 0], 2, sx[k], sy[k], k);
        if (sprites[k] <= 0) {
            log_warn("tour: cannot place a sprite");
            return;
        }
    }
    spr_ok = 1;
}

static void show_sprites(int32_t on)
{
    if (!spr_ok) return;
    for (int32_t k = 0; k < 4; k++) fmrb_gfx_set_sprite_visible(WINDOW, sprites[k], on && !(k == 0 && hidden0));
}

static void sprite_status(void)
{
    buf_t b = { 0 };
    put(&b, "step "); put_int(&b, step);
    put(&b, paused ? "  paused" : "  moving");
    put(&b, hidden0 ? "  1: hidden  " : "  1: shown  ");
    text(6, Y0 + 124, b.s, INK);
}

static void draw_sprites(void)
{
    if (!spr_tried) setup_sprites();
    if (!spr_ok) {
        text(6, Y0 + 20, "no sprites", C_RED);
        return;
    }
    text(6, Y0 + 4, "4 sprites, 2 frames each", INK_SUB);
    fmrb_gfx_draw_rect(WINDOW, 6, Y0 + 16, 216, 104, INK_SUB);
    sprite_status();
}

/* Keeps *v in lo..hi, turning *d at an end. */
static void bounce(int32_t *v, int32_t *d, int32_t lo, int32_t hi)
{
    *v += *d;
    if (*v < lo) { *v = lo; *d = -*d; }
    else if (*v > hi) { *v = hi; *d = -*d; }
}

static void step_sprites(void)
{
    if (!spr_ok || paused) return;
    for (int32_t k = 0; k < 4; k++) {
        bounce(&sx[k], &dx[k], 7, 205);
        bounce(&sy[k], &dy[k], Y0 + 17, Y0 + 107);
        fmrb_gfx_move_sprite(WINDOW, sprites[k], sx[k], sy[k]);
    }
    step++;
    if (step % 4 == 0) {
        for (int32_t k = 0; k < 4; k++) fmrb_gfx_set_sprite_frame(WINDOW, sprites[k], step / 4 % 2);
    }
    sprite_status();
    fmrb_gfx_present_raw(WINDOW, 0, 0, 0);
}

/* ---- page 5: tiles */

/* Tile i of the sheet (4 to a row) at (x, y). */
static void tile(int32_t i, int32_t x, int32_t y)
{
    fmrb_gfx_draw_tile_raw(WINDOW, sheet, 16 * (i % 4), 16 * (i / 4), 16, 16, x, y);
}

static void draw_tiles(void)
{
    if (!sheet_tried) {
        sheet_tried = 1;
        sheet = load_sprite(SHEET_SRC, "tiles.png", 64, 32);
        if (!sheet) log_warn("tour: no tiles from " SHEET_SRC);
    }
    if (!sheet) {
        text(6, Y0 + 20, "no tiles", C_RED);
        return;
    }
    text(6, Y0 + 4, "draw_tile: one tile per call", INK_SUB);
    fmrb_gfx_fill_rect(WINDOW, 6, Y0 + 16, 72, 36, C_PANEL);
    for (int32_t i = 0; i < 8; i++) tile(i, 8 + 18 * (i % 4), Y0 + 18 + 18 * (i / 4));
    text(86, Y0 + 18, "tilesheet.png", INK);
    text(86, Y0 + 30, "64x32 px, 8 tiles", INK);
    text(86, Y0 + 42, "a 12x4 map below", INK);
    fmrb_gfx_fill_rect(WINDOW, 18, Y0 + 58, 192, 64, C_SKY);
    for (int32_t r = 0; r < 4; r++) {
        for (int32_t c = 0; TILE_MAP[r][c]; c++) {
            if (TILE_MAP[r][c] != '.') tile(TILE_MAP[r][c] - '0', 18 + 16 * c, Y0 + 58 + 16 * r);
        }
    }
}

/* ---- page 6: sound */

static void draw_sound(void)
{
    static const char *const rows[] = {
        "S: a scale on pulse 1", "B: a beep on pulse 2", "X: stop", "", "notes end by the clock",
    };
    for (int32_t i = 0; i < 5; i++) text(6, Y0 + 6 + i * 12, rows[i], i == 4 ? INK_SUB : INK);
}

/* A note sounds until it is switched off, so its end is booked by the clock
   (frames stretch when drawing is slow). */
static void note(int32_t ch, int32_t freq, int32_t ms, int32_t volume)
{
    fmrb_audio_note_on_raw(AUDIO, ch, freq, volume, 2, 0);
    note_off_at[ch] = fmrb_app_uptime_ms() + ms;
}

static void silence(void)
{
    for (int32_t ch = 0; ch < 2; ch++) {
        fmrb_audio_note_off(AUDIO, ch);
        note_off_at[ch] = 0;
    }
    scale_i = -1;
}

static void tick_sound(int64_t now)
{
    for (int32_t ch = 0; ch < 2; ch++) {
        if (note_off_at[ch] != 0 && note_off_at[ch] <= now) {
            fmrb_audio_note_off(AUDIO, ch);
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

/* ---- page 7: a tune and a voice */

static void draw_sound_plus(void)
{
    buf_t t = { 0 }, v = { 0 };
    put(&t, "tune   "); put(&t, TUNE_STATES[tune]);
    put(&v, "voice  "); put(&v, VOICE_STATES[voice]);
    const char *rows[] = { "M: korobeiniki (FMSQ) on / off", "V: a voice (WAV)", "", t.s, v.s };
    for (int32_t i = 0; i < 5; i++) text(6, Y0 + 6 + i * 12, rows[i], INK);
    text(6, Y0 + 78, TUNE_SRC, INK_SUB);
    text(6, Y0 + 90, "voice/mahjong/default/pon.wav", INK_SUB);
}

static void toggle_tune(void)
{
    if (tune == 1) {
        fmrb_audio_stop(AUDIO);
        tune = 0;
        return;
    }
    if (!tune_loaded) {
        tune_loaded = sync_file(TUNE_SRC, CACHE "tune.fmsq") &&
                      fmrb_audio_load_fmsq_file(AUDIO, 0, CACHE "tune.fmsq", len(CACHE "tune.fmsq")) >= 0;
        if (!tune_loaded) {
            log_warn("tour: cannot load " TUNE_SRC);
            tune = 2;
            return;
        }
    }
    fmrb_audio_play_slot_raw(AUDIO, 0, 0); /* slot 0 on MAIN */
    tune = 1;
}

static void play_voice(void)
{
    int32_t r = fmrb_audio_play_wav(AUDIO, VOICE, len(VOICE));
    voice = r == 1 ? 1 : r == 0 ? 2 : 3;
}

/* ---- page 8: files */

static int32_t file_write(const char *path, const char *s)
{
    return fmrb_file_write(path, len(path), (const uint8_t *)s, len(s)) == 1;
}

static int32_t file_delete(const char *path) { return fmrb_file_delete(path, len(path)) == 1; }

static void setup_files(void)
{
    fmrb_file_mkdir(DIR, len(DIR));
    file_write(DIR "/hello.txt", "hello from the tour");
}

static void clean_files(void)
{
    file_delete(DIR "/count.txt");
    file_delete(DIR "/hello.txt");
    file_delete(DIR);
}

static void draw_files(void)
{
    static const char *const labels[] = { "dir", "wrote", "read", "count", "list", "free", "last" };
    buf_t v[7] = { 0 };
    char d[64];
    put(&v[0], DIR "/");
    int64_t size = fmrb_file_size(DIR "/hello.txt", len(DIR "/hello.txt"));
    if (size >= 0) { put(&v[1], "hello.txt, "); put_int(&v[1], size); put(&v[1], " B"); } else { put(&v[1], "-"); }
    int32_t n = fmrb_file_read(DIR "/hello.txt", len(DIR "/hello.txt"), (uint8_t *)d, sizeof(d));
    if (n >= 0) put_read(&v[2], n < (int32_t)sizeof(d) ? n : (int32_t)sizeof(d), d); else put(&v[2], "-");
    int32_t lines = 0;
    n = fmrb_file_read(DIR "/count.txt", len(DIR "/count.txt"), 0, 0); /* its size */
    if (n > 0) {
        static uint8_t data[1024];
        if (n > (int32_t)sizeof(data)) n = sizeof(data);
        n = fmrb_file_read(DIR "/count.txt", len(DIR "/count.txt"), data, n);
        for (int32_t i = 0; i < n; i++) lines += data[i] == '\n';
    }
    put_int(&v[3], lines); put(&v[3], " lines");
    n = fmrb_file_list_raw(DIR, len(DIR), d, sizeof(d));
    /* one name per line: a space between them */
    for (int32_t i = 0; i < n && i < (int32_t)sizeof(d); i++) {
        if (d[i] != '\n') { char c[2] = { d[i], 0 }; put(&v[4], c); }
        else if (i + 1 < n) put(&v[4], " ");
    }
    int64_t free = fmrb_file_free_bytes(DIR, len(DIR));
    if (free >= 0) { put_int(&v[5], free / 1024); put(&v[5], " KB"); } else { put(&v[5], "-"); }
    put(&v[6], FILE_STATES[file_last]);
    for (int32_t i = 0; i < 7; i++) row(6, 58, Y0 + 6 + i * 11, labels[i], v[i].s);
    text(6, Y0 + 86, "all removed when you leave the page", INK_SUB);
}

static void file_key(int32_t sc)
{
    if (sc == 0x1A) { /* W */
        fmrb_file_append(DIR "/count.txt", len(DIR "/count.txt"), (const uint8_t *)"w\n", 2);
        file_last = 1;
    } else if (sc == 0x07) { /* D */
        file_last = file_delete(DIR "/count.txt") ? 2 : 3;
    }
}

/* ---- page 9: input */

static int32_t in_pad(int32_t x, int32_t y) { return x > 6 && x < 221 && y > Y0 + 16 && y < Y0 + 99; }

static int32_t clamp(int32_t v, int32_t lo, int32_t hi) { return v < lo ? lo : v > hi ? hi : v; }

static void draw_input(void)
{
    text(6, Y0 + 4, "drag inside the box to draw", INK_SUB);
    fmrb_gfx_draw_rect(WINDOW, 6, Y0 + 16, 216, 84, INK_SUB);
    for (int32_t i = 0; i < n_pts; i++) {
        if (p_start[i]) fmrb_gfx_set_pixel(WINDOW, px[i], py[i], C_BLUE);
        else fmrb_gfx_draw_line(WINDOW, px[i - 1], py[i - 1], px[i], py[i], C_BLUE);
    }
    row(6, 42, Y0 + 106, "typed", typed);
    row(6, 42, Y0 + 118, "last", input);
}

/* Keeps a point of the stroke (the first one starts it) and draws the line
   to it. */
static void add_point(int32_t x, int32_t y, int32_t start)
{
    if (n_pts >= MAX_POINTS) return;
    x = clamp(x, 7, 220);
    y = clamp(y, Y0 + 17, Y0 + 98);
    int32_t i = n_pts++;
    px[i] = (int16_t)x;
    py[i] = (int16_t)y;
    p_start[i] = (uint8_t)start;
    if (start) fmrb_gfx_set_pixel(WINDOW, x, y, C_BLUE);
    else fmrb_gfx_draw_line(WINDOW, px[i - 1], py[i - 1], x, y, C_BLUE);
    fmrb_gfx_present_raw(WINDOW, 0, 0, 0);
}

static void type_char(char c)
{
    if (n_typed == 30) { /* keep the last 30 */
        for (int32_t i = 0; i < 29; i++) typed[i] = typed[i + 1];
        n_typed = 29;
    }
    typed[n_typed++] = c;
    typed[n_typed] = '\0';
}

/* ---- page 10: the system side */

static void draw_system(void)
{
    static const char *const labels[] = { "name", "pid", "platform", "language", "uptime", "clock", "memory", "toml" };
    buf_t v[8] = { 0 };
    char s[96];
    put_read(&v[0], fmrb_app_name(s, sizeof(s)), s);
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
    int32_t n = fmrb_app_script_path(s, sizeof(s) - 1);
    int64_t size = -1;
    if (n > 5 && n < (int32_t)sizeof(s) - 1) {
        s[n - 4] = 't'; s[n - 3] = 'o'; s[n - 2] = 'm'; s[n - 1] = 'l';
        size = fmrb_file_size(s, n);
    }
    if (size >= 0) { put_int(&v[7], size); put(&v[7], " B"); } else { put(&v[7], "-"); }
    for (int32_t i = 0; i < 8; i++) row(6, 86, Y0 + 6 + i * 11, labels[i], v[i].s);
    if (blink) fmrb_gfx_fill_circle(WINDOW, fmrb_gfx_area_width(WINDOW) - 10, Y0 + 8, 3, C_GREEN);
}

/* ---- page 11: the clipboard, the clock, the app's wasm numbers */

#define SYS_Y(i) (Y0 + 6 + (i) * 11)

static void draw_system_plus(void)
{
    char clip[24];
    int32_t n = fmrb_app_clipboard_raw(20, clip, sizeof(clip) - 1);
    if (n < 0) n = 0;
    if (n > (int32_t)sizeof(clip) - 1) n = sizeof(clip) - 1;
    for (int32_t i = 0; i < n; i++) {
        if (clip[i] == '\n') { n = i; break; }
    }
    text(6, SYS_Y(0), "clipboard", INK_SUB);
    if (n > 0) fmrb_gfx_draw_text_raw(WINDOW, 70, SYS_Y(0), clip, n, INK, PAPER, 1);
    else text(70, SYS_Y(0), "(empty)", INK);
    buf_t v[7] = { 0 };
    put_int(&v[0], fmrb_app_clipboard_gen());
    row(6, 70, SYS_Y(1), "changes", v[0].s);
    text(6, SYS_Y(2), "wallclock", INK_SUB);
    if (fmrb_gfx_draw_wallclock(WINDOW, 70, SYS_Y(2), INK, PAPER) != 1) text(70, SYS_Y(2), "-", INK);
    static const char *const labels[] = { "memory", "binary", "hooks", "last hook", "wasm apps", "frames" };
    fmrb_app_wasm_app_stats_t a;
    if (fmrb_app_wasm_app_stats(fmrb_app_pid(), &a) == 1) {
        put_int(&v[1], a.pages); put(&v[1], " pages, max "); put_int(&v[1], a.max_pages);
        put_int(&v[2], a.binary_size); put(&v[2], " B");
        put_int(&v[3], a.calls); put(&v[3], " calls");
        put_int(&v[4], a.hook_us); put(&v[4], " us, max "); put_int(&v[4], a.hook_max_us);
    } else {
        for (int32_t i = 1; i <= 4; i++) put(&v[i], "-");
    }
    fmrb_app_wasm_stats_t w;
    if (fmrb_app_wasm_stats(&w) == 1) {
        put_int(&v[5], w.apps); put(&v[5], ", pool "); put_int(&v[5], w.pool_used / 1024); put(&v[5], " KB");
    } else {
        put(&v[5], "-");
    }
    fmrb_app_gfx_stats_t gs;
    if (fmrb_app_gfx_stats(&gs) == 1) put_int(&v[6], gs.presents); else put(&v[6], "-");
    for (int32_t i = 0; i < 6; i++) row(6, 70, SYS_Y(i + 3), labels[i], v[i + 1].s);
}

/* ---- the page frame */

static void draw(void)
{
    int32_t w = fmrb_gfx_area_width(WINDOW), h = fmrb_gfx_area_height(WINDOW);
    fmrb_gfx_fill_rect(WINDOW, 0, 0, w, h, PAPER);
    buf_t head = { 0 };
    put_int(&head, page + 1); put(&head, "/11 "); put(&head, PAGES[page]);
    text(4, 2, head.s, INK);
    switch (page) {
    case P_SHAPES: draw_shapes(); break;
    case P_TEXT: draw_text(); break;
    case P_IMAGE: draw_image(); break;
    case P_SPRITES: draw_sprites(); break;
    case P_TILES: draw_tiles(); break;
    case P_SOUND: draw_sound(); break;
    case P_SOUND_PLUS: draw_sound_plus(); break;
    case P_FILES: draw_files(); break;
    case P_INPUT: draw_input(); break;
    case P_SYSTEM: draw_system(); break;
    default: draw_system_plus(); break;
    }
    text(4, h - 10, KEYS[page], INK_SUB);
    fmrb_gfx_present_raw(WINDOW, 0, 0, 0);
}

/* Leaves the page shown, then enters p. */
static void set_page(int32_t p)
{
    if (page == P_SPRITES) {
        show_sprites(0);
    } else if (page == P_SOUND_PLUS && tune == 1) {
        fmrb_audio_stop(AUDIO);
        tune = 0;
    } else if (page == P_FILES) {
        clean_files();
    }
    page = p;
    buf_t b = { 0 };
    put(&b, "tour: page "); put(&b, PAGES[p]);
    log_info(b.s);
    if (p == P_SPRITES) {
        show_sprites(1);
    } else if (p == P_FILES) {
        setup_files();
        file_last = 0;
    }
    draw();
}

/* ---- the hooks */

void on_create(void)
{
    started = fmrb_app_uptime_ms();
    buf_t b = { 0 };
    put(&b, "tour: started on "); put(&b, platform());
    log_info(b.s);
    draw();
}

void on_destroy(void)
{
    fmrb_audio_note_off(AUDIO, 0);
    fmrb_audio_note_off(AUDIO, 1);
    fmrb_audio_stop(AUDIO);
    clean_files();
    if (img_ok) fmrb_gfx_delete_image(WINDOW, img.id);
    fmrb_gfx_delete_all_sprites(WINDOW);
    log_info("tour: bye");
}

int32_t on_update(void)
{
    int64_t now = fmrb_app_uptime_ms();
    tick_sound(now);
    int32_t b = (now - started) / 500 % 2 == 0;
    if (b != blink) {
        blink = b;
        if (page == P_SYSTEM) draw();
    }
    if (page == P_SPRITES) step_sprites();
    if (now / 1000 != second) {
        second = now / 1000;
        if (page == P_SYSTEM_PLUS) draw();
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
    if (sc == 0x4F) { set_page((page + 1) % N_PAGES); return; }           /* right */
    if (sc == 0x50) { set_page((page + N_PAGES - 1) % N_PAGES); return; } /* left */
    if (sc >= 0x1E && sc <= 0x26) { set_page(sc - 0x1E); return; }        /* 1-9 */
    if (sc == 0x27) { set_page(9); return; }                               /* 0 */
    switch (page) {
    case P_TEXT:
        if (sc == 0x17) font_mode = (font_mode + 1) % 3; /* T */
        break;
    case P_IMAGE:
        if (sc == 0x0C) img_shown = !img_shown; /* I */
        break;
    case P_SPRITES:
        if (sc == 0x0B && spr_ok) { /* H */
            hidden0 = !hidden0;
            fmrb_gfx_set_sprite_visible(WINDOW, sprites[0], !hidden0);
        } else if (sc == 0x13) { /* P */
            paused = !paused;
        }
        break;
    case P_SOUND:
        if (sc == 0x16) { scale_i = 0; scale_at = fmrb_app_uptime_ms(); } /* S */
        else if (sc == 0x05) note(1, 988, 90, 14);                        /* B */
        else if (sc == 0x1B) silence();                                   /* X */
        break;
    case P_SOUND_PLUS:
        if (sc == 0x10) toggle_tune();      /* M */
        else if (sc == 0x19) play_voice();  /* V */
        break;
    case P_FILES:
        file_key(sc);
        break;
    case P_INPUT:
        if (sc == 0x2A) { /* backspace */
            n_typed = 0;
            typed[0] = '\0';
            n_pts = 0;
        } else if (ev->character >= ' ' && ev->character < 127) {
            type_char((char)ev->character);
        }
        break;
    case P_SYSTEM_PLUS:
        if (sc == 0x06) { /* C */
            static const char copied[] = "copied by the tour";
            fmrb_app_set_clipboard(copied, len(copied));
        }
        break;
    }
    draw();
}

static void set_input(const buf_t *b)
{
    for (int32_t i = 0; i <= b->n && i < (int32_t)sizeof(input) - 1; i++) input[i] = b->s[i];
    input[sizeof(input) - 1] = '\0';
}

void on_event(const fmrb_app_event_t *ev)
{
    buf_t b = { 0 };
    switch (ev->type) {
    case FMRB_APP_EVENT_TYPE_MOUSE_DOWN:
        if (ev->button == 1 && page == P_INPUT && in_pad(ev->x, ev->y)) {
            pen = 1;
            add_point(ev->x, ev->y, 1);
        }
        break;
    case FMRB_APP_EVENT_TYPE_MOUSE_MOVE:
        if (pen) add_point(ev->x, ev->y, 0);
        break;
    case FMRB_APP_EVENT_TYPE_MOUSE_UP:
        if (ev->button != 1) return;
        put(&b, "click "); put_int(&b, ev->x); put(&b, ","); put_int(&b, ev->y);
        set_input(&b);
        if (pen) {
            pen = 0;
            draw();
            return;
        }
        set_page((page + 1) % N_PAGES);
        break;
    case FMRB_APP_EVENT_TYPE_KEY_DOWN:
        if (ev->character > ' ' && ev->character < 127) {
            char c[2] = { (char)ev->character, 0 };
            put(&b, "key "); put(&b, c);
        } else {
            put(&b, "key code "); put_int(&b, ev->keycode);
        }
        set_input(&b);
        key(ev);
        break;
    }
}
