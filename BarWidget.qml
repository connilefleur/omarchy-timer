import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "TimerModel.js" as Model

// Timer icon for the bar, styled like the indicator icons next to the clock.
// Idle it hides the same way inactive indicators do, peeking in dimmed while
// the center of the bar is hovered; while counting it shows the remaining
// time; when an alarm rings it blinks in the urgent color until clicked.
//
//   left click    set a timer (or manage the running one)
//   right click   pause / resume, or restart the last timer when idle
//   middle click  cancel
//   scroll        add / remove a minute while counting
BarWidget {
  id: root
  moduleName: "io.github.connilefleur.timer"

  readonly property var timer: bar && bar.shell ? bar.shell.serviceFor("io.github.connilefleur.timer") : null
  readonly property string status: timer ? timer.status : "idle"
  readonly property bool counting: status === "running" || status === "paused"
  readonly property bool ringing: status === "ringing"
  readonly property bool showTime: counting && !vertical
  readonly property string timeText: counting ? Model.formatClock(timer.remainingMs) : ""
  readonly property color iconColor: ringing && bar ? bar.urgent : button.foreground
  // Same reveal rule as omarchy.indicators' inactive block.
  readonly property bool revealed: status !== "idle"
    || setting("alwaysShow", false) === true
    || hover.hovered
    || (bar && bar.centerSectionRevealHeld === true && bar.centerHoverRevealSuppressed !== true)

  readonly property string tooltip: {
    if (!timer) return "Timer"
    if (ringing) return "Timer done · click to stop the alarm"
    if (status === "paused") return "Paused · " + timeText + " left · " + timer.alarm.label
    if (status === "running")
      return timer.alarm.label + " at " + Qt.formatTime(new Date(timer.endAt), "HH:mm")
        + "\nRight click pause · Middle click cancel · Scroll ±1 min"
    return "Timer\nRight click restarts " + Model.formatDuration(timer.lastDurationSec)
  }

  function screenName() {
    var window = root.QsWindow.window
    return window && window.screen ? window.screen.name : ""
  }

  function openFlow() {
    if (!timer) return
    if (flowLoader.item) flowLoader.item.open()
    else flowLoader.active = true
  }

  implicitWidth: root.vertical || root.revealed ? button.implicitWidth : 0
  implicitHeight: !root.vertical || root.revealed ? button.implicitHeight : 0
  clip: true

  HoverHandler { id: hover }

  function onFocusedMonitor() {
    var focused = Hyprland.focusedMonitor
    var mine = root.screenName()
    return !focused || !mine || focused.name === mine
  }

  Connections {
    target: root.timer
    function onFlowRequested() { if (root.onFocusedMonitor()) root.openFlow() }
    // A ringing alarm puts its "Timer done" card up on the focused monitor.
    function onStatusChanged() {
      if (root.ringing && root.onFocusedMonitor()) root.openFlow()
    }
  }

  Loader {
    id: flowLoader
    active: false
    source: Qt.resolvedUrl("Flow.qml")
    onLoaded: {
      item.timer = root.timer
      item.screen = root.QsWindow.window ? root.QsWindow.window.screen : null
      item.open()
    }
  }

  Connections {
    target: flowLoader.item
    function onDismissed() { Qt.callLater(function() { flowLoader.active = false }) }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    tooltipText: root.tooltip
    dimmed: root.status === "idle" || root.status === "paused"
    concealed: !root.revealed
    interactive: root.revealed
    horizontalMargin: 5
    verticalPadding: 5
    fixedWidth: root.vertical ? -1
      : Style.bar.statusSlot + (root.showTime ? timeLabel.implicitWidth + Style.space(5) : 0)
    fixedHeight: root.vertical ? Style.bar.statusSlot : -1

    onPressed: function(b) {
      if (!root.timer) return
      if (root.ringing) root.timer.stopAlarm()
      else if (b === Qt.MiddleButton) root.timer.cancel()
      else if (b === Qt.RightButton) {
        if (root.counting) root.timer.togglePause()
        else root.timer.startLast()
      }
      else root.openFlow()
    }

    onWheelMoved: function(delta) {
      if (root.counting && root.timer) root.timer.addSeconds(delta > 0 ? 60 : -60)
    }

    Item {
      id: iconSlot
      x: 0
      width: root.vertical ? parent.width : Style.bar.statusSlot
      height: parent.height

      OpticalGlyph {
        id: glyph
        anchors.centerIn: parent
        width: Style.bar.iconCanvas
        height: Style.bar.iconCanvas
        text: Model.glyph(root.ringing ? 0xF009E : 0xF051B)
        fontFamily: button.fontFamily
        fontSize: Style.font.caption
        color: root.iconColor

        SequentialAnimation on opacity {
          running: root.ringing
          loops: Animation.Infinite
          alwaysRunToEnd: true
          NumberAnimation { to: 0.25; duration: 450; easing.type: Easing.InOutQuad }
          NumberAnimation { to: 1; duration: 450; easing.type: Easing.InOutQuad }
        }
      }
    }

    Text {
      id: timeLabel
      visible: root.showTime
      anchors.left: iconSlot.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.timeText
      color: root.iconColor
      font.family: button.fontFamily
      font.pixelSize: Style.font.body
      font.features: { "tnum": 1 }
      renderType: Text.NativeRendering
    }
  }
}
