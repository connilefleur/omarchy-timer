import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "TimerModel.js" as Model

// Set-timer prompt, styled like Omarchy's reminder prompt:
//
//   1. minutes  type a duration ("25", "1h30", "90s"), Enter
//   2. alarm    pick what happens at the end, Enter (Space previews a sound)
//
// With a timer already counting it opens on a small manage list instead, and
// while an alarm rings or a suspend is pending it shows a "Timer done" card
// that Esc, Enter or any click dismisses (stopping the alarm or the suspend).
Item {
  id: root

  property var timer: null
  property var screen: null

  property bool opened: false
  property string step: "minutes"   // "minutes" | "alarm" | "manage" | "alert"
  property string filterText: ""
  property string error: ""
  property int seconds: 0
  property int cursor: 0

  signal dismissed()

  readonly property string fontFamily: Style.font.menuFamily
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int promptHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  readonly property int rowHeight: Math.max(Style.space(38), Style.font.body + Style.font.caption + Style.space(16))

  readonly property bool paused: timer && timer.status === "paused"
  readonly property var manageActions: [
    { id: "toggle", label: paused ? "Resume" : "Pause", hint: "", glyph: paused ? 0xF040A : 0xF03E4 },
    { id: "add1", label: "+1 min", hint: "", glyph: 0xF0415 },
    { id: "add5", label: "+5 min", hint: "", glyph: 0xF0415 },
    { id: "new", label: "New timer", hint: "Replaces this one", glyph: 0xF051B },
    { id: "cancel", label: "Cancel timer", hint: "", glyph: 0xF0156 }
  ]
  readonly property bool alerting: timer && (timer.status === "ringing" || timer.status === "suspending")
  readonly property var alarmOptions: Model.ALARMS
  readonly property var rows: step === "alarm" ? alarmOptions : (step === "manage" ? manageActions : [])

  readonly property string title: {
    if (!timer) return ""
    if (step === "alarm") return Model.formatDuration(seconds) + " · when it ends"
    if (step === "manage") return (paused ? "Paused · " : "") + Model.formatClock(timer.remainingMs) + " · " + timer.alarm.label
    if (step === "alert" && timer.status === "suspending") return "Suspending in " + Math.ceil(timer.remainingMs / 1000) + " s"
    if (step === "alert") return "Timer done · " + Model.formatDuration(timer.durationSec)
    return ""
  }

  function open() {
    if (!timer) return
    filterText = ""
    error = ""
    if (alerting) {
      step = "alert"
    } else if (timer.status === "running" || timer.status === "paused") {
      step = "manage"
      cursor = 0
    } else {
      step = "minutes"
    }
    opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function dismiss() {
    opened = false
    dismissed()
  }

  function stopAlarm() {
    timer.stopAlarm()
    dismiss()
  }

  // The alarm can also be stopped from the notification or the bar icon, and
  // a pending suspend ends by suspending.
  Connections {
    target: root.timer
    function onStatusChanged() {
      if (root.opened && root.step === "alert" && !root.alerting) root.dismiss()
    }
  }

  function submitMinutes() {
    var text = filterText.trim()
    var parsed = text === "" ? timer.lastDurationSec : Model.parseDuration(text)
    if (parsed <= 0) {
      error = "Type minutes, like 25, 1h30 or 90s"
      return
    }
    seconds = parsed
    error = ""
    step = "alarm"
    cursor = 0
    for (var i = 0; i < alarmOptions.length; i++)
      if (alarmOptions[i].id === timer.lastAlarmId) cursor = i
  }

  function activate(index) {
    if (index < 0 || index >= rows.length) return
    var row = rows[index]
    if (step === "alarm") {
      timer.start(seconds, row.id)
      dismiss()
      return
    }
    if (row.id === "toggle") timer.togglePause()
    else if (row.id === "add1") timer.addSeconds(60)
    else if (row.id === "add5") timer.addSeconds(300)
    else if (row.id === "cancel") { timer.cancel(); dismiss() }
    else if (row.id === "new") { step = "minutes"; filterText = ""; error = "" }
  }

  function moveCursor(delta) {
    if (rows.length === 0) return
    cursor = (cursor + delta + rows.length) % rows.length
  }

  function back() {
    if (step === "alarm") {
      step = "minutes"
      filterText = seconds > 0 ? String(Math.round(seconds / 60 * 100) / 100) : ""
    } else if (step === "minutes" && filterText !== "") {
      filterText = ""
      error = ""
    } else {
      dismiss()
    }
  }

  PanelWindow {
    id: panel
    screen: root.screen
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "io.github.connilefleur.timer"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.step === "alert" ? root.stopAlarm() : root.dismiss()
    }

    BorderSurface {
      id: card
      width: Math.min(Style.space(340), panel.width - Style.gapsOut * 2)
      height: Math.min(content.implicitHeight + contentTopInset + contentBottomInset, panel.height - Style.gapsOut * 2)
      radius: Style.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: if (root.step === "alert") root.stopAlarm() }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          var key = event.key
          event.accepted = true

          if (root.step === "alert") {
            if (key === Qt.Key_Escape || key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) root.stopAlarm()
            else event.accepted = false
            return
          }

          if (key === Qt.Key_Escape) { root.back(); return }

          if (root.step === "minutes") {
            if (Util.editsFilter(event, root.filterText)) {
              root.filterText = Util.editedFilter(event, root.filterText)
              root.error = ""
            } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
              root.submitMinutes()
            } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
              root.filterText += event.text
              root.error = ""
            } else {
              event.accepted = false
            }
            return
          }

          if (key === Qt.Key_Down || key === Qt.Key_Tab || event.text === "j") root.moveCursor(1)
          else if (key === Qt.Key_Up || key === Qt.Key_Backtab || event.text === "k") root.moveCursor(-1)
          else if (key === Qt.Key_Return || key === Qt.Key_Enter) root.activate(root.cursor)
          else if (key === Qt.Key_Backspace) root.back()
          else if (key === Qt.Key_Space && root.step === "alarm") root.timer.preview(root.rows[root.cursor].id)
          else if (event.text >= "1" && event.text <= "9" && Number(event.text) <= root.rows.length) root.activate(Number(event.text) - 1)
          else event.accepted = false
        }
      }

      Column {
        id: content
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.md

        // Prompt line: the typed minutes, or the title of a list step.
        Item {
          width: parent.width
          height: root.promptHeight

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.step === "minutes"
              ? (root.filterText || "Timer in minutes...")
              : root.title
            color: root.foreground
            opacity: root.step !== "minutes" || root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }
        }

        Text {
          visible: root.step === "alert"
          width: parent.width
          textFormat: Text.PlainText
          text: root.timer && root.timer.status === "suspending"
            ? Model.glyph(0xF04B2) + "  Playback stopped · Esc to cancel"
            : Model.glyph(0xF009E) + "  " + (root.timer ? root.timer.alarm.label : "") + " · Esc to stop"
          color: root.foreground
          opacity: 0.58
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          visible: root.step === "minutes" && root.error !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: root.error
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Repeater {
          model: root.rows

          Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool current: index === root.cursor
            readonly property bool hasSound: root.step === "alarm" && Model.soundPath(modelData) !== ""

            width: content.width
            height: root.rowHeight
            radius: Style.cornerRadius
            color: current ? Color.menu.selectedBackground : "transparent"

            Text {
              id: rowGlyph
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.rowPaddingX
              anchors.verticalCenter: parent.verticalCenter
              width: Style.font.iconLarge + Style.spacing.sm
              textFormat: Text.PlainText
              text: Model.glyph(row.modelData.glyph)
              color: row.current ? Color.menu.selectedText : root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.iconLarge
            }

            Column {
              anchors.left: rowGlyph.right
              anchors.leftMargin: Style.spacing.lg
              anchors.right: previewButton.visible ? previewButton.left : shortcut.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xxs

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: row.modelData.label
                color: row.current ? Color.menu.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Text {
                visible: text !== ""
                width: parent.width
                textFormat: Text.PlainText
                text: row.modelData.hint
                color: root.foreground
                opacity: 0.55
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onPositionChanged: root.cursor = row.index
              onClicked: root.activate(row.index)
            }

            PanelActionButton {
              id: previewButton
              visible: row.hasSound
              anchors.right: shortcut.left
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              iconText: Model.glyph(0xF040A)
              tooltipText: "Preview"
              foreground: root.foreground
              onClicked: root.timer.preview(row.modelData.id)
            }

            Text {
              id: shortcut
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.rowPaddingX
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: String(row.index + 1)
              color: root.foreground
              opacity: 0.4
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }
}
