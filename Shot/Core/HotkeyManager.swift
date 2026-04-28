//
//  HotkeyManager.swift
//  ScreenshotTool
//
//  Created by yakir on 2026/3/24.
//

import Carbon
import Cocoa

class HotkeyManager {

  typealias Handler = () -> Void

  private var hotkeys: [UInt32: (ref: EventHotKeyRef?, handler: Handler)] = [:]
  private var nextID: UInt32 = 1

  struct Modifiers: OptionSet {
    let rawValue: UInt32

    static let command = Modifiers(rawValue: UInt32(cmdKey))
    static let shift = Modifiers(rawValue: UInt32(shiftKey))
    static let option = Modifiers(rawValue: UInt32(optionKey))
    static let control = Modifiers(rawValue: UInt32(controlKey))
  }

  func register(keyCode: UInt32, modifiers: Modifiers, handler: @escaping Handler) {
    let id = nextID
    nextID += 1

    let hotKeyID = EventHotKeyID(
      signature: OSType(0x53_43_54_4C),  // "SCTL"
      id: id
    )

    var hotKeyRef: EventHotKeyRef?
    let status = RegisterEventHotKey(
      keyCode,
      modifiers.rawValue,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )

    if status == noErr {
      hotkeys[id] = (ref: hotKeyRef, handler: handler)
    }

    // 安装事件处理器（只需一次）
    installEventHandler()
  }

  private var eventHandlerInstalled = false

  private func installEventHandler() {
    guard !eventHandlerInstalled else { return }
    eventHandlerInstalled = true

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )

    let this = Unmanaged.passUnretained(self).toOpaque()

    InstallEventHandler(
      GetApplicationEventTarget(),
      { (_, event, userData) -> OSStatus in
        guard let event = event, let userData = userData else {
          return OSStatus(eventNotHandledErr)
        }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &hotKeyID
        )

        guard status == noErr else { return status }

        let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

        if let entry = manager.hotkeys[hotKeyID.id] {
          DispatchQueue.main.async {
            entry.handler()
          }
        }

        return noErr
      },
      1,
      &eventType,
      this,
      nil
    )
  }

  deinit {
    for (_, entry) in hotkeys {
      if let ref = entry.ref {
        UnregisterEventHotKey(ref)
      }
    }
  }
}
