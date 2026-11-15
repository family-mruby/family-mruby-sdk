// tour: hello plus a tour of the main functions, one page at a time --
// shapes, text (Japanese too), a picture, sound and the system side (the
// app's information, clocks, memory, a file, the last input). Every SDK
// language has this same app with the same screen (c/examples/tour is the
// C one), so the languages can be compared line by line; the common
// specification is in docs/tour.md.
//
//	click or 1-5   change page
//	q              quit
//	the page's own keys are listed at its bottom
package main

import "github.com/family-mruby/family-mruby-sdk/tinygo/fmrb"

// The page is white and the palette is picked for contrast against it
// (RGB332, RRRGGGBB). 0x01 would be the transparent key: not used.
const (
	paper   = 0xFF // page background (white)
	ink     = 0x00 // body text and outlines (black)
	inkSub  = 0x49 // captions (dark gray)
	cRed    = 0xC0
	cGreen  = 0x0C
	cBlue   = 0x02
	cOrange = 0xE8 // stands in for yellow
	cTeal   = 0x0F // stands in for cyan
	cPurple = 0x82 // stands in for magenta
	cPanel  = 0xB6 // light gray fill
)

const (
	picture  = "/usr/share/asterism/icon.png"
	cached   = "/cache/app/tour/icon.png"
	dataFile = "/home/tour.txt"
	sampleJa = "\u3053\u3093\u306b\u3061\u306f ABC \u65e5\u672c\u8a9e" // konnichiwa ABC nihongo
)

var pages = [...]string{"Shapes", "Text", "Image", "Sound", "System"}
var keys = [...]string{
	"click or 1-5: pages  q: quit",
	"T: font",
	"I: show / hide the picture",
	"1 scale  3 beep  0 stop",
	"W: write a file",
}
var scale = [...]int32{262, 294, 330, 349, 392, 440, 494, 523}

type tour struct {
	page      int
	fontMode  int
	started   int64
	blink     bool
	img       fmrb.Image
	imgTried  bool
	imgOK     bool
	imgShown  bool
	noteOffAt [2]int64 // per channel, 0: no note
	scaleI    int      // next note of the scale, -1: none
	scaleAt   int64
	fileText  string
	input     string
}

var audio = fmrb.NewAudio()

func (t *tour) OnCreate() {
	t.started = fmrb.UptimeMs()
	t.scaleI = -1
	t.imgShown = true
	t.input = "-"
	t.fileText = readData()
	fmrb.LogInfo("tour: started on " + platform())
	t.draw()
}

func (t *tour) OnDestroy() {
	audio.NoteOff(0)
	audio.NoteOff(1)
	if t.imgOK {
		fmrb.Window.DeleteImage(t.img)
	}
	fmrb.LogInfo("tour: bye")
}

func platform() string {
	if fmrb.App.Platform() == fmrb.PlatformESP32 {
		return "esp32"
	}
	return "linux"
}

// ---- the page frame

func (t *tour) draw() {
	g := fmrb.Window
	w, h := g.AreaWidth(), g.AreaHeight()
	g.FillRect(0, 0, w, h, paper)
	g.DrawTextBg(4, 2, fmrb.Itoa(int64(t.page+1))+"/5 "+pages[t.page], ink, paper)
	const y0 = 14
	switch t.page {
	case 0:
		t.drawShapes(y0)
	case 1:
		t.drawText(y0)
	case 2:
		t.drawImage(y0)
	case 3:
		t.drawSound(y0)
	default:
		t.drawSystem(y0)
	}
	g.DrawTextBg(4, h-10, keys[t.page], inkSub, paper)
	g.Present()
}

// ---- page 1: shapes

func (t *tour) drawShapes(y0 int32) {
	g := fmrb.Window
	g.DrawRoundRect(6, y0+4, 56, 26, 6, cTeal)
	g.FillRoundRect(70, y0+4, 56, 26, 6, cGreen)
	g.DrawEllipse(34, y0+52, 26, 14, cPurple)
	g.FillEllipse(98, y0+52, 26, 14, cRed)
	g.DrawTriangle(8, y0+104, 60, y0+104, 34, y0+74, cOrange)
	g.FillTriangle(72, y0+104, 124, y0+104, 98, y0+74, cBlue)
	colors := [...]int32{cRed, cOrange, cGreen, cTeal}
	for i, dx := range [...]int32{-30, -10, 10, 30} {
		g.DrawLine(160, y0+104, 160+dx, y0+8, colors[i])
	}
	for i := int32(0); i < 3; i++ {
		g.DrawCircle(140+i*22, y0+40, 9, ink)
		g.FillCircle(140+i*22, y0+40, 4, cPanel)
	}
}

