import SwiftUI

struct FunctionDetailView: View {
    let function: FunctionInfo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                // MARK: - Top Row (Name & Schema)
                HStack(spacing: 24) {
                    detailField(label: "FUNCTION NAME", value: function.name)
                    detailField(label: "SCHEMA", value: function.schema)
                    Spacer()
                }
                
                // MARK: - Middle Row (Return Type & Language)
                HStack(spacing: 24) {
                    detailField(label: "RETURN TYPE", value: function.returnType)
                    detailField(label: "LANGUAGE", value: function.language)
                    Spacer()
                }

                // MARK: - Function Definition
                VStack(alignment: .leading, spacing: 6) {
                    Text("FUNCTION DEFINITION")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    
                    Text(function.definition.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.system(size: 13, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                }

                // MARK: - Attributes
                VStack(alignment: .leading, spacing: 6) {
                    Text("ATTRIBUTES")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 12) {
                        attributeBadge(label: function.volatility.uppercased())
                        attributeBadge(label: function.isStrict ? "STRICT" : "CALLED ON NULL INPUT")
                        attributeBadge(label: function.isSecurityDefiner ? "SECURITY DEFINER" : "SECURITY INVOKER")
                    }
                }
                
                // MARK: - Arguments
                if !function.arguments.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ARGUMENTS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        
                        Text(function.arguments)
                            .font(.system(size: 13, design: .monospaced))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                    }
                }
            }
            .padding(24)
        }
        .background(GlintDesign.appBackground)
    }

    @ViewBuilder
    private func detailField(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.system(size: 13))
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .frame(minWidth: 160, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
        }
    }
    
    @ViewBuilder
    private func attributeBadge(label: String) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
    }
}
