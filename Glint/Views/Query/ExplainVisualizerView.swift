//
//  ExplainVisualizerView.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

import SwiftUI

/// Renders a PostgreSQL EXPLAIN plan as an interactive tree with cost bars,
/// row accuracy indicators, timing breakdown, and buffer statistics.
struct ExplainVisualizerView: View {
    let plan: ExplainPlan

    enum ViewMode: String, CaseIterable {
        case tree = "Tree"
        case rawJSON = "JSON"
        case rawText = "Text"
    }

    @State private var viewMode: ViewMode = .tree
    @State private var expandedNodes: Set<UUID> = []
    @State private var isInitialized = false
    @State private var hoveredNodeId: UUID?
    @State private var showCopiedToast = false

    var body: some View {
        VStack(spacing: 0) {
            summaryHeader
            Divider()

            // Actionable warnings or healthy plan summary — Tree mode only
            if viewMode == .tree {
                let warnings = generateWarnings()
                if !warnings.isEmpty {
                    warningsPanel(warnings)
                    Divider()
                } else if plan.wasAnalyze {
                    healthyPlanBanner
                    Divider()
                }
            }

            switch viewMode {
            case .tree:
                treeView
            case .rawJSON:
                rawView(plan.rawJSON)
            case .rawText:
                rawView(plan.rawText)
            }
        }
        .onAppear {
            if !isInitialized {
                expandAllNodes(plan.rootNode)
                isInitialized = true
            }
        }
    }

    // MARK: - Summary Header

