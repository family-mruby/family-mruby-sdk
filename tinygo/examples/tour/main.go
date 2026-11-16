// tour: hello plus a tour of the main functions, one page at a time --
// shapes, text (Japanese too), a picture, sprites, tiles, sound, a tune and
// a voice, files, pointer and keys, and the system side (the app's
// information, clocks, memory, the clipboard, its own wasm numbers). Every
// SDK language has this same app with the same screen (c/examples/tour is
// the C one), so the languages can be compared line by line; the common
// specification is in docs/tour.md.
//
//	click, arrows, 1-9, 0   change page
//	q                       quit
//	the page's own keys are listed at its bottom
package main

import "github.com/family-mruby/family-mruby-sdk/tinygo/fmrb"

// The page is white and the palette is picked for contrast against it
// (RGB332, RRRGGGBB). 0x01 would be the transparent key: not used.
const (
	paper   = 0xFF // page background (white)
	ink     = 0x00 // body text (black)
	inkSub  = 0x49 // captions, labels, frames (dark gray)
	cRed    = 0xC0
	cGreen  = 0x0C
	cBlue   = 0x02
	cOrange = 0xE8
	cTeal   = 0x0F
	cPanel  = 0xB6 // light gray fill
	cSky    = 0x9B // the tile map's sky
)

const (
	y0       = 14 // the top of a page's body
	cache    = "/cache/app/tour/"
	picture  = "/usr/share/asterism/icon.png"
	sheetSrc = "/usr/share/sprites/test/tilesheet.png"
	tuneSrc  = "/usr/share/music/korobeiniki.fmsq"
	voice    = "/usr/share/sounds/voice/mahjong/default/pon.wav"
	dir      = "/home/tour"
	sampleJa = "\u3053\u3093\u306b\u3061\u306f ABC \u65e5\u672c\u8a9e" // konnichiwa ABC nihongo
)

const (
	pShapes = iota
	pText
	pImage
	pSprites
	pTiles
	pSound
	pFiles
	pInput
	pSystem
	pSystemPlus
	nPages
)

var pages = [nPages]string{"Shapes", "Text", "Image", "Sprites", "Tiles", "Sound", "Files", "Input", "System", "System+"}
var keys = [nPages]string{
	"click, arrows, 1-9, 0: pages  q: quit",
	"T: font",
	"I: show / hide the picture",
	"H: hide / show one  P: pause",
	"arrows: pages  q: quit",
	"S B: notes  M: tune  V: voice  X: off",
	"W: append  D: delete count.txt",
	"drag: draw  type  BS: clear",
	"arrows: pages  q: quit",
	"C: copy to the clipboard",
}
var scale = [...]int32{262, 294, 330, 349, 392, 440, 494, 523}
var spriteFiles = [4]string{"enemy1_a", "enemy1_b", "enemy2_a", "enemy2_b"}
var tileMap = [4]string{
	"............",
	"........33..",
	"..0.1...22..",
	"444455554444",
}

const maxPoints = 256

type tour struct {
	page      int
	fontMode  int
	started   int64
	blink     bool
	second    int64
	img       fmrb.Image
	imgTried  bool
	imgOK     bool
	imgShown  bool
	noteOffAt [2]int64 // per channel, 0: no note
	scaleI    int      // next note of the scale, -1: none
	scaleAt   int64
	input     string // the last input

	// sprites
	sprTried bool
	sprOK    bool
	sprites  [4]fmrb.Sprite
	sx, sy   [4]int32
	dx, dy   [4]int32
	step     int32
	paused   bool
	hidden0  bool

	// tiles
	sheetTried bool
	sheetOK    bool
	sheet      fmrb.SpriteImage

	// a tune and a voice
	tuneLoaded bool
	tune       string
	voice      string

	// files
	fileLast string

	// input
	pen    bool
	nPts   int
	px, py [maxPoints]int32
	pStart [maxPoints]bool // the first point of a stroke
	typed  string
}

var audio = fmrb.NewAudio()
var g = fmrb.Window

func (t *tour) OnCreate() {
	t.started = fmrb.UptimeMs()
	t.scaleI = -1
	t.imgShown = true
	t.input = "-"
	t.tune = "stopped"
	t.voice = "-"
	t.dx = [4]int32{2, -2, 3, -3}
	t.dy = [4]int32{1, 2, -1, -2}
	fmrb.LogInfo("tour: started on " + platform())
	t.draw()
}

