import SwiftUI

struct NewCollectionSheet: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var collectionName = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 28))
                .foregroundColor(.accentColor)

            Text("New Collection")
                .font(.headline)

            TextField("Collection name", text: $collectionName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)
                .accessibilityLabel("Collection name")

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Button("Create") {
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
