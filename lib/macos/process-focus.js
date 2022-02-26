#!/usr/bin/osascript -l JavaScript

// process-focus.js [PID...]
//
// Make up to 5 attempts, 200ms apart, to give focus to the window associated
// with each PID.

function run (pids) {
  function focusProcess (unixId) {
    try {
      SystemEvents.processes.whose({ unixId: unixId })[0].frontmost = true
    } catch {
      return false
    }
    return true
  }
  const SystemEvents = Application('System Events')
  for (const pid of pids) {
    for (let i = 0; i < 5; i++) {
      if (!focusProcess(pid)) {
        delay(0.2)
        continue
      }
      break
    }
  }
}
