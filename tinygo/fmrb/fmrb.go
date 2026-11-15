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
)

func strPtr(s string) (unsafe.Pointer, int32) {
	if len(s) == 0 {
		return nil, 0
	}
	return unsafe.Pointer(unsafe.StringData(s)), int32(len(s))
}

// ---- the app's hooks

// Event kinds (the firmware's fmrb_hid_event_type_t).
const (
	KeyDown     int32 = 1
	KeyUp       int32 = 2
	MouseMove   int32 = 3
	MouseDown   int32 = 4
	MouseUp     int32 = 5
	GamepadDown int32 = 6
	GamepadUp   int32 = 7
	GamepadAxis int32 = 8
	KanaMode    int32 = 9
	MouseWheel  int32 = 10
)

// Event is one input event. Which fields mean something depends on Kind:
// keys have Keycode, Modifier and Character; mouse events X and Y (in the
// app's area) and, pressed or released, Button; the wheel Value (the delta);
// gamepad buttons Button and Value (the pad); an axis Button (the axis),
// Value and Keycode (the pad); the kana mode Value.
type Event struct {
	Kind, X, Y, Button, Keycode, Modifier, Character, Value int32
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

var app any

// SetApp sets the value whose hooks the firmware calls. Call it from init.
func SetApp(a any) { app = a }

//export on_create
func onCreate() {
	if a, ok := app.(creator); ok {
		a.OnCreate()
	}
}

//export on_update
func onUpdate() int32 {
	if a, ok := app.(updater); ok {
		return a.OnUpdate()
	}
	return -1
}

//export on_event
func onEvent(kind, x, y, button, keycode, modifier, character, value int32) {
	if a, ok := app.(eventHandler); ok {
		a.OnEvent(Event{kind, x, y, button, keycode, modifier, character, value})
	}
}

//export on_destroy
func onDestroy() {
	if a, ok := app.(destroyer); ok {
		a.OnDestroy()
	}
}

//export on_suspend
func onSuspend() {
	if a, ok := app.(suspender); ok {
		a.OnSuspend()
	}
}

//export on_resume
func onResume() {
	if a, ok := app.(resumer); ok {
		a.OnResume()
	}
}

//export on_resize
func onResize(w, h int32) {
	if a, ok := app.(resizer); ok {
		a.OnResize(w, h)
	}
}

//export on_quit_request
func onQuitRequest() {
	if a, ok := app.(quitRequester); ok {
		a.OnQuitRequest()
	}
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

func (g Gfx) AreaWidth() int32  { return gfxAreaWidth(int32(g)) }
func (g Gfx) AreaHeight() int32 { return gfxAreaHeight(int32(g)) }
func (g Gfx) Clear(color int32) { gfxClear(int32(g), color) }
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

// ---- FmrbApp

// UptimeUs is the microseconds since power-on.
func UptimeUs() int64 { return appUptimeUs() }

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
