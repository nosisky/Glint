//
//  PgBackendActivity.swift
//  Glint
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky

import Foundation

struct PgBackendActivity: Identifiable, Equatable, Hashable {
    let id: Int // Using pid as the unique ID
    var pid: Int { id }
    let user: String
    let applicationName: String
    let clientAddr: String
    let state: String
    let waitEvent: String
    let query: String
    let queryStart: Date?
    
    var duration: TimeInterval? {
        guard let queryStart = queryStart else { return nil }
        return Date().timeIntervalSince(queryStart)
    }
    
    var sortDuration: Double {
        duration ?? 0.0
    }
    
    var formattedDuration: String {
        guard let duration = duration else { return "-" }
        if duration < 1 { return String(format: "%.0f ms", duration * 1000) }
        if duration < 60 { return String(format: "%.1f s", duration) }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return "\(minutes)m \(seconds)s"
    }
}
