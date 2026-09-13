import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "TimerModel.js" as Model

// Single timer shared by every bar (one per monitor). Owns the countdown,
// what happens when it ends, and IPC. State lives in memory only: a shell
// restart or plugin reload cancels a running timer.
//
//   status: "idle" | "running" | "paused" | "ringing" | "suspending"
//
// "suspending" is the grace period before a suspend alarm puts the machine
// to sleep; stopAlarm() cancels it just like it silences a ringing alarm.
Item {
  id: root

  property string status: "idle"
  property int durationSec: 0          // total, including time added while running
  property real endAt: 0               // epoch ms, while running
  property real pausedRemainingMs: 0   // while paused
  property real suspendAt: 0           // epoch ms, while suspending
  property string alarmId: "stop-playback"
  property int lastDurationSec: 25 * 60
  property string lastAlarmId: "stop-playback"
  property real now: Date.now()
  property bool dismissPending: false

  readonly property var alarm: Model.alarmById(alarmId)
  readonly property real remainingMs: status === "running" ? Math.max(0, endAt - now)
    : status === "paused" ? pausedRemainingMs
    : status === "suspending" ? Math.max(0, suspendAt - now)
    : 0
  readonly property real progress: durationSec > 0 ? Math.min(1, remainingMs / (durationSec * 1000)) : 0

  // Asks the bar on the focused monitor to show the set-timer flow.
  signal flowRequested()

  readonly property int suspendGraceMs: 15 * 1000

  // Child processes get fixed executables and only the variables listed here.
  // pw-play, busctl and qs find the PipeWire socket, the session bus and the
  // shell's IPC socket through XDG_RUNTIME_DIR; it is passed on only if it has
  // the logind shape.
  readonly property string runtimeDir: {
    var dir = String(Quickshell.env("XDG_RUNTIME_DIR") || "")
    return /^\/run\/user\/[0-9]+$/.test(dir) ? dir : ""
  }
  readonly property var sessionEnv: runtimeDir !== "" ? ({ XDG_RUNTIME_DIR: runtimeDir }) : ({})
  readonly property var notifyBus: ["/usr/bin/busctl", "--user", "--", "call",
    "org.freedesktop.Notifications", "/org/freedesktop/Notifications", "org.freedesktop.Notifications"]

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
    return true
  }

  function resume() {
    if (status !== "paused") return false
    now = Date.now()
    endAt = now + pausedRemainingMs
    status = "running"
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
    suspendAt = 0
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
    return true
  }

  // The alarm sound loops (or the suspend grace period runs) until this runs:
  // from the bar icon, the "Timer done" card (Esc), the notification, or IPC.
  function stopAlarm() {
    if (status !== "ringing" && status !== "suspending") return false
    cancel()
    dismissNotification()
    return true
  }

  // Omarchy's notification server keeps a toast up when its sender closes it,
  // so this goes through the shell's own dismiss IPC. A toast still being sent
  // is dismissed once it is up.
  function dismissNotification() {
    if (notifier.busy) {
      dismissPending = true
      return
    }
    dismissPending = false
    dismisser.launch(shellIpc(["notifications", "dismiss", "Timer done"]), sessionEnv)
  }

  // An IPC call into this shell process: qs talks to it directly, by pid.
  function shellIpc(args) {
    return ["/usr/bin/qs", "ipc", "--pid", String(Quickshell.processId), "call", "--"].concat(args)
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

    if (ended.suspend) {
      status = "suspending"
      now = Date.now()
      suspendAt = now + suspendGraceMs
      notify("Timer done", detail + " · suspending in " + Math.round(suspendGraceMs / 1000) + " s, click to cancel", ended.glyph, true)
    } else if (Model.soundPath(ended) !== "") {
      ring()
      notify("Timer done", label + " · click to stop the alarm", ended.glyph, true)
    } else {
      status = "idle"
      notify("Timer done", label + " · " + detail, ended.glyph, false)
    }
    endAt = 0
  }

  // Same command as Omarchy's System > Suspend; Omarchy locks the session
  // on the way down.
  function suspendNow() {
    status = "idle"
    suspendAt = 0
    dismissNotification()
    power.launch(["/usr/bin/systemctl", "--no-ask-password", "suspend"], {})
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

  // Sound paths are fixed files under /usr/share/sounds (see TimerModel.js).
  function playSound() {
    sound.launch(["/usr/bin/pw-play", Model.soundPath(alarm)], sessionEnv)
  }

  function ring() {
    status = "ringing"
    playSound()
  }

  function stopSound() {
    soundGap.stop()
    sound.kill()
  }

  function preview(id) {
    var path = Model.soundPath(Model.alarmById(id))
    if (path === "" || status === "ringing") return
    previewSound.kill()
    previewSound.launch(["/usr/bin/pw-play", path], sessionEnv)
  }

  // Calls org.freedesktop.Notifications.Notify directly, the way
  // omarchy-notification-send does. A stoppable notification is critical, so
  // it stays up until clicked; clicking runs the stop IPC call through qs.
  function notify(title, body, glyphCode, stoppable) {
    dismissPending = false
    var hints = ["urgency", "y", stoppable ? "2" : "0", "omarchy-glyph", "s", Model.glyph(glyphCode)]
    if (stoppable)
      hints = hints.concat(["omarchy-exec-argv", "s", JSON.stringify(shellIpc(["io.github.connilefleur.timer", "stop"]))])
    notifier.launch(notifyBus.concat([
      "Notify", "susssasa{sv}i",
      "omarchy-action", "0", "", title, body,
      "0", String(hints.length / 3)
    ]).concat(hints).concat(["-1"]), sessionEnv)
  }

  // ---- clocks

  Timer {
    interval: 250
    repeat: true
    running: root.status === "running" || root.status === "suspending"
    triggeredOnStart: true
    onTriggered: {
      root.now = Date.now()
      if (root.status === "running" && root.endAt > 0 && root.now >= root.endAt) root.finish()
      else if (root.status === "suspending" && root.now >= root.suspendAt) root.suspendNow()
    }
  }

  // ---- child processes

  // The longest sound runs about 6 s; the alarm loops by relaunching it.
  BoundedProcess {
    id: sound
    deadlineMs: 15000
    onCompleted: if (root.status === "ringing") soundGap.restart()
  }

  BoundedProcess {
    id: previewSound
    deadlineMs: 15000
  }

  Timer {
    id: soundGap
    interval: 700
    onTriggered: if (root.status === "ringing") root.playSound()
  }

  BoundedProcess {
    id: power
    deadlineMs: 30000
  }

  BoundedProcess {
    id: notifier
    deadlineMs: 5000
    maxOutput: 256
    onCompleted: if (root.dismissPending) root.dismissNotification()
  }

  BoundedProcess {
    id: dismisser
    deadlineMs: 5000
    maxOutput: 256
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
    function suspendNow(): string {
      if (root.status !== "suspending") return "unhandled"
      root.suspendNow()
      return "ok"
    }
    function status(): string { return root.statusJson() }
    function alarms(): string {
      return Model.ALARMS.map(function(a) { return a.id }).join("\n")
    }
  }
}
