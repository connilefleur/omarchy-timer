// Pure helpers for the timer plugin: duration parsing, formatting, and the
// catalogue of things that can happen when a timer ends.

var SOUND_DIR = "/usr/share/sounds/freedesktop/stereo/"

// `sound` is a file in SOUND_DIR that loops until dismissed; `pauseMedia`
// pauses every MPRIS player that is currently playing; `suspend` puts the
// machine to sleep after a short, cancelable grace period.
var ALARMS = [
  { id: "stop-playback", label: "Stop playback", hint: "Pause music & video", glyph: 0xF03E4, sound: "", pauseMedia: true },
  { id: "stop-and-suspend", label: "Stop playback & suspend", hint: "Pause, then sleep after 15 s", glyph: 0xF04B2, sound: "", pauseMedia: true, suspend: true },
  { id: "alarm-clock", label: "Alarm clock", hint: "", glyph: 0xF0020, sound: "alarm-clock-elapsed.oga", pauseMedia: false },
  { id: "bell", label: "Bell", hint: "", glyph: 0xF009E, sound: "bell.oga", pauseMedia: false },
  { id: "ringtone", label: "Ringtone", hint: "", glyph: 0xF03F2, sound: "phone-incoming-call.oga", pauseMedia: false },
  { id: "chime", label: "Chime", hint: "", glyph: 0xF075A, sound: "complete.oga", pauseMedia: false },
  { id: "silent", label: "Notification only", hint: "No sound", glyph: 0xF009C, sound: "", pauseMedia: false }
]

function glyph(codePoint) {
  return String.fromCodePoint(codePoint)
}

function alarmById(id) {
  for (var i = 0; i < ALARMS.length; i++)
    if (ALARMS[i].id === id) return ALARMS[i]
  return ALARMS[0]
}

function alarmIndex(id) {
  for (var i = 0; i < ALARMS.length; i++)
    if (ALARMS[i].id === id) return i
  return 0
}

function soundPath(alarm) {
  return alarm && alarm.sound ? SOUND_DIR + alarm.sound : ""
}

// Minutes are the unit: "25", "1.5", "0,5" and ".5" are minutes. "1h30",
// "90s", "2m30s" and "mm:ss" / "h:mm:ss" are accepted too. Returns seconds,
// or 0 if invalid.
// Longest accepted input; anything a person types is far shorter.
var MAX_DURATION_TEXT = 32
// One week; also keeps the countdown's millisecond math far from float limits.
var MAX_DURATION_SEC = 7 * 24 * 3600

function parseDuration(value) {
  var raw = String(value || "")
  if (raw.length > MAX_DURATION_TEXT) return 0
  var seconds = parseDurationText(raw)
  return seconds > 0 && seconds <= MAX_DURATION_SEC ? seconds : 0
}

function parseDurationText(value) {
  var text = String(value || "").trim().toLowerCase().replace(/\s+/g, "").replace(/,/g, ".")
  if (text === "") return 0
  // ".5" -> "0.5", "1h.5" -> "1h0.5"
  text = text.replace(/(^|[^\d])\./g, "$10.")

  if (/^\d+(\.\d+)?$/.test(text)) return Math.round(Number(text) * 60)

  if (/^\d+(:\d{1,2}){1,2}$/.test(text)) {
    var parts = text.split(":").map(Number)
    var seconds = 0
    for (var i = 0; i < parts.length; i++) seconds = seconds * 60 + parts[i]
    return seconds
  }

  if (!/^(\d+(\.\d+)?[hms])*\d*$/.test(text)) return 0
  var units = { h: 3600, m: 60, s: 1 }
  var total = 0
  var lastUnit = ""
  var re = /(\d+(?:\.\d+)?)([hms]?)/g
  var token
  while ((token = re.exec(text)) !== null) {
    // A trailing bare number takes the unit below the previous one ("1h30").
    var unit = token[2] || (lastUnit === "h" ? "m" : lastUnit === "m" ? "s" : "m")
    total += Number(token[1]) * units[unit]
    lastUnit = unit
  }
  return Math.round(total)
}

function pad(n) {
  return n < 10 ? "0" + n : String(n)
}

// 1:02:03, 12:34, 0:05
function formatClock(ms) {
  var total = Math.max(0, Math.ceil(ms / 1000))
  var h = Math.floor(total / 3600)
  var m = Math.floor((total % 3600) / 60)
  var s = total % 60
  return h > 0 ? h + ":" + pad(m) + ":" + pad(s) : m + ":" + pad(s)
}

// "25 min", "1 h 30 min", "45 s"
function formatDuration(seconds) {
  var total = Math.max(0, Math.round(seconds))
  var h = Math.floor(total / 3600)
  var m = Math.floor((total % 3600) / 60)
  var s = total % 60
  var parts = []
  if (h > 0) parts.push(h + " h")
  if (m > 0) parts.push(m + " min")
  if (s > 0 || parts.length === 0) parts.push(s + " s")
  return parts.join(" ")
}

if (typeof module !== "undefined") {
  module.exports = {
    ALARMS: ALARMS,
    alarmById: alarmById,
    alarmIndex: alarmIndex,
    soundPath: soundPath,
    parseDuration: parseDuration,
    formatClock: formatClock,
    formatDuration: formatDuration
  }
}
