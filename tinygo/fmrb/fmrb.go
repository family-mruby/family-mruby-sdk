// Package fmrb is the TinyGo SDK of Family mruby: the app's side of the
// boundary between a wasm app and the firmware.
//
// An app sets itself with SetApp (from an init function) and implements the
// hooks it wants: OnCreate, OnUpdate, OnEvent, OnDestroy, OnSuspend,
// OnResume, OnResize, OnQuitRequest. The firmware owns the window, its
// frame and the loop, and calls the hooks; Window draws in the area inside
// the frame, whose (0, 0) is its top-left.
//
// Build with: tinygo build -target=wasm-unknown -gc=conservative -opt=z -no-debug
// (tinygo/build.rb does it).
package fmrb

import "unsafe"

// Results of the boundary functions.
const (
	ErrFailed int32 = -1
	ErrArg    int32 = -2
	None      int32 = -3 // nil in Ruby
)

func strPtr(s string) (unsafe.Pointer, int32) {
	if len(s) == 0 {
		return nil, 0
	}
	return unsafe.Pointer(unsafe.StringData(s)), int32(len(s))
}

// ---- the app's hooks

// Event types: FmrbApp::event's choices (a Symbol in Ruby), in the header's
// order (FMRB_APP_EVENT_TYPE_*).
const (
	KeyDown int32 = iota
	KeyUp
	MouseDown
	MouseUp
	MouseMove
	MouseWheel
	GamepadDown
	GamepadUp
	GamepadAxis
	KanaMode
)

// Event is one input event: FmrbApp::event (fmrb_app_event_t, 60 bytes; the
// firmware passes a pointer to it). Which fields mean something depends on
// Type, as in Ruby's event Hash: keys have Keycode, Scancode, Modifier and
// Character; mouse events X and Y (in the app's area), WX and WY (in the
// window) and, pressed or released, Button; the wheel also Delta; gamepad
// buttons GamepadID and Button; an axis GamepadID, Axis and Value; the kana
// mode Mode. The others are 0.
type Event struct {
	Type      int32
	X, Y      int32
	WX, WY    int32
	Button    int32
	Keycode   int32
	Scancode  int32
	Modifier  int32
	Character int32
	Delta     int32
	GamepadID int32
	Axis      int32
	Value     int32
	Mode      int32
}

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

// The record is on the firmware's side of the call (the app's own stack,
// below its stack pointer): copied before the app's hook sees it.
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
	PlatformESP32 int32 = 0
	PlatformLinux int32 = 1
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
	return readString(func(out unsafe.Pointer, size int32) int32 { return appName(out, size) })
}
func (AppT) Language() string {
	return readString(func(out unsafe.Pointer, size int32) int32 { return appLanguage(out, size) })
}
func (AppT) Pid() int32            { return appPid() }
func (AppT) Platform() int32       { return appPlatform() }
func (AppT) UserAreaWidth() int32  { return appUserAreaWidth() }
func (AppT) UserAreaHeight() int32 { return appUserAreaHeight() }
func (AppT) ThemeBg() int32        { return appThemeBg() }
func (AppT) ThemeFg() int32        { return appThemeFg() }
func (AppT) ThemeAccent() int32    { return appThemeAccent() }

// Stop ends the app after the hook it is called from returns.
func (AppT) Stop() { appStop() }

// UptimeUs is the microseconds since power-on.
func UptimeUs() int64 { return appUptimeUs() }

// UptimeMs is the milliseconds since power-on.
func UptimeMs() int64 { return appUptimeMs() }

// ---- FmrbAudio

// Audio is an FmrbAudio receiver: the app's sound.
type Audio int32

// NewAudio is FmrbAudio.new: the app's sound (receiver 0 for now).
func NewAudio() Audio { return 0 }

// NoteOn sounds a note on a channel with Ruby's defaults (volume 10, duty
// 2, no sweep).
func (a Audio) NoteOn(channel, freq int32) { audioNoteOnRaw(int32(a), channel, freq, 10, 2, 0) }

// NoteOnRaw is note_on with nothing left out.
func (a Audio) NoteOnRaw(channel, freq, volume, duty, sweep int32) {
	audioNoteOnRaw(int32(a), channel, freq, volume, duty, sweep)
}

func (a Audio) NoteOff(channel int32) { audioNoteOff(int32(a), channel) }

