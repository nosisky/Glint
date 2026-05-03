//
//  ExplainPlan.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

import Foundation

// MARK: - Plan Node

/// A single node in a PostgreSQL EXPLAIN plan tree.
/// Each node represents one step in the query execution pipeline (scan, join, sort, etc.).
struct ExplainNode: Identifiable, Sendable {
    let id: UUID
    let nodeType: String
    let relationName: String?
    let alias: String?
    let schema: String?
    let startupCost: Double
    let totalCost: Double
    let planRows: Int64
    let planWidth: Int

    // ANALYZE-only fields (nil when using plain EXPLAIN without ANALYZE)
    let actualStartupTime: Double?
    let actualTotalTime: Double?
    let actualRows: Int64?
    let actualLoops: Int?

    // BUFFERS-only fields (nil when BUFFERS is not requested)
    let sharedHit: Int64?
    let sharedRead: Int64?
    let sharedWritten: Int64?

    // Descriptive metadata surfaced in the plan
    let filter: String?
    let joinType: String?
    let indexName: String?
    let scanDirection: String?
    let sortKey: [String]?
    let strategy: String?
    let hashCondition: String?
    let indexCondition: String?
    let rowsRemovedByFilter: Int64?
    let output: [String]?

    let children: [ExplainNode]

    // MARK: Computed Properties

    /// Time spent exclusively in this node (subtracting children's contribution).
    /// Accounts for loop multipliers on both parent and child nodes.
    var exclusiveTimeMs: Double {
        guard let total = actualTotalTime else { return 0 }
        let loops = Double(actualLoops ?? 1)
        let childTime = children.reduce(0.0) { sum, child in
            let childLoops = Double(child.actualLoops ?? 1)
            return sum + (child.actualTotalTime ?? 0) * childLoops
        }
        return max(0, total * loops - childTime)
    }

    /// Ratio of actual rows to planned rows. A value far from 1.0 indicates
    /// the planner's cardinality estimate was inaccurate — the primary cause
    /// of suboptimal query plans in PostgreSQL.
    var rowEstimateAccuracy: Double? {
        guard let actual = actualRows, planRows > 0 else { return nil }
        return Double(actual) / Double(planRows)
    }

    /// True if actual rows differ from planned rows by more than 10×.
    var isBadEstimate: Bool {
        guard let ratio = rowEstimateAccuracy else { return false }
        return ratio > 10.0 || ratio < 0.1
    }

    /// Total rows processed including loop iterations.
    var totalActualRows: Int64? {
        guard let rows = actualRows else { return nil }
        return rows * Int64(actualLoops ?? 1)
    }
}

// MARK: - Plan Container

/// A fully parsed PostgreSQL EXPLAIN plan, containing the root node tree
/// and top-level metadata (planning/execution times).
struct ExplainPlan: Sendable {
    let rootNode: ExplainNode
    let planningTime: Double?
    let executionTime: Double?
    let rawJSON: String
    let rawText: String
    let wasAnalyze: Bool

    /// The total cost of the root node (planner's unit-less cost estimate).
    var totalCost: Double { rootNode.totalCost }

    /// The total wall-clock time from the root node (including all children and loops).
    var totalActualTime: Double? {
        guard let time = rootNode.actualTotalTime,
              let loops = rootNode.actualLoops else { return nil }
        return time * Double(loops)
    }

    /// Recursively flattens the tree into a list for aggregate analysis.
    var allNodes: [ExplainNode] {
        var result: [ExplainNode] = []
        func collect(_ node: ExplainNode) {
            result.append(node)
            for child in node.children { collect(child) }
        }
        collect(rootNode)
        return result
    }

    /// The node consuming the most exclusive time — the bottleneck.
    var bottleneckNode: ExplainNode? {
        allNodes.max(by: { $0.exclusiveTimeMs < $1.exclusiveTimeMs })
    }

    /// Total number of nodes in the plan tree.
    var nodeCount: Int { allNodes.count }

    /// Generates a human-readable text representation of the plan tree,
    /// matching the style of `EXPLAIN (FORMAT TEXT)` output from Postgres.
    /// Used when ANALYZE mode skips the second TEXT query to avoid
    /// double-executing the query.
    var textRepresentation: String {
        var lines: [String] = []
        renderNode(rootNode, depth: 0, isLast: true, prefix: "", into: &lines)

        if let planTime = planningTime {
            lines.append("Planning Time: \(String(format: "%.3f", planTime)) ms")
        }
        if let execTime = executionTime {
            lines.append("Execution Time: \(String(format: "%.3f", execTime)) ms")
        }
        return lines.joined(separator: "\n")
    }

