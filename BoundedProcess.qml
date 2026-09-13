import QtQuick
import Quickshell.Io

// Runs the service's child processes (alarm sound, preview, suspend,
// notifications) under fixed limits:
//   - the caller passes an absolute executable and the complete environment;
//     nothing is inherited from the shell
//   - stdout and stderr are read as raw chunks and capped at maxOutput
//     characters in total; going over kills the process
//   - a hard deadline kills a process that hangs
// Callers only run leaf executables (pw-play, systemctl, busctl, qs) that
// start no children, so SIGKILL on the process ends everything it ran; Process
// reaps it.
// launch() during a run queues the new run behind it; a later launch()
// replaces a run that is still waiting.
Process {
  id: proc

  property int deadlineMs: 10000
  property int maxOutput: 1024
  property string output: ""
  property int received: 0
  property bool failed: false
  property bool wanted: false
  property var queued: null
  // True from launch() until the run (and any queued one) has ended; running
  // only turns true once the process has actually started.
  readonly property bool busy: wanted || running || queued !== null

  // ok: exited 0 on its own, within the output cap and the deadline.
  signal completed(bool ok)

  clearEnvironment: true
  stdinEnabled: false

  function launch(argv, env) {
    queued = { argv: argv, env: env || ({}) }
    if (!wanted && !running) startQueued()
  }

  function kill() {
    queued = null
    wanted = false
    if (running) proc.signal(9)
  }

  function startQueued() {
    if (wanted || running || !queued) return
    var next = queued
    queued = null
    output = ""
    received = 0
    failed = false
    command = next.argv
    environment = next.env
    wanted = true
    running = true
  }

  function take(data, keep) {
    received += data.length
    if (received > maxOutput) {
      failed = true
      if (running) proc.signal(9)
    } else if (keep) {
      output += data
    }
  }

  stdout: SplitParser {
    splitMarker: ""
    onRead: data => proc.take(data, true)
  }

  stderr: SplitParser {
    splitMarker: ""
    onRead: data => proc.take(data, false)
  }

  // Process starts asynchronously, so the deadline (and a kill() that came
  // in before the start) is applied once it is actually running.
  onStarted: {
    if (!wanted) proc.signal(9)
    else deadline.restart()
  }

  onExited: (exitCode, exitStatus) => {
    deadline.stop()
    wanted = false
    proc.completed(exitCode === 0 && exitStatus === 0 && !failed)
  }

  onRunningChanged: {
    if (running) return
    wanted = false
    if (queued) Qt.callLater(startQueued)
  }

  property Timer deadline: Timer {
    interval: proc.deadlineMs
    onTriggered: {
      proc.failed = true
      if (proc.running) proc.signal(9)
    }
  }

  Component.onDestruction: kill()
}
