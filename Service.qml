import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "TimerModel.js" as Model

// Single timer shared by every bar (one per monitor). Owns the countdown,
// what happens when it ends, IPC, and the state file that lets a running
// timer survive a shell restart or plugin reload.
//
//   status: "idle" | "running" | "paused" | "ringing"
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  property string status: "idle"
  property int durationSec: 0          // total, including time added while running
  property real endAt: 0               // epoch ms, while running
  property real pausedRemainingMs: 0   // while paused
  property string alarmId: "stop-playback"
  property int lastDurationSec: 25 * 60
  property string lastAlarmId: "stop-playback"
  property real now: Date.now()
  property bool stateLoaded: false

  readonly property var alarm: Model.alarmById(alarmId)
  readonly property real remainingMs: status === "running" ? Math.max(0, endAt - now)
    : status === "paused" ? pausedRemainingMs
    : 0
  readonly property real progress: durationSec > 0 ? Math.min(1, remainingMs / (durationSec * 1000)) : 0

  // Asks the bar on the focused monitor to show the set-timer flow.
  signal flowRequested()

  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/timer.json"
  readonly property int missedGraceMs: 5 * 60 * 1000

  // ---- control

  function start(seconds, id) {
    var sec = Math.round(Number(seconds) || 0)
    if (sec <= 0) return false
    stopSound()
    alarmId = Model.alarmById(id || lastAlarmId).id
    durationSec = sec
    lastDurationSec = sec
    lastAlarmId = alarmId
    now = Date.now()
    endAt = now + sec * 1000
    pausedRemainingMs = 0
    status = "running"
    save()
    return true
  }

  function startLast() {
    return start(lastDurationSec, lastAlarmId)
  }

  function pause() {
    if (status !== "running") return false
    now = Date.now()
    pausedRemainingMs = Math.max(0, endAt - now)
    status = "paused"
    save()
    return true
  }

  function resume() {
    if (status !== "paused") return false
    now = Date.now()
    endAt = now + pausedRemainingMs
    status = "running"
    save()
    return true
  }

  function togglePause() {
    return status === "running" ? pause() : resume()
  }

  function cancel() {
    stopSound()
    status = "idle"
    endAt = 0
    pausedRemainingMs = 0
    save()
    return true
  }

  function addSeconds(seconds) {
    var delta = Math.round(Number(seconds) || 0)
    if (status === "running") {
      now = Date.now()
      var remaining = Math.max(0, endAt - now) + delta * 1000
      if (remaining <= 0) { finish(); return true }
      endAt = now + remaining
    } else if (status === "paused") {
      pausedRemainingMs = Math.max(1000, pausedRemainingMs + delta * 1000)
    } else {
      return false
    }
    durationSec = Math.max(1, durationSec + delta)
    save()
    return true
  }

  // The alarm sound loops until this runs: from the bar icon, the ringing
  // card (Esc), the notification, or IPC.
  function stopAlarm() {
    if (status !== "ringing") return false
    cancel()
    Quickshell.execDetached([omarchyPath + "/bin/omarchy-shell", "notifications", "dismiss", "Timer done"])
    return true
  }

  // ---- ending

  function finish() {
    var ended = alarm
    var label = Model.formatDuration(durationSec)
    var detail = ended.label

    if (ended.pauseMedia) {
      var paused = pauseAllMedia()
      detail = paused > 0
        ? "Paused " + paused + (paused === 1 ? " player" : " players")
        : "Nothing was playing"
    }

    if (Model.soundPath(ended) !== "") {
      ring()
      notify("Timer done", label + " · click to stop the alarm", ended.glyph, true)
    } else {
      status = "idle"
      notify("Timer done", label + " · " + detail, ended.glyph, false)
    }
    endAt = 0
    save()
  }

  function isProxyPlayer(player) {
    var dbusName = String(player && player.dbusName || "").toLowerCase()
    var desktopEntry = String(player && player.desktopEntry || "").toLowerCase()
    return dbusName.indexOf("playerctld") !== -1 || desktopEntry === "playerctld"
  }

  // Pauses every playing MPRIS player (browsers, Spotify, mpv, ...). pause()
  // is idempotent, so it is preferred over toggling.
  function pauseAllMedia() {
    var players = Mpris.players ? Mpris.players.values : []
    var count = 0
    for (var i = 0; i < players.length; i++) {
      var player = players[i]
      if (!player || isProxyPlayer(player) || !player.isPlaying) continue
      if (player.canPause) {
        player.pause()
        count++
      } else if (player.canTogglePlaying) {
        player.togglePlaying()
        count++
      }
    }
    return count
  }

  function ring() {
    status = "ringing"
    soundProc.command = ["pw-play", Model.soundPath(alarm)]
    soundProc.running = true
  }

  function stopSound() {
    soundGap.stop()
    if (soundProc.running) soundProc.running = false
  }

  function preview(id) {
    var path = Model.soundPath(Model.alarmById(id))
    if (path === "" || status === "ringing") return
    previewProc.running = false
    previewProc.command = ["pw-play", path]
    previewProc.running = true
  }

  // A stoppable notification is critical, so it stays up until clicked.
  function notify(title, body, glyphCode, stoppable) {
    var args = [omarchyPath + "/bin/omarchy-notification-send", "-g", Model.glyph(glyphCode)]
    if (stoppable) args = args.concat(["-u", "critical"])
    args = args.concat([title, body])
    if (stoppable) args = args.concat(["--exec", omarchyPath + "/bin/omarchy-shell", "io.github.connilefleur.timer", "stop"])
    Quickshell.execDetached(args)
  }

  // ---- persistence

  function save() {
    if (!stateLoaded) return
    stateFile.setText(JSON.stringify({
      version: 1,
      status: status,
      durationSec: durationSec,
      endAt: endAt,
      pausedRemainingMs: pausedRemainingMs,
      alarmId: alarmId,
      lastDurationSec: lastDurationSec,
      lastAlarmId: lastAlarmId
    }, null, 2) + "\n")
  }

  function restore(text) {
    var data = null
    try { data = JSON.parse(text || "{}") } catch (e) { data = null }
    if (data && data.version === 1) {
      lastDurationSec = Number(data.lastDurationSec) > 0 ? Number(data.lastDurationSec) : lastDurationSec
      lastAlarmId = Model.alarmById(data.lastAlarmId).id
      alarmId = Model.alarmById(data.alarmId).id
      durationSec = Number(data.durationSec) || 0
      now = Date.now()

      if (data.status === "running" && Number(data.endAt) > 0) {
        endAt = Number(data.endAt)
        status = "running"
        // Ended while the shell was down: honor it if that was recent.
        if (endAt <= now && now - endAt > missedGraceMs) status = "idle"
      } else if (data.status === "paused" && Number(data.pausedRemainingMs) > 0) {
        pausedRemainingMs = Number(data.pausedRemainingMs)
        status = "paused"
      } else if (data.status === "ringing" && Model.soundPath(alarm) !== "") {
        // Still unacknowledged when the shell went away: keep ringing.
        ring()
      }
    }
    stateLoaded = true
    if (status === "running" && endAt <= now) finish()
  }

  FileView {
    id: stateFile
    path: root.statePath
    atomicWrites: true
    printErrors: false
    onLoaded: if (!root.stateLoaded) root.restore(text())
    onLoadFailed: if (!root.stateLoaded) root.restore("")
  }

  // ---- clocks

  Timer {
    interval: 250
    repeat: true
    running: root.status === "running"
    triggeredOnStart: true
    onTriggered: {
      root.now = Date.now()
      if (root.endAt > 0 && root.now >= root.endAt) root.finish()
    }
  }

  Process {
    id: soundProc
    onExited: if (root.status === "ringing") soundGap.restart()
  }

  Process { id: previewProc }

  Timer {
    id: soundGap
    interval: 700
    onTriggered: if (root.status === "ringing") soundProc.running = true
  }

  // ---- IPC: omarchy-shell io.github.connilefleur.timer <method> [args]

  function statusJson() {
    return JSON.stringify({
      status: status,
      remaining: Math.ceil(remainingMs / 1000),
      remainingText: status === "idle" ? "" : Model.formatClock(remainingMs),
      duration: durationSec,
      alarm: alarmId
    })
  }

  IpcHandler {
    target: "io.github.connilefleur.timer"

    function open(): string { root.flowRequested(); return "ok" }
    function start(duration: string): string {
      return root.start(Model.parseDuration(duration), root.lastAlarmId) ? "ok" : "invalid duration"
    }
    function startWith(duration: string, alarm: string): string {
      return root.start(Model.parseDuration(duration), alarm) ? "ok" : "invalid duration"
    }
    function restart(): string { return root.startLast() ? "ok" : "unhandled" }
    function pause(): string { return root.pause() ? "ok" : "unhandled" }
    function resume(): string { return root.resume() ? "ok" : "unhandled" }
    function toggle(): string { return root.togglePause() ? "ok" : "unhandled" }
    function add(duration: string): string {
      return root.addSeconds(Model.parseDuration(duration)) ? "ok" : "unhandled"
    }
    function cancel(): string { return root.cancel() ? "ok" : "unhandled" }
    function stop(): string { return root.stopAlarm() ? "ok" : "unhandled" }
    function status(): string { return root.statusJson() }
    function alarms(): string {
      return Model.ALARMS.map(function(a) { return a.id }).join("\n")
    }
  }
}
