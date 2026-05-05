import SwiftUI

struct ImportWizardView: View {
    @State private var viewModel = ImportViewModel()
    @Environment(\.dismiss) var dismiss
    
    // Dependencies
    var appState: AppState
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Import Data")
                .font(.largeTitle)
                .bold()
            
            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }
            
            if let success = viewModel.successMessage {
                Text(success)
                    .foregroundColor(.green)
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
            }
            
            GroupBox("1. Select CSV File") {
                HStack {
                    Button("Choose File...") {
                        viewModel.selectFile()
                    }
                    .disabled(viewModel.isImporting)
                    
                    if let url = viewModel.selectedFileURL {
                        Text(url.lastPathComponent)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No file selected")
                            .foregroundColor(.secondary)
                    }
                    
                    if viewModel.isParsingFile {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            GroupBox("2. Select Destination Table") {
                HStack {
                    Picker("Table:", selection: $viewModel.selectedTable) {
                        ForEach(viewModel.availableTables, id: \.self) { table in
                            Text(table).tag(table)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .disabled(viewModel.isImporting || viewModel.availableTables.isEmpty)
                    .onChange(of: viewModel.selectedTable) { newValue in
                        Task {
                            if let pool = appState.connectionPool, let conn = try? await pool.getConnection() {
                                await viewModel.fetchColumns(for: newValue, connection: conn)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            if !viewModel.csvHeaders.isEmpty && !viewModel.tableColumns.isEmpty {
                GroupBox("3. Map Columns") {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("CSV Column")
                                .bold()
                                .frame(width: 150, alignment: .leading)
                            Text("Database Column")
                                .bold()
                        }
                        .padding(.bottom, 4)
                        
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach($viewModel.mappings) { $mapping in
                                    HStack {
                                        Text(mapping.csvColumnName)
                                            .frame(width: 150, alignment: .leading)
                                        
                                        Picker("", selection: $mapping.dbColumnName) {
                                            Text("Ignore").tag("")
                                            ForEach(viewModel.tableColumns, id: \.self) { col in
                                                Text(col).tag(col)
                                            }
                                        }
                                        .labelsHidden()
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            
            Spacer()
            
            HStack {
                if viewModel.isImporting {
                    ProgressView(value: viewModel.importProgress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(maxWidth: .infinity)
                    
                    Text("\(Int(viewModel.importProgress * 100))%")
                        .font(.caption)
                }
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                
                Button("Start Import") {
                    Task {
                        if let pool = appState.connectionPool, let conn = try? await pool.getConnection() {
                            viewModel.startImport(connection: conn)
                        } else {
                            viewModel.errorMessage = "No active database connection."
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedFileURL == nil || viewModel.selectedTable.isEmpty || viewModel.isImporting)
            }
        }
        .padding()
        .frame(width: 600, height: 650)
        .onAppear {
            Task {
                if let pool = appState.connectionPool, let conn = try? await pool.getConnection() {
                    await viewModel.fetchTables(connection: conn)
                } else {
                    viewModel.errorMessage = "No active database connection."
                }
            }
        }
    }
}
