import Foundation
import PostgresNIO
import AppKit

enum CSVExportError: Error, LocalizedError {
    case exportCancelled
    case fileSystemError(String)
    
    var errorDescription: String? {
        switch self {
        case .exportCancelled: return "Export cancelled by user."
        case .fileSystemError(let msg): return "File system error: \(msg)"
        }
    }
}

actor CSVExporter {
    
    /// Exports the provided SQL query results to a CSV file.
    /// This method streams the rows directly from the database to disk, bypassing memory limits.
    /// - Parameters:
    ///   - connection: The PostgresConnection to use.
    ///   - sql: The fully qualified SQL query (typically built without a LIMIT clause).
    ///   - tableName: The name of the table (used to suggest a filename).
    static func exportStreamToCSV(connection: PostgresConnection, sql: String, tableName: String) async throws {
        // 1. Prompt user for save location
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
            throw CSVExportError.exportCancelled
        }
        
        // 2. Open file stream
        guard FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil) else {
            throw CSVExportError.fileSystemError("Could not create file at path: \(fileURL.path)")
        }
        
        let fileHandle = try FileHandle(forWritingTo: fileURL)
        defer {
            try? fileHandle.close()
        }
        
        // 3. Execute query and fetch row sequence
        let rowSequence = try await connection.query(sql)
        
        var isFirstRow = true
        var writeCount = 0
        
        // 4. Stream rows to disk
        for try await row in rowSequence {
            let cells = row.makeRandomAccess()
            
            // Write CSV Header on first iteration
            if isFirstRow {
                let headers = (0..<cells.count).map { escapeCSV(cells[$0].columnName) }
                let headerLine = headers.joined(separator: ",") + "\n"
                if let data = headerLine.data(using: .utf8) {
                    fileHandle.write(data)
                }
                isFirstRow = false
            }
            
            // Write Row Data
            var rowValues: [String] = []
            for i in 0..<cells.count {
                let cell = cells[i]
                
                let rawValue: String
                if var bytes = cell.bytes {
                    if let str = try? cell.decode(String.self) {
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
                fileHandle.write(data)
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
}
