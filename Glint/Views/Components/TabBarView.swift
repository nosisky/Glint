import SwiftUI

struct TabBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                @Bindable var state = appState
                
                ForEach(appState.workspaceTabs) { tab in
                    WorkspaceTabItem(tab: tab, isActive: appState.activeWorkspaceTabId == tab.id) {
                        appState.activeWorkspaceTabId = tab.id
                    } onClose: {
                        appState.closeTab(id: tab.id)
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct WorkspaceTabItem: View {
    let tab: WorkspaceTab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false
    @State private var isHoveringClose = false

    var body: some View {
        HStack(spacing: 8) {
            // Icon
            if tab.selectedFunction != nil {
                Image(systemName: "f.cursive.circle")
                    .font(.system(size: 11))
                    .foregroundColor(isActive ? .accentColor : .secondary)
            } else if tab.selectedTable != nil {
                Image(systemName: "tablecells")
                    .font(.system(size: 11))
                    .foregroundColor(isActive ? .accentColor : .secondary)
            } else {
                Image(systemName: "square.dashed")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Text(tab.title)
                .font(.system(size: 12, weight: isActive ? .medium : .regular))
                .foregroundColor(isActive ? .primary : .secondary)
                .lineLimit(1)
                .frame(maxWidth: 160, alignment: .leading)
            
            // Close button
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(isHoveringClose ? .primary : .secondary)
                    .opacity(isHovering || isActive ? 1 : 0)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isHoveringClose ? Color(nsColor: .separatorColor).opacity(0.4) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHoveringClose = hovering
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 36)
        .background(
            ZStack {
                if isActive {
                    Color(nsColor: .controlBackgroundColor)
                } else if isHovering {
                    Color(nsColor: .separatorColor).opacity(0.2)
                }
            }
        )
        // Top accent line for active tab
        .overlay(alignment: .top) {
            if isActive {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        // Bottom mask to blend active tab with content area
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(height: 1)
                    .offset(y: 1) // Cover the divider below it
            }
        }
        // Right border divider
        .overlay(alignment: .trailing) {
            if !isActive {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.3))
                    .frame(width: 1)
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            onSelect()
        }
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.1), value: isActive)
        .animation(.easeInOut(duration: 0.1), value: isHovering)
    }
}
