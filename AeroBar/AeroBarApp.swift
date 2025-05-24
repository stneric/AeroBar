//
//  AeroBarApp.swift
//  AeroBar
//
//  Created by Eric Stein on 24.05.25.
//

import SwiftUI
import ServiceManagement

@main
struct AerospaceStatusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarManager: StatusBarManager?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarManager = StatusBarManager()
        // Force icon registration becuase currently its square when it should be rounded
        NSApp.setActivationPolicy(.regular)
        NSApp.setActivationPolicy(.accessory)
        // Register for login item
        if #available(macOS 13.0, *) {
            try? SMAppService.mainApp.register()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        statusBarManager?.cleanup()
    }
}

