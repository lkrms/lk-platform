#!/usr/bin/osascript -l JavaScript

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

function printItems (items) {
  for (let i = 0; i < items.length; i++) {
    const props = items[i].properties()
    if (!i) {
      console.log(Object.keys(props)
        .join('\t'))
    }
    console.log(Object.values(props)
      .join('\t'))
  }
}

function run () {
  const SystemEvents = Application('System Events')
  printItems(SystemEvents.loginItems())
}