func (t *tour) OnDestroy() {
	audio.NoteOff(0)
	audio.NoteOff(1)
	audio.Stop()
	cleanFiles()
	if t.imgOK {
		g.DeleteImage(t.img)
	}
	g.DeleteAllSprites()
	fmrb.LogInfo("tour: bye")
}

func platform() string {
	if fmrb.App.Platform() == fmrb.PlatformESP32 {
		return "esp32"
	}
	return "linux"
}

func itoa(v int64) string { return fmrb.Itoa(v) }

func text(x, y int32, s string, color int32) { g.DrawTextBg(x, y, s, color, paper) }

// A label and its value on one row.
func row(x, vx, y int32, label, value string) {
	text(x, y, label, inkSub)
	text(vx, y, value, ink)
}

// ---- the page frame

func (t *tour) draw() {
	w, h := g.AreaWidth(), g.AreaHeight()
	g.FillRect(0, 0, w, h, paper)
	text(4, 2, itoa(int64(t.page+1))+"/10 "+pages[t.page], ink)
	switch t.page {
	case pShapes:
		drawShapes()
	case pText:
		t.drawText()
	case pImage:
		t.drawImage()
	case pSprites:
		t.drawSprites()
	case pTiles:
		t.drawTiles()
	case pSound:
		t.drawSound()
	case pFiles:
		t.drawFiles()
	case pInput:
		t.drawInput()
	case pSystem:
		t.drawSystem()
	default:
		drawSystemPlus()
	}
	text(4, h-10, keys[t.page], inkSub)
	g.Present()
}

// ---- page 1: shapes

// round to the nearest integer, halves away from zero
func round(v float64) int32 {
	if v >= 0 {
		return int32(v + 0.5)
	}
	return -int32(-v + 0.5)
}

// sinDeg is sin of an angle in degrees: folded into -90..90, then the
// Taylor series to x^13 (TinyGo's math.Sin would import libm's sin, which a
// wasm app has none of).
func sinDeg(deg int32) float64 {
	d := (deg%360 + 360) % 360 // 0..359
	if d > 180 {
		d -= 360 // -179..180
	}
	if d > 90 {
		d = 180 - d
	} else if d < -90 {
		d = -180 - d
	}
	x := float64(d) * 3.141592653589793 / 180
	term, sum := x, x
	for n := 1; n <= 6; n++ {
		term *= -x * x / float64((2*n)*(2*n+1))
		sum += term
	}
	return sum
}

func cosDeg(deg int32) float64 { return sinDeg(deg + 90) }

func drawShapes() {
	// left: the filled shapes, 57 x 25, 7 apart
	g.FillRect(10, 22, 57, 25, cBlue)
	g.FillRoundRect(10, 54, 57, 25, 6, cTeal)
	g.FillEllipse(38, 98, 28, 12, cOrange)
	g.FillTriangle(10, 142, 66, 142, 38, 118, cRed)
	// centre: concentric circles, 8 apart
	rings := [4]int32{cRed, cOrange, cTeal, cBlue}
	for i, c := range rings {
		g.DrawCircle(114, 82, int32(i+1)*8, c)
	}
	g.FillCircle(114, 82, 3, cRed)
	// right: a regular hexagon around (190, 82), r 32, pointing up
	const cx, cy, r = 190, 82, 32
	var vx, vy [6]int32
	for k := int32(0); k < 6; k++ {
		a := -90 + 60*k
		vx[k] = cx + round(r*cosDeg(a))
		vy[k] = cy + round(r*sinDeg(a))
	}
	for k := 0; k < 3; k++ {
		g.DrawLine(vx[k], vy[k], vx[k+3], vy[k+3], cTeal)
	}
	g.DrawCircle(cx, cy, int32(r*cosDeg(30))-1, cOrange) // inside, 1 dot clear
	for k := 0; k < 6; k++ {
		g.DrawLine(vx[k], vy[k], vx[(k+1)%6], vy[(k+1)%6], cBlue)
	}
	g.FillCircle(cx, cy, 3, cRed)
}

// ---- page 2: text

func (t *tour) drawText() {
	modes := [...]string{"default font", "ja font", "mixed (ascii + ja)"}
	text(6, y0+6, modes[t.fontMode], inkSub)
	switch t.fontMode {
	case 0:
		text(6, y0+20, "ABC abc 123", cBlue)
	case 1:
		g.SetFont(fmrb.FontJa, 12)
		text(6, y0+20, sampleJa, cBlue)
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
		"sum(1..10) = " + itoa(int64(sum)),
		"2^16 = " + itoa(1<<16),
		"area " + itoa(int64(g.AreaWidth())) + "x" + itoa(int64(g.AreaHeight())),
		"SDK " + fmrb.SDKVersion,
	}
	for i, r := range rows {
		text(6, y0+40+int32(i)*10, r, ink)
	}
}

