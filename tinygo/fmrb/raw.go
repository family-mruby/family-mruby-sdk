// Code written by hand to match fmruby-core's sdk/c/fmrb_boundary.h
// (generated there from sig/*.rbs). tools/check_bindings.rb compares every import here with
// that header: name, parameters and result. The generator takes over in a
// later phase (doc/wasm_apps W5).
//
// Each function is the flat boundary function as the firmware registers it
// (import module "fmrb"). A String is a pointer and a length; a result is 0
// or more on success, ErrFailed or ErrArg otherwise (None where Ruby gives
// nil). FmrbAudio's functions take the receiver number first (0 for now).
// Only what the SDK's wrappers use is here: functions that pass a record
// (wallclock, image info, file info, the song status, composite regions) are
// not yet.

package fmrb

import "unsafe"

// ---- FmrbApp (no receiver: the app itself)

//go:wasmimport fmrb app_name
func appName(out unsafe.Pointer, outSize int32) int32

//go:wasmimport fmrb app_user_area_width
func appUserAreaWidth() int32

//go:wasmimport fmrb app_user_area_height
func appUserAreaHeight() int32

//go:wasmimport fmrb app_platform
func appPlatform() int32

//go:wasmimport fmrb app_stop
func appStop() int32

//go:wasmimport fmrb app_theme_bg
func appThemeBg() int32

//go:wasmimport fmrb app_theme_fg
func appThemeFg() int32

//go:wasmimport fmrb app_theme_accent
func appThemeAccent() int32

//go:wasmimport fmrb app_language
func appLanguage(out unsafe.Pointer, outSize int32) int32

//go:wasmimport fmrb app_pid
func appPid() int32

//go:wasmimport fmrb app_uptime_ms
func appUptimeMs() int64

//go:wasmimport fmrb app_clipboard_raw
func appClipboardRaw(limit int32, out unsafe.Pointer, outSize int32) int32

//go:wasmimport fmrb app_set_clipboard
func appSetClipboard(text unsafe.Pointer, textLen int32) int32

//go:wasmimport fmrb app_clipboard_gen
func appClipboardGen() int32

//go:wasmimport fmrb app_uptime_us
func appUptimeUs() int64

// ---- FmrbAudio (the first argument is the receiver number, 0 for now)

//go:wasmimport fmrb audio_note_on_raw
func audioNoteOnRaw(audio int32, channel int32, freq int32, volume int32, duty int32, sweep int32) int32

//go:wasmimport fmrb audio_note_off
func audioNoteOff(audio int32, channel int32) int32

// ---- FmrbFile (by path, no state)

//go:wasmimport fmrb file_read
func fileRead(path unsafe.Pointer, pathLen int32, out unsafe.Pointer, outSize int32) int32

//go:wasmimport fmrb file_write
func fileWrite(path unsafe.Pointer, pathLen int32, data unsafe.Pointer, dataLen int32) int32

//go:wasmimport fmrb file_exist
func fileExist(path unsafe.Pointer, pathLen int32) int32

//go:wasmimport fmrb file_size
func fileSize(path unsafe.Pointer, pathLen int32) int64

//go:wasmimport fmrb file_delete
func fileDelete(path unsafe.Pointer, pathLen int32) int32

//go:wasmimport fmrb file_list_raw
func fileListRaw(dir unsafe.Pointer, dirLen int32, out unsafe.Pointer, outSize int32) int32

// ---- FmrbGfx (the first argument is the drawer number)

//go:wasmimport fmrb gfx_canvas_id
func gfxCanvasID(gfx int32) int32

//go:wasmimport fmrb gfx_area_width
func gfxAreaWidth(gfx int32) int32

//go:wasmimport fmrb gfx_area_height
func gfxAreaHeight(gfx int32) int32

//go:wasmimport fmrb gfx_origin_x
func gfxOriginX(gfx int32) int32

//go:wasmimport fmrb gfx_origin_y
func gfxOriginY(gfx int32) int32

//go:wasmimport fmrb gfx_clear
func gfxClear(gfx int32, color int32) int32

//go:wasmimport fmrb gfx_set_pixel
func gfxSetPixel(gfx int32, x int32, y int32, color int32) int32

//go:wasmimport fmrb gfx_get_pixel
func gfxGetPixel(gfx int32, x int32, y int32) int32

//go:wasmimport fmrb gfx_draw_line
func gfxDrawLine(gfx int32, x0 int32, y0 int32, x1 int32, y1 int32, color int32) int32

//go:wasmimport fmrb gfx_draw_rect
func gfxDrawRect(gfx int32, x int32, y int32, w int32, h int32, color int32) int32

//go:wasmimport fmrb gfx_fill_rect
func gfxFillRect(gfx int32, x int32, y int32, w int32, h int32, color int32) int32

//go:wasmimport fmrb gfx_draw_round_rect
func gfxDrawRoundRect(gfx int32, x int32, y int32, w int32, h int32, r int32, color int32) int32

//go:wasmimport fmrb gfx_fill_round_rect
func gfxFillRoundRect(gfx int32, x int32, y int32, w int32, h int32, r int32, color int32) int32

//go:wasmimport fmrb gfx_draw_circle
func gfxDrawCircle(gfx int32, x int32, y int32, r int32, color int32) int32

//go:wasmimport fmrb gfx_fill_circle
func gfxFillCircle(gfx int32, x int32, y int32, r int32, color int32) int32

//go:wasmimport fmrb gfx_fill_triangle
func gfxFillTriangle(gfx int32, x0 int32, y0 int32, x1 int32, y1 int32, x2 int32, y2 int32, color int32) int32

//go:wasmimport fmrb gfx_draw_text_raw
func gfxDrawTextRaw(gfx int32, x int32, y int32, text unsafe.Pointer, textLen int32, color int32, bgColor int32, mixed int32) int32

//go:wasmimport fmrb gfx_set_font_raw
func gfxSetFontRaw(gfx int32, family int32, size int32) int32

//go:wasmimport fmrb gfx_set_text_size_raw
func gfxSetTextSizeRaw(gfx int32, size int32) int32

//go:wasmimport fmrb gfx_present_raw
func gfxPresentRaw(gfx int32, x int32, y int32, positioned int32) int32

//go:wasmimport fmrb gfx_rgb_to_332
func gfxRgbTo332(r int32, g int32, b int32) int32

// ---- Log

//go:wasmimport fmrb log_debug_raw
func logDebugRaw(msg unsafe.Pointer, msgLen int32) int32

//go:wasmimport fmrb log_info_raw
func logInfoRaw(msg unsafe.Pointer, msgLen int32) int32

//go:wasmimport fmrb log_warn_raw
func logWarnRaw(msg unsafe.Pointer, msgLen int32) int32

//go:wasmimport fmrb log_error_raw
func logErrorRaw(msg unsafe.Pointer, msgLen int32) int32
