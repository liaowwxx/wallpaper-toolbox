import AppKit
import SwiftUI

struct ScenePropertiesSheet: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    let item: WallpaperItem

    @State private var rows: [SceneWallpaperProperty] = []
    @State private var isLoading = true
    @State private var applyTask: Task<Void, Never>?

    private let labelWidth: CGFloat = 120

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Group {
                if isLoading {
                    loadingState
                } else if rows.isEmpty {
                    emptyState
                } else {
                    propertiesList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !rows.isEmpty {
                Divider()
                footer
            }
        }
        .frame(width: 460, height: 560)
        .task { loadProperties() }
        .onDisappear { applyTask?.cancel() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text("Scene Properties")
                    .font(.headline)
                Text(item.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Close")
        }
        .padding(16)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading properties...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No editable scene properties")
                .font(.headline)
            Text("This wallpaper does not declare configurable properties in project.json.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(24)
    }

    private var propertiesList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(rows) { row in
                    propertyRow(row)
                }
            }
            .padding(16)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                resetAll()
            } label: {
                Label("Reset All", systemImage: "arrow.counterclockwise")
            }

            Spacer()

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    @ViewBuilder
    private func propertyRow(_ row: SceneWallpaperProperty) -> some View {
        switch row.type {
        case "group":
            sectionHeader(row.text ?? row.key)
        case "description", "label":
            if let text = row.text, !text.isEmpty {
                descriptionRow(text)
            }
        case "slider":
            rowCard {
                sliderRow(row)
            }
        case "bool":
            rowCard {
                toggleRow(row)
            }
        case "color":
            rowCard {
                colorRow(row)
            }
        case "combo":
            rowCard {
                comboRow(row)
            }
        case "file":
            rowCard {
                fileRow(row)
            }
        default:
            rowCard {
                textRow(row)
            }
        }
    }

    private func sliderRow(_ row: SceneWallpaperProperty) -> some View {
        let minimum = row.min ?? 0
        let maximum = max(row.max ?? 100, minimum)
        let step = max(row.step ?? 1, 0.0001)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label(for: row))
                    .font(.callout)
                    .frame(width: labelWidth, alignment: .leading)
                Spacer()
                Text(sliderDisplayText(row))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 48, alignment: .trailing)
            }
            Slider(value: sliderBinding(for: row), in: minimum...maximum, step: step)
                .padding(.leading, labelWidth + 8)
        }
    }

    private func toggleRow(_ row: SceneWallpaperProperty) -> some View {
        Toggle(isOn: boolBinding(for: row)) {
            Text(label(for: row))
                .font(.callout)
        }
        .toggleStyle(.switch)
    }

    private func colorRow(_ row: SceneWallpaperProperty) -> some View {
        HStack {
            Text(label(for: row))
                .font(.callout)
                .frame(width: labelWidth, alignment: .leading)
            Spacer()
            ColorPicker("", selection: colorBinding(for: row), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 80)
        }
    }

    private func comboRow(_ row: SceneWallpaperProperty) -> some View {
        fieldRow(row) {
            Picker("", selection: stringBinding(for: row)) {
                ForEach(optionKeys(for: row), id: \.self) { key in
                    Text(row.options?[key] ?? key).tag(key)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 220)
        }
    }

    private func textRow(_ row: SceneWallpaperProperty) -> some View {
        fieldRow(row) {
            TextField("", text: stringBinding(for: row))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
        }
    }

    private func fileRow(_ row: SceneWallpaperProperty) -> some View {
        fieldRow(row) {
            HStack(spacing: 8) {
                Text(currentValue(for: row.id).stringValue.isEmpty ? "Not selected" : URL(fileURLWithPath: currentValue(for: row.id).stringValue).lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Button {
                    chooseFile(for: row)
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Choose file")
            }
            .frame(maxWidth: 240, alignment: .trailing)
        }
    }

    private func fieldRow<Content: View>(_ row: SceneWallpaperProperty, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label(for: row))
                .font(.callout)
                .frame(width: labelWidth, alignment: .leading)
            Spacer(minLength: 8)
            content()
        }
    }

    private func rowCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(12)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 6)
    }

    private func descriptionRow(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private func loadProperties() {
        isLoading = true
        rows = SceneWallpaperPropertiesService.loadVisibleProperties(for: item.path)
        isLoading = false
    }

    private func updateProperty(_ key: String, value: ScenePropertyValue) {
        guard rows.contains(where: { $0.key == key }) else { return }
        try? SceneWallpaperPropertiesService.setProperty(key: key, value: value, for: item.path)
        rows = SceneWallpaperPropertiesService.loadVisibleProperties(for: item.path)
        scheduleApply()
    }

    private func resetAll() {
        try? SceneWallpaperPropertiesService.resetAllProperties(for: item.path)
        loadProperties()
        scheduleApply()
    }

    private func scheduleApply() {
        applyTask?.cancel()
        applyTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            viewModel.refreshSceneWallpaperProperties(for: item)
        }
    }

    private func chooseFile(for row: SceneWallpaperProperty) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            updateProperty(row.id, value: .string(url.path))
        }
    }

    private func label(for row: SceneWallpaperProperty) -> String {
        let raw = row.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw?.isEmpty == false ? raw! : row.key
    }

    private func optionKeys(for row: SceneWallpaperProperty) -> [String] {
        let keys = Array((row.options ?? [:]).keys)
        if keys.contains(row.currentValue.stringValue) {
            return keys.sorted()
        }
        return ([row.currentValue.stringValue] + keys).filter { !$0.isEmpty }.sorted()
    }

    private func currentValue(for key: String) -> ScenePropertyValue {
        rows.first(where: { $0.key == key })?.currentValue ?? .null
    }

    private func sliderBinding(for row: SceneWallpaperProperty) -> Binding<Double> {
        Binding(
            get: {
                switch currentValue(for: row.id) {
                case .number(let value):
                    return value
                case .string(let value):
                    return Double(value) ?? (row.min ?? 0)
                default:
                    return row.min ?? 0
                }
            },
            set: { updateProperty(row.id, value: .number($0)) }
        )
    }

    private func boolBinding(for row: SceneWallpaperProperty) -> Binding<Bool> {
        Binding(
            get: {
                switch currentValue(for: row.id) {
                case .bool(let value):
                    return value
                case .number(let value):
                    return value != 0
                case .string(let value):
                    return value.lowercased() == "true" || value == "1"
                case .null:
                    return false
                }
            },
            set: { updateProperty(row.id, value: .bool($0)) }
        )
    }

    private func stringBinding(for row: SceneWallpaperProperty) -> Binding<String> {
        Binding(
            get: { currentValue(for: row.id).stringValue },
            set: { updateProperty(row.id, value: .string($0)) }
        )
    }

    private func colorBinding(for row: SceneWallpaperProperty) -> Binding<Color> {
        Binding(
            get: { Self.color(from: currentValue(for: row.id).stringValue) },
            set: { updateProperty(row.id, value: .string(Self.string(from: $0))) }
        )
    }

    private func sliderDisplayText(_ row: SceneWallpaperProperty) -> String {
        let value: Double
        switch currentValue(for: row.id) {
        case .number(let number):
            value = number
        case .string(let string):
            value = Double(string) ?? 0
        default:
            value = 0
        }
        if abs(value.rounded() - value) < 0.0001 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.2f", value)
    }

    private static func color(from raw: String) -> Color {
        let values = raw.split(whereSeparator: \.isWhitespace).compactMap { Double($0) }
        guard values.count >= 3 else { return .white }
        return Color(.sRGB, red: values[0], green: values[1], blue: values[2], opacity: values.count >= 4 ? values[3] : 1)
    }

    private static func string(from color: Color) -> String {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return String(format: "%.5f %.5f %.5f", nsColor.redComponent, nsColor.greenComponent, nsColor.blueComponent)
    }
}
