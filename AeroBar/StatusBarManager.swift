//
//  StatusBarManager.swift
//  AeroBar
//
//  Created by Eric Stein on 24.05.25.
//

import Cocoa
import Foundation

class StatusBarManager: NSObject {
    private var statusItem: NSStatusItem?
    private var backupTimer: Timer?
    private let aerospaceManager = AerospaceManager()
    private var lastKnownWorkspace: String = ""
    private var lastKnownWorkspaces: [String] = []
    private var updateWorkItem: DispatchWorkItem?
    private var isUpdating = false
    
    override init() {
        super.init()
        setupStatusItem()
        updateDisplay() // Initial update only
        setupSmartWatcher()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let statusItem = statusItem else { return }
        
        if let button = statusItem.button {
            button.title = "Loading..."
            button.target = self
            button.action = #selector(statusItemClicked)
        }
    }
    
    private func setupSmartWatcher() {
        // Listen for application activation - this is when workspace switches usually happen
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        // Listen for space changes (when user manually switches with Mission Control, etc.)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(spaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        
        // Listen for window focus changes (when switching between windows in same app)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(windowDidChange),
            name: NSWorkspace.didDeactivateApplicationNotification,
            object: nil
        )
        
        // Very infrequent backup timer - only every 60 seconds as safety net
        // This catches edge cases where notifications might be missed
        backupTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
            print("Safety backup check triggered")
            self.smartUpdate(reason: "backup")
        }
        
        print("Smart watcher setup complete - event-driven updates only")
    }
    
    @objc private func applicationDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        
        // Filter out our own app and system apps
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return }
        if app.bundleIdentifier?.hasPrefix("com.apple.") == true { return }
        
        print("App activated: \(app.localizedName ?? "unknown")")
        smartUpdate(reason: "app_switch")
    }
    
    @objc private func spaceDidChange(_ notification: Notification) {
        print("Space changed via Mission Control")
        smartUpdate(reason: "space_change")
    }
    
    @objc private func windowDidChange(_ notification: Notification) {
        // This fires when switching between windows, might indicate workspace change
        smartUpdate(reason: "window_change", delay: 0.1)
    }
    
    private func smartUpdate(reason: String, delay: TimeInterval = 0.2) {
        // Cancel previous update if still pending
        updateWorkItem?.cancel()
        
        // Create new work item
        updateWorkItem = DispatchWorkItem { [weak self] in
            print("Smart update triggered by: \(reason)")
            self?.updateDisplay()
        }
        
        // Small delay to let aerospace catch up
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: updateWorkItem!)
    }
    
    @objc private func statusItemClicked() {
        showMenu()
    }
    
    private func showMenu() {
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "Current: \(lastKnownWorkspace)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Force Refresh", action: #selector(refreshClicked), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitClicked), keyEquivalent: "q"))
        
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }
    
    @objc private func refreshClicked() {
        print("Manual refresh requested")
        updateDisplay()
    }
    
    @objc private func quitClicked() {
        NSApplication.shared.terminate(nil)
    }
    
    private func updateDisplay() {
        // Prevent concurrent updates
        guard !isUpdating else {
            print("Update already in progress, skipping...")
            return
        }
        
        isUpdating = true
        
        aerospaceManager.getWorkspaceInfo { [weak self] result in
            DispatchQueue.main.async {
                self?.isUpdating = false
                
                switch result {
                case .success(let workspaceInfo):
                    // Only update if something actually changed
                    let workspaceChanged = workspaceInfo.focusedWorkspace != self?.lastKnownWorkspace
                    let workspacesChanged = workspaceInfo.allWorkspaces != self?.lastKnownWorkspaces
                    
                    if workspaceChanged || workspacesChanged {
                        if workspaceChanged {
                            print("Workspace changed: \(self?.lastKnownWorkspace ?? "?") → \(workspaceInfo.focusedWorkspace)")
                        }
                        if workspacesChanged {
                            print("Workspace list changed: \(workspaceInfo.allWorkspaces)")
                        }
                        
                        self?.updateStatusItemTitle(with: workspaceInfo)
                        self?.lastKnownWorkspace = workspaceInfo.focusedWorkspace
                        self?.lastKnownWorkspaces = workspaceInfo.allWorkspaces
                    } else {
                        print("No change detected, skipping UI update")
                    }
                    
                case .failure(let error):
                    print("Error: \(error)")
                    switch error {
                    case .timeout:
                        // Don't update UI on timeout, keep previous state
                        print("Timeout occurred, keeping previous state")
                    case .permissionDenied:
                        self?.statusItem?.button?.title = "Permission Denied"
                    case .aerospaceNotFound:
                        self?.statusItem?.button?.title = "No AeroSpace"
                    default:
                        self?.statusItem?.button?.title = "Error"
                    }
                }
            }
        }
    }
    
    private func updateStatusItemTitle(with info: WorkspaceInfo) {
        let display = info.allWorkspaces.map { workspace in
            workspace == info.focusedWorkspace ? "●" : "○"
        }.joined()
        
        let newTitle = "[\(display)]"
        statusItem?.button?.title = newTitle
    }
    
    func cleanup() {
        updateWorkItem?.cancel()
        backupTimer?.invalidate()
        backupTimer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    deinit {
        cleanup()
    }
}
