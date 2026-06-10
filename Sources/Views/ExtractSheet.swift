import SwiftUI

struct ExtractSheet: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "shippingbox")
                    .font(.title3)
                    .foregroundStyle(.tint)
                Text("Extract Wallpapers")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summarySection
                    outputSection
                    optionsSection
                    logSection
                }
                .padding()
            }

            Divider()

            HStack {
                if viewModel.isExtracting {
                    Button("Stop") {
                        viewModel.stopExtraction()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button(viewModel.copyOnly ? "Copy Selected" : "Extract Selected") {
                        Task { await viewModel.extract() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.selectedIDs.isEmpty || viewModel.outputDirectory == nil)

                    if !viewModel.copyOnly {
                        Button("Extract All") {
                            Task { await viewModel.extractAll() }
                        }
                        .disabled(viewModel.selectedDirectory == nil || viewModel.outputDirectory == nil)
                    }
                }

                Spacer()
                Button("Close") { dismiss() }
            }
            .padding()
        }
        .frame(width: 550, height: 650)
    }

    private var summarySection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "checkmark.rectangle")
                    .foregroundStyle(.tint)
                Text("\(viewModel.selectedIDs.count) wallpapers selected")
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let dir = viewModel.selectedDirectory {
                HStack {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text("Input: \(dir.path)")
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output Directory")
                .fontWeight(.medium)

            HStack {
                if let out = viewModel.outputDirectory {
                    Text(out.path)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("Not set").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Choose...") {
                    viewModel.selectOutputDirectory()
                }
            }
            .padding(10)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Options").fontWeight(.medium)

            Toggle("Copy only", isOn: Binding(
                get: { viewModel.copyOnly }, set: { viewModel.copyOnly = $0 }))
                .fontWeight(.medium)
                .tint(.green)

            if !viewModel.copyOnly {
                Toggle("Single directory (-s)", isOn: Binding(
                get: { viewModel.singleDir }, set: { viewModel.singleDir = $0 }))
            Toggle("Recursive (-r)", isOn: Binding(
                get: { viewModel.recursive }, set: { viewModel.recursive = $0 }))
            Toggle("Copy project.json (-c)", isOn: Binding(
                get: { viewModel.copyProject }, set: { viewModel.copyProject = $0 }))
            Toggle("Use name for output (-n)", isOn: Binding(
                get: { viewModel.useName }, set: { viewModel.useName = $0 }))
            Toggle("Overwrite existing", isOn: Binding(
                get: { viewModel.overwrite }, set: { viewModel.overwrite = $0 }))
            Toggle("Debug info (-d)", isOn: Binding(
                get: { viewModel.debugInfo }, set: { viewModel.debugInfo = $0 }))
            Toggle("Convert TEX (-t)", isOn: Binding(
                get: { viewModel.convertTex }, set: { viewModel.convertTex = $0 }))
            Toggle("No TEX convert", isOn: Binding(
                get: { viewModel.noTexConvert }, set: { viewModel.noTexConvert = $0 }))

            VStack(alignment: .leading, spacing: 4) {
                Text("Ignore extensions (-i):").font(.caption)
                TextField("e.g. .png,.jpg", text: Binding(
                    get: { viewModel.ignoreExts }, set: { viewModel.ignoreExts = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Ignore extensions")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Only extensions (-e):").font(.caption)
                TextField("e.g. .png,.jpg", text: Binding(
                    get: { viewModel.onlyExts }, set: { viewModel.onlyExts = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Only extensions")
            }
            }
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output").fontWeight(.medium)

            ScrollView {
                Text(viewModel.extractionOutput.isEmpty ? "Ready..." : viewModel.extractionOutput)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(viewModel.extractionOutput.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 200)
            .padding(8)
            .background(.regularMaterial)
            .compositingGroup()
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.quaternary, lineWidth: 0.5)
            )
        }
    }
}