    private func renderNode(_ node: ExplainNode, depth: Int, isLast: Bool, prefix: String, into lines: inout [String]) {
        var desc = ""

        // Indentation: root has no arrow, children get ->
        if depth == 0 {
            desc = ""
        } else {
            desc = prefix + (isLast ? "->  " : "->  ")
        }

        // Node type and key details
        desc += node.nodeType
        if let rel = node.relationName {
            desc += " on \(rel)"
            if let alias = node.alias, alias != rel {
                desc += " \(alias)"
            }
        }
        if let idx = node.indexName {
            desc += " using \(idx)"
        }

        // Cost and rows
        desc += "  (cost=\(String(format: "%.2f", node.startupCost))..\(String(format: "%.2f", node.totalCost))"
        desc += " rows=\(node.planRows) width=\(node.planWidth))"

        // ANALYZE timing
        if let actualTime = node.actualTotalTime, let actualRows = node.actualRows {
            let loops = node.actualLoops ?? 1
            desc += " (actual time=\(String(format: "%.3f", node.actualStartupTime ?? 0))..\(String(format: "%.3f", actualTime))"
            desc += " rows=\(actualRows) loops=\(loops))"
        }

        lines.append(desc)

        // Detail lines
        let indent = depth == 0 ? "  " : prefix + "    "
        if let filter = node.filter {
            lines.append("\(indent)Filter: \(filter)")
            if let removed = node.rowsRemovedByFilter, removed > 0 {
                lines.append("\(indent)Rows Removed by Filter: \(removed)")
            }
        }
        if let cond = node.indexCondition {
            lines.append("\(indent)Index Cond: \(cond)")
        }
        if let cond = node.hashCondition {
            lines.append("\(indent)Hash Cond: \(cond)")
        }
        if let keys = node.sortKey, !keys.isEmpty {
            lines.append("\(indent)Sort Key: \(keys.joined(separator: ", "))")
        }

        // Buffer stats
        if let hit = node.sharedHit, hit > 0 {
            var bufLine = "\(indent)Buffers: shared hit=\(hit)"
            if let read = node.sharedRead, read > 0 { bufLine += " read=\(read)" }
            if let written = node.sharedWritten, written > 0 { bufLine += " written=\(written)" }
            lines.append(bufLine)
        }

        // Render children
        let childPrefix = depth == 0 ? "  " : prefix + "    "
        for (i, child) in node.children.enumerated() {
            renderNode(child, depth: depth + 1, isLast: i == node.children.count - 1, prefix: childPrefix, into: &lines)
        }
    }

    // MARK: - JSON Parser

    enum ParseError: LocalizedError {
        case invalidJSON
        case missingPlan
        case unexpectedStructure(String)

        var errorDescription: String? {
            switch self {
            case .invalidJSON:
                return "The EXPLAIN output is not valid JSON."
            case .missingPlan:
                return "No 'Plan' key found in the EXPLAIN output."
            case .unexpectedStructure(let detail):
                return "Unexpected plan structure: \(detail)"
            }
        }
    }

    /// Parses the JSON output of `EXPLAIN (FORMAT JSON)`.
    ///
    /// PostgreSQL returns the plan as: `[{"Plan": {...}, "Planning Time": ..., "Execution Time": ...}]`
    /// The `Plan` object contains a recursive `Plans` array for child nodes.
    static func parse(json: String, rawText: String = "", wasAnalyze: Bool = false) throws -> ExplainPlan {
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let firstEntry = parsed.first
        else {
            throw ParseError.invalidJSON
        }

        guard let planDict = firstEntry["Plan"] as? [String: Any] else {
            throw ParseError.missingPlan
        }

        let rootNode = try parseNode(planDict)
        let planningTime = firstEntry["Planning Time"] as? Double
        let executionTime = firstEntry["Execution Time"] as? Double

        return ExplainPlan(
            rootNode: rootNode,
            planningTime: planningTime,
            executionTime: executionTime,
            rawJSON: json,
            rawText: rawText,
            wasAnalyze: wasAnalyze
        )
    }

    /// Recursively parses a single plan node from the JSON dictionary.
    /// Handles Int/Int64 ambiguity from JSONSerialization (platform-dependent).
    private static func parseNode(_ dict: [String: Any]) throws -> ExplainNode {
        guard let nodeType = dict["Node Type"] as? String else {
            throw ParseError.unexpectedStructure("Missing 'Node Type'")
        }

        let childPlans = dict["Plans"] as? [[String: Any]] ?? []
        let children = try childPlans.map { try parseNode($0) }

        return ExplainNode(
            id: UUID(),
            nodeType: nodeType,
            relationName: dict["Relation Name"] as? String,
            alias: dict["Alias"] as? String,
            schema: dict["Schema"] as? String,
            startupCost: dict["Startup Cost"] as? Double ?? 0,
            totalCost: dict["Total Cost"] as? Double ?? 0,
            planRows: decodeInt64(dict["Plan Rows"]),
            planWidth: dict["Plan Width"] as? Int ?? 0,
            actualStartupTime: dict["Actual Startup Time"] as? Double,
            actualTotalTime: dict["Actual Total Time"] as? Double,
            actualRows: decodeOptionalInt64(dict["Actual Rows"]),
            actualLoops: dict["Actual Loops"] as? Int,
            sharedHit: decodeOptionalInt64(dict["Shared Hit Blocks"]),
            sharedRead: decodeOptionalInt64(dict["Shared Read Blocks"]),
            sharedWritten: decodeOptionalInt64(dict["Shared Written Blocks"]),
            filter: dict["Filter"] as? String,
            joinType: dict["Join Type"] as? String,
            indexName: dict["Index Name"] as? String,
            scanDirection: dict["Scan Direction"] as? String,
            sortKey: dict["Sort Key"] as? [String],
            strategy: dict["Strategy"] as? String,
            hashCondition: dict["Hash Cond"] as? String,
            indexCondition: dict["Index Cond"] as? String,
            rowsRemovedByFilter: decodeOptionalInt64(dict["Rows Removed by Filter"]),
            output: dict["Output"] as? [String],
            children: children
        )
    }

    // MARK: - Numeric Helpers

    /// JSONSerialization can decode integers as Int or Int64 depending on magnitude
    /// and platform. These helpers normalize the result.
    private static func decodeInt64(_ value: Any?) -> Int64 {
        if let v = value as? Int64 { return v }
        if let v = value as? Int { return Int64(v) }
        if let v = value as? Double { return Int64(v) }
        return 0
    }

    private static func decodeOptionalInt64(_ value: Any?) -> Int64? {
        guard let value else { return nil }
        if let v = value as? Int64 { return v }
        if let v = value as? Int { return Int64(v) }
        if let v = value as? Double { return Int64(v) }
        return nil
    }
}
