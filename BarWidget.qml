import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar button for Focus: a timer glyph that turns into a live countdown while a
// session runs. Click opens the Focus panel; the idle tooltip shows today's
// study time and the current streak.
BarWidget {
  id: root
  moduleName: "luckydubey.focus"

  readonly property string focusBin: "omarchy-focus"

  property bool focusActive: false
  property string countdown: ""
  property string tip: idleTip
  property string idleTip: "Focus — click to start"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function openPanel() {
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", root.moduleName, "{}"])
  }

  function pad(n) { return (n < 10 ? "0" : "") + n }

  function update(raw) {
    var data = Util.parseModuleJson(raw)

    focusActive = data.active === true

    if (!focusActive) {
      countdown = ""
      tip = idleTip
      return
    }

    var r = Math.max(0, Number(data.remaining_seconds || 0))
    countdown = pad(Math.floor(r / 60)) + ":" + pad(r % 60)

    var ends = ""
    if (data.ends_at) {
      var d = new Date(Number(data.ends_at) * 1000)
      ends = pad(d.getHours()) + ":" + pad(d.getMinutes())
    }

    tip = String(data.subject || "Focus") + (ends ? " — ends " + ends : "")
  }

  function fmt(seconds) {
    var s = Math.round(Number(seconds) || 0)
    var h = Math.floor(s / 3600)
    var m = Math.round((s % 3600) / 60)
    if (h > 0) return m > 0 ? h + "h " + m + "m" : h + "h"
    return m + "m"
  }

  function updateSummary(raw) {
    var data = Util.parseModuleJson(raw)
    var s = data && data.summary ? data.summary : null
    if (!s) return
    var parts = ["Focus", "today " + fmt(s.today_seconds)]
    if (s.current_streak > 0) parts.push(s.current_streak + "-day streak")
    idleTip = parts.join("  ·  ") + "\nClick to start"
    if (!focusActive) tip = idleTip
  }

  Component.onCompleted: { refresh(); summaryProc.running = true }

  // Status every second while a session runs, every 5s otherwise.
  Timer {
    interval: root.focusActive ? 1000 : 5000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: if (!summaryProc.running) summaryProc.running = true
  }

  Process {
    id: statusProc
    command: [root.focusBin, "status", "--json"]
    property string buf: ""
    stdout: SplitParser {
      onRead: function(data) { statusProc.buf += data }
    }
    onExited: function(exitCode) {
      if (exitCode === 0) root.update(statusProc.buf)
      else {
        root.focusActive = false
        root.countdown = ""
        root.tip = "Focus — omarchy-focus not found"
      }
      statusProc.buf = ""
    }
  }

  Process {
    id: summaryProc
    command: [root.focusBin, "chart", "--period", "week", "--json"]
    property string buf: ""
    stdout: SplitParser {
      onRead: function(data) { summaryProc.buf += data }
    }
    onExited: function(exitCode) {
      if (exitCode === 0) root.updateSummary(summaryProc.buf)
      summaryProc.buf = ""
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.focusActive && root.countdown !== "" ? "󰔛 " + root.countdown : "󰔛"
    tooltipText: root.tip
    useActiveColor: false
    // Give the live countdown room instead of the icon slot.
    fixedWidth: root.vertical ? -1 : (root.focusActive ? Style.space(58) : Style.bar.statusSlot)
    opticalSize: root.focusActive ? Style.space(56) : Style.bar.iconCanvas
    fontSize: root.focusActive ? Style.font.caption : Style.bar.iconFont
    onPressed: root.openPanel()
  }
}
