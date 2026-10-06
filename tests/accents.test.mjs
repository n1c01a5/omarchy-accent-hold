// Run with: node --test tests/
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"

// Accents.js is a QML JavaScript library: drop the pragma and load it as CommonJS.
const source = readFileSync(fileURLToPath(new URL("../Accents.js", import.meta.url)), "utf8")
  .replace(/^\.pragma library\s*/, "")
const module = { exports: {} }
new Function("module", source)(module)
const A = module.exports

test("defaults follow the macOS English sets", () => {
  const config = A.parseConfig("")
  assert.deepEqual(config.accents.e, ["è", "é", "ê", "ë", "ē", "ė", "ę"])
  assert.equal(A.letters(config.accents), "aceilnosuyz")
  assert.equal(config.holdDelay, 0)
  assert.equal(config.position, "window")
})

test("config overrides, disables and validates letters", () => {
  const config = A.parseConfig(JSON.stringify({
    holdDelay: 350.4,
    position: "pointer",
    excludeClasses: ["^steam_app_", 3, ""],
    accents: { e: "éèêë", o: "", k: "ķ", AB: "x", t: 5 }
  }))
  assert.deepEqual(config.accents.e, ["é", "è", "ê", "ë"])
  assert.deepEqual(config.accents.o, [])
  assert.deepEqual(config.accents.k, ["ķ"])
  assert.equal(config.accents.t, undefined)
  assert.equal(A.letters(config.accents), "aceiklnsuyz")
  assert.equal(config.holdDelay, 350)
  assert.equal(config.position, "pointer")
  assert.deepEqual(config.excludeClasses, ["^steam_app_"])
})

test("broken or hostile config falls back to defaults", () => {
  for (const text of ["{", "[]", "null", "42", '{"holdDelay":-5,"position":"nowhere"}']) {
    const config = A.parseConfig(text)
    assert.equal(A.letters(config.accents), "aceilnosuyz")
    assert.equal(config.holdDelay, 0)
    assert.equal(config.position, "window")
  }
})

test("uppercase variants drop characters without a single uppercase form", () => {
  const { accents } = A.parseConfig("")
  assert.deepEqual(A.variantsFor(accents, "s", false), ["ß", "ś", "š"])
  assert.deepEqual(A.variantsFor(accents, "s", true), ["Ś", "Š"])
  assert.deepEqual(A.variantsFor(accents, "E", true), ["È", "É", "Ê", "Ë", "Ē", "Ė", "Ę"])
  assert.deepEqual(A.variantsFor(accents, "q", false), [])
})

test("lua config is a quoted, escaped table", () => {
  const config = A.parseConfig(JSON.stringify({ excludeClasses: ['a"b\\c'] }))
  assert.equal(
    A.luaConfig(config),
    '{ letters = "aceilnosuyz", hold_delay = 0, position = "window", exclude_classes = {"a\\"b\\\\c"} }'
  )
  assert.equal(A.luaString("/x/y z/accent-hold.lua"), '"/x/y z/accent-hold.lua"')
})

test("hold events are parsed and validated", () => {
  const event = A.parseEvent('accent-hold>>{"letter":"e","shift":true,"x":10,"y":20,"monitor":"eDP-1"}')
  assert.deepEqual(event, { letter: "e", shift: true, x: 10, y: 20, monitor: "eDP-1" })
  assert.equal(A.parseEvent('other>>{"letter":"e"}'), null)
  assert.equal(A.parseEvent('accent-hold>>{"letter":"ee"}'), null)
  assert.equal(A.parseEvent("accent-hold>>not json"), null)
})

test("numbers run 1 to 9 then 0", () => {
  assert.deepEqual([0, 1, 8, 9].map(A.numberLabel), ["1", "2", "9", "0"])
  assert.deepEqual(["1", "9", "0", "a", "12"].map(A.digitIndex), [0, 8, 9, -1, -1])
})

test("key input uses the role table, then the typed text", () => {
  const roles = { 1: { key: "Escape" }, 2: { key: "Named", name: "BackSpace" } }
  assert.deepEqual(A.keyInput(1, "\u001b", roles), { key: "Escape" })
  assert.deepEqual(A.keyInput(2, "\b", roles), { key: "Named", name: "BackSpace" })
  assert.deepEqual(A.keyInput(88, "x", roles), { key: "Text", text: "x" })
  assert.deepEqual(A.keyInput(99, "\u0001", roles), { key: "Named" })
  assert.deepEqual(A.keyInput(99, "", roles), { key: "Named" })
})

test("numeric keypad picks digits even with NumLock off", () => {
  const roles = { 10: { key: "Named", name: "End" }, 11: { key: "Left" } }
  const keypadDigits = { 10: "1", 11: "4" }
  assert.deepEqual(A.keyInput(10, "", roles, true, keypadDigits), { key: "Text", text: "1" })
  assert.deepEqual(A.keyInput(11, "", roles, true, keypadDigits), { key: "Text", text: "4" })
  // The same keys outside the keypad keep their meaning.
  assert.deepEqual(A.keyInput(10, "", roles, false, keypadDigits), { key: "Named", name: "End" })
  assert.deepEqual(A.keyInput(11, "", roles, false, keypadDigits), { key: "Left" })
  // NumLock on: the keypad already sends the digit as text.
  assert.deepEqual(A.keyInput(49, "1", roles, true, keypadDigits), { key: "Text", text: "1" })
})

test("popup keys follow the macOS accent menu", () => {
  const none = { count: 7, highlighted: -1 }
  const third = { count: 7, highlighted: 2 }
  const d = (input, state) => A.decideKey(input, state)

  assert.deepEqual(d({ key: "Text", text: "2" }, none), { action: "commit", index: 1 })
  assert.deepEqual(d({ key: "Text", text: "8" }, none), { action: "pass", text: "8" })
  assert.deepEqual(d({ key: "Right" }, none), { action: "highlight", index: 0 })
  assert.deepEqual(d({ key: "Left" }, none), { action: "highlight", index: 6 })
  assert.deepEqual(d({ key: "Tab" }, { count: 7, highlighted: 6 }), { action: "highlight", index: 0 })
  assert.deepEqual(d({ key: "Backtab" }, third), { action: "highlight", index: 1 })
  assert.deepEqual(d({ key: "Return" }, third), { action: "commit", index: 2 })
  assert.deepEqual(d({ key: "Space" }, third), { action: "commit", index: 2 })
  assert.deepEqual(d({ key: "Return" }, none), { action: "pass", keysym: "Return" })
  assert.deepEqual(d({ key: "Space" }, none), { action: "pass", text: " " })
  assert.deepEqual(d({ key: "Escape" }, third), { action: "cancel" })
  assert.deepEqual(d({ key: "Text", text: "x" }, third), { action: "pass", text: "x" })
  assert.deepEqual(d({ key: "Named", name: "BackSpace" }, none), { action: "pass", keysym: "BackSpace" })
  assert.deepEqual(d({ key: "Named" }, none), { action: "cancel" })
  assert.deepEqual(d({ key: "Modifier" }, none), { action: "ignore" })
})

test("typing commands replace the letter or pass the key through", () => {
  assert.deepEqual(A.commitCommand("é"), ["wtype", "-k", "BackSpace", "--", "é"])
  assert.deepEqual(A.passCommand({ text: "-" }), ["wtype", "--", "-"])
  assert.deepEqual(A.passCommand({ keysym: "Return" }), ["wtype", "-k", "Return"])
})
