   //
//  JSONEditorPopover.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//

import SwiftUI

struct JSONEditorPopover: View {
    let columnName: String
    let initialValue: String?
    let onClose: () -> Void
    let onSave: (String?) -> Void

    @State private var jsonText: String = ""
    @State private var formatError: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(columnName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text("JSONB")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(GlintDesign.panelBackground)
            .overlay(alignment: .bottom) { Divider() }
            
            // Editor
            ZStack(alignment: .topLeading) {
                TextEditor(text: $jsonText)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(GlintDesign.appBackground)
                    .padding(8)
                    .autocorrectionDisabled(true)
                    .onChange(of: jsonText) { _, _ in
                        formatError = nil // clear error on edit
                    }
                
                if jsonText.isEmpty && initialValue == nil {
                    Text("NULL")
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: 400, height: 300)
            
            if let err = formatError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Divider()
            
            // Footer
            HStack {
                Button(role: .destructive) {
                    onSave(nil)
                } label: {
                    Text("Set NULL")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(nsColor: .systemRed))
                
                Spacer()
                
                Button("Format JSON") {
                    formatJSON()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
                .padding(.trailing, 8)
                
                Button("Cancel") {
                    onClose()
                }
                .controlSize(.regular)
                
                Button("Save") {
                    // Pre-flight check: is it valid JSON? We don't block saving if invalid,
                    // but we can format it nicely.
                    onSave(jsonText.isEmpty ? nil : jsonText)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding(16)
            .background(GlintDesign.panelBackground)
        }
        .onAppear {
            if let val = initialValue {
                jsonText = prettify(val)
            }
        }
    }
    
    private func formatJSON() {
        let pretty = prettify(jsonText)
        if pretty == jsonText {
            // Might be invalid, check it
            if let data = jsonText.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) == nil {
                formatError = "Invalid JSON syntax."
            } else {
                formatError = nil
            }
        } else {
            jsonText = pretty
            formatError = nil
        }
    }

    private func prettify(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys, .fragmentsAllowed]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return text
        }
        return prettyString
    }
}
