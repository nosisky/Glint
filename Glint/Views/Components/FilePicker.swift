//
//  FilePicker.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//

import SwiftUI
import UniformTypeIdentifiers

/// A UI component that displays a path (or placeholder) and a button to pick a file.
struct FilePicker: View {
    let title: String
    @Binding var path: String?
    var allowedContentTypes: [UTType] = [.data, .plainText]

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .frame(width: 80, alignment: .trailing)
                .foregroundColor(.secondary)

            Button("Choose…") {
                selectFile()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )

            if let currentPath = path, !currentPath.isEmpty {
                let filename = URL(fileURLWithPath: currentPath).lastPathComponent
                Text(filename)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(.primary)
                
                Button {
                    path = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Text("None selected")
                    .foregroundColor(.secondary)
                    .italic()
            }
            Spacer()
        }
        .font(.system(size: 12))
    }

    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = allowedContentTypes
        
        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
        }
    }
}
