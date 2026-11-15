// bounce: a square bounces in the window; a click or a key changes its
// color. The smallest TinyGo app on Family mruby (doc/wasm_apps W1b).
package main

import "github.com/family-mruby/family-mruby-sdk/tinygo/fmrb"

const size = 14

type bounce struct {
	x, y, dx, dy int32
	w, h         int32
	color        int
	frames       int64
	lastKey      int32
}

var palette = [...][3]int32{
	{255, 64, 64}, {64, 224, 64}, {64, 128, 255}, {255, 224, 0}, {255, 96, 255}, {0, 224, 224},
}

var bg, fg int32

func (b *bounce) OnCreate() {
	bg = fmrb.RGB(0, 0, 64)
	fg = fmrb.RGB(255, 255, 255)
	b.w, b.h = fmrb.Window.AreaWidth(), fmrb.Window.AreaHeight()
	b.x, b.y, b.dx, b.dy = 4, 24, 2, 1
	fmrb.LogInfo("bounce: hello from TinyGo (area " + fmrb.Itoa(int64(b.w)) + "x" + fmrb.Itoa(int64(b.h)) + ")")
}

func (b *bounce) OnUpdate() int32 {
	b.x += b.dx
	b.y += b.dy
	if b.x < 0 || b.x+size > b.w {
		b.dx = -b.dx
		b.x += 2 * b.dx
	}
	if b.y < 22 || b.y+size > b.h {
		b.dy = -b.dy
		b.y += 2 * b.dy
	}
	b.frames++

	g := fmrb.Window
	g.FillRect(0, 0, b.w, b.h, bg)
	g.DrawText(2, 2, "TinyGo on Family mruby", fg)
	g.DrawText(2, 12, "frame "+fmrb.Itoa(b.frames)+"  key "+fmrb.Itoa(int64(b.lastKey)), fg)
	c := palette[b.color]
	g.FillRoundRect(b.x, b.y, size, size, 3, fmrb.RGB(c[0], c[1], c[2]))
	g.Present()
	return 33
}

func (b *bounce) OnEvent(ev fmrb.Event) {
	switch ev.Kind {
	case fmrb.MouseDown, fmrb.KeyDown:
		b.color = (b.color + 1) % len(palette)
		if ev.Kind == fmrb.KeyDown {
			b.lastKey = ev.Character
		}
	}
}

func (b *bounce) OnResize(w, h int32) {
	b.w, b.h = fmrb.Window.AreaWidth(), fmrb.Window.AreaHeight()
}

func (b *bounce) OnDestroy() {
	fmrb.LogInfo("bounce: bye after " + fmrb.Itoa(b.frames) + " frames")
}

func init() { fmrb.SetApp(&bounce{}) }

func main() {}
