// Tests for the film model and library, compiled with swiftc in CI (no simulator needed):
//   swiftc RetroCam/ColorGrade.swift RetroCam/FilmStock.swift RetroCam/FilmLibrary.swift RetroCam/Roll.swift RetroCam/FilmCode.swift ci/film-tests/main.swift
import CoreGraphics
import Foundation

var failures = 0
func check(_ condition: Bool, _ message: String, line: Int = #line) {
    if !condition { failures += 1; print("FAIL line \(line): \(message)") }
}
func near(_ a: CGFloat, _ b: CGFloat, _ tol: CGFloat = 1e-6) -> Bool { abs(a - b) <= tol }

// Built-in films: unique ids, sane values inside the ADJUST panel's ranges.
let ids = FilmStock.all.map(\.id)
check(Set(ids).count == ids.count, "film ids are unique")
check(FilmStock.all.count == 15, "15 built-in films, got \(FilmStock.all.count)")
for f in FilmStock.all {
    check(!f.isCustom, "\(f.id) is not custom")
    check((0...1).contains(f.contrast), "\(f.id) contrast in range")
    check((-1...1).contains(f.key), "\(f.id) key in range")
    check((0...0.25).contains(f.blackLift), "\(f.id) fade in range")
    check((0.75...1).contains(f.whitePoint), "\(f.id) whites in range")
    check((0.6...3).contains(f.grainSize), "\(f.id) grain size in range")
    check((0...1.2).contains(f.vignette), "\(f.id) vignette in range")
    check((0...1).contains(f.toneAmount) && (0...1).contains(f.bloom) && (0...1).contains(f.fog), "\(f.id) 0...1 values")
    check(near(f.red + f.green + f.blue, 1, 0.02), "\(f.id) channel weights sum to ~1")
}

// Toning: neutral (or amount 0) leaves grey alone; amount 1 hits ink, mid and paper.
for t in Toning.allCases {
    let k0 = t.coefficients(amount: 0)
    check(near(k0.r.0, 0) && near(k0.r.1, 1) && near(k0.r.2, 0), "\(t) at amount 0 is identity")
    let k = t.coefficients(amount: 1)
    func f(_ c: (CGFloat, CGFloat, CGFloat), _ x: CGFloat) -> CGFloat { c.0 + c.1 * x + c.2 * x * x }
    let s = t.stops
    check(near(f(k.r, 0), s.ink.r) && near(f(k.g, 0.5), s.mid.g) && near(f(k.b, 1), s.paper.b), "\(t) passes through its stops")
}
let n = Toning.neutral.coefficients(amount: 1)
check(near(n.g.0, 0) && near(n.g.1, 1) && near(n.g.2, 0), "neutral toning is identity")

// Colour filters: weights sum to 1 and presets are recognised.
for c in ColorFilter.allCases {
    let w = c.weights
    check(near(w.r + w.g + w.b, 1, 0.011), "\(c) weights sum to 1")
    check(ColorFilter.matching(red: w.r, green: w.g, blue: w.b) == c, "\(c) matches itself")
}
check(FilmStock.redFilter.colorFilter == .red, "RED FILTER uses the red filter")
check(FilmStock.ortho.colorFilter == .ortho, "ORTHO is orthochromatic")
check(FilmStock.infrared.colorFilter == .infrared, "INFRARED uses the IR mix")
var mixed = FilmStock.classic400
mixed.apply(.orange)
check(mixed.colorFilter == .orange, "apply(filter) sets the weights")

// Codable: round trip, and old or partial data still decodes.
let encoder = JSONEncoder(), decoder = JSONDecoder()
for f in FilmStock.all {
    let back = try! decoder.decode(FilmStock.self, from: encoder.encode(f))
    check(back == f, "\(f.id) survives encode/decode")
}
let partial = #"{"id":"custom-old","name":"OLD ONE","contrast":0.9}"#.data(using: .utf8)!
let old = try! decoder.decode(FilmStock.self, from: partial)
check(old.name == "OLD ONE" && near(old.contrast, 0.9) && old.tone == .neutral && old.fog == 0, "partial film decodes with defaults")
check(old.isCustom, "custom prefix recognised")
check(old.effect == .none && near(old.effectAmount, 0.5) && near(old.effectX, 0.5), "old films decode with no effect")
var fx = FilmStock.frost400
fx.effect = .swirl; fx.effectAmount = 0.8; fx.effectX = 0.2; fx.effectY = 0.7
let fxBack = try! decoder.decode(FilmStock.self, from: encoder.encode(fx))
check(fxBack == fx, "effect settings survive encode/decode")
check(LensEffect.swirl.usesCenter && !LensEffect.drag.usesCenter && LensEffect.halftone.isPrintEffect, "effect kinds")
check(Set(LensEffect.allCases.map(\.label)).count == LensEffect.allCases.count, "effect labels unique")

