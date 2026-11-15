// Package fmrb is the TinyGo SDK of Family mruby: the app's side of the
// boundary between a wasm app and the firmware.
//
// An app sets itself with SetApp (from an init function) and implements the
// hooks it wants: OnCreate, OnUpdate, OnEvent, OnDestroy, OnSuspend,
// OnResume, OnResize, OnQuitRequest. The firmware owns the window, its
// frame and the loop, and calls the hooks; Window draws in the area inside
// the frame, whose (0, 0) is its top-left.
//
// This package is the hand-written layer: the hooks and Go shapes for the
// common functions. Under it, package raw (fmrb/raw) is generated from the
// boundary (tools/gen_bindings.rb) and has every function, record and choice;
// call it directly for what is not wrapped here.
//
// Build with: tinygo build -target=wasm-unknown -gc=conservative -opt=z -no-debug
// (tinygo/build.rb does it).
package fmrb

import (
	"unsafe"

	"github.com/family-mruby/family-mruby-sdk/tinygo/fmrb/raw"
)

// Results of the boundary functions.
const (
	ErrFailed = raw.ErrFailed
	ErrArg    = raw.ErrArg
	None      = raw.None // nil in Ruby
)

// SDKVersion is this SDK's version.
const SDKVersion = raw.SDKVersion

func strPtr(s string) (unsafe.Pointer, int32) {
	if len(s) == 0 {
		return nil, 0
	}
	return unsafe.Pointer(unsafe.StringData(s)), int32(len(s))
}

// ---- the app's hooks

// Event types: FmrbApp::event's choices (a Symbol in Ruby).
const (
	KeyDown     = raw.AppEventTypeKeyDown
	KeyUp       = raw.AppEventTypeKeyUp
	MouseDown   = raw.AppEventTypeMouseDown
	MouseUp     = raw.AppEventTypeMouseUp
	MouseMove   = raw.AppEventTypeMouseMove
	MouseWheel  = raw.AppEventTypeMouseWheel
	GamepadDown = raw.AppEventTypeGamepadDown
	GamepadUp   = raw.AppEventTypeGamepadUp
	GamepadAxis = raw.AppEventTypeGamepadAxis
	KanaMode    = raw.AppEventTypeKanaMode
)

// Event is one input event: FmrbApp::event (raw.AppEventRecord, the firmware's
// record; it passes a pointer to it). Which fields mean something depends on
// Type, as in Ruby's event Hash: keys have Keycode, Scancode, Modifier and
// Character; mouse events X and Y (in the app's area), WX and WY (in the
// window) and, pressed or released, Button; the wheel also Delta; gamepad
// buttons GamepadID and Button; an axis GamepadID, Axis and Value; the kana
// mode Mode. The others are 0.
type Event = raw.AppEventRecord

type creator interface{ OnCreate() }

// An updater's OnUpdate returns the ms until its next call (negative: the
// firmware's default, 330 ms).
type updater interface{ OnUpdate() int32 }
type eventHandler interface{ OnEvent(ev Event) }
type destroyer interface{ OnDestroy() }
type suspender interface{ OnSuspend() }
type resumer interface{ OnResume() }
type resizer interface{ OnResize(w, h int32) }
type quitRequester interface{ OnQuitRequest() }

var theApp any

// SetApp sets the value whose hooks the firmware calls. Call it from init.
func SetApp(a any) { theApp = a }

//export on_create
func onCreate() {
	if a, ok := theApp.(creator); ok {
		a.OnCreate()
	}
}

//export on_update
func onUpdate() int32 {
	if a, ok := theApp.(updater); ok {
		return a.OnUpdate()
	}
	return -1
}

// eventBuffer is where the firmware writes the event record before it
// calls on_event (raw.EventBufferSize bytes, 8-byte aligned). The
// firmware asks for its address once, through fmrb_event_buffer. Without
// it the firmware would put the record on the app's stack, and a small app
// whose optimiser dropped the stack pointer would be refused.
var eventBuffer [raw.EventBufferSize / 8]uint64

//export fmrb_event_buffer
func fmrbEventBuffer() unsafe.Pointer {
	return unsafe.Pointer(&eventBuffer)
}

// The record is in eventBuffer: copied before the app's hook sees it.
//
//export on_event
func onEvent(ev *Event) {
	if a, ok := theApp.(eventHandler); ok {
		a.OnEvent(*ev)
	}
}

