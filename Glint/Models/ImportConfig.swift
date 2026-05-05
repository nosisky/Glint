//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

import Foundation

/// Represents a mapping between a CSV column and a database column.
struct ImportMapping: Identifiable, Hashable, Sendable {
    let id = UUID()
    var csvColumnName: String
    var csvColumnIndex: Int
    var dbColumnName: String
    var dbDataType: String
    
    init(csvColumnName: String, csvColumnIndex: Int, dbColumnName: String, dbDataType: String) {
        self.csvColumnName = csvColumnName
        self.csvColumnIndex = csvColumnIndex
        self.dbColumnName = dbColumnName
        self.dbDataType = dbDataType
    }
}

/// Options for parsing the CSV file.
struct ImportOptions: Equatable, Sendable {
    var hasHeaderRow: Bool
    var delimiter: Character
    var quoteCharacter: Character
    var batchSize: Int
    
    init(hasHeaderRow: Bool = true, delimiter: Character = ",", quoteCharacter: Character = "\"", batchSize: Int = 1000) {
        self.hasHeaderRow = hasHeaderRow
        self.delimiter = delimiter
        self.quoteCharacter = quoteCharacter
        self.batchSize = batchSize
    }
}

/// Represents the summary of an import operation.
struct ImportResult: Sendable {
    var rowsInserted: Int
    var rowsFailed: Int
    var errorMessage: String?
    var totalTime: TimeInterval
    
    init(rowsInserted: Int = 0, rowsFailed: Int = 0, errorMessage: String? = nil, totalTime: TimeInterval = 0) {
        self.rowsInserted = rowsInserted
        self.rowsFailed = rowsFailed
        self.errorMessage = errorMessage
        self.totalTime = totalTime
    }
}
