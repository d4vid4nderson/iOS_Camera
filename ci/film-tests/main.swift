// Tests for the film model and library, compiled with swiftc in CI (no simulator needed):
//   swiftc RetroCam/FilmStock.swift RetroCam/FilmLibrary.swift ci/film-tests/main.swift
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

if failures == 0 { print("film tests: all passed") } else { print("film tests: \(failures) failed"); exit(1) }