// ---- FmrbFile (by path; the places a Ruby app's File may read and write)

// FileRead reads a whole file; ok is false when there is none.
func FileRead(path string) (data []byte, ok bool) {
	p, n := strPtr(path)
	size := fileRead(p, n, nil, 0)
	if size < 0 {
		return nil, false
	}
	if size == 0 {
		return []byte{}, true
	}
	data = make([]byte, size)
	got := fileRead(p, n, unsafe.Pointer(&data[0]), size)
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
	return fileWrite(p, n, d, int32(len(data))) == 1
}

func FileExist(path string) bool { p, n := strPtr(path); return fileExist(p, n) == 1 }

// FileSize is the size in bytes; ok is false when there is no such file.
func FileSize(path string) (size int64, ok bool) {
	p, n := strPtr(path)
	size = fileSize(p, n)
	return size, size >= 0
}

// FileDelete deletes a file or an empty directory.
func FileDelete(path string) bool { p, n := strPtr(path); return fileDelete(p, n) == 1 }

// FileList is the names in a directory (a directory's with a "/" after it);
// ok is false when it cannot be read.
func FileList(dir string) (names []string, ok bool) {
	p, n := strPtr(dir)
	s := readString(func(out unsafe.Pointer, size int32) int32 { return fileListRaw(p, n, out, size) })
	if fileListRaw(p, n, nil, 0) < 0 {
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
func RGB(r, g, b int32) int32 { return gfxRgbTo332(r, g, b) }

func (g Gfx) AreaWidth() int32           { return gfxAreaWidth(int32(g)) }
func (g Gfx) AreaHeight() int32          { return gfxAreaHeight(int32(g)) }
func (g Gfx) Clear(color int32)          { gfxClear(int32(g), color) }
func (g Gfx) SetPixel(x, y, color int32) { gfxSetPixel(int32(g), x, y, color) }
func (g Gfx) DrawLine(x0, y0, x1, y1, color int32) {
	gfxDrawLine(int32(g), x0, y0, x1, y1, color)
}
func (g Gfx) DrawRect(x, y, w, h, color int32) { gfxDrawRect(int32(g), x, y, w, h, color) }
func (g Gfx) FillRect(x, y, w, h, color int32) { gfxFillRect(int32(g), x, y, w, h, color) }
func (g Gfx) DrawRoundRect(x, y, w, h, r, color int32) {
	gfxDrawRoundRect(int32(g), x, y, w, h, r, color)
}
func (g Gfx) FillRoundRect(x, y, w, h, r, color int32) {
	gfxFillRoundRect(int32(g), x, y, w, h, r, color)
}
func (g Gfx) DrawCircle(x, y, r, color int32) { gfxDrawCircle(int32(g), x, y, r, color) }
func (g Gfx) FillCircle(x, y, r, color int32) { gfxFillCircle(int32(g), x, y, r, color) }
func (g Gfx) FillTriangle(x0, y0, x1, y1, x2, y2, color int32) {
	gfxFillTriangle(int32(g), x0, y0, x1, y1, x2, y2, color)
}

// DrawText draws text with a transparent background.
func (g Gfx) DrawText(x, y int32, text string, color int32) {
	p, n := strPtr(text)
	gfxDrawTextRaw(int32(g), x, y, p, n, color, Transparent, 0)
}

// DrawTextBg draws text on a background color (Transparent for none).
func (g Gfx) DrawTextBg(x, y int32, text string, color, bg int32) {
	p, n := strPtr(text)
	gfxDrawTextRaw(int32(g), x, y, p, n, color, bg, 0)
}

func (g Gfx) SetTextSize(size int32) { gfxSetTextSizeRaw(int32(g), size) }

// Present shows what was drawn, at the window's place.
func (g Gfx) Present() { gfxPresentRaw(int32(g), 0, 0, 0) }

// ---- Log (the same log as a Ruby app's)

func LogDebug(msg string) { p, n := strPtr(msg); logDebugRaw(p, n) }
func LogInfo(msg string)  { p, n := strPtr(msg); logInfoRaw(p, n) }
func LogWarn(msg string)  { p, n := strPtr(msg); logWarnRaw(p, n) }
func LogError(msg string) { p, n := strPtr(msg); logErrorRaw(p, n) }

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
