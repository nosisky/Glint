import Foundation
import SwiftUI

@MainActor
@Observable
class ImportViewModel {
    var selectedFileURL: URL?
    var options = ImportOptions()
    var csvHeaders: [String] = []
    var mappings: [ImportMapping] = []
    
    // DB Context
    var availableTables: [String] = []
    var selectedTable: String = ""
    var tableColumns: [String] = []
    var tableColumnTypes: [String: String] = [:]
    
    // Status
    var isParsingFile = false
    var isImporting = false
    var importProgress: Double = 0.0
    var errorMessage: String?
    var successMessage: String?
    
    init() {}
    
    /// Called when the user selects a file
    @MainActor
    func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        
        if panel.runModal() == .OK {
            self.selectedFileURL = panel.url
            parseFirstLine()
        }
    }
    
    private func parseFirstLine() {
        guard let url = selectedFileURL else { return }
        isParsingFile = true
        errorMessage = nil
        
        Task {
            do {
                let data = try Data(contentsOf: url, options: .alwaysMapped)
                let delimiterByte = options.delimiter.asciiValue ?? 44
                let quoteByte = options.quoteCharacter.asciiValue ?? 34
                let newlineByte: UInt8 = 10
                let crByte: UInt8 = 13
                
                var currentFieldBytes = [UInt8]()
                var headers = [String]()
                var insideQuotes = false
                var lastCharWasQuote = false
                var processedBytes = 0
                
                for byte in data {
                    processedBytes += 1
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
                            headers.append(fieldString)
                            currentFieldBytes.removeAll(keepingCapacity: true)
                        } else if byte == newlineByte && !insideQuotes {
                            if currentFieldBytes.last == crByte {
                                currentFieldBytes.removeLast()
                            }
                            let fieldString = String(bytes: currentFieldBytes, encoding: .utf8) ?? ""
                            headers.append(fieldString)
                            break // Stop after first row
                        } else {
                            currentFieldBytes.append(byte)
                        }
                    }
                }
                
                if headers.isEmpty && !currentFieldBytes.isEmpty {
                    if currentFieldBytes.last == crByte {
                        currentFieldBytes.removeLast()
                    }
                    let fieldString = String(bytes: currentFieldBytes, encoding: .utf8) ?? ""
                    headers.append(fieldString)
                }
                
                guard !headers.isEmpty else {
                    self.errorMessage = "File is empty."
                    self.isParsingFile = false
                    return
                }
                
                self.csvHeaders = headers
                self.mappings = headers.enumerated().compactMap { index, header in
                    if self.tableColumns.contains(header), let dataType = self.tableColumnTypes[header] {
                        return ImportMapping(csvColumnName: header, csvColumnIndex: index, dbColumnName: header, dbDataType: dataType)
                    }
                    return nil
                }
                self.isParsingFile = false
            } catch {
                self.errorMessage = "Error reading file: \(error.localizedDescription)"
                self.isParsingFile = false
            }
        }
    }
    
    func fetchTables(connection: PostgresConnection) async {
        do {
            let tables = try await connection.queryAll("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'")
            var result: [String] = []
            for row in tables {
                let randomAccess = row.makeRandomAccess()
                if let name = try? randomAccess[0].decode(String.self) {
                    result.append(name)
                }
            }
            self.availableTables = result
            if let first = result.first {
                self.selectedTable = first
            }
        } catch {
            self.errorMessage = "Failed to fetch tables: \(error.localizedDescription)"
        }
    }
    
    func fetchColumns(for table: String, connection: PostgresConnection) async {
        do {
            let query = "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = '\(table)'"
            let cols = try await connection.queryAll(query)
            var result: [String] = []
            var types: [String: String] = [:]
            
            for row in cols {
                let randomAccess = row.makeRandomAccess()
                if let name = try? randomAccess[0].decode(String.self),
                   let type = try? randomAccess[1].decode(String.self) {
                    result.append(name)
                    types[name] = type
                }
            }
            self.tableColumns = result
            self.tableColumnTypes = types
            
            // Refresh mappings based on new table columns
            self.mappings = self.csvHeaders.enumerated().compactMap { index, header in
                if self.tableColumns.contains(header), let dataType = self.tableColumnTypes[header] {
                    return ImportMapping(csvColumnName: header, csvColumnIndex: index, dbColumnName: header, dbDataType: dataType)
                }
                return nil
            }
        } catch {
            self.errorMessage = "Failed to fetch columns: \(error.localizedDescription)"
        }
    }
    
    func startImport(connection: PostgresConnection) {
        guard let url = selectedFileURL else {
            self.errorMessage = "No file selected."
            return
        }
        
        guard !selectedTable.isEmpty else {
            self.errorMessage = "No table selected."
            return
        }
        
        guard !mappings.isEmpty else {
            self.errorMessage = "No columns mapped."
            return
        }
        
        self.isImporting = true
        self.errorMessage = nil
        self.successMessage = nil
        self.importProgress = 0.0
        
        Task {
            do {
                let importer = DataImporter()
                let stream = try await importer.importCSV(
                    url: url,
                    toTable: selectedTable,
                    mappings: mappings,
                    options: options,
                    connection: connection
                )
                
                for try await progress in stream {
                    self.importProgress = progress
                }
                
                self.successMessage = "Successfully imported data into \(self.selectedTable)."
                self.isImporting = false
                
            } catch {
                self.errorMessage = "Import failed: \(error.localizedDescription)"
                self.isImporting = false
            }
        }
    }
    
    private func parseCSVLine(_ line: String, delimiter: Character, quoteChar: Character) -> [String] {
        var fields: [String] = []
        var currentField = ""
        var insideQuotes = false
        
        for char in line {
            if char == quoteChar {
                insideQuotes.toggle()
            } else if char == delimiter && !insideQuotes {
                fields.append(currentField)
                currentField = ""
            } else {
                currentField.append(char)
            }
        }
        fields.append(currentField)
        return fields
    }
}
