import SwiftUI
import Observation

struct ServerSettingsView: View {
    @Environment(STAppViewModel.self) private var appViewModel

    @State private var serverURL = ""
    @State private var authMode: STAuthMode = .none
    @State private var basicUsername = ""
    @State private var basicPassword = ""
    @State private var userHandle = ""
    @State private var userPassword = ""
    @State private var allowSelfSigned = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("e.g. 192.168.1.100:8000", text: $serverURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .textContentType(.URL)
                    Toggle("Allow self-signed certificates", isOn: $allowSelfSigned)
                }

                Section("Authentication") {
                    Picker("Auth Mode", selection: $authMode) {
                        ForEach(STAuthMode.allCases, id: \.self) { mode in Text(mode.displayName).tag(mode) }
                    }
                    switch authMode {
                    case .basicAuth:
                        TextField("Username", text: $basicUsername).autocapitalization(.none).disableAutocorrection(true)
                        SecureField("Password", text: $basicPassword)
                    case .userAccount:
                        TextField("Handle", text: $userHandle).autocapitalization(.none).disableAutocorrection(true)
                        SecureField("Password", text: $userPassword)
                    case .none: EmptyView()
                    }
                }

                if let error = appViewModel.errorMessage {
                    Section { Text(error).foregroundStyle(.red).font(.caption) }
                }

                Section {
                    Button(action: connect) {
                        HStack {
                            Spacer()
                            if appViewModel.isConnecting { ProgressView() } else { Text("Connect").bold() }
                            Spacer()
                        }
                    }
                    .disabled(serverURL.trimmingCharacters(in: .whitespaces).isEmpty || appViewModel.isConnecting)
                }
            }
            .navigationTitle("Connect to SillyTavern")
            .onAppear {
                let config = appViewModel.serverConfig
                serverURL = config.displayURL
                authMode = config.authMode
                basicUsername = config.basicAuthUsername
                userHandle = config.userHandle
                allowSelfSigned = config.allowSelfSignedCerts
            }
        }
    }

    private func connect() {
        var config = STServerConfig()
        config.serverURL = serverURL
        config.authMode = authMode
        config.basicAuthUsername = basicUsername
        config.basicAuthPassword = basicPassword
        config.userHandle = userHandle
        config.userPassword = userPassword
        config.allowSelfSignedCerts = allowSelfSigned
        appViewModel.saveAndConnect(config)
    }
}

#Preview {
    ServerSettingsView().environment(STAppViewModel())
}
