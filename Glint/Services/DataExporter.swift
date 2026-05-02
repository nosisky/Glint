   //
//  CSVExporter.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

import Foundation
import PostgresNIO
import AppKit

enum DataExportError: Error, LocalizedError {
    case exportCancelled
    case fileSystemError(String)
    
    var errorDescription: String? {
        switch self {
        case .exportCancelled: return "Export cancelled by user."
        case .fileSystemError(let msg): return "File system error: \(msg)"
        }
    }
}

actor DataExporter {
    
    /// Exports the provided SQL query results to a CSV file.
    /// This method streams the rows directly from the database to disk, bypassing memory limits.
    /// - Parameters:
    ///   - connection: The PostgresConnection to use.
    ///   - sql: The fully qualified SQL query (typically built without a LIMIT clause).
    ///   - tableName: The name of the table (used to suggest a filename).
    static func exportStreamToCSV(connection: PostgresConnection, sql: String, tableName: String) async throws {
        // Prompt user for save location
        let fileURL = try await MainActor.run {
            let panel = NSSavePanel()
            panel.title = "Export Table as CSV"
            panel.nameFieldStringValue = "\(tableName)_export_\(Int(Date().timeIntervalSince1970)).csv"
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            
            if panel.runModal() == .OK, let url = panel.url {
                return url
            }
            throw DataExportError.exportCancelled
        }
        
        // Open file stream
        guard FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil) else {
            throw DataExportError.fileSystemError("Could not create file at path: \(fileURL.path)")
        }
        
        let fileHandle = try FileHandle(forWritingTo: fileURL)
        defer {
            try? fileHandle.close()
        }
        
        // Execute query and fetch row sequence
        let rowSequence = try await connection.query(sql)
        
        var isFirstRow = true
        var writeCount = 0
        
        // Stream rows to disk
        for try await row in rowSequence {
            let cells = row.makeRandomAccess()
            
            // Write CSV Header on first iteration
            if isFirstRow {
                let headers = (0..<cells.count).map { escapeCSV(cells[$0].columnName) }
                let headerLine = headers.joined(separator: ",") + "\n"
                if let data = headerLine.data(using: .utf8) {
                    try await Task.detached {
                        try fileHandle.write(contentsOf: data)
                    }.value
                }
                isFirstRow = false
            }
            
            // Write Row Data
            var rowValues: [String] = []
            for i in 0..<cells.count {
                let cell = cells[i]
                
                let rawValue: String
                if var bytes = cell.bytes {
                    if cell.dataType == .bytea {
                        let length = bytes.readableBytes
                        if let rawBytes = bytes.readBytes(length: length) {
                            rawValue = "\\x" + rawBytes.map { String(format: "%02x", $0) }.joined()
                        } else {
                            rawValue = "\\x"
                        }
                    } else if let str = try? cell.decode(String.self) {
                        rawValue = str
                    } else {
                        // Fallback for complex binary types that bypass standard formatting
                        rawValue = bytes.readString(length: bytes.readableBytes) ?? ""
                    }
                } else {
                    rawValue = "" // NULL representation
                }
                
                rowValues.append(escapeCSV(rawValue))
            }
            
            let rowLine = rowValues.joined(separator: ",") + "\n"
            if let data = rowLine.data(using: .utf8) {
                try await Task.detached {
                    try fileHandle.write(contentsOf: data)
                }.value
            }
            
            writeCount += 1
            if writeCount % 1000 == 0 {
                // Yield to prevent blocking the async thread too long on massive tables
                await Task.yield()
            }
        }
    }
    
    /// Escapes a string to conform to RFC 4180 CSV specifications.
    private static func escapeCSV(_ value: String) -> String {
        guard !value.isEmpty else { return "" }
        
        var needsQuotes = false
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            needsQuotes = true
        }
        
        if needsQuotes {
            let escapedQuotes = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escapedQuotes)\""
        }
        
        return value
    }

    /// Exports the provided SQL query results to a JSON file.
    /// Streams the rows directly from the database to disk.
    static func exportStreamToJSON(connection: PostgresConnection, sql: String, tableName: String) async throws {
        // Prompt user for save location
        let fileURL = try await MainActor.run {
            let panel = NSSavePanel()
            panel.title = "Export Table as JSON"
            panel.nameFieldStringValue = "\(tableName)_export_\(Int(Date().timeIntervalSince1970)).json"
            panel.allowedContentTypes = [.json]
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            
            if panel.runModal() == .OK, let url = panel.url {
                return url
            }
            throw DataExportError.exportCancelled
        }
        
        // Open file stream
        guard FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil) else {
            throw DataExportError.fileSystemError("Could not create file at path: \(fileURL.path)")
        }
        
        let fileHandle = try FileHandle(forWritingTo: fileURL)
        defer {
            // Ensure JSON array is properly closed if it was opened
            try? fileHandle.write(contentsOf: "\n]".data(using: .utf8) ?? Data())
            try? fileHandle.close()
        }
        
        // Write JSON opening bracket
        if let data = "[\n".data(using: .utf8) {
            try await Task.detached { 
                try fileHandle.write(contentsOf: data) 
            }.value
        }
        
        let rowSequence = try await connection.query(sql)
        
        var isFirstRow = true
        var writeCount = 0
        var columnNames: [String] = []
        
        for try await row in rowSequence {
            let cells = row.makeRandomAccess()
            
            if isFirstRow {
                columnNames = (0..<cells.count).map { cells[$0].columnName }
            }
            
            var rowDict: [String: Any] = [:]
            for i in 0..<cells.count {
                let cell = cells[i]
                if var bytes = cell.bytes {
                    if cell.dataType == .bytea {
                        let length = bytes.readableBytes
                        if let rawBytes = bytes.readBytes(length: length) {
                            rowDict[columnNames[i]] = "\\x" + rawBytes.map { String(format: "%02x", $0) }.joined()
                        } else {
                            rowDict[columnNames[i]] = "\\x"
                        }
                    } else if cell.dataType == .numeric || cell.dataType == .int2 || cell.dataType == .int4 || cell.dataType == .int8 || cell.dataType == .float4 || cell.dataType == .float8 {
                        if let str = try? cell.decode(String.self), let num = Double(str) {
                            rowDict[columnNames[i]] = num
                        } else {
                            rowDict[columnNames[i]] = try? cell.decode(String.self)
                        }
                    } else if cell.dataType == .bool {
                        if let b = try? cell.decode(Bool.self) {
                            rowDict[columnNames[i]] = b
                        }
                    } else if let str = try? cell.decode(String.self) {
                        rowDict[columnNames[i]] = str
                    } else {
                        rowDict[columnNames[i]] = bytes.readString(length: bytes.readableBytes) ?? ""
                    }
                } else {
                    rowDict[columnNames[i]] = NSNull()
                }
            }
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: rowDict, options: [])
                let prefix = isFirstRow ? "  " : ",\n  "
                if let prefixData = prefix.data(using: .utf8) {
                    try await Task.detached {
                        try fileHandle.write(contentsOf: prefixData)
                        try fileHandle.write(contentsOf: jsonData)
                    }.value
                }
            } catch {
                // Ignore serialization error for this row
            }
            
            isFirstRow = false
            writeCount += 1
            if writeCount % 1000 == 0 {
                await Task.yield()
            }
        }
    }
}
