// bounce: a square bounces in the window; a click or a key changes its
// color and sounds a short note, q ends the app. The smallest TinyGo app on
// Family mruby (doc/wasm_apps W1b). It also shows what FmrbApp and FmrbFile
// give: the app's name (in the log) and pid, and the size of its own .app.toml.
package main

import "github.com/family-mruby/family-mruby-sdk/tinygo/fmrb"

const (
	size = 14
	top  = 32 // the square stays below the three text lines
	toml = "/app/tinygo/bounce.app.toml"
)

type bounce struct {
	x, y, dx, dy int32
	w, h         int32
	color        int
	frames       int64
	lastKey      int32
	beep         int32 // frames left of the note
	info         string
}

var palette = [...][3]int32{
	{255, 64, 64}, {64, 224, 64}, {64, 128, 255}, {224, 160, 0}, {255, 96, 255}, {0, 160, 160},
}

var (
	bg, fg int32
	audio  = fmrb.NewAudio()
)

func (b *bounce) OnCreate() {
	// White paper and black ink, as every SDK sample (never 0x01: the canvas
	// color key, which shows through).
	bg = fmrb.RGB(255, 255, 255)
	fg = fmrb.RGB(0, 0, 0)
	b.w, b.h = fmrb.Window.AreaWidth(), fmrb.Window.AreaHeight()
	b.x, b.y, b.dx, b.dy = 4, top+2, 2, 1
	b.info = "pid " + fmrb.Itoa(int64(fmrb.App.Pid()))
	if n, ok := fmrb.FileSize(toml); ok {
		b.info += "  toml " + fmrb.Itoa(n) + " B"
	}
	fmrb.LogInfo("bounce: hello from TinyGo, " + fmrb.App.Name() + " (area " + fmrb.Itoa(int64(b.w)) + "x" + fmrb.Itoa(int64(b.h)) + ")")
}

func (b *bounce) OnUpdate() int32 {
	b.x += b.dx
	b.y += b.dy
	if b.x < 0 || b.x+size > b.w {
		b.dx = -b.dx
		b.x += 2 * b.dx
	}
	if b.y < top || b.y+size > b.h {
		b.dy = -b.dy
		b.y += 2 * b.dy
	}
	b.frames++
	if b.beep > 0 {
		b.beep--
		if b.beep == 0 {
			audio.NoteOff(0)
		}
	}

	g := fmrb.Window
	g.FillRect(0, 0, b.w, b.h, bg)
	g.DrawText(2, 2, "TinyGo on Family mruby", fg)
	g.DrawText(2, 12, "frame "+fmrb.Itoa(b.frames)+"  key "+fmrb.Itoa(int64(b.lastKey)), fg)
	g.DrawText(2, 22, b.info, fg)
	c := palette[b.color]
	g.FillRoundRect(b.x, b.y, size, size, 3, fmrb.RGB(c[0], c[1], c[2]))
	g.Present()
	return 33
}

func (b *bounce) OnEvent(ev fmrb.Event) {
	switch ev.Type {
	case fmrb.KeyDown:
		if ev.Character == 'q' {
			fmrb.App.Stop()
			return
		}
		b.lastKey = ev.Character
		b.next()
	case fmrb.MouseDown:
		b.next()
	}
}

// next changes the color and sounds a short note in it.
func (b *bounce) next() {
	b.color = (b.color + 1) % len(palette)
	audio.NoteOn(0, 440+int32(b.color)*110)
	b.beep = 4
}

func (b *bounce) OnResize(w, h int32) {
	b.w, b.h = fmrb.Window.AreaWidth(), fmrb.Window.AreaHeight()
}

func (b *bounce) OnDestroy() {
	if b.beep > 0 {
		audio.NoteOff(0)
	}
	fmrb.LogInfo("bounce: bye after " + fmrb.Itoa(b.frames) + " frames")
}

func init() { fmrb.SetApp(&bounce{}) }

func main() {}
