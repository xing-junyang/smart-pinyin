//
//  main.swift
//  smart pinyin
//
//  Entry point for the macOS Input Method.
//  Sets up the IMKServer and runs the application event loop.
//

import Cocoa
import InputMethodKit

// MARK: - Logging

/// Configure basic console logging for debugging.
/// Input method logs appear in Console.app under the process name.
func configureLogging() {
    NSLog("🚀 SmartPinyin input method starting (Build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"))")
}

// MARK: - Entry Point

configureLogging()

// Read connection name from Info.plist
let connectionName = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String
    ?? "SmartPinyin_Connection"

NSLog("📋 Connection name: \(connectionName)")

// Create the IMKServer – this registers the input method with the system.
let server = IMKServer(
    name: connectionName,
    bundleIdentifier: Bundle.main.bundleIdentifier
)

if server == nil {
    NSLog("❌ Failed to create IMKServer")
} else {
    NSLog("✅ IMKServer created successfully")
}

// Run the main event loop.
// The app stays alive as long as the input method is active.
NSApplication.shared.run()

