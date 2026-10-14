import Foundation

// Gera um projeto que usa todos os campos do formato .openframe. A versão
// multiplataforma (qt/) lê este arquivo nos testes e precisa gravá-lo de volta
// com o mesmo conteúdo: é o que garante que os dois apps abrem os mesmos projetos.
// Uso: scripts/make-fixture.sh  (grava qt/tests/fixtures/completo.openframe)

func uuid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }

var p = Project()
p.name = "Projeto completo"
p.fps = 29.97
p.canvas.aspect = .r9x16
p.canvas.background = .color(RGBA(0.1, 0.2, 0.3, 1))
p.tracks[0].id = uuid(1)

var video = Material(kind: .video, path: "/media/clipe.mov", name: "clipe.mov",
                     duration: 12_345_678, width: 1080, height: 1920, hasAudio: true)
video.id = uuid(10)
var photo = Material(kind: .photo, path: "/media/foto.jpg", name: "foto.jpg",
                     duration: 0, width: 4032, height: 3024, hasAudio: false)
photo.id = uuid(11)
var audio = Material(kind: .audio, path: "/media/música.m4a", name: "música.m4a",
                     duration: 60_000_000, width: 0, height: 0, hasAudio: true)
audio.id = uuid(12)
p.materials = [video, photo, audio]

var a = Segment(materialId: video.id, source: TimeRange(start: 1_000_000, duration: 4_000_000), targetStart: 0)
a.id = uuid(20)
a.speed = 2
a.volume = 0.8
a.fadeIn = 250_000
a.fadeOut = 500_000
a.transform.scale = 1.25
a.transform.x = -0.1
a.transform.y = 0.2
a.transform.rotation = 15
a.opacity = 0.9
a.adjust.brightness = 0.1
a.adjust.contrast = -0.2
a.adjust.saturation = 0.3
a.adjust.exposure = 0.05
a.adjust.temperature = 0.4
a.adjust.tint = -0.1
a.adjust.highlights = 0.2
a.adjust.shadows = -0.3
a.adjust.hue = 0.15
a.adjust.sharpen = 0.5
a.adjust.vignette = 0.6
a.adjust.fade = 0.25
a.adjust.grain = 0.35
a.filter = FilterSetting(preset: .cinematic, intensity: 0.75)
var e1 = VideoEffect(kind: .rgbSplit, intensity: 0.4); e1.id = uuid(30)
var e2 = VideoEffect(kind: .shake, intensity: 0.7); e2.id = uuid(31)
a.effects = [e1, e2]
a.animationIn = SegmentAnimation(kind: .zoomIn, duration: 400_000)
a.animationOut = SegmentAnimation(kind: .slideLeft, duration: 600_000)
a.transition = Transition(kind: .dissolve, duration: 500_000)

var b = Segment(materialId: photo.id, source: TimeRange(start: 0, duration: 3_000_000), targetStart: 0)
b.id = uuid(21)
p.tracks[0].segments = [a, b]
TimelineEditor.relayoutMain(&p)

var music = Track(kind: .audio)
music.id = uuid(2)
music.muted = true
var m = Segment(materialId: audio.id, source: TimeRange(start: 0, duration: 5_000_000), targetStart: 500_000)
m.id = uuid(22)
music.segments = [m]

var titles = Track(kind: .text)
titles.id = uuid(3)
titles.hidden = true
var style = TextStyle()
style.fontName = "Inter"
style.fontFace = "Semibold"
style.fontSize = 0.05
style.bold = false
style.italic = true
style.underline = true
style.textCase = .upper
style.color = RGBA(1, 0.85, 0.1, 1)
style.opacity = 0.95
style.strokeColor = RGBA(0, 0, 0, 0.5)
style.strokeWidth = 8
style.letterSpacing = 0.05
style.lineSpacing = -0.1
style.backgroundEnabled = true
style.backgroundColor = RGBA(0.2, 0.2, 0.2, 0.7)
style.backgroundRadius = 0.3
style.backgroundPaddingX = 0.4
style.backgroundPaddingY = 0.2
style.shadow = false
style.shadowColor = RGBA(0, 0, 0, 0.4)
style.shadowDistance = 0.06
style.shadowAngle = -45
style.shadowBlur = 0.2
style.alignment = .left
style.x = 0.1
style.y = 0.5
style.scale = 1.5
style.rotation = -5
style.maxWidth = 0.8
var t = Segment.text(TextContent(text: "Olá, mundo!\nSegunda linha 🎬", style: style), at: 1_000_000, duration: 2_000_000)
t.id = uuid(23)
t.animationIn = SegmentAnimation(kind: .typewriter, duration: 1_000_000)
titles.segments = [t]

var overlays = Track(kind: .video)
overlays.id = uuid(4)
var o = Segment(materialId: photo.id, source: TimeRange(start: 0, duration: 2_000_000), targetStart: 750_000)
o.id = uuid(24)
o.transform.scale = 0.5
overlays.segments = [o]

p.tracks += [overlays, music, titles]

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try ProjectStore.save(p, to: out)

// Variações do fundo do canvas (o enum com valor associado tem codificação própria).
for (name, bg) in [("fundo-preto", CanvasBackground.black), ("fundo-desfoque", .blur(0.6))] {
    var q = Project()
    q.tracks[0].id = uuid(1)
    q.canvas.background = bg
    try ProjectStore.save(q, to: out.deletingLastPathComponent().appendingPathComponent("\(name).openframe"))
}
print("ok: \(out.path)")
