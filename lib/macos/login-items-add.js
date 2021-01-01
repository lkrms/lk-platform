#!/usr/bin/osascript -l JavaScript

function run (paths) {
  const SystemEvents = Application('System Events')
  for (const path of paths) {
    const loginItem = SystemEvents.LoginItem({
      path: path
    })
    SystemEvents.loginItems.push(loginItem)
  }
}