//export on_destroy
func onDestroy() {
	if a, ok := theApp.(destroyer); ok {
		a.OnDestroy()
	}
}

//export on_suspend
func onSuspend() {
	if a, ok := theApp.(suspender); ok {
		a.OnSuspend()
	}
}

//export on_resume
func onResume() {
	if a, ok := theApp.(resumer); ok {
		a.OnResume()
	}
}

//export on_resize
func onResize(w, h int32) {
	if a, ok := theApp.(resizer); ok {
		a.OnResize(w, h)
	}
}

//export on_quit_request
func onQuitRequest() {
	if a, ok := theApp.(quitRequester); ok {
		a.OnQuitRequest()
	}
}

// ---- FmrbApp (the app itself; its window functions work from any hook)

// Platforms (FmrbApp#platform).
const (
	PlatformESP32 = raw.AppPlatformEsp32
	PlatformLinux = raw.AppPlatformLinux
)

// AppT is FmrbApp: the running app and its window.
type AppT struct{}

// App is the running app.
var App AppT

// readString calls a boundary function that writes a String into the
// caller's buffer and returns its full length.
func readString(f func(out unsafe.Pointer, size int32) int32) string {
	var buf [64]byte
	n := f(unsafe.Pointer(&buf[0]), int32(len(buf)))
	if n < 0 {
		return ""
	}
	if int(n) > len(buf) {
		big := make([]byte, n)
		n = f(unsafe.Pointer(&big[0]), n)
		if n < 0 || int(n) > len(big) {
			return ""
		}
		return string(big[:n])
	}
	return string(buf[:n])
}

// (An imported function is not a value in TinyGo: each goes in a closure.)
func (AppT) Name() string {
	return readString(func(out unsafe.Pointer, size int32) int32 { return raw.AppName(out, size) })
}
func (AppT) Language() string {
	return readString(func(out unsafe.Pointer, size int32) int32 { return raw.AppLanguage(out, size) })
}
func (AppT) Pid() int32            { return raw.AppPid() }
func (AppT) Platform() int32       { return raw.AppPlatform() }
func (AppT) UserAreaWidth() int32  { return raw.AppUserAreaWidth() }
func (AppT) UserAreaHeight() int32 { return raw.AppUserAreaHeight() }
func (AppT) ThemeBg() int32        { return raw.AppThemeBg() }
func (AppT) ThemeFg() int32        { return raw.AppThemeFg() }
func (AppT) ThemeAccent() int32    { return raw.AppThemeAccent() }

// ScriptPath is the file the app was started from (its .app.wasm).
func (AppT) ScriptPath() string {
	return readString(func(out unsafe.Pointer, size int32) int32 { return raw.AppScriptPath(out, size) })
}

// Clock is the date and time now (FmrbApp.wallclock); ok is false when the
// device does not know it yet.
type Clock struct {
	Year                             int32
	Month, Day, Hour, Minute, Second int32
}

func Wallclock() (c Clock, ok bool) {
	var r raw.AppWallclockRecord
	if raw.AppWallclock(unsafe.Pointer(&r)) != 1 {
		return c, false
	}
	return Clock{int32(r.Year()), int32(r.Month()), int32(r.Day()), int32(r.Hour()),
		int32(r.Minute()), int32(r.Second())}, true
}

// MemoryFree is the free bytes of the whole machine's memory pool.
func MemoryFree() uint32 {
	var r raw.AppSysPoolInfoRecord
	if raw.AppSysPoolInfo(unsafe.Pointer(&r)) != 1 {
		return 0
	}
	return r.Free
}

// Stop ends the app after the hook it is called from returns.
func (AppT) Stop() { raw.AppStop() }

// UptimeUs is the microseconds since power-on.
func UptimeUs() int64 { return raw.AppUptimeUs() }

// UptimeMs is the milliseconds since power-on.
func UptimeMs() int64 { return raw.AppUptimeMs() }

// ---- FmrbAudio

// Audio is an FmrbAudio receiver: the app's sound.
type Audio int32

// NewAudio is FmrbAudio.new: the app's sound (receiver 0 for now).
func NewAudio() Audio { return 0 }

// NoteOn sounds a note on a channel with Ruby's defaults (volume 10, duty
// 2, no sweep).
func (a Audio) NoteOn(channel, freq int32) { raw.AudioNoteOnRaw(int32(a), channel, freq, 10, 2, 0) }

