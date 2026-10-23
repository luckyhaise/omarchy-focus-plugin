import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  readonly property string focusBin: "omarchy-focus"

  property bool opened: false
  property string requestedView: ""
  property string view: "timer" // timer | running | stats | log | delete | subjects

  // data
  property var subjects: []
  property var paletteColors: []
  property var sounds: []
  property var status: ({ active: false })
  property var chart: null
  property var days: []
  property int defaultMinutes: 30
  property string defaultSound: "loud_bell"

  // timer
  property int selected: 0
  property string minutesInput: ""
  property int soundIndex: 0

  // log
  property int logSelected: 0
  property string logMinutes: ""
  property int logDateOffset: 0

  // delete
  property int deleteDayIndex: -1
  property int deleteSubjectIndex: 0
  property string deleteStage: "day"

  // subjects
  property string newSubject: ""
  property string colorTarget: ""
  property string chartPeriod: "month"

  property string fontFamily: Style.font.menuFamily
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color accent: Color.accent
  property color danger: Color.urgent
  property color dim: Qt.darker(foreground, 1.65)
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int cardWidth: Math.min(Style.space(600), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(500), panel.height - Style.gapsOut * 2)

  // ------------------------------------------------------------- lifecycle
  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    root.opened = true
    root.requestedView = payload.view || ""
    if (payload.view) root.view = payload.view

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })

    root.refreshConfig()
    root.refreshStatus()
    root.refreshSubjects()
    root.refreshSounds()
    root.refreshPalette()
    root.refreshChart()
    root.refreshDays()
  }

  function close() { root.opened = false }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "luckydubey.focus")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function setView(v) {
    root.view = v
    if (v === "stats") root.refreshChart()
    if (v === "delete") root.refreshDays()
    if (v === "log") root.refreshSubjects()
    if (v === "subjects") { root.refreshSubjects(); root.refreshPalette() }
  }

  // --------------------------------------------------------------- helpers
  function pad(n) { return (n < 10 ? "0" : "") + n }

  function fmt(seconds) {
    var s = Math.round(Number(seconds) || 0)
    if (s <= 0) return "0m"
    var h = Math.floor(s / 3600)
    var m = Math.round((s % 3600) / 60)
    if (h > 0) return m > 0 ? h + "h " + m + "m" : h + "h"
    if (m > 0) return m + "m"
    return s + "s"
  }

  function activeSubjects() {
    var out = []
    for (var i = 0; i < root.subjects.length; i++)
      if (!root.subjects[i].deleted) out.push(root.subjects[i])
    return out
  }

  function currentTag() {
    var list = root.activeSubjects()
    if (list.length === 0) return ""
    return list[Math.max(0, Math.min(root.selected, list.length - 1))].name
  }

  function logTag() {
    var list = root.activeSubjects()
    if (list.length === 0) return ""
    return list[Math.max(0, Math.min(root.logSelected, list.length - 1))].name
  }

  function moveSelection(delta, count, current) {
    if (count === 0) return 0
    return (current + delta + count) % count
  }

  function cycleSound(delta) {
    if (root.sounds.length === 0) return
    root.soundIndex = (root.soundIndex + delta + root.sounds.length) % root.sounds.length
  }

  function secondsToClock(secs) {
    var s = Math.max(0, Math.floor(secs))
    return pad(Math.floor(s / 60)) + ":" + pad(s % 60)
  }

  function studyDayDate(offset) {
    var d = new Date()
    d.setHours(d.getHours() - 4)
    d.setDate(d.getDate() + offset)
    return d
  }

  function studyDayString(offset) { return Qt.formatDate(root.studyDayDate(offset), "yyyy-MM-dd") }
  function studyDayLabel(offset) { return Qt.formatDate(root.studyDayDate(offset), "ddd, d MMM yyyy") }

  function activeTotals() {
    var out = []
    if (!root.chart || !root.chart.totals) return out
    for (var i = 0; i < root.chart.totals.length; i++)
      if (!root.chart.totals[i].deleted) out.push(root.chart.totals[i])
    return out
  }

  function deletedTotals() {
    var out = []
    if (!root.chart || !root.chart.totals) return out
    for (var i = 0; i < root.chart.totals.length; i++)
      if (root.chart.totals[i].deleted) out.push(root.chart.totals[i])
    return out
  }

  function summary() {
    return root.chart && root.chart.summary ? root.chart.summary : ({})
  }

  function plural(n, word) { return n + " " + word + (n === 1 ? "" : "s") }

  // "2026-10-05" -> "5 Oct"
  function shortDate(key) {
    if (!key) return ""
    var p = String(key).split("-")
    if (p.length < 3) return key
    return Qt.formatDate(new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2])), "d MMM")
  }

  function rangeCaption() {
    if (!root.chart) return ""
    var names = { week: "Last 7 days", month: "Last 30 days", year: "Last 12 months", all: "All time" }
    var s = root.summary()
    var text = names[root.chart.period] || ""
    if (s.range_start && s.range_start !== root.chart.from)
      text += "  ·  since " + root.shortDate(s.range_start)
    return text + "  ·  today " + root.fmt(s.today_seconds)
  }

  function deltaNote() {
    var s = root.summary()
    if (!root.chart) return ""
    if (!s.has_previous) return s.tracking_since ? "since " + root.shortDate(s.tracking_since) : "nothing yet"
    var prevName = { week: "last week", month: "prev 30d", year: "last year" }[root.chart.period]
    var prev = s.previous_total_seconds
    if (prev <= 0) return "none " + prevName
    var pct = Math.round((root.chart.total_seconds - prev) / prev * 100)
    return (pct >= 0 ? "▲ " : "▼ ") + Math.abs(pct) + "% vs " + prevName
  }

  function deltaColor() {
    var s = root.summary()
    if (!root.chart || !s.has_previous || s.previous_total_seconds <= 0) return root.dim
    return root.chart.total_seconds >= s.previous_total_seconds ? root.accent : root.danger
  }

  function currentDay() {
    if (root.deleteDayIndex < 0 || root.deleteDayIndex >= root.days.length) return null
    return root.days[root.deleteDayIndex]
  }

  function run(args, after) {
    root.afterActionFn = after || function() {}
    Quickshell.execDetached(args)
    afterAction.restart()
  }

  property var afterActionFn: function() {}

  // --------------------------------------------------------------- actions
  function start() {
    var tag = root.currentTag()
    if (!tag) { root.setView("subjects"); return }

    var mins = root.minutesInput ? parseInt(root.minutesInput) : root.defaultMinutes
    if (!mins || mins < 1) mins = root.defaultMinutes

    var sound = root.sounds.length > 0 ? root.sounds[root.soundIndex] : root.defaultSound
    var args = [root.focusBin, "--work", String(mins), "--tag", tag]
    if (sound) args = args.concat(["--work-sound", sound])

    root.dismiss()
    Quickshell.execDetached(args)
  }

  function stopSession() {
    root.run([root.focusBin, "stop"], function() { root.refreshStatus(); root.setView("timer") })
  }

  function extendSession() {
    root.run([root.focusBin, "extend", "5"], function() { root.refreshStatus() })
  }

  function addLog() {
    var tag = root.logTag()
    var mins = parseInt(root.logMinutes)
    if (!tag || !mins || mins < 1) return

    root.logMinutes = ""
    root.run(
      [root.focusBin, "log", "--date", root.studyDayString(root.logDateOffset), "--", tag, String(mins)],
      function() { root.refreshChart(); root.refreshDays(); root.setView("stats") }
    )
  }

  function addSubject() {
    var name = root.newSubject.trim()
    if (!name) return
    root.newSubject = ""
    root.run([root.focusBin, "subjects", "add", name], function() { root.refreshSubjects() })
  }

  function deleteSubject(name) {
    root.colorTarget = ""
    root.run([root.focusBin, "subjects", "delete", name], function() {
      root.refreshSubjects()
      root.refreshChart()
    })
  }

  function setColor(name, color) {
    root.colorTarget = ""
    root.run([root.focusBin, "subjects", "color", name, color], function() {
      root.refreshSubjects()
      root.refreshChart()
    })
  }

  function pickDay(i) {
    root.deleteDayIndex = i
    root.deleteSubjectIndex = 0
    root.deleteStage = "subject"
  }

  function deleteSelectedSubject() {
    var day = root.currentDay()
    if (!day || !day.subjects || day.subjects.length === 0) return
    var tag = day.subjects[root.deleteSubjectIndex].tag

    root.run([root.focusBin, "delete", "--date", day.day, "--subject", tag], function() {
      root.refreshDays()
      root.refreshChart()
      root.deleteStage = "day"
      root.deleteDayIndex = -1
    })
  }

  function deleteWholeDay() {
    var day = root.currentDay()
    if (!day) return

    root.run([root.focusBin, "delete", "--date", day.day], function() {
      root.refreshDays()
      root.refreshChart()
      root.deleteStage = "day"
      root.deleteDayIndex = -1
    })
  }

  // ------------------------------------------------------------- processes
  function refreshStatus() { statusProc.run() }
  function refreshSubjects() { subjectsProc.run() }
  function refreshSounds() { soundsProc.run() }
  function refreshChart() { chartProc.run() }
  function refreshPalette() { paletteProc.run() }
  function refreshConfig() { configProc.run() }
  function refreshDays() { daysProc.run() }

  JsonProcess {
    id: statusProc
    cmd: [root.focusBin, "status", "--json"]
    onParsed: function(obj) {
      root.status = obj || ({ active: false })
      if (root.requestedView !== "") { root.view = root.requestedView; root.requestedView = ""; return }
      if (root.status.active && root.view === "timer") root.view = "running"
      if (!root.status.active && root.view === "running") root.view = "timer"
    }
  }

  JsonProcess {
    id: subjectsProc
    cmd: [root.focusBin, "subjects", "list", "--all", "--json"]
    onParsed: function(obj) { root.subjects = obj || [] }
  }

  JsonProcess {
    id: paletteProc
    cmd: [root.focusBin, "subjects", "palette", "--json"]
    onParsed: function(obj) { root.paletteColors = obj || [] }
  }

  JsonProcess {
    id: soundsProc
    cmd: [root.focusBin, "sounds", "--json"]
    onParsed: function(obj) {
      root.sounds = obj || []
      for (var i = 0; i < root.sounds.length; i++)
        if (root.sounds[i] === root.defaultSound) root.soundIndex = i
    }
  }

  JsonProcess {
    id: configProc
    cmd: [root.focusBin, "config", "--json"]
    onParsed: function(obj) {
      if (!obj) return
      if (obj.work_minutes > 0) root.defaultMinutes = obj.work_minutes
      if (obj.work_sound) root.defaultSound = obj.work_sound
    }
  }

  JsonProcess {
    id: chartProc
    cmd: [root.focusBin, "chart", "--period", root.chartPeriod, "--json"]
    onParsed: function(obj) { root.chart = obj }
  }

  JsonProcess {
    id: daysProc
    cmd: [root.focusBin, "days", "--json"]
    onParsed: function(obj) { root.days = obj || [] }
  }

  Timer { id: afterAction; interval: 350; onTriggered: root.afterActionFn() }

  Timer {
    interval: 1000
    running: root.opened && root.view === "running"
    repeat: true
    onTriggered: root.refreshStatus()
  }

  Component.onCompleted: {
    root.refreshPalette()
    root.refreshConfig()
  }

  // -------------------------------------------------------------------- UI
  PanelWindow {
    id: panel

    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "luckydubey-focus"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: root.scrim }

    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

    BorderSurface {
      id: card

      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) { root.handleKey(event) }
      }

      Item {
        id: content

        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        // -------------------------------------------------------- header
        Item {
          id: header

          width: parent.width
          height: Style.space(30)

          Text {
            id: titleText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "󰔛  Focus"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(5)

            Repeater {
              model: [["timer", "Timer"], ["stats", "Stats"], ["log", "Log"], ["delete", "Delete"], ["subjects", "Subjects"]]

              FocusPill {
                required property var modelData
                text: modelData[1]
                chip: true
                selected: root.view === modelData[0] || (modelData[0] === "timer" && root.view === "running")
                accent: root.accent
                fg: root.foreground
                dim: root.dim
                fontFamily: root.fontFamily
                onClicked: root.setView(modelData[0])
              }
            }
          }
        }

        Rectangle {
          id: divider
          anchors.top: header.bottom
          anchors.topMargin: Style.space(8)
          anchors.left: parent.left
          anchors.right: parent.right
          height: 1
          color: root.border
          opacity: 0.5
        }

        // ------------------------------------------------------- timer
        Item {
          id: timerView
          visible: root.view === "timer"
          anchors.top: divider.bottom
          anchors.topMargin: Style.space(12)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom

          Row {
            id: timerControls
            width: parent.width
            spacing: Style.space(10)

            // subject list
            Column {
              width: parent.width * 0.56
              spacing: Style.space(6)

              Text {
                text: "Subject"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              ListView {
                id: timerList
                width: parent.width
                height: Math.min(timerView.height - timerHint.height - Style.space(40), Math.max(Style.space(34), root.activeSubjects().length * Style.space(34) + 2))
                clip: true
                model: root.activeSubjects()
                spacing: Style.space(2)

                delegate: SubjectRow {
                  required property var modelData
                  required property int index
                  width: timerList.width
                  tag: modelData.name
                  swatch: modelData.color
                  selected: index === root.selected
                  fontFamily: root.fontFamily
                  fg: root.foreground
                  dim: root.dim
                  accent: root.accent
                  onClicked: root.selected = index
                }

                Text {
                  anchors.centerIn: parent
                  visible: root.activeSubjects().length === 0
                  text: "No subjects yet"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }
            }

            // controls
            Column {
              width: parent.width * 0.44 - Style.space(10)
              spacing: Style.space(12)

              Column {
                spacing: Style.space(6)
                width: parent.width

                Text {
                  text: "Minutes  ·  default " + root.defaultMinutes
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Rectangle {
                  width: parent.width
                  height: Style.space(38)
                  radius: Style.cornerRadius / 2
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
                  border.width: 1
                  border.color: root.minutesInput ? root.accent : root.border

                  Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.minutesInput || root.defaultMinutes
                    color: root.minutesInput ? root.foreground : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                    font.bold: true
                  }

                  Text {
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "min"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              Column {
                spacing: Style.space(6)
                width: parent.width

                Text {
                  text: "End chime  ·  ← →"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                FocusPill {
                  width: parent.width
                  text: root.sounds.length > 0 ? root.sounds[root.soundIndex] : "—"
                  fontFamily: root.fontFamily
                  fg: root.foreground
                  dim: root.foreground
                  accent: root.accent
                  onClicked: root.cycleSound(1)
                }
              }

              FocusPill {
                width: parent.width
                text: "Start Focus"
                primary: true
                enabled: root.activeSubjects().length > 0
                accent: root.accent
                fg: root.foreground
                dim: root.dim
                fontFamily: root.fontFamily
                onClicked: root.start()
              }
            }
          }

          Text {
            id: timerHint
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            text: "↑↓ subject   ·   type minutes   ·   ←→ chime   ·   Enter start   ·   Esc close"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        // ----------------------------------------------------- running
        Item {
          id: runningView
          visible: root.view === "running"
          anchors.top: divider.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom

          Column {
            anchors.centerIn: parent
            spacing: Style.space(6)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.status.subject || "Focus"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.secondsToClock(root.status.remaining_seconds)
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.space(72)
              font.bold: true
              font.letterSpacing: 1
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.status.ends_at ? ("ends " + Qt.formatDateTime(new Date(root.status.ends_at * 1000), "HH:mm")) : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(12)

              FocusPill {
                text: "+5 min"
                accent: root.accent
                fg: root.foreground
                dim: root.dim
                fontFamily: root.fontFamily
                onClicked: root.extendSession()
              }

              FocusPill {
                text: "Stop"
                danger: true
                dangerColor: root.danger
                fg: root.foreground
                dim: root.dim
                fontFamily: root.fontFamily
                onClicked: root.stopSession()
              }
            }
          }
        }

        // ------------------------------------------------------- stats
        Item {
          id: statsView
          visible: root.view === "stats"
          anchors.top: divider.bottom
          anchors.topMargin: Style.space(12)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom

          readonly property var sum: root.summary()

          Row {
            id: periodRow
            spacing: Style.space(5)

            Repeater {
              model: [["week", "Week"], ["month", "Month"], ["year", "Year"], ["all", "All"]]

              FocusPill {
                required property var modelData
                text: modelData[1]
                chip: true
                selected: root.chartPeriod === modelData[0]
                accent: root.accent
                fg: root.foreground
                dim: root.dim
                fontFamily: root.fontFamily
                onClicked: { root.chartPeriod = modelData[0]; root.refreshChart() }
              }
            }
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: periodRow.verticalCenter
            width: parent.width - periodRow.width - Style.space(12)
            horizontalAlignment: Text.AlignRight
            text: root.rangeCaption()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideLeft
          }

          Row {
            id: tiles
            anchors.top: periodRow.bottom
            anchors.topMargin: Style.space(10)
            width: parent.width
            spacing: Style.space(6)

            readonly property real tileWidth: (width - spacing * 3) / 4

            StatTile {
              width: tiles.tileWidth
              label: "Total"
              value: root.chart ? root.fmt(root.chart.total_seconds) : "—"
              note: root.deltaNote()
              noteColor: root.deltaColor()
              fontFamily: root.fontFamily
              fg: root.foreground
              dim: root.dim
              accent: root.accent
            }

            StatTile {
              width: tiles.tileWidth
              label: "Daily average"
              value: root.fmt(statsView.sum.daily_average_seconds)
              note: statsView.sum.days_in_range
                ? "total ÷ " + root.plural(statsView.sum.days_in_range, "day")
                : "no study yet"
              highlight: true
              fontFamily: root.fontFamily
              fg: root.foreground
              dim: root.dim
              accent: root.accent
            }

            StatTile {
              width: tiles.tileWidth
              label: "Days studied"
              value: (statsView.sum.study_days || 0) + " / " + (statsView.sum.days_in_range || 0)
              note: statsView.sum.study_days
                ? root.fmt(statsView.sum.study_day_average_seconds) + " each"
                : "—"
              fontFamily: root.fontFamily
              fg: root.foreground
              dim: root.dim
              accent: root.accent
            }

            StatTile {
              width: tiles.tileWidth
              label: "Streak"
              value: "󰈸 " + root.plural(statsView.sum.current_streak || 0, "day")
              note: "best " + root.plural(statsView.sum.longest_streak || 0, "day")
              fontFamily: root.fontFamily
              fg: root.foreground
              dim: root.dim
              accent: root.accent
            }
          }

          FocusChart {
            id: chart
            anchors.top: tiles.bottom
            anchors.topMargin: Style.space(4)
            anchors.left: parent.left
            anchors.right: parent.right
            height: Style.space(170)
            chartData: root.chart
            averageSeconds: statsView.sum.bar_average_seconds || 0
            averageUnit: statsView.sum.bar_unit || "day"
            fontFamily: root.fontFamily
            foreground: root.foreground
            dim: root.dim
            axis: root.border
            accent: root.accent
          }

          Text {
            id: legendTitle
            anchors.top: chart.bottom
            anchors.topMargin: Style.space(14)
            text: "SUBJECTS"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 0.8
          }

          Text {
            anchors.right: parent.right
            anchors.baseline: legendTitle.baseline
            visible: statsView.sum.best_day_seconds > 0
            text: "best day  " + root.shortDate(statsView.sum.best_day) + " · " + root.fmt(statsView.sum.best_day_seconds)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          ListView {
            id: legendList
            anchors.top: legendTitle.bottom
            anchors.topMargin: Style.space(5)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            clip: true
            model: root.activeTotals().concat(root.deletedTotals())
            spacing: Style.space(3)

            delegate: Item {
              id: subjRow

              required property var modelData

              readonly property real share: root.chart && root.chart.total_seconds > 0
                ? modelData.seconds / root.chart.total_seconds : 0

              width: legendList.width
              height: Style.space(22)
              opacity: modelData.deleted ? 0.5 : 1

              Rectangle {
                id: swatch
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(9)
                height: Style.space(9)
                radius: 2
                color: subjRow.modelData.color
              }

              Text {
                id: subjName
                anchors.left: swatch.right
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * 0.3
                text: subjRow.modelData.tag + (subjRow.modelData.deleted ? "  · deleted" : "")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              // share-of-total bar
              Rectangle {
                id: track
                anchors.left: subjName.right
                anchors.leftMargin: Style.space(8)
                anchors.right: subjTime.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: height / 2
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)

                Rectangle {
                  height: parent.height
                  radius: parent.radius
                  width: Math.max(parent.height, parent.width * subjRow.share)
                  color: subjRow.modelData.color

                  Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                }
              }

              Text {
                id: subjTime
                anchors.right: subjPct.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(56)
                horizontalAlignment: Text.AlignRight
                text: root.fmt(subjRow.modelData.seconds)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                id: subjPct
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(34)
                horizontalAlignment: Text.AlignRight
                text: Math.round(subjRow.share * 100) + "%"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              anchors.centerIn: parent
              visible: legendList.count === 0
              text: "Nothing logged in this period"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }
        }

        // --------------------------------------------------------- log
        Item {
          id: logView
          visible: root.view === "log"
          anchors.top: divider.bottom
          anchors.topMargin: Style.space(12)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom

          Row {
            id: logControls
            width: parent.width
            spacing: Style.space(10)

            Column {
              width: parent.width * 0.56
              spacing: Style.space(6)

              Text {
                text: "Subject"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              ListView {
                id: logList
                width: parent.width
                height: Math.min(logView.height - logHint.height - Style.space(40), Math.max(Style.space(34), root.activeSubjects().length * Style.space(34) + 2))
                clip: true
                model: root.activeSubjects()
                spacing: Style.space(2)

                delegate: SubjectRow {
                  required property var modelData
                  required property int index
                  width: logList.width
                  tag: modelData.name
                  swatch: modelData.color
                  selected: index === root.logSelected
                  fontFamily: root.fontFamily
                  fg: root.foreground
                  dim: root.dim
                  accent: root.accent
                  onClicked: root.logSelected = index
                }
              }
            }

            Column {
              width: parent.width * 0.44 - Style.space(10)
              spacing: Style.space(12)

              Column {
                spacing: Style.space(6)
                width: parent.width

                Text {
                  text: "How long did you study?"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Rectangle {
                  width: parent.width
                  height: Style.space(38)
                  radius: Style.cornerRadius / 2
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
                  border.width: 1
                  border.color: root.logMinutes ? root.accent : root.border

                  Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.logMinutes || "45"
                    color: root.logMinutes ? root.foreground : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                    font.bold: true
                  }

                  Text {
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "min"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              Column {
                spacing: Style.space(6)
                width: parent.width

                Text {
                  text: "Day  ·  ← →"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                FocusPill {
                  width: parent.width
                  text: root.studyDayLabel(root.logDateOffset)
                  fontFamily: root.fontFamily
                  fg: root.foreground
                  dim: root.foreground
                  accent: root.accent
                  onClicked: root.logDateOffset = 0
                }
              }

              FocusPill {
                width: parent.width
                text: "Add Study Time"
                primary: true
                enabled: root.activeSubjects().length > 0 && parseInt(root.logMinutes) > 0
                accent: root.accent
                fg: root.foreground
                dim: root.dim
                fontFamily: root.fontFamily
                onClicked: root.addLog()
              }
            }
          }

          Text {
            id: logHint
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            text: "Type minutes   ·   ↑↓ subject   ·   ←→ day   ·   Enter add   ·   for offline study"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        // ------------------------------------------------------ delete
        Item {
          id: deleteView
          visible: root.view === "delete"
          anchors.top: divider.bottom
          anchors.topMargin: Style.space(12)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom

          // stage: pick a day
          Item {
            anchors.fill: parent
            visible: root.deleteStage === "day"

            Text {
              id: delDaysTitle
              text: "Pick a day to edit"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            ListView {
              id: dayList
              anchors.top: delDaysTitle.bottom
              anchors.topMargin: Style.space(6)
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              clip: true
              model: root.days
              spacing: Style.space(2)

              delegate: Rectangle {
                required property var modelData
                required property int index

                width: dayList.width
                height: Style.space(34)
                radius: Style.cornerRadius / 2
                color: dayHover.hovered ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06) : "transparent"

                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.day
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                Text {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.fmt(modelData.total_seconds) + "  ›"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                HoverHandler { id: dayHover }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.pickDay(index) }
              }

              Text {
                anchors.centerIn: parent
                visible: root.days.length === 0
                text: "No study sessions yet"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }

          // stage: pick a subject within the day
          Item {
            anchors.fill: parent
            visible: root.deleteStage === "subject"

            Row {
              id: delHeader
              spacing: Style.space(10)

              FocusPill {
                text: "‹ Back"
                chip: true
                accent: root.accent
                fg: root.foreground
                dim: root.dim
                fontFamily: root.fontFamily
                onClicked: { root.deleteStage = "day"; root.deleteDayIndex = -1 }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.currentDay() ? root.currentDay().day : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
            }

            Text {
              id: delSubjTitle
              anchors.top: delHeader.bottom
              anchors.topMargin: Style.space(10)
              text: "Pick a subject to delete (or delete the whole day)"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            ListView {
              id: delSubjList
              anchors.top: delSubjTitle.bottom
              anchors.topMargin: Style.space(6)
              anchors.left: parent.left
              anchors.right: parent.right
              height: Math.min(Style.space(190), Math.max(Style.space(34), (root.currentDay() ? root.currentDay().subjects.length : 0) * Style.space(34) + 2))
              clip: true
              model: root.currentDay() ? root.currentDay().subjects : []
              spacing: Style.space(2)

              delegate: SubjectRow {
                required property var modelData
                required property int index
                width: delSubjList.width
                tag: modelData.tag
                swatch: modelData.color
                deleted: modelData.deleted
                rightText: root.fmt(modelData.seconds)
                selected: index === root.deleteSubjectIndex
                fontFamily: root.fontFamily
                fg: root.foreground
                dim: root.dim
                accent: root.accent
                onClicked: root.deleteSubjectIndex = index
              }
            }

            Row {
              anchors.top: delSubjList.bottom
              anchors.topMargin: Style.space(14)
              spacing: Style.space(10)

              FocusPill {
                text: "Delete subject"
                danger: true
                dangerColor: root.danger
                fg: root.foreground
                dim: root.dim
                fontFamily: root.fontFamily
                enabled: (root.currentDay() ? root.currentDay().subjects.length : 0) > 0
                onClicked: root.deleteSelectedSubject()
              }

              FocusPill {
                text: "Delete whole day"
                accent: root.accent
                fg: root.foreground
                dim: root.dim
                fontFamily: root.fontFamily
                onClicked: root.deleteWholeDay()
              }
            }
          }
        }

        // ---------------------------------------------------- subjects
        Item {
          id: subjectsView
          visible: root.view === "subjects"
          anchors.top: divider.bottom
          anchors.topMargin: Style.space(12)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom

          Rectangle {
            id: addBox
            width: parent.width
            height: Style.space(36)
            radius: Style.cornerRadius / 2
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
            border.width: 1
            border.color: root.newSubject ? root.accent : root.border

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              text: root.newSubject || "Type a new subject name, press Enter"
              color: root.newSubject ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          Text {
            id: subjCount
            anchors.top: addBox.bottom
            anchors.topMargin: Style.space(8)
            text: root.activeSubjects().length + " / 20 subjects"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          ListView {
            id: subjectManageList
            anchors.top: subjCount.bottom
            anchors.topMargin: Style.space(6)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: paletteBox.top
            anchors.bottomMargin: Style.space(8)
            clip: true
            model: root.activeSubjects()
            spacing: Style.space(2)

            delegate: SubjectRow {
              required property var modelData
              required property int index
              width: subjectManageList.width
              tag: modelData.name
              swatch: modelData.color
              actionText: "󰆴"
              fontFamily: root.fontFamily
              fg: root.foreground
              dim: root.dim
              accent: root.accent
              onClicked: root.colorTarget = (root.colorTarget === modelData.name ? "" : modelData.name)
              onAction: root.deleteSubject(modelData.name)
            }
          }

          Rectangle {
            id: paletteBox
            visible: root.colorTarget !== ""
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: visible ? Style.space(36) : 0
            radius: Style.cornerRadius / 2
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: "Color"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              Repeater {
                model: root.paletteColors

                Rectangle {
                  required property var modelData

                  width: Style.space(16)
                  height: Style.space(16)
                  radius: 4
                  color: modelData
                  border.width: colorHover.hovered ? 2 : 1
                  border.color: colorHover.hovered ? root.foreground : Qt.rgba(0, 0, 0, 0.25)
                  scale: colorHover.hovered ? 1.15 : 1

                  Behavior on scale { NumberAnimation { duration: 110 } }

                  HoverHandler { id: colorHover }
                  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setColor(root.colorTarget, modelData) }
                }
              }
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------- key handling
  function handleKey(event) {
    if (event.key === Qt.Key_Escape) {
      if (root.view === "subjects" && root.newSubject !== "") root.newSubject = ""
      else if (root.view === "timer" && root.minutesInput !== "") root.minutesInput = ""
      else if (root.view === "log" && root.logMinutes !== "") root.logMinutes = ""
      else if (root.view === "delete" && root.deleteStage === "subject") { root.deleteStage = "day"; root.deleteDayIndex = -1 }
      else if (root.view !== "timer" && root.view !== "running") root.setView("timer")
      else root.dismiss()
      event.accepted = true
      return
    }

    if (root.view === "timer") {
      var n = root.activeSubjects().length
      if (event.key === Qt.Key_Up) { root.selected = root.moveSelection(-1, n, root.selected); event.accepted = true }
      else if (event.key === Qt.Key_Down) { root.selected = root.moveSelection(1, n, root.selected); event.accepted = true }
      else if (event.key === Qt.Key_Left) { root.cycleSound(-1); event.accepted = true }
      else if (event.key === Qt.Key_Right) { root.cycleSound(1); event.accepted = true }
      else if (event.key === Qt.Key_Backspace) { root.minutesInput = root.minutesInput.slice(0, -1); event.accepted = true }
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.start(); event.accepted = true }
      else if (event.text && event.text.length === 1 && event.text >= "0" && event.text <= "9" && root.minutesInput.length < 4) {
        root.minutesInput += event.text
        event.accepted = true
      }
      return
    }

    if (root.view === "log") {
      var ln = root.activeSubjects().length
      if (event.key === Qt.Key_Up) { root.logSelected = root.moveSelection(-1, ln, root.logSelected); event.accepted = true }
      else if (event.key === Qt.Key_Down) { root.logSelected = root.moveSelection(1, ln, root.logSelected); event.accepted = true }
      else if (event.key === Qt.Key_Left) { root.logDateOffset -= 1; event.accepted = true }
      else if (event.key === Qt.Key_Right) { root.logDateOffset += 1; if (root.logDateOffset > 0) root.logDateOffset = 0; event.accepted = true }
      else if (event.key === Qt.Key_Backspace) { root.logMinutes = root.logMinutes.slice(0, -1); event.accepted = true }
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.addLog(); event.accepted = true }
      else if (event.text && event.text.length === 1 && event.text >= "0" && event.text <= "9" && root.logMinutes.length < 4) {
        root.logMinutes += event.text
        event.accepted = true
      }
      return
    }

    if (root.view === "stats") {
      if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
        var periods = ["week", "month", "year", "all"]
        var i = periods.indexOf(root.chartPeriod)
        i = (i + (event.key === Qt.Key_Right ? 1 : -1) + periods.length) % periods.length
        root.chartPeriod = periods[i]
        root.refreshChart()
        event.accepted = true
      } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
        var n = root.chart && root.chart.bars ? root.chart.bars.length : 0
        if (n > 0) {
          var cur = chart.hoverIndex
          chart.hoverIndex = (event.key === Qt.Key_Up)
            ? (cur <= 0 ? n - 1 : cur - 1)
            : (cur + 1) % n
        }
        event.accepted = true
      }
      return
    }

    if (root.view === "delete") {
      if (root.deleteStage === "day") {
        if (event.key === Qt.Key_Up && root.days.length > 0) { root.deleteDayIndex = Math.max(0, root.deleteDayIndex - 1); event.accepted = true }
        else if (event.key === Qt.Key_Down && root.days.length > 0) { root.deleteDayIndex = Math.min(root.days.length - 1, root.deleteDayIndex + 1); event.accepted = true }
        else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.deleteDayIndex >= 0) { root.pickDay(root.deleteDayIndex); event.accepted = true }
      } else {
        var day = root.currentDay()
        var sn = day ? day.subjects.length : 0
        if (event.key === Qt.Key_Up) { root.deleteSubjectIndex = root.moveSelection(-1, sn, root.deleteSubjectIndex); event.accepted = true }
        else if (event.key === Qt.Key_Down) { root.deleteSubjectIndex = root.moveSelection(1, sn, root.deleteSubjectIndex); event.accepted = true }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.deleteSelectedSubject(); event.accepted = true }
        else if (event.key === Qt.Key_Backspace) { root.deleteStage = "day"; root.deleteDayIndex = -1; event.accepted = true }
      }
      return
    }

    if (root.view === "subjects") {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.addSubject(); event.accepted = true }
      else if (event.key === Qt.Key_Backspace) { root.newSubject = root.newSubject.slice(0, -1); event.accepted = true }
      else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && root.newSubject.length < 24) {
        root.newSubject += event.text
        event.accepted = true
      }
      return
    }

    if (root.view === "running") {
      if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) { root.extendSession(); event.accepted = true }
    }
  }
}