// ---- page 2: text

func (t *tour) drawText(y0 int32) {
	g := fmrb.Window
	modes := [...]string{"default font", "ja font", "mixed (ascii + ja)"}
	g.DrawTextBg(6, y0+6, modes[t.fontMode], inkSub, paper)
	switch t.fontMode {
	case 0:
		g.DrawTextBg(6, y0+20, "ABC abc 123", cBlue, paper)
	case 1:
		g.SetFont(fmrb.FontJa, 12)
		g.DrawTextBg(6, y0+20, sampleJa, cBlue, paper)
		g.SetFont(fmrb.FontDefault, 0)
	default:
		g.DrawTextMixed(6, y0+20, sampleJa, cBlue, paper)
	}
	sum := 0
	for i := 1; i <= 10; i++ {
		sum += i
	}
	rows := [...]string{
		"language " + fmrb.App.Language(),
		"sum(1..10) = " + fmrb.Itoa(int64(sum)),
		"2^16 = " + fmrb.Itoa(1<<16),
		"area " + fmrb.Itoa(int64(g.AreaWidth())) + "x" + fmrb.Itoa(int64(g.AreaHeight())),
		"SDK " + fmrb.SDKVersion,
	}
	for i, r := range rows {
		g.DrawTextBg(6, y0+40+int32(i)*10, r, ink, paper)
	}
}

// ---- page 3: a picture

func (t *tour) drawImage(y0 int32) {
	g := fmrb.Window
	if !t.imgTried {
		t.imgTried = true
		if g.SyncFile(picture, cached) {
			t.img, t.imgOK = g.CreateImage(cached)
		}
		if !t.imgOK {
			fmrb.LogWarn("tour: no picture from " + picture)
		}
	}
	g.DrawTextBg(6, y0+6, picture, inkSub, paper)
	if !t.imgOK {
		g.DrawTextBg(6, y0+20, "no picture", cRed, paper)
		return
	}
	if t.imgShown {
		g.DrawImage(t.img, 6, y0+20, 2.0)
	}
	g.DrawTextBg(80, y0+20, "id "+fmrb.Itoa(int64(t.img.ID)), ink, paper)
	g.DrawTextBg(80, y0+32, fmrb.Itoa(int64(t.img.Width))+"x"+fmrb.Itoa(int64(t.img.Height))+" px, x2", ink, paper)
}

// ---- page 4: sound

func (t *tour) drawSound(y0 int32) {
	g := fmrb.Window
	rows := [...]string{"1: a scale on pulse 1", "3: a beep on pulse 2", "0: stop", "", "notes end by the clock"}
	for i, r := range rows {
		c := int32(ink)
		if i == 4 {
			c = inkSub
		}
		g.DrawTextBg(6, y0+6+int32(i)*12, r, c, paper)
	}
}

// A note sounds until it is switched off, so its end is booked by the
// clock (frames stretch when drawing is slow).
func (t *tour) note(ch, freq, ms, volume int32) {
	audio.NoteOnRaw(ch, freq, volume, 2, 0)
	t.noteOffAt[ch] = fmrb.UptimeMs() + int64(ms)
}

func (t *tour) silence() {
	for ch := range t.noteOffAt {
		audio.NoteOff(int32(ch))
		t.noteOffAt[ch] = 0
	}
	t.scaleI = -1
}

func (t *tour) tickSound(now int64) {
	for ch, at := range t.noteOffAt {
		if at != 0 && at <= now {
			audio.NoteOff(int32(ch))
			t.noteOffAt[ch] = 0
		}
	}
	if t.scaleI >= 0 && now >= t.scaleAt {
		if t.scaleI >= len(scale) {
			t.scaleI = -1
			return
		}
		t.note(0, scale[t.scaleI], 150, 12)
		t.scaleI++
		t.scaleAt = now + 200
	}
}

// ---- page 5: the system side

func two(v int32) string {
	if v < 10 {
		return "0" + fmrb.Itoa(int64(v))
	}
	return fmrb.Itoa(int64(v))
}