// ---- page 3: a picture

func (t *tour) drawImage() {
	if !t.imgTried {
		t.imgTried = true
		if g.SyncFile(picture, cache+"icon.png") {
			t.img, t.imgOK = g.CreateImage(cache + "icon.png")
		}
		if !t.imgOK {
			fmrb.LogWarn("tour: no picture from " + picture)
		}
	}
	text(6, y0+6, picture, inkSub)
	if !t.imgOK {
		text(6, y0+20, "no picture", cRed)
		return
	}
	if t.imgShown {
		g.DrawImage(t.img, 6, y0+20, 2.0)
	}
	text(80, y0+20, "id "+itoa(int64(t.img.ID)), ink)
	text(80, y0+32, itoa(int64(t.img.Width))+"x"+itoa(int64(t.img.Height))+" px, x2", ink)
}

// ---- page 4: sprites

// loadSprite syncs a picture and reads it into a new sprite image.
func loadSprite(src, name string, w, h int32) (fmrb.SpriteImage, bool) {
	dest := cache + name
	if !g.SyncFile(src, dest) {
		return fmrb.SpriteImage{}, false
	}
	img, ok := g.NewSpriteImage(w, h, 0x00, true)
	return img, ok && g.LoadSpriteImage(img, dest)
}

func (t *tour) setupSprites() {
	t.sprTried = true
	var imgs [4]fmrb.SpriteImage
	for i, f := range spriteFiles {
		img, ok := loadSprite("/usr/share/sprites/shooter/"+f+".png", f+".png", 16, 12)
		if !ok {
			fmrb.LogWarn("tour: no sprite " + f)
			return
		}
		imgs[i] = img
	}
	for k := int32(0); k < 4; k++ {
		frames := imgs[0:2]
		if k%2 == 1 {
			frames = imgs[2:4]
		}
		t.sx[k], t.sy[k] = 16+52*k, y0+24+20*k
		s, ok := g.NewSprite(frames, t.sx[k], t.sy[k], k)
		if !ok {
			fmrb.LogWarn("tour: cannot place a sprite")
			return
		}
		t.sprites[k] = s
	}
	t.sprOK = true
}

func (t *tour) showSprites(on bool) {
	if !t.sprOK {
		return
	}
	for k, s := range t.sprites {
		g.SetSpriteVisible(s, on && !(k == 0 && t.hidden0))
	}
}

func (t *tour) spriteStatus() {
	state := "moving"
	if t.paused {
		state = "paused"
	}
	shown := "shown"
	if t.hidden0 {
		shown = "hidden"
	}
	text(6, y0+124, "step "+itoa(int64(t.step))+"  "+state+"  1: "+shown+"  ", ink)
}

func (t *tour) drawSprites() {
	if !t.sprTried {
		t.setupSprites()
	}
	if !t.sprOK {
		text(6, y0+20, "no sprites", cRed)
		return
	}
	text(6, y0+4, "4 sprites, 2 frames each", inkSub)
	g.DrawRect(6, y0+16, 216, 104, inkSub)
	t.spriteStatus()
}

// bounce keeps v in lo..hi, turning d at an end.
func bounce(v, d *int32, lo, hi int32) {
	*v += *d
	if *v < lo {
		*v, *d = lo, -*d
	} else if *v > hi {
		*v, *d = hi, -*d
	}
}

func (t *tour) stepSprites() {
	if !t.sprOK || t.paused {
		return
	}
	for k := range t.sprites {
		bounce(&t.sx[k], &t.dx[k], 7, 205)
		bounce(&t.sy[k], &t.dy[k], y0+17, y0+107)
		g.MoveSprite(t.sprites[k], t.sx[k], t.sy[k])
	}
	t.step++
	if t.step%4 == 0 {
		for _, s := range t.sprites {
			g.SetSpriteFrame(s, t.step/4%2)
		}
	}
	t.spriteStatus()
	g.Present()
}

// ---- page 5: tiles

