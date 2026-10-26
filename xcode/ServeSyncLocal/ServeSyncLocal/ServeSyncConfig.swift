//
//  ServeSyncConfig.swift
//  ServeSyncLocal
//
//  Created for ServeSync Sprint 3.
//

import Foundation

public enum ServeSyncConfig {
    /// Development Server URL:
    /// - When running in the Xcode iOS Simulator on the Mac, routes to `http://127.0.0.1:8000`.
    /// - When running on a physical iPhone/iPad connected over the local network, routes to the Mac's LAN IP (`http://192.168.1.95:8000`).
    #if targetEnvironment(simulator)
    public static let defaultBaseURL: URL = URL(string: "http://127.0.0.1:8000")!
    #else
    public static let defaultBaseURL: URL = URL(string: "http://192.168.1.95:8000")!
    #endif
}