// Library: edits, save, update, rename, delete.
var lib = FilmLibrary()
var edited = FilmStock.noir
edited.contrast = 0.2
lib.setEdit(edited)
check(lib.isEdited(id: "noir") && lib.current(id: "noir")?.contrast == 0.2, "edit remembered")
lib.setEdit(.noir)
check(!lib.isEdited(id: "noir"), "editing back to the original clears the edit")
lib.setEdit(edited)
let saved = lib.saveNew(from: edited, named: "  late night  ", id: "custom-1")
check(saved.isCustom && saved.name == "LATE NIGHT" && near(saved.contrast, 0.2), "saved film keeps settings, cleaned name")
check(lib.all.last?.id == "custom-1" && lib.original(id: "custom-1") != nil, "saved film is in the picker")
var tweak = saved
tweak.grainSize = 2.5
lib.setEdit(tweak)
check(lib.isEdited(id: "custom-1"), "custom film can be edited")
lib.update(tweak)
check(!lib.isEdited(id: "custom-1") && lib.original(id: "custom-1")?.grainSize == 2.5, "update writes into the saved film")
lib.rename(id: "custom-1", to: "a very long film name that goes on")
check(lib.original(id: "custom-1")?.name.count == FilmLibrary.maxNameLength, "names are capped")
check(FilmLibrary.cleanName("   ") == "MY FILM", "empty names get a default")

// Persistence round trip through a scratch defaults suite.
let suite = "film-tests-\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
lib.setEdit(edited)
lib.save(to: defaults)
let loaded = FilmLibrary.load(from: defaults)
check(loaded == lib, "library survives save/load")
lib.delete(id: "custom-1")
check(lib.original(id: "custom-1") == nil && !lib.isEdited(id: "custom-1"), "delete removes film and edits")
defaults.removePersistentDomain(forName: suite)

// Rolls: numbering, naming, frame counting, persistence.
var roll = Roll(number: 7)
check(roll.albumTitle == "Roll 07", "unnamed roll title")
roll.expose(film: "CLASSIC 400")
roll.expose(film: "NOIR 400")
check(roll.frames == 2 && roll.film == "CLASSIC 400" && roll.albumTitle == "Roll 07 · CLASSIC 400", "first frame names the roll")
for _ in 0..<50 { roll.expose(film: "X") }
check(roll.frames == Roll.length && roll.isFinished, "roll stops at 36")
check(roll.next().number == 8 && roll.next().frames == 0 && roll.next().film == nil, "next roll is fresh")
var one = Roll(number: 1); one.expose(film: "PAN 50"); one.unexpose()
check(one.frames == 0 && one.film == nil, "a failed first frame un-names the roll")
let rollSuite = "roll-tests-\(UUID().uuidString)"
let rollDefaults = UserDefaults(suiteName: rollSuite)!
check(Roll.load(from: rollDefaults) == Roll(number: 1), "fresh install starts on roll 1")
roll.save(to: rollDefaults)
check(Roll.load(from: rollDefaults) == roll, "roll survives save/load")
rollDefaults.removePersistentDomain(forName: rollSuite)

// Developing: instant, at roll end, or 9:00 the morning after the roll is finished.
var utc = Calendar(identifier: .gregorian)
utc.timeZone = TimeZone(identifier: "UTC")!
let finishedAt = Date(timeIntervalSince1970: 1_793_000_000)          // 07:13 UTC, a Sunday
check(DevelopMode.instant.readyDate(finished: nil, calendar: utc) == .distantPast, "instant is always ready")
check(DevelopMode.rollEnd.readyDate(finished: nil, calendar: utc) == nil, "roll-end waits for the roll")
check(DevelopMode.rollEnd.readyDate(finished: finishedAt, calendar: utc) == finishedAt, "roll-end ready when finished")
let morning = DevelopMode.nextMorning.readyDate(finished: finishedAt, calendar: utc)!
let parts = utc.dateComponents([.hour, .minute], from: morning)
check(parts.hour == DevelopMode.labHour && parts.minute == 0 && morning > finishedAt
      && morning.timeIntervalSince(finishedAt) < 2 * 86_400, "next morning is 9:00 the next day")
