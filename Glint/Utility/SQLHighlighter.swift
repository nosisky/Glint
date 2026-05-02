//
//  SQLHighlighter.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

import SwiftUI

/// A lightweight SQL syntax highlighter using AttributedString and Regular Expressions.
struct SQLHighlighter {
    
    static func highlight(_ sql: String) -> AttributedString {
        var attrStr = AttributedString(sql)
        attrStr.foregroundColor = .primary
        
        let stringLiteralRegex = try! NSRegularExpression(pattern: "'[^']*'")
        let numberRegex = try! NSRegularExpression(pattern: "\\b\\d+(\\.\\d+)?\\b")
        let keywordRegex = try! NSRegularExpression(pattern: "\\b(CREATE|TABLE|PRIMARY KEY|NOT NULL|DEFAULT|INDEX|UNIQUE|ON|USING|ALTER|ADD|CONSTRAINT|FOREIGN KEY|REFERENCES|SELECT|FROM|WHERE|INSERT|INTO|VALUES|UPDATE|SET|DELETE|AND|OR|AS|JOIN|LEFT|RIGHT|INNER|OUTER|GROUP BY|ORDER BY|ASC|DESC|LIMIT|OFFSET)\\b", options: [.caseInsensitive])
        let dataTypeRegex = try! NSRegularExpression(pattern: "\\b(uuid|integer|int|smallint|bigint|serial|bigserial|boolean|bool|text|varchar|character varying|char|date|time|timestamp|timestamptz|json|jsonb|numeric|decimal|real|double precision)\\b", options: [.caseInsensitive])
        let functionRegex = try! NSRegularExpression(pattern: "\\b(now|current_timestamp|current_date|uuid_generate_v4|gen_random_uuid|count|sum|avg|min|max)\\b\\s*\\(", options: [.caseInsensitive])
        
        let nsRange = NSRange(sql.startIndex..<sql.endIndex, in: sql)
        
        func applyColor(to matchRange: NSRange, color: Color, bold: Bool = false) {
            if let range = Range(matchRange, in: sql),
               let lower = AttributedString.Index(range.lowerBound, within: attrStr),
               let upper = AttributedString.Index(range.upperBound, within: attrStr) {
                let attrRange = lower..<upper
                attrStr[attrRange].foregroundColor = color
                if bold {
                    attrStr[attrRange].inlinePresentationIntent = .stronglyEmphasized
                }
            }
        }
        
        // 1. Strings
        stringLiteralRegex.enumerateMatches(in: sql, options: [], range: nsRange) { match, _, _ in
            applyColor(to: match!.range, color: .orange)
        }
        
        // 2. Numbers
        numberRegex.enumerateMatches(in: sql, options: [], range: nsRange) { match, _, _ in
            applyColor(to: match!.range, color: .cyan)
        }
        
        // 3. Keywords
        keywordRegex.enumerateMatches(in: sql, options: [], range: nsRange) { match, _, _ in
            applyColor(to: match!.range, color: .purple, bold: true)
        }
        
        // 4. Data Types
        dataTypeRegex.enumerateMatches(in: sql, options: [], range: nsRange) { match, _, _ in
            applyColor(to: match!.range, color: .blue)
        }
        
        // 5. Built-in Functions
        functionRegex.enumerateMatches(in: sql, options: [], range: nsRange) { match, _, _ in
            applyColor(to: match!.range(at: 1), color: Color(nsColor: .systemTeal))
        }
        
        return attrStr
    }
}
