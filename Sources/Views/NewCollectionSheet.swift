import SwiftUI

struct NewCollectionSheet: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(SettingsStore.self) private var settings
    @State private var collectionName = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 28))
                .foregroundStyle(.tint)

            Text(L10n.t("New Collection", settings.appLanguage))
                .font(.headline)

            TextField(L10n.t("Collection name", settings.appLanguage), text: $collectionName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)
                .accessibilityLabel(L10n.t("Collection name", settings.appLanguage))

            HStack(spacing: 12) {
                Button(L10n.t("Cancel", settings.appLanguage)) { dismiss() }
                    .keyboardShortcut(.escape)

                Button(L10n.t("Create", settings.appLanguage)) {
                    let name = collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    viewModel.createCollection(name: name)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(32)
        .frame(width: 320, height: 200)
    }
}