var later = Roll(number: 3)
later.expose(film: "NOIR 400", develop: .rollEnd)
check(later.developMode == .rollEnd && !later.isDeveloped(), "unfinished roll-end roll is undeveloped")
later.finish(at: finishedAt)
check(later.isDeveloped(at: finishedAt), "finished roll-end roll develops")
let oldJSON = #"{"number":2,"frames":5}"#.data(using: .utf8)!
let oldRoll = try! JSONDecoder().decode(Roll.self, from: oldJSON)
check(oldRoll.develop == .instant && oldRoll.finishedAt == nil && oldRoll.frames == 5, "older saved rolls still load")

// Film recipe links: compact, round trip within a click of every dial, new id, old links
// still open, junk rejected.
var recipe = FilmStock.lith
recipe.name = "MY LITH"; recipe.effect = .swirl; recipe.effectAmount = 0.7; recipe.contrast = 0.81
recipe.effectX = 0.25; recipe.effectY = 0.6; recipe.key = -0.35; recipe.exposure = 0.3
let link = FilmCode.url(for: recipe)!
check(["exposures", "https"].contains(link.scheme ?? "") && link.lastPathComponent.count <= 50, "film code is compact (\(link.lastPathComponent.count) chars)")
let received = FilmCode.film(from: link)!
check(received.isCustom && received.id != recipe.id && received.name == "MY LITH", "received film is a new custom film")
check(received.effect == .swirl && received.tone == recipe.tone && received.iso == recipe.iso, "enums and ISO survive")
// Packed to 1/255 of each range: well inside the dials' 0.01-0.1 steps.
let pairs: [(CGFloat, CGFloat, String)] = [
    (received.contrast, recipe.contrast, "contrast"), (received.key, recipe.key, "key"),
    (received.red, recipe.red, "red"), (received.green, recipe.green, "green"), (received.blue, recipe.blue, "blue"),
    (received.blackLift, recipe.blackLift, "fade"), (received.whitePoint, recipe.whitePoint, "whites"),
    (received.grain, recipe.grain, "grain"), (received.grainSize, recipe.grainSize, "grain size"),
    (received.vignette, recipe.vignette, "vignette"), (received.toneAmount, recipe.toneAmount, "tone amount"),
    (received.bloom, recipe.bloom, "glow"), (received.exposure, recipe.exposure, "exposure"),
    (received.effectAmount, recipe.effectAmount, "fx amount"),
    (received.effectX, recipe.effectX, "fx x"), (received.effectY, recipe.effectY, "fx y"),
]
for (got, want, name) in pairs { check(near(got, want, 0.012), "\(name) survives the link (\(got) vs \(want))") }
for film in FilmStock.all {
    let back = FilmCode.film(from: FilmCode.url(for: film)!)!
    check(back.name == film.name && back.tone == film.tone && near(back.contrast, film.contrast, 0.005), "\(film.id) round-trips")
}
// A link from the first sharing build (zlib JSON) still opens.
var oldFilm = FilmStock.noir; oldFilm.id = "shared"; oldFilm.name = "OLD NOIR"
let oldPacked = try! (JSONEncoder().encode(oldFilm) as NSData).compressed(using: .zlib) as Data
var oldParts = URLComponents(); oldParts.scheme = "exposures"; oldParts.host = "film"
oldParts.queryItems = [URLQueryItem(name: "d", value: FilmCode.base64url(oldPacked))]
check(FilmCode.film(from: oldParts.url!)?.name == "OLD NOIR", "older film links still open")
check(FilmCode.film(from: URL(string: "exposures://film?d=garbage")!) == nil, "damaged old links are rejected")
check(FilmCode.film(from: URL(string: "exposures://f/garbage")!) == nil, "damaged links are rejected")
check(FilmCode.film(from: URL(string: "https://example.com/film?d=abc")!) == nil, "other links are ignored")
var shareLib = FilmLibrary()
shareLib.add(received)
check(shareLib.original(id: received.id) != nil && shareLib.all.last?.id == received.id, "shared film added to the picker")