// NoteOnRaw is note_on with nothing left out.
func (a Audio) NoteOnRaw(channel, freq, volume, duty, sweep int32) {
	raw.AudioNoteOnRaw(int32(a), channel, freq, volume, duty, sweep)
}

func (a Audio) NoteOff(channel int32) { raw.AudioNoteOff(int32(a), channel) }

// ---- FmrbFile (by path; the places a Ruby app's File may read and write)

// FileRead reads a whole file; ok is false when there is none.
func FileRead(path string) (data []byte, ok bool) {
	p, n := strPtr(path)
	size := raw.FileRead(p, n, nil, 0)
	if size < 0 {
		return nil, false
	}
	if size == 0 {
		return []byte{}, true
	}
	data = make([]byte, size)
	got := raw.FileRead(p, n, unsafe.Pointer(&data[0]), size)
	if got < 0 {
		return nil, false
	}
	if got < size {
		data = data[:got]
	}
	return data, true
}

// FileWrite writes a whole file, replacing it.
func FileWrite(path string, data []byte) bool {
	p, n := strPtr(path)
	var d unsafe.Pointer
	if len(data) > 0 {
		d = unsafe.Pointer(&data[0])
	}
	return raw.FileWrite(p, n, d, int32(len(data))) == 1
}

func FileExist(path string) bool { p, n := strPtr(path); return raw.FileExist(p, n) == 1 }

// FileSize is the size in bytes; ok is false when there is no such file.
func FileSize(path string) (size int64, ok bool) {
	p, n := strPtr(path)
	size = raw.FileSize(p, n)
	return size, size >= 0
}

// FileDelete deletes a file or an empty directory.
func FileDelete(path string) bool { p, n := strPtr(path); return raw.FileDelete(p, n) == 1 }

// FileList is the names in a directory (a directory's with a "/" after it);
// ok is false when it cannot be read.
func FileList(dir string) (names []string, ok bool) {
	p, n := strPtr(dir)
	s := readString(func(out unsafe.Pointer, size int32) int32 { return raw.FileListRaw(p, n, out, size) })
	if raw.FileListRaw(p, n, nil, 0) < 0 {
		return nil, false
	}
	start := 0
	for i := 0; i <= len(s); i++ {
		if i == len(s) || s[i] == '\n' {
			if i > start {
				names = append(names, s[start:i])
			}
			start = i + 1
		}
	}
	return names, true
}

// ---- FmrbGfx

// Gfx is a drawer: a canvas, a drawing origin and an area.
type Gfx int32

// Window is the app window's drawer, opened by the firmware before OnCreate.
const Window Gfx = 0

// Transparent as a text background leaves what is under the text.
const Transparent int32 = -1

// RGB turns 0-255 components into the firmware's 8-bit color (RGB332).
func RGB(r, g, b int32) int32 { return raw.GfxRgbTo332(r, g, b) }

func (g Gfx) AreaWidth() int32           { return raw.GfxAreaWidth(int32(g)) }
func (g Gfx) AreaHeight() int32          { return raw.GfxAreaHeight(int32(g)) }
func (g Gfx) Clear(color int32)          { raw.GfxClear(int32(g), color) }
func (g Gfx) SetPixel(x, y, color int32) { raw.GfxSetPixel(int32(g), x, y, color) }
func (g Gfx) DrawLine(x0, y0, x1, y1, color int32) {
	raw.GfxDrawLine(int32(g), x0, y0, x1, y1, color)
}
func (g Gfx) DrawRect(x, y, w, h, color int32) { raw.GfxDrawRect(int32(g), x, y, w, h, color) }
func (g Gfx) FillRect(x, y, w, h, color int32) { raw.GfxFillRect(int32(g), x, y, w, h, color) }
func (g Gfx) DrawRoundRect(x, y, w, h, r, color int32) {
	raw.GfxDrawRoundRect(int32(g), x, y, w, h, r, color)
}
func (g Gfx) FillRoundRect(x, y, w, h, r, color int32) {
	raw.GfxFillRoundRect(int32(g), x, y, w, h, r, color)
}
func (g Gfx) DrawCircle(x, y, r, color int32) { raw.GfxDrawCircle(int32(g), x, y, r, color) }
func (g Gfx) FillCircle(x, y, r, color int32) { raw.GfxFillCircle(int32(g), x, y, r, color) }
func (g Gfx) FillTriangle(x0, y0, x1, y1, x2, y2, color int32) {
	raw.GfxFillTriangle(int32(g), x0, y0, x1, y1, x2, y2, color)
}