func (t *tour) drawTiles() {
	if !t.sheetTried {
		t.sheetTried = true
		t.sheet, t.sheetOK = loadSprite(sheetSrc, "tiles.png", 64, 32)
		if !t.sheetOK {
			fmrb.LogWarn("tour: no tiles from " + sheetSrc)
		}
	}
	if !t.sheetOK {
		text(6, y0+20, "no tiles", cRed)
		return
	}
	text(6, y0+4, "draw_tile: one tile per call", inkSub)
	g.FillRect(6, y0+16, 72, 36, cPanel)
	for i := int32(0); i < 8; i++ {
		t.tile(i, 8+18*(i%4), y0+18+18*(i/4))
	}
	text(86, y0+18, "tilesheet.png", ink)
	text(86, y0+30, "64x32 px, 8 tiles", ink)
	text(86, y0+42, "a 12x4 map below", ink)
	g.FillRect(18, y0+58, 192, 64, cSky)
	for r, line := range tileMap {
		for c := 0; c < len(line); c++ {
			if line[c] != '.' {
				t.tile(int32(line[c]-'0'), 18+16*int32(c), y0+58+16*int32(r))
			}
		}
	}
}

// tile draws tile i of the sheet (4 to a row) at (x, y).
func (t *tour) tile(i, x, y int32) {
	g.DrawTile(t.sheet, 16*(i%4), 16*(i/4), 16, 16, x, y)
}

// ---- page 6: sound