func tomlPath() string {
	p := fmrb.App.ScriptPath()
	if len(p) > 5 && p[len(p)-5:] == ".wasm" {
		return p[:len(p)-5] + ".toml"
	}
	return p
}

func readData() string {
	if data, ok := fmrb.FileRead(dataFile); ok {
		return string(data)
	}
	return "-"
}

func (t *tour) drawSystem(y0 int32) {
	g := fmrb.Window
	clock := "-"
	if c, ok := fmrb.Wallclock(); ok {
		clock = two(c.Hour) + ":" + two(c.Minute) + ":" + two(c.Second)
	}
	toml := "-"
	if n, ok := fmrb.FileSize(tomlPath()); ok {
		toml = fmrb.Itoa(n) + " B"
	}
	rows := [...][2]string{
		{"name", fmrb.App.Name()},
		{"pid", fmrb.Itoa(int64(fmrb.App.Pid()))},
		{"platform", platform()},
		{"language", fmrb.App.Language()},
		{"uptime", fmrb.Itoa((fmrb.UptimeMs()-t.started)/1000) + " s"},
		{"clock", clock},
		{"memory", fmrb.Itoa(int64(fmrb.MemoryFree()/1024)) + " KB free"},
		{"toml", toml},
		{"file", t.fileText},
		{"input", t.input},
	}
	for i, r := range rows {
		y := y0 + 6 + int32(i)*11
		g.DrawTextBg(6, y, r[0], inkSub, paper)
		g.DrawTextBg(86, y, r[1], ink, paper)
	}
	if t.blink {
		g.FillCircle(g.AreaWidth()-10, y0+8, 3, cGreen)
	}
}

// W: count the writes in a file of the app's own (under /home).
func (t *tour) writeData() {
	n := int64(0)
	if data, ok := fmrb.FileRead(dataFile); ok {
		for _, c := range data {
			if c >= '0' && c <= '9' {
				n = n*10 + int64(c-'0')
			}
		}
	}
	if !fmrb.FileWrite(dataFile, []byte(fmrb.Itoa(n+1))) {
		fmrb.LogWarn("tour: cannot write " + dataFile)
	}
	t.fileText = readData()
}

// ---- the loop and input

func (t *tour) OnUpdate() int32 {
	now := fmrb.UptimeMs()
	t.tickSound(now)
	blink := (now-t.started)/500%2 == 0
	if blink != t.blink {
		t.blink = blink
		if t.page == 4 {
			t.draw()
		}
	}
	return 100
}

func (t *tour) setPage(p int) {
	t.page = p
	fmrb.LogInfo("tour: page " + pages[p])
	t.draw()
}

func (t *tour) OnEvent(ev fmrb.Event) {
	switch ev.Type {
	case fmrb.MouseUp:
		if ev.Button != 1 {
			return
		}
		t.input = "click " + fmrb.Itoa(int64(ev.X)) + "," + fmrb.Itoa(int64(ev.Y))
		t.setPage((t.page + 1) % len(pages))
	case fmrb.KeyDown:
		if ev.Character > ' ' && ev.Character < 127 {
			t.input = "key " + string(rune(ev.Character))
		} else {
			t.input = "key code " + fmrb.Itoa(int64(ev.Keycode))
		}
		t.key(ev)
	}
}

func (t *tour) key(ev fmrb.Event) {
	sc := ev.Scancode
	if ev.Character == 'q' {
		fmrb.App.Stop()
		return
	}
	if t.page == 3 {
		switch sc {
		case 0x1E: // 1
			t.scaleI = 0
			t.scaleAt = fmrb.UptimeMs()
			return
		case 0x20: // 3
			t.note(1, 988, 90, 14)
			return
		case 0x27: // 0
			t.silence()
			return
		}
	}
	switch {
	case sc >= 0x1E && sc <= 0x22: // 1-5
		t.setPage(int(sc - 0x1E))
		return
	case t.page == 1 && sc == 0x17: // T
		t.fontMode = (t.fontMode + 1) % 3
	case t.page == 2 && sc == 0x0C: // I
		t.imgShown = !t.imgShown
	case t.page == 4 && sc == 0x1A: // W
		t.writeData()
	}
	t.draw()
}

func init() { fmrb.SetApp(&tour{}) }

func main() {}
