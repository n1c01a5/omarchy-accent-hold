.pragma library

// Pure logic shared by Service.qml and the Node tests: variant tables,
// config parsing, event payloads and popup key handling.

// macOS English (ABC / US) press-and-hold sets, in macOS order.
var DEFAULT_ACCENTS = {
  a: "àáâäæãåā",
  c: "çćč",
  e: "èéêëēėę",
  i: "îïíīįì",
  l: "ł",
  n: "ñń",
  o: "ôöòóœøōõ",
  s: "ßśš",
  u: "ûüùúū",
  y: "ÿ",
  z: "žźż"
}

var EVENT_PREFIX = "accent-hold>>"
var MAX_VARIANTS = 10

function chars(text) {
  return Array.from(String(text || ""))
}

function unique(list) {
  var seen = {}
  return list.filter(function(item) {
    if (seen[item]) return false
    seen[item] = true
    return true
  })
}

function parseConfig(text) {
  var raw = {}
  try {
    raw = text && String(text).trim() ? JSON.parse(text) : {}
  } catch (e) {
    raw = {}
  }
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) raw = {}

  var accents = {}
  for (var letter in DEFAULT_ACCENTS) accents[letter] = chars(DEFAULT_ACCENTS[letter])

  if (raw.accents && typeof raw.accents === "object") {
    for (var key in raw.accents) {
      if (!/^[a-z]$/.test(key) || typeof raw.accents[key] !== "string") continue
      accents[key] = unique(chars(raw.accents[key]).filter(function(c) { return c.trim() !== "" }))
        .slice(0, MAX_VARIANTS)
    }
  }

  var holdDelay = Number(raw.holdDelay)
  return {
    accents: accents,
    holdDelay: isFinite(holdDelay) && holdDelay > 0 ? Math.round(holdDelay) : 0,
    position: raw.position === "pointer" ? "pointer" : "window",
    excludeClasses: Array.isArray(raw.excludeClasses)
      ? raw.excludeClasses.filter(function(p) { return typeof p === "string" && p !== "" })
      : []
  }
}

function letters(accents) {
  return Object.keys(accents).filter(function(letter) {
    return accents[letter].length > 0
  }).sort().join("")
}

// Uppercase forms that are a single character; "ß" has none and is dropped.
function variantsFor(accents, letter, upper) {
  var list = accents[String(letter || "").toLowerCase()] || []
  if (!upper) return list.slice()
  return unique(list.map(function(c) { return c.toUpperCase() })
    .filter(function(c) { return chars(c).length === 1 }))
}

function luaString(value) {
  return "\"" + String(value).replace(/[\\"]/g, "\\$&").replace(/\n/g, "\\n") + "\""
}

function luaConfig(config) {
  return "{ letters = " + luaString(letters(config.accents))
    + ", hold_delay = " + config.holdDelay
    + ", position = " + luaString(config.position)
    + ", exclude_classes = {" + config.excludeClasses.map(luaString).join(", ") + "} }"
}

function parseEvent(data) {
  var text = String(data || "")
  if (text.indexOf(EVENT_PREFIX) !== 0) return null
  try {
    var p = JSON.parse(text.slice(EVENT_PREFIX.length))
    if (!/^[a-z]$/.test(p.letter)) return null
    return {
      letter: p.letter,
      shift: p.shift === true,
      x: Number(p.x) || 0,
      y: Number(p.y) || 0,
      monitor: typeof p.monitor === "string" ? p.monitor : ""
    }
  } catch (e) {
    return null
  }
}

function numberLabel(index) {
  return index === 9 ? "0" : String(index + 1)
}

function digitIndex(text) {
  if (!/^[0-9]$/.test(text)) return -1
  return text === "0" ? 9 : Number(text) - 1
}

// Turns a Qt key press into the input decideKey expects. `roles` maps the Qt
// key codes the popup reacts to (built from Qt.Key_* in QML) to their input.
// `keypadDigits` maps the keys a numeric keypad sends while NumLock is off
// (End, Down, ...) to their digit, so the keypad always picks a variant, as
// on macOS.
function keyInput(code, text, roles, keypad, keypadDigits) {
  if (keypad && keypadDigits && keypadDigits[code]) return { key: "Text", text: keypadDigits[code] }
  if (roles[code]) return roles[code]
  var value = String(text || "")
  var printable = value.length > 0 && value.charCodeAt(0) >= 32 && value.charCodeAt(0) !== 127
  return printable ? { key: "Text", text: value } : { key: "Named" }
}

// Decides what a key press in the popup does.
// input: { key: "Left"|"Right"|"Tab"|"Backtab"|"Return"|"Space"|"Escape"
//               |"Modifier"|"Named"|"Text", name?: keysym, text?: string }
// state: { count, highlighted }
// returns one of:
//   { action: "commit", index }      replace the letter with variant `index`
//   { action: "highlight", index }   move the highlight
//   { action: "cancel" }             close, keep the letter
//   { action: "pass", text } or { action: "pass", keysym }
//                                    close, keep the letter, type the key
//   { action: "ignore" }
function decideKey(input, state) {
  var count = state.count
  var current = state.highlighted

  switch (input.key) {
  case "Modifier":
    return { action: "ignore" }
  case "Escape":
    return { action: "cancel" }
  case "Right":
  case "Tab":
    return { action: "highlight", index: current < 0 ? 0 : (current + 1) % count }
  case "Left":
  case "Backtab":
    return { action: "highlight", index: current < 0 ? count - 1 : (current - 1 + count) % count }
  case "Return":
    return current >= 0 ? { action: "commit", index: current } : { action: "pass", keysym: "Return" }
  case "Space":
    return current >= 0 ? { action: "commit", index: current } : { action: "pass", text: " " }
  case "Named":
    return input.name ? { action: "pass", keysym: input.name } : { action: "cancel" }
  case "Text":
    var digit = digitIndex(input.text)
    if (digit >= 0 && digit < count) return { action: "commit", index: digit }
    return input.text ? { action: "pass", text: input.text } : { action: "ignore" }
  }
  return { action: "ignore" }
}

// wtype argv for each outcome.
function commitCommand(variant) {
  return ["wtype", "-k", "BackSpace", "--", variant]
}

function passCommand(decision) {
  if (decision.keysym) return ["wtype", "-k", decision.keysym]
  return ["wtype", "--", decision.text]
}

if (typeof module !== "undefined") {
  module.exports = {
    DEFAULT_ACCENTS: DEFAULT_ACCENTS,
    parseConfig: parseConfig,
    letters: letters,
    variantsFor: variantsFor,
    luaString: luaString,
    luaConfig: luaConfig,
    parseEvent: parseEvent,
    numberLabel: numberLabel,
    digitIndex: digitIndex,
    keyInput: keyInput,
    decideKey: decideKey,
    commitCommand: commitCommand,
    passCommand: passCommand
  }
}