// Web links (https://<share host>/f/<code> and /r/<id>).
let panCode = FilmCode.url(for: .pan50)!.lastPathComponent
let web = URL(string: "https://exposures.example.workers.dev/f/\(panCode)")!
check(FilmCode.film(from: web, webHost: "exposures.example.workers.dev")?.name == "PAN 50", "web film links open")
check(FilmCode.film(from: web, webHost: "other.example.com") == nil, "film links from other sites are ignored")
check(ShareLinks.rollID(from: URL(string: "https://exposures.example.workers.dev/r/AbCd234xyz")!, host: "exposures.example.workers.dev") == "AbCd234xyz", "web roll links parse")
check(ShareLinks.rollID(from: URL(string: "exposures://r/AbCd234xyz")!) == "AbCd234xyz", "app roll links parse")
check(ShareLinks.rollID(from: URL(string: "https://evil.example.com/r/AbCd234xyz")!, host: "exposures.example.workers.dev") == nil, "roll links from other sites are ignored")
check(ShareLinks.rollID(from: URL(string: "exposures://r/short")!) == nil, "bad roll ids are rejected")
check(ShareLinks.userID(from: URL(string: "https://exposures.example.workers.dev/u/AbCd234xyzQR")!, host: "exposures.example.workers.dev") == "AbCd234xyzQR", "web profile links parse")
check(ShareLinks.userID(from: URL(string: "exposures://u/AbCd234xyzQR")!) == "AbCd234xyzQR", "app profile links parse")
check(ShareLinks.userID(from: URL(string: "exposures://r/AbCd234xyz")!) == nil, "a roll link isn't a profile link")
check(ShareLinks.rollID(from: URL(string: "exposures://u/AbCd234xyzQR")!) == nil, "a profile link isn't a roll link")
check(ShareLinks.userID(from: URL(string: "https://evil.example.com/u/AbCd234xyzQR")!, host: "exposures.example.workers.dev") == nil, "profile links from other sites are ignored")

// Roll names.
var named = Roll(number: 7)
named.expose(film: "CLASSIC 400")
check(named.title == "Roll 07" && named.albumTitle == "Roll 07 · CLASSIC 400", "unnamed roll titles")
named.name = Roll.cleanName("  Beach day  ")
check(named.title == "Beach day" && named.albumTitle == "Roll 07 · Beach day", "named roll titles")

// Part-shot rolls can go back in the camera; finished or full ones can't.
var food = Roll(number: 3)
check(!food.isOpen, "a roll with nothing shot isn't part-shot")
food.expose(film: "CLASSIC 400")
check(food.isOpen, "a part-shot roll can be loaded again")
var finishedEarly = food
finishedEarly.finish()
check(!finishedEarly.isOpen, "a finished roll stays finished")
var full = Roll(number: 4)
for _ in 0..<Roll.length { full.expose(film: "CLASSIC 400") }
check(!full.isOpen, "a full roll can't be loaded again")
check(Roll.freshNumber(after: [3, 9, 4]) == 10, "new rolls get a number no roll has")
check(Roll.freshNumber(after: []) == 1, "the first roll is roll 1")
check(Roll.cleanName("   ") == nil, "an empty name clears it")
check(Roll.cleanName(String(repeating: "x", count: 40))?.count == Roll.maxNameLength, "names are capped")
let namedBack = try! JSONDecoder().decode(Roll.self, from: JSONEncoder().encode(named))
check(namedBack.name == "Beach day", "roll names are saved")
check(named.next().name == nil, "a new roll starts unnamed")

// Share card captions.
check(FilmStock.pan50.shareCaption == "Black & white  ·  ISO 50  ·  Fine grain", "PAN 50 caption: \(FilmStock.pan50.shareCaption)")
check(FilmStock.selenium.shareCaption.hasPrefix("Selenium toned"), "selenium film says it's toned")
check(FilmStock.expired.shareCaption.hasPrefix("Black & white"), "a light tint still reads as black & white")
check(FilmStock.push3200.shareCaption.hasSuffix("Heavy grain"), "push film is heavy grain")
for film in FilmStock.all { check(film.shareCaption.contains("ISO \(film.iso)"), "\(film.id) caption has its ISO") }

