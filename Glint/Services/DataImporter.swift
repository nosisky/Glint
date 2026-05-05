import Foundation
import PostgresNIO
import NIOCore
import NIOPosix

/// Service responsible for streaming CSV data and bulk-inserting it into a Postgres database.
actor DataImporter {
    enum ImportError: LocalizedError {
        case fileReadError
        case parsingError(row: Int, message: String)
        case databaseError(String)
        
        var errorDescription: String? {
            switch self {
            case .fileReadError: return "Failed to read the file."
            case .parsingError(let row, let msg): return "Parsing failed at row \(row): \(msg)"
            case .databaseError(let msg): return "Database error: \(msg)"
            }
        }
    }
    
    init() {}
    
    /// Streams a CSV file using memory mapping, parsing it (RFC 4180), and executes batched inserts.
    func importCSV(
        url: URL,
        toTable: String,
        mappings: [ImportMapping],
        options: ImportOptions,
        connection: PostgresConnection
    ) async throws -> AsyncThrowingStream<Double, Error> {
        let client = try await connection.getClient()
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Start transaction
                    _ = try await client.query(PostgresQuery(unsafeSQL: "BEGIN TRANSACTION"))
                    
                    let data = try Data(contentsOf: url, options: .alwaysMapped)
                    let totalBytes = data.count
                    
                    let delimiterByte = options.delimiter.asciiValue ?? 44
                    let quoteByte = options.quoteCharacter.asciiValue ?? 34
                    let newlineByte: UInt8 = 10
                    let crByte: UInt8 = 13
                    
                    var currentFieldBytes = [UInt8]()
                    var currentRow = [String]()
                    var insideQuotes = false
                    var lastCharWasQuote = false
                    
                    var processedBytes = 0
                    var currentRowCount = 0
                    
                    var batchCount = 0
                    var currentBatch = [[String]]()
                    currentBatch.reserveCapacity(options.batchSize)
                    
                    // Helper to process row
                    func processRow(_ row: [String]) async throws {
                        currentRowCount += 1
                        if options.hasHeaderRow && currentRowCount == 1 { return }
                        
                        var rowData = [String]()
                        for mapping in mappings {
                            if mapping.csvColumnIndex < row.count {
                                rowData.append(row[mapping.csvColumnIndex])
                            } else {
                                rowData.append("")
                            }
                        }
                        currentBatch.append(rowData)
                        batchCount += 1
                        
                        if batchCount >= options.batchSize {
                            try await executeBatch(currentBatch, table: toTable, mappings: mappings, client: client)
                            currentBatch.removeAll(keepingCapacity: true)
                            batchCount = 0
                            
                            let progress = min(1.0, Double(processedBytes) / Double(totalBytes))
                            continuation.yield(progress)
                        }
                    }
                    
                    for byte in data {
                        processedBytes += 1
                        
                        // Handle UTF-8 BOM blindly at start
                        if processedBytes <= 3 && (byte == 0xEF || byte == 0xBB || byte == 0xBF) {
                            continue
                        }
                        
                        if byte == quoteByte {
                            if insideQuotes {
                                if lastCharWasQuote {
                                    currentFieldBytes.append(quoteByte)
                                    lastCharWasQuote = false
                                    insideQuotes = true
                                } else {
                                    lastCharWasQuote = true
                                    insideQuotes = false
                                }
                            } else {
                                if lastCharWasQuote {
                                    currentFieldBytes.append(quoteByte)
                                    insideQuotes = true
                                    lastCharWasQuote = false
                                } else {
                                    insideQuotes = true
                                }
                            }
                        } else {
                            if lastCharWasQuote {
                                lastCharWasQuote = false
                            }
                            
                            if byte == delimiterByte && !insideQuotes {
                                let fieldString = String(bytes: currentFieldBytes, encoding: .utf8) ?? ""
                                currentRow.append(fieldString)
                                currentFieldBytes.removeAll(keepingCapacity: true)
                            } else if byte == newlineByte && !insideQuotes {
                                if currentFieldBytes.last == crByte {
                                    currentFieldBytes.removeLast()
                                }
                                let fieldString = String(bytes: currentFieldBytes, encoding: .utf8) ?? ""
                                currentRow.append(fieldString)
                                
                                try await processRow(currentRow)
                                currentRow.removeAll(keepingCapacity: true)
                                currentFieldBytes.removeAll(keepingCapacity: true)
                            } else {
                                currentFieldBytes.append(byte)
                            }
                        }
                    }
                    
                    // Flush last row
                    if !currentFieldBytes.isEmpty || !currentRow.isEmpty {
                        if currentFieldBytes.last == crByte {
                            currentFieldBytes.removeLast()
                        }
                        let fieldString = String(bytes: currentFieldBytes, encoding: .utf8) ?? ""
                        currentRow.append(fieldString)
                        try await processRow(currentRow)
                    }
                    
                    // Execute remaining rows
                    if !currentBatch.isEmpty {
                        try await executeBatch(currentBatch, table: toTable, mappings: mappings, client: client)
                        continuation.yield(1.0)
                    }
                    
                    _ = try await client.query(PostgresQuery(unsafeSQL: "COMMIT"))
                    continuation.finish()
                } catch {
                    _ = try? await client.query(PostgresQuery(unsafeSQL: "ROLLBACK"))
                    
                    if let psqlError = error as? PSQLError, let serverInfo = psqlError.serverInfo {
                        var errorMsg = serverInfo[.message] ?? "Unknown database error"
                        if let detail = serverInfo[.detail] {
                            errorMsg += " - \(detail)"
                        }
                        continuation.finish(throwing: ImportError.databaseError(errorMsg))
                    } else {
                        continuation.finish(throwing: ImportError.databaseError(String(reflecting: error)))
                    }
                }
            }
        }
    }
    
    private func executeBatch(_ batch: [[String]], table: String, mappings: [ImportMapping], client: PostgresClient) async throws {
        let escapedTable = table.replacingOccurrences(of: "\"", with: "\"\"")
        let columnNames = mappings.map { "\"\($0.dbColumnName.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ", ")
        
        let unnestParams = mappings.enumerated().map { index, _ in "$\(index + 1)::text[]" }.joined(separator: ", ")
        let unnestAliases = mappings.enumerated().map { index, _ in "c\(index + 1)" }.joined(separator: ", ")
        let selectColumns = mappings.enumerated().map { index, mapping in "CAST(NULLIF(c\(index + 1), '') AS \(mapping.dbDataType))" }.joined(separator: ", ")
        
        let sql = "INSERT INTO \"\(escapedTable)\" (\(columnNames)) SELECT \(selectColumns) FROM UNNEST(\(unnestParams)) AS t(\(unnestAliases))"
        var query = PostgresQuery(unsafeSQL: sql)
        
        for (index, _) in mappings.enumerated() {
            let columnData: [String] = batch.map { $0[index] }
            query.binds.append(columnData)
        }
        
        let rows = try await client.query(query)
        for try await _ in rows {}
    }
}
