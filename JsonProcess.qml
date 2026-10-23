import QtQuick
import Quickshell
import Quickshell.Io

// Runs a command and emits its parsed JSON on exit. SplitParser is used
// instead of StdioCollector because the latter is not exposed to third-party
// (scoped) shell plugins.
Item {
  id: root

  property var cmd: []
  property string buf: ""
  property bool available: true

  signal parsed(var obj)

  function run() { if (!proc.running) proc.running = true }
  function kill() { if (proc.running) proc.running = false }

  Process {
    id: proc

    command: root.cmd
    running: false

    stdout: SplitParser {
      onRead: function(data) { root.buf += data }
    }

    onExited: function(exitCode) {
      var text = root.buf
      root.buf = ""

      if (exitCode !== 0) {
        root.parsed(null)
        return
      }

      try {
        root.parsed(JSON.parse(text))
      } catch (e) {
        root.parsed(null)
      }
    }
  }
}
