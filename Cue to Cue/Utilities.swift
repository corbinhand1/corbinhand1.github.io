//
//  Utilities.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/11/24.
//

import Foundation


// MARK: - App identity

enum AppInfo {
    /// Marketing version from the bundle (e.g. "2.1"), set by MARKETING_VERSION.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// "Cue to Cue 2.1"
    static var nameWithVersion: String {
        version.isEmpty ? "Cue to Cue" : "Cue to Cue \(version)"
    }
}
