#!/usr/bin/osascript -l JavaScript

// process-focus.js [PID...]
//
// Make up to 5 attempts, 200ms apart, to give focus to the window associated
// with each PID.

function _out (handle, ...args) {
  for (const arg of args) {
    handle.writeData($.NSString.alloc
      .initWithString(String(arg) + '\n')
      .dataUsingEncoding($.NSUTF8StringEncoding))
  }
}

console.log = function () {
  _out($.NSFileHandle.fileHandleWithStandardOutput, ...arguments)
}

console.error = function () {
  _out($.NSFileHandle.fileHandleWithStandardError, ...arguments)
}

function run (pids) {
  function focusProcess (unixId) {
    try {
      SystemEvents.processes.whose({
        unixId: unixId
      })[0].frontmost = true
      console.log("focusProcess succeeded")
    } catch {
      console.error("focusProcess failed")
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