    private var summaryHeader: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.8))
                Text("Query Plan")
                    .font(.system(size: 13, weight: .semibold))
            }

            if plan.wasAnalyze {
                statusPill("ANALYZED", color: .green)
            } else {
                statusPill("ESTIMATED", color: .orange)
            }

            Text("·").foregroundStyle(.quaternary)

            Text("\(plan.nodeCount) node\(plan.nodeCount == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Spacer()

            if let planTime = plan.planningTime {
                metricBadge("Planning", value: formatMs(planTime))
            }
            if let execTime = plan.executionTime {
                metricBadge("Execution", value: formatMs(execTime))
            }
            metricBadge("Cost", value: String(format: "%.0f", plan.totalCost))

            viewModeSelector

            if viewMode == .tree && plan.nodeCount > 1 {
                HStack(spacing: 4) {
                    Button {
                        expandAllNodes(plan.rootNode)
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 9))
                            .help("Expand All")
                    }
                    .buttonStyle(.plain)

                    Button {
                        expandedNodes.removeAll()
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 9))
                            .help("Collapse All")
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(GlintDesign.panelBackground)
    }

    private var viewModeSelector: some View {
        HStack(spacing: 1) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Button { viewMode = mode } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 10, weight: viewMode == mode ? .semibold : .regular))
                        .foregroundStyle(viewMode == mode ? .primary : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            viewMode == mode ? GlintDesign.quietAccent : .clear,
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(GlintDesign.appBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(GlintDesign.hairline, lineWidth: 1)
        )
    }

    // MARK: - Warnings Panel

    /// Generates actionable performance warnings from the plan analysis.
    private func generateWarnings() -> [PlanWarning] {
        var warnings: [PlanWarning] = []
        let allNodes = plan.allNodes

        // Sequential scans with filters on large tables (potential missing index).
        // A seq scan WITHOUT a filter is optimal — the query needs every row,
        // so an index would just add overhead. Only warn when a filter is present
        // because that means an index could skip the rows that get filtered out.
        for node in allNodes where node.nodeType.lowercased().contains("seq scan") {
            let hasFilter = node.filter != nil || node.rowsRemovedByFilter != nil
            if let rel = node.relationName, hasFilter {
                let rowCount = node.totalActualRows ?? node.planRows
                if rowCount > 500 || (!plan.wasAnalyze && node.planRows > 500) {
                    let filterDesc = node.filter.map { " with filter \($0)" } ?? ""
                    warnings.append(PlanWarning(
                        severity: .warning,
                        icon: "magnifyingglass",
                        message: "Sequential Scan on \"\(rel)\" (\(formatNumber(rowCount)) rows)\(filterDesc)",
                        suggestion: "An index on the filtered column(s) could avoid scanning the full table."
                    ))
                }
            }
        }

        // Bad row estimates
        for node in allNodes where node.isBadEstimate {
            if let rel = node.relationName ?? (node.indexName.map { "index \($0)" }) {
                let ratio = node.rowEstimateAccuracy ?? 0
                let direction = ratio > 1 ? "underestimated" : "overestimated"
                warnings.append(PlanWarning(
                    severity: .error,
                    icon: "exclamationmark.triangle.fill",
                    message: "Planner \(direction) rows for \"\(rel)\" by \(String(format: "%.0f", max(ratio, 1/ratio)))×",
                    suggestion: "Run ANALYZE on this table to update planner statistics."
                ))
            }
        }

        // High rows removed by filter (inefficient filtering)
        for node in allNodes {
            if let removed = node.rowsRemovedByFilter, removed > 1000 {
                let scanned = (node.totalActualRows ?? node.planRows) + removed
                let filterRatio = scanned > 0 ? Double(removed) / Double(scanned) : 0
                if filterRatio > 0.5 {
                    let rel = node.relationName ?? node.nodeType
                    warnings.append(PlanWarning(
                        severity: .warning,
                        icon: "line.3.horizontal.decrease",
                        message: "\(formatNumber(removed)) rows removed by filter on \"\(rel)\"",
                        suggestion: "A more selective index could reduce the rows scanned."
                    ))
                }
            }
        }

        // Disk reads (cache misses)
        if plan.wasAnalyze {
            let totalRead = allNodes.compactMap(\.sharedRead).reduce(0, +)
            let totalHit = allNodes.compactMap(\.sharedHit).reduce(0, +)
            if totalRead > 100 && totalHit > 0 {
                let hitRate = Double(totalHit) / Double(totalHit + totalRead) * 100
                if hitRate < 90 {
                    warnings.append(PlanWarning(
                        severity: .info,
                        icon: "internaldrive",
                        message: "Buffer cache hit rate: \(String(format: "%.0f", hitRate))% (\(formatNumber(totalRead)) disk reads)",
                        suggestion: "Frequently accessed data is being read from disk. Consider increasing shared_buffers."
                    ))
                }
            }
        }

        return warnings
    }

    private struct PlanWarning: Identifiable {
        let id = UUID()
        let severity: Severity
        let icon: String
        let message: String
        let suggestion: String

        enum Severity {
            case info, warning, error

            var color: Color {
                switch self {
                case .info: return .blue
                case .warning: return .orange
                case .error: return .red
                }
            }
        }
    }

    private func warningsPanel(_ warnings: [PlanWarning]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(warnings) { warning in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: warning.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(warning.severity.color)
                        .frame(width: 16, height: 16)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(warning.message)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                        Text(warning.suggestion)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
        }
        .background(Color.orange.opacity(0.03))
    }

    /// Shown when ANALYZE finds no performance issues — gives users
    /// positive confirmation that the plan is healthy.
    private var healthyPlanBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.green)
            Text("No performance issues detected")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            if let execTime = plan.executionTime {
                Text("·")
                    .foregroundStyle(.quaternary)
                Text("Total: \(formatMs(execTime))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.03))
    }

    // MARK: - Tree View

    private var treeView: some View {
        VStack(alignment: .leading, spacing: 0) {
            treeColumnHeaders

            ScrollView(.vertical) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let flatNodes = flattenTree(plan.rootNode, depth: 0)
                        ForEach(Array(flatNodes.enumerated()), id: \.element.node.id) { index, entry in
                            nodeRow(entry.node, depth: entry.depth, index: index)
                        }
                    }
                    .frame(minWidth: 800)
                }
            }

            Spacer(minLength: 0)
        }
        .background(GlintDesign.appBackground.opacity(0.5))
    }

    /// Pinned column headers for the tree grid — matches the pattern used in
    /// TableStructureView and QueryResultGridView throughout the app.
    private var treeColumnHeaders: some View {
        HStack(spacing: 0) {
            Text("OPERATION")
                .frame(minWidth: 280, alignment: .leading)
            if plan.wasAnalyze {
                Text("TIME %")
                    .frame(width: 140, alignment: .leading)
                    .padding(.horizontal, 8)
            }
            Text("ROWS (EST → ACT)")
                .frame(minWidth: 180, alignment: .leading)
                .padding(.horizontal, 8)
            if plan.wasAnalyze {
                Text("TIME")
                    .frame(width: 80, alignment: .trailing)
                    .padding(.horizontal, 8)
                Text("BUFFERS")
                    .frame(minWidth: 120, alignment: .leading)
                    .padding(.horizontal, 8)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    // MARK: - Node Row

    private func nodeRow(_ node: ExplainNode, depth: Int, index: Int) -> some View {
        let totalTime = plan.totalActualTime ?? 1.0
        let timePercent = totalTime > 0 ? node.exclusiveTimeMs / totalTime : 0
        let isHovered = hoveredNodeId == node.id
        let isBottleneck = plan.bottleneckNode?.id == node.id && plan.wasAnalyze

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                // Indentation + disclosure triangle
                HStack(spacing: 0) {
                    Spacer().frame(width: CGFloat(depth) * 20)

                    if !node.children.isEmpty {
                        Button { toggleExpand(node.id) } label: {
                            Image(systemName: expandedNodes.contains(node.id) ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Spacer().frame(width: 16)
                    }
                }

                // Node icon + type label
                HStack(spacing: 6) {
                    nodeIcon(node)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(nodeLabel(node))
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        if let detail = inlineDetail(node) {
                            Text(detail)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .frame(minWidth: max(1, 260 - CGFloat(depth) * 20), alignment: .leading)

                // Cost bar with percentage label
                if plan.wasAnalyze {
                    costBar(percent: timePercent, isBottleneck: isBottleneck)
                        .frame(width: 140)
                        .padding(.horizontal, 8)
                }

                // Rows: estimated vs actual
                rowsCell(node)
                    .frame(minWidth: 180, alignment: .leading)
                    .padding(.horizontal, 8)

                // Exclusive time
                if plan.wasAnalyze {
                    timeCell(node, totalTime: totalTime)
                        .frame(width: 80, alignment: .trailing)
                        .padding(.horizontal, 8)

                    // Buffer stats
                    buffersCell(node)
                        .frame(minWidth: 120, alignment: .leading)
                        .padding(.horizontal, 8)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 16)
            .background(rowBackground(index: index, isHovered: isHovered, isBottleneck: isBottleneck))
            .onHover { hoveredNodeId = $0 ? node.id : nil }

            Divider().opacity(0.15).padding(.leading, CGFloat(depth) * 20 + 32)
        }
    }

    private func rowBackground(index: Int, isHovered: Bool, isBottleneck: Bool) -> some View {
        Group {
            if isBottleneck {
                Color.red.opacity(isHovered ? 0.10 : 0.05)
            } else if isHovered {
                Color.primary.opacity(0.04)
            } else if index % 2 == 1 {
                GlintDesign.alternatingRow.opacity(0.5)
            } else {
                Color.clear
            }
        }
    }

    // MARK: - Tree Flattening

    /// Flattens the tree respecting the expand/collapse state, producing a
    /// stable sequential index for correct alternating row colors.
    private struct FlatEntry {
        let node: ExplainNode
        let depth: Int
    }

    private func flattenTree(_ node: ExplainNode, depth: Int) -> [FlatEntry] {
        var result = [FlatEntry(node: node, depth: depth)]
        if expandedNodes.contains(node.id) {
            for child in node.children {
                result.append(contentsOf: flattenTree(child, depth: depth + 1))
            }
        }
        return result
    }

    // MARK: - Node Components

    private func nodeIcon(_ node: ExplainNode) -> some View {
        let (icon, color) = iconSpec(for: node)
        return Image(systemName: icon)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 18, height: 18)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }

    private func iconSpec(for node: ExplainNode) -> (String, Color) {
        let type = node.nodeType.lowercased()

        // Scans
        if type.contains("seq scan")                          { return ("magnifyingglass", .orange) }
        if type.contains("index only scan")                   { return ("bolt.fill", .green) }
        if type.contains("index scan")                        { return ("bolt", .green) }
        if type.contains("bitmap heap scan")                  { return ("square.grid.3x3.fill", .blue) }
        if type.contains("bitmap index scan")                 { return ("square.grid.3x3", .blue) }

        // Joins
        if type.contains("nested loop")                       { return ("arrow.triangle.merge", .purple) }
        if type.contains("hash join")                         { return ("arrow.triangle.merge", .purple) }
        if type.contains("merge join")                        { return ("arrow.triangle.merge", .purple) }

        // Aggregation & Sorting
        if type.contains("sort")                              { return ("arrow.up.arrow.down", .cyan) }
        if type.contains("aggregate") || type.contains("group") { return ("sum", .indigo) }
        if type.contains("unique")                            { return ("sparkle", .indigo) }
        if type.contains("window")                            { return ("rectangle.split.3x1", .indigo) }

        // Hash operations
        if type.contains("hash")                              { return ("number", .teal) }

        // Control nodes
        if type.contains("limit")                             { return ("stop.fill", .gray) }
        if type.contains("result")                            { return ("checkmark.circle", .gray) }
        if type.contains("append")                            { return ("plus.rectangle.on.rectangle", .brown) }
        if type.contains("subquery") || type.contains("cte")  { return ("arrow.turn.down.right", .mint) }
        if type.contains("materialize")                       { return ("square.stack.3d.up", .pink) }
        if type.contains("gather")                            { return ("arrow.triangle.branch", .yellow) }

        // DML operations
        if type.contains("modify") || type.contains("insert") || type.contains("update") || type.contains("delete") {
            return ("pencil", .red)
        }

        return ("gearshape", .secondary)
    }

    private func nodeLabel(_ node: ExplainNode) -> String {
        var parts: [String] = []

        if let join = node.joinType {
            parts.append(join)
        }
        parts.append(node.nodeType)

        if let rel = node.relationName {
            parts.append("on")
            parts.append(rel)
            if let alias = node.alias, alias != rel {
                parts.append("(\(alias))")
            }
        }

        if let idx = node.indexName {
            parts.append("using")
            parts.append(idx)
        }

        return parts.joined(separator: " ")
    }

    /// Compact inline detail shown directly beneath the node label.
    private func inlineDetail(_ node: ExplainNode) -> String? {
        if let cond = node.indexCondition { return cond }
        if let cond = node.hashCondition { return cond }
        if let filter = node.filter {
            if let removed = node.rowsRemovedByFilter, removed > 0 {
                return "\(filter)  (removed \(formatNumber(removed)))"
            }
            return filter
        }
        if let keys = node.sortKey, !keys.isEmpty {
            return "Sort: \(keys.joined(separator: ", "))"
        }
        return nil
    }

    // MARK: - Cost Bar

    private func costBar(percent: Double, isBottleneck: Bool) -> some View {
        let clamped = min(max(percent, 0), 1.0)
        let barColor: Color
        if isBottleneck     { barColor = .red }
        else if clamped > 0.5 { barColor = .red }
        else if clamped > 0.2 { barColor = .orange }
        else                  { barColor = .green }

        return HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor.opacity(0.7))
                        .frame(width: max(2, geo.size.width * clamped), height: 6)
                }
            }
            .frame(width: 80, height: 6)

            Text(String(format: "%.0f%%", clamped * 100))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(barColor)
                .frame(width: 36, alignment: .trailing)
        }
    }

    // MARK: - Data Cells

    @ViewBuilder
    private func rowsCell(_ node: ExplainNode) -> some View {
        HStack(spacing: 4) {
            Text("Est \(formatNumber(node.planRows))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)

            if let actual = node.actualRows {
                Text("→")
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)

                let total = node.totalActualRows ?? actual
                Text("Act \(formatNumber(total))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(estimateColor(node))

                if node.isBadEstimate {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.red)
                        .help("Row estimate is off by more than 10×. Consider running ANALYZE on this table or updating statistics.")
                }

                // Show loop multiplier when > 1 — critical for nested loop plans
                if let loops = node.actualLoops, loops > 1 {
                    Text("×\(loops)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.orange)
                        .help("This node executed \(loops) times (loops). Per-loop: \(actual) rows.")
                }
            }
        }
    }

    private func estimateColor(_ node: ExplainNode) -> Color {
        guard let ratio = node.rowEstimateAccuracy else { return .primary }
        if ratio > 10.0 || ratio < 0.1 { return .red }
        if ratio > 5.0  || ratio < 0.2 { return .orange }
        return .green
    }

    @ViewBuilder
    private func timeCell(_ node: ExplainNode, totalTime: Double) -> some View {
        let exclusive = node.exclusiveTimeMs
        let percent = totalTime > 0 ? exclusive / totalTime : 0
        let color: Color = percent > 0.5 ? .red : (percent > 0.2 ? .orange : .secondary)

        Text(formatMs(exclusive))
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
    }

    @ViewBuilder
    private func buffersCell(_ node: ExplainNode) -> some View {
        let hit = node.sharedHit ?? 0
        let read = node.sharedRead ?? 0
        let written = node.sharedWritten ?? 0

        if hit > 0 || read > 0 || written > 0 {
            HStack(spacing: 6) {
                if hit > 0 {
                    bufferStat("H", value: hit, color: .green)
                }
                if read > 0 {
                    bufferStat("R", value: read, color: .orange)
                }
                if written > 0 {
                    bufferStat("W", value: written, color: .red)
                }
            }
        } else {
            Text("—")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
        }
    }

    private func bufferStat(_ label: String, value: Int64, color: Color) -> some View {
        HStack(spacing: 2) {
            Text("\(label):")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(formatNumber(value))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    // MARK: - Raw View

    private func rawView(_ text: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    showCopiedToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showCopiedToast = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showCopiedToast ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(showCopiedToast ? "Copied" : "Copy")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(showCopiedToast ? .green : .primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(8)
            }

            ScrollView {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
    }

    // MARK: - Shared Components

    private func statusPill(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }

    private func metricBadge(_ label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Formatting

    private func formatMs(_ ms: Double) -> String {
        if ms >= 1000 { return String(format: "%.1fs", ms / 1000) }
        if ms >= 1    { return String(format: "%.1fms", ms) }
        return String(format: "%.2fms", ms)
    }

    private func formatNumber(_ n: Int64) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 10_000    { return String(format: "%.0fK", Double(n) / 1_000) }
        if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    // MARK: - State Management

    private func toggleExpand(_ id: UUID) {
        if expandedNodes.contains(id) {
            expandedNodes.remove(id)
        } else {
            expandedNodes.insert(id)
        }
    }

    private func expandAllNodes(_ node: ExplainNode) {
        expandedNodes.insert(node.id)
        for child in node.children {
            expandAllNodes(child)
        }
    }
}