// DrawText draws text with a transparent background.
func (g Gfx) DrawText(x, y int32, text string, color int32) {
	p, n := strPtr(text)
	raw.GfxDrawTextRaw(int32(g), x, y, p, n, color, Transparent, 0)
}

// DrawTextBg draws text on a background color (Transparent for none).
func (g Gfx) DrawTextBg(x, y int32, text string, color, bg int32) {
	p, n := strPtr(text)
	raw.GfxDrawTextRaw(int32(g), x, y, p, n, color, bg, 0)
}

// DrawTextMixed draws text that mixes ASCII (the default font) and Japanese
// (the ja font) on one line.
func (g Gfx) DrawTextMixed(x, y int32, text string, color, bg int32) {
	p, n := strPtr(text)
	raw.GfxDrawTextRaw(int32(g), x, y, p, n, color, bg, 1)
}

func (g Gfx) SetTextSize(size int32) { raw.GfxSetTextSizeRaw(int32(g), size) }

// Fonts (FmrbGfx#set_font's family).
const (
	FontDefault = raw.GfxSetFontRawFamilyDefault
	FontJa      = raw.GfxSetFontRawFamilyJa
	FontJaBold  = raw.GfxSetFontRawFamilyJaBold
)

// SetFont picks the font; size is the ja font's height (12 or 16; 0: its default).
func (g Gfx) SetFont(family, size int32) { raw.GfxSetFontRaw(int32(g), family, size) }

func (g Gfx) DrawEllipse(x, y, rx, ry, color int32) {
	raw.GfxDrawEllipse(int32(g), x, y, rx, ry, color)
}
func (g Gfx) FillEllipse(x, y, rx, ry, color int32) {
	raw.GfxFillEllipse(int32(g), x, y, rx, ry, color)
}
func (g Gfx) DrawTriangle(x0, y0, x1, y1, x2, y2, color int32) {
	raw.GfxDrawTriangle(int32(g), x0, y0, x1, y1, x2, y2, color)
}

// Image is a picture the graphics side decoded (FmrbGfx#create_image).
type Image struct{ ID, Width, Height int32 }

// SyncFile copies a file to where the graphics side reads it (dest, under
// /cache); create_image and the like read from there.
func (g Gfx) SyncFile(path, dest string) bool {
	p, n := strPtr(path)
	d, dn := strPtr(dest)
	return raw.GfxSyncFileRaw(int32(g), p, n, d, dn) == 1
}

// CreateImage decodes a picture file (PNG); ok is false when it cannot.
func (g Gfx) CreateImage(path string) (img Image, ok bool) {
	p, n := strPtr(path)
	var r raw.GfxImageInfoRecord
	if raw.GfxCreateImage(int32(g), p, n, unsafe.Pointer(&r)) != 1 {
		return img, false
	}
	return Image{int32(r.ID), int32(r.Width), int32(r.Height)}, true
}

// DrawImage draws an image at a scale (1.0: its own size).
func (g Gfx) DrawImage(img Image, x, y int32, scale float64) {
	raw.GfxDrawImageRaw(int32(g), img.ID, x, y, scale, 0)
}

func (g Gfx) DeleteImage(img Image) { raw.GfxDeleteImage(int32(g), img.ID) }

// Present shows what was drawn, at the window's place.
func (g Gfx) Present() { raw.GfxPresentRaw(int32(g), 0, 0, 0) }

// ---- Log (the same log as a Ruby app's)

func LogDebug(msg string) { p, n := strPtr(msg); raw.LogDebugRaw(p, n) }
func LogInfo(msg string)  { p, n := strPtr(msg); raw.LogInfoRaw(p, n) }
func LogWarn(msg string)  { p, n := strPtr(msg); raw.LogWarnRaw(p, n) }
func LogError(msg string) { p, n := strPtr(msg); raw.LogErrorRaw(p, n) }

// Itoa formats an integer without strconv (keeps the app small).
func Itoa(v int64) string {
	if v == 0 {
		return "0"
	}
	var b [20]byte
	i := len(b)
	neg := v < 0
	u := uint64(v)
	if neg {
		u = uint64(-v)
	}
	for u > 0 {
		i--
		b[i] = byte('0' + u%10)
		u /= 10
	}
	if neg {
		i--
		b[i] = '-'
	}
	return string(b[i:])
}
