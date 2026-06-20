import SwiftUI

struct ExtractSheet: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "shippingbox")
                    .font(.title3)
                    .foregroundStyle(.tint)
                Text(L10n.t("Extract Wallpapers", settings.appLanguage))
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(L10n.t("Close", settings.appLanguage)) { dismiss() }
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
                    Button(L10n.t("Stop", settings.appLanguage)) {
                        viewModel.stopExtraction()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button(L10n.t(viewModel.copyOnly ? "Copy Selected" : "Extract Selected", settings.appLanguage)) {
                        Task { await viewModel.extract() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.selectedIDs.isEmpty || viewModel.outputDirectory == nil)

                    if !viewModel.copyOnly {
                        Button(L10n.t("Extract All", settings.appLanguage)) {
                            Task { await viewModel.extractAll() }
                        }
                        .disabled(viewModel.selectedDirectory == nil || viewModel.outputDirectory == nil)
                    }
                }

                Spacer()
                Button(L10n.t("Close", settings.appLanguage)) { dismiss() }
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
                Text(String(format: L10n.t("%d wallpapers selected", settings.appLanguage), viewModel.selectedIDs.count))
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let dir = viewModel.selectedDirectory {
                HStack {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(String(format: L10n.t("Input: %@", settings.appLanguage), dir.path))
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
            Text(L10n.t("Output Directory", settings.appLanguage))
                .fontWeight(.medium)

            HStack {
                if let out = viewModel.outputDirectory {
                    Text(out.path)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(L10n.t("Not set", settings.appLanguage)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.t("Choose...", settings.appLanguage)) {
                    viewModel.selectOutputDirectory()
                }
            }
            .padding(10)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("Options", settings.appLanguage)).fontWeight(.medium)

            Toggle(L10n.t("Copy only", settings.appLanguage), isOn: Binding(
                get: { viewModel.copyOnly }, set: { viewModel.copyOnly = $0 }))
                .fontWeight(.medium)
                .tint(.green)

            if !viewModel.copyOnly {
                Toggle(L10n.t("Single directory (-s)", settings.appLanguage), isOn: Binding(
                get: { viewModel.singleDir }, set: { viewModel.singleDir = $0 }))
            Toggle(L10n.t("Recursive (-r)", settings.appLanguage), isOn: Binding(
                get: { viewModel.recursive }, set: { viewModel.recursive = $0 }))
            Toggle(L10n.t("Copy project.json (-c)", settings.appLanguage), isOn: Binding(
                get: { viewModel.copyProject }, set: { viewModel.copyProject = $0 }))
            Toggle(L10n.t("Use name for output (-n)", settings.appLanguage), isOn: Binding(
                get: { viewModel.useName }, set: { viewModel.useName = $0 }))
            Toggle(L10n.t("Overwrite existing", settings.appLanguage), isOn: Binding(
                get: { viewModel.overwrite }, set: { viewModel.overwrite = $0 }))
            Toggle(L10n.t("Debug info (-d)", settings.appLanguage), isOn: Binding(
                get: { viewModel.debugInfo }, set: { viewModel.debugInfo = $0 }))
            Toggle(L10n.t("Convert TEX (-t)", settings.appLanguage), isOn: Binding(
                get: { viewModel.convertTEX }, set: { viewModel.convertTEX = $0 }))
            Toggle(L10n.t("No TEX convert", settings.appLanguage), isOn: Binding(
                get: { viewModel.noTEXConvert }, set: { viewModel.noTEXConvert = $0 }))

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("Ignore extensions (-i):", settings.appLanguage)).font(.caption)
                TextField("e.g. .png,.jpg", text: Binding(
                    get: { viewModel.ignoreExtensions }, set: { viewModel.ignoreExtensions = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(L10n.t("Ignore extensions", settings.appLanguage))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("Only extensions (-e):", settings.appLanguage)).font(.caption)
                TextField("e.g. .png,.jpg", text: Binding(
                    get: { viewModel.onlyExtensions }, set: { viewModel.onlyExtensions = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(L10n.t("Only extensions", settings.appLanguage))
            }
            }
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("Output", settings.appLanguage)).fontWeight(.medium)

            ScrollView {
                Text(viewModel.extractionOutput.isEmpty ? L10n.t("Ready...", settings.appLanguage) : viewModel.extractionOutput)
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
