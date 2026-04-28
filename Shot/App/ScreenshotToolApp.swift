//
//  ScreenshotToolApp.swift
//  ScreenshotTool
//
//  Created by macOS Swift Architect on 2026/4/2.
//

import SwiftUI

@main
struct ScreenshotToolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            Text("Preferences")
                .frame(width: 400, height: 300)
        }
    }
}