func (t *tour) drawSound() {
	rows := [...]string{"S: a scale on pulse 1", "B: a beep on pulse 2", "M: korobeiniki (FMSQ) on / off",
		"V: a voice (WAV)", "X: stop it all", "", "tune   " + t.tune, "voice  " + t.voice}
	for i, r := range rows {
		text(6, y0+6+int32(i)*12, r, ink)
	}
	text(6, y0+114, "notes end by the clock", inkSub)
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

// The tune and the voice.

func (t *tour) stopTune() {
	if t.tune == "playing" {
		audio.Stop()
		t.tune = "stopped"
	}
}

func (t *tour) toggleTune() {
	if t.tune == "playing" {
		t.stopTune()
		return
	}
	if !t.tuneLoaded {
		t.tuneLoaded = g.SyncFile(tuneSrc, cache+"tune.fmsq") && audio.LoadFmsqFile(0, cache+"tune.fmsq")
		if !t.tuneLoaded {
			fmrb.LogWarn("tour: cannot load " + tuneSrc)
			t.tune = "cannot load"
			return
		}
	}
	audio.PlaySlot(0, fmrb.AudioMain)
	t.tune = "playing"
}

func (t *tour) playVoice() {
	switch r := audio.PlayWav(voice); {
	case r == 1:
		t.voice = "played"
	case r == 0:
		t.voice = "not on this machine"
	default:
		t.voice = "failed"
	}
}

// ---- page 7: files

func setupFiles() {
	fmrb.FileMkdir(dir)
	fmrb.FileWrite(dir+"/hello.txt", []byte("hello from the tour"))
}

func cleanFiles() {
	fmrb.FileDelete(dir + "/count.txt")
	fmrb.FileDelete(dir + "/hello.txt")
	fmrb.FileDelete(dir)
}

func (t *tour) drawFiles() {
	size := "-"
	if n, ok := fmrb.FileSize(dir + "/hello.txt"); ok {
		size = "hello.txt, " + itoa(n) + " B"
	}
	read := "-"
	if data, ok := fmrb.FileRead(dir + "/hello.txt"); ok {
		read = string(data)
	}
	lines := 0
	if data, ok := fmrb.FileRead(dir + "/count.txt"); ok {
		for _, c := range data {
			if c == '\n' {
				lines++
			}
		}
	}
	list := ""
	if names, ok := fmrb.FileList(dir); ok {
		for i, n := range names {
			if i > 0 {
				list += " "
			}
			list += n
		}
	}
	free := "-"
	if n, ok := fmrb.FileFreeBytes(dir); ok {
		free = itoa(n/1024) + " KB"
	}
	rows := [...][2]string{
		{"dir", dir + "/"},
		{"wrote", size},
		{"read", read},
		{"count", itoa(int64(lines)) + " lines"},
		{"list", list},
		{"free", free},
		{"last", t.fileLast},
	}
	for i, r := range rows {
		row(6, 58, y0+6+int32(i)*11, r[0], r[1])
	}
	text(6, y0+86, "all removed when you leave the page", inkSub)
}

func (t *tour) fileKey(sc int32) {
	switch sc {
	case 0x1A: // W
		fmrb.FileAppend(dir+"/count.txt", []byte("w\n"))
		t.fileLast = "appended"
	case 0x07: // D
		if fmrb.FileDelete(dir + "/count.txt") {
			t.fileLast = "deleted count.txt"
		} else {
			t.fileLast = "no count.txt"
		}
	}
}

// ---- page 8: input

func inPad(x, y int32) bool { return x > 6 && x < 221 && y > y0+16 && y < y0+99 }

func clamp(v, lo, hi int32) int32 {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

func (t *tour) drawInput() {
	text(6, y0+4, "drag inside the box to draw", inkSub)
	g.DrawRect(6, y0+16, 216, 84, inkSub)
	for i := 0; i < t.nPts; i++ {
		if t.pStart[i] {
			g.SetPixel(t.px[i], t.py[i], cBlue)
		} else {
			g.DrawLine(t.px[i-1], t.py[i-1], t.px[i], t.py[i], cBlue)
		}
	}
	row(6, 42, y0+106, "typed", t.typed)
	row(6, 42, y0+118, "last", t.input)
}

// addPoint keeps a point of the stroke (the first one starts it) and
// draws the line to it.
func (t *tour) addPoint(x, y int32, start bool) {
	if t.nPts >= maxPoints {
		return
	}
	x, y = clamp(x, 7, 220), clamp(y, y0+17, y0+98)
	i := t.nPts
	t.px[i], t.py[i], t.pStart[i] = x, y, start
	t.nPts++
	if start {
		g.SetPixel(x, y, cBlue)
	} else {
		g.DrawLine(t.px[i-1], t.py[i-1], x, y, cBlue)
	}
	g.Present()
}

// ---- page 9: the system side

func two(v int32) string {
	if v < 10 {
		return "0" + itoa(int64(v))
	}
	return itoa(int64(v))
}

func tomlPath() string {
	p := fmrb.App.ScriptPath()
	if len(p) > 5 && p[len(p)-5:] == ".wasm" {
		return p[:len(p)-5] + ".toml"
	}
	return p
}

func (t *tour) drawSystem() {
	clock := "-"
	if c, ok := fmrb.Wallclock(); ok {
		clock = two(c.Hour) + ":" + two(c.Minute) + ":" + two(c.Second)
	}
	toml := "-"
	if n, ok := fmrb.FileSize(tomlPath()); ok {
		toml = itoa(n) + " B"
	}
	rows := [...][2]string{
		{"name", fmrb.App.Name()},
		{"pid", itoa(int64(fmrb.App.Pid()))},
		{"platform", platform()},
		{"language", fmrb.App.Language()},
		{"uptime", itoa((fmrb.UptimeMs()-t.started)/1000) + " s"},
		{"clock", clock},
		{"memory", itoa(int64(fmrb.MemoryFree()/1024)) + " KB free"},
		{"toml", toml},
	}
	for i, r := range rows {
		row(6, 86, y0+6+int32(i)*11, r[0], r[1])
	}
	if t.blink {
		g.FillCircle(g.AreaWidth()-10, y0+8, 3, cGreen)
	}
}

// ---- page 10: the clipboard, the clock, the app's wasm numbers

func drawSystemPlus() {
	clip := fmrb.Clipboard(20)
	for i := 0; i < len(clip); i++ {
		if clip[i] == '\n' {
			clip = clip[:i]
			break
		}
	}
	if clip == "" {
		clip = "(empty)"
	}
	y := func(i int32) int32 { return y0 + 6 + i*11 }
	text(6, y(0), "clipboard", inkSub)
	g.DrawTextMixed(70, y(0), clip, ink, paper)
	row(6, 70, y(1), "changes", itoa(int64(fmrb.ClipboardGen())))
	text(6, y(2), "wallclock", inkSub)
	if !g.DrawWallclock(70, y(2), ink, paper) {
		text(70, y(2), "-", ink)
	}
	mem, binary, hooks, last := "-", "-", "-", "-"
	if s, ok := fmrb.WasmAppStats(fmrb.App.Pid()); ok {
		mem = itoa(int64(s.Pages)) + " pages, max " + itoa(int64(s.MaxPages))
		binary = itoa(int64(s.BinarySize)) + " B"
		hooks = itoa(int64(s.Calls)) + " calls"
		last = itoa(int64(s.HookUs)) + " us, max " + itoa(int64(s.HookMaxUs))
	}
	apps := "-"
	if s, ok := fmrb.WasmStats(); ok {
		apps = itoa(int64(s.Apps())) + ", pool " + itoa(int64(s.PoolUsed()/1024)) + " KB"
	}
	frames := "-"
	if s, ok := fmrb.GfxStats(); ok {
		frames = itoa(int64(s.Presents))
	}
	rows := [...][2]string{
		{"memory", mem}, {"binary", binary}, {"hooks", hooks}, {"last hook", last},
		{"wasm apps", apps}, {"frames", frames},
	}
	for i, r := range rows {
		row(6, 70, y(int32(i)+3), r[0], r[1])
	}
}

// ---- the loop and input

func (t *tour) OnUpdate() int32 {
	now := fmrb.UptimeMs()
	t.tickSound(now)
	blink := (now-t.started)/500%2 == 0
	if blink != t.blink {
		t.blink = blink
		if t.page == pSystem {
			t.draw()
		}
	}
	if t.page == pSprites {
		t.stepSprites()
	}
	if sec := now / 1000; sec != t.second {
		t.second = sec
		if t.page == pSystemPlus {
			t.draw()
		}
	}
	return 100
}

// setPage leaves the page shown, then enters p.
func (t *tour) setPage(p int) {
	switch t.page {
	case pSprites:
		t.showSprites(false)
	case pSound:
		t.stopTune()
	case pFiles:
		cleanFiles()
	}
	t.page = p
	fmrb.LogInfo("tour: page " + pages[p])
	switch p {
	case pSprites:
		t.showSprites(true)
	case pFiles:
		setupFiles()
		t.fileLast = "-"
	}
	t.draw()
}

func (t *tour) OnEvent(ev fmrb.Event) {
	switch ev.Type {
	case fmrb.MouseDown:
		if ev.Button == 1 && t.page == pInput && inPad(ev.X, ev.Y) {
			t.pen = true
			t.addPoint(ev.X, ev.Y, true)
		}
	case fmrb.MouseMove:
		if t.pen {
			t.addPoint(ev.X, ev.Y, false)
		}
	case fmrb.MouseUp:
		if ev.Button != 1 {
			return
		}
		t.input = "click " + itoa(int64(ev.X)) + "," + itoa(int64(ev.Y))
		if t.pen {
			t.pen = false
			t.draw()
			return
		}
		t.setPage((t.page + 1) % nPages)
	case fmrb.KeyDown:
		if ev.Character > ' ' && ev.Character < 127 {
			t.input = "key " + string(rune(ev.Character))
		} else {
			t.input = "key code " + itoa(int64(ev.Keycode))
		}
		t.key(ev)
	}
}

func (t *tour) key(ev fmrb.Event) {
	sc := ev.Scancode
	switch {
	case ev.Character == 'q':
		fmrb.App.Stop()
		return
	case sc == 0x4F: // right
		t.setPage((t.page + 1) % nPages)
		return
	case sc == 0x50: // left
		t.setPage((t.page + nPages - 1) % nPages)
		return
	case sc >= 0x1E && sc <= 0x26: // 1-9
		t.setPage(int(sc - 0x1E))
		return
	case sc == 0x27: // 0
		t.setPage(9)
		return
	}
	switch t.page {
	case pText:
		if sc == 0x17 { // T
			t.fontMode = (t.fontMode + 1) % 3
		}
	case pImage:
		if sc == 0x0C { // I
			t.imgShown = !t.imgShown
		}
	case pSprites:
		if sc == 0x0B && t.sprOK { // H
			t.hidden0 = !t.hidden0
			g.SetSpriteVisible(t.sprites[0], !t.hidden0)
		} else if sc == 0x13 { // P
			t.paused = !t.paused
		}
	case pSound:
		switch sc {
		case 0x16: // S
			t.scaleI = 0
			t.scaleAt = fmrb.UptimeMs()
		case 0x05: // B
			t.note(1, 988, 90, 14)
		case 0x10: // M
			t.toggleTune()
		case 0x19: // V
			t.playVoice()
		case 0x1B: // X
			t.silence()
			t.stopTune()
		}
	case pFiles:
		t.fileKey(sc)
	case pInput:
		if sc == 0x2A { // backspace
			t.typed = ""
			t.nPts = 0
		} else if ev.Character >= ' ' && ev.Character < 127 {
			t.typed += string(rune(ev.Character))
			if len(t.typed) > 30 {
				t.typed = t.typed[len(t.typed)-30:]
			}
		}
	case pSystemPlus:
		if sc == 0x06 { // C
			fmrb.SetClipboard("copied by the tour")
		}
	}
	t.draw()
}

func init() { fmrb.SetApp(&tour{}) }

func main() {}
