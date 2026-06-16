import SwiftUI

struct ConnectionSettingsView: View {
    @Environment(RemoteLibraryViewModel.self) private var library

    var body: some View {
        @Bindable var library = library

        Form {
            Section {
                TextField("Server URL", text: $library.serverURLText)
                    .serverURLInputStyle()

                TextField("Username", text: $library.username)
                    .plainCredentialInputStyle()

                SecureField("Password", text: $library.password)
            } header: {
                Text("Windows Library")
            } footer: {
                Text("Point this at the Windows API URL shown by the server control panel.")
            }

            Section {
                Button {
                    Task { await library.connect() }
                } label: {
                    Label("Connect", systemImage: "network")
                }
                .disabled(library.isLoading)

                Button {
                    Task { await library.loadSampleLibrary() }
                } label: {
                    Label("Load Sample Manifest", systemImage: "doc.badge.gearshape")
                }
                .disabled(library.isLoading)
            }

            Section("Server Capabilities") {
                CapabilityRow(
                    title: "Range streaming",
                    isEnabled: library.manifest?.supportsRangeStreaming == true
                )
                CapabilityRow(
                    title: "Remote unpack jobs",
                    isEnabled: library.manifest?.supportsUnpackJobs == true
                )
                LabeledContent("Schema") {
                    Text(library.manifest.map { "\($0.schemaVersion)" } ?? "Unknown")
                }
                LabeledContent("Server") {
                    Text(library.manifest?.serverVersion ?? "Unknown")
                }
            }

            if let job = library.latestJob {
                Section("Latest Job") {
                    LabeledContent("Job") {
                        Text(job.id)
                    }
                    LabeledContent("State") {
                        Text(job.state)
                    }
                    if let message = job.message {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .statusOverlay()
    }
}

private extension View {
    @ViewBuilder
    func serverURLInputStyle() -> some View {
        #if os(iOS)
        keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self
        #endif
    }

    @ViewBuilder
    func plainCredentialInputStyle() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self
        #endif
    }
}

private struct CapabilityRow: View {
    let title: String
    let isEnabled: Bool

    var body: some View {
        HStack {
            Label(title, systemImage: isEnabled ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(isEnabled ? .primary : .secondary)
            Spacer()
        }
    }
}