// MARK: Colour films

let plain = ColorGrade()
check(plain.isIdentity, "a default grade changes nothing")
for (r, g, b) in [(0.0, 0.0, 0.0), (1.0, 1.0, 1.0), (0.2, 0.5, 0.8), (0.9, 0.4, 0.1)] {
    let out = plain.map(r, g, b)
    check(abs(out.0 - r) < 1e-9 && abs(out.1 - g) < 1e-9 && abs(out.2 - b) < 1e-9, "identity grade keeps (\(r), \(g), \(b))")
}
var curves = ColorGrade()
curves.greenHighlights = 1
curves.blueHighlights = -1
check(curves.map(0, 0, 0) == (0, 0, 0) && curves.map(1, 1, 1) == (1, 1, 1), "curves keep black and white")
let lifted = curves.map(0.667, 0.667, 0.667)
check(lifted.1 > 0.75 && lifted.2 < 0.6 && abs(lifted.0 - 0.667) < 1e-9, "green lifted, blue lowered in the highlights")

var split = ColorGrade()
split.shadowHue = 0.6; split.shadowAmount = 1      // blue
split.highlightHue = 0.1; split.highlightAmount = 1  // orange
let dark = split.map(0.15, 0.15, 0.15), light = split.map(0.85, 0.85, 0.85)
check(dark.2 > dark.0, "shadows lean blue")
check(light.0 > light.2, "highlights lean orange")
check(abs(ColorGrade.luma(dark.0, dark.1, dark.2) - 0.15) < 0.02, "split toning keeps brightness")

var mono = ColorGrade()
mono.saturation = 0
let grey = mono.map(0.9, 0.3, 0.2)
check(abs(grey.0 - grey.1) < 1e-9 && abs(grey.1 - grey.2) < 1e-9, "no saturation is grey")

var aquaGrade = ColorGrade()
aquaGrade.aqua = 1
let sky = aquaGrade.map(0.3, 0.5, 0.9)
check(ColorGrade.hsv(sky.0, sky.1, sky.2).0 < ColorGrade.hsv(0.3, 0.5, 0.9).0, "blues move toward aqua")
let skin = aquaGrade.map(0.9, 0.6, 0.45)
check(abs(skin.0 - 0.9) < 1e-9 && abs(skin.1 - 0.6) < 1e-9, "aqua leaves warm colours alone")

check(plain.cubeData(size: 5).count == 5 * 5 * 5 * 4 * MemoryLayout<Float>.size, "colour cube size")

let colorFilms = FilmStock.all.filter(\.color)
check(colorFilms.count == 5, "five colour films")
check(FilmStock.all.filter { !$0.color }.count == 15, "black & white films are unchanged")
for film in colorFilms {
    check(film.shareCaption.hasPrefix("Color"), "\(film.id) reads as colour")
    let back = FilmCode.film(from: FilmCode.url(for: film)!)!
    check(back.color, "\(film.id) link keeps it a colour film")
    for (name, a, b) in [("saturation", film.saturation, back.saturation), ("warmth", film.warmth, back.warmth),
                         ("shadow hue", film.shadowHue, back.shadowHue), ("highlights", film.highlightAmount, back.highlightAmount),
                         ("green high", film.greenHighlights, back.greenHighlights), ("blue high", film.blueHighlights, back.blueHighlights),
                         ("halation", film.halation, back.halation), ("contrast", film.contrast, back.contrast)] {
        check(abs(a - b) < 0.01, "\(film.id) link keeps \(name)")
    }
    let json = try! JSONEncoder().encode(film)
    let decoded = try! JSONDecoder().decode(FilmStock.self, from: json)
    check(decoded == film, "\(film.id) saves and loads")
}
check(!FilmCode.film(from: FilmCode.url(for: .pan50)!)!.color, "black & white links stay black & white")
let oldSaved = try! JSONEncoder().encode(FilmStock.noir)
check(!(try! JSONDecoder().decode(FilmStock.self, from: oldSaved)).color, "films saved before colour load as black & white")

if failures == 0 { print("film tests: all passed") } else { print("film tests: \(failures) failed"); exit(1) }
