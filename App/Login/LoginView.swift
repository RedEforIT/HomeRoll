import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("serverURL") private var server = ""
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.07, blue: 0.16), .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 64)).symbolRenderingMode(.multicolor)
                Text(String(localized: "HomeRoll")).font(.system(size: 40, weight: .bold))
                Text(String(localized: "Deine Mediathek auf deinem eigenen Server")).foregroundStyle(.secondary)
                VStack(spacing: 12) {
                    field(String(localized: "Server, z. B. https://fotos.example.com"), text: $server, icon: "server.rack")
                        .textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
                    field(String(localized: "E-Mail"), text: $email, icon: "person")
                        .textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled()
                    HStack {
                        Image(systemName: "lock").frame(width: 24).foregroundStyle(.secondary)
                        SecureField(String(localized: "Passwort"), text: $password).textContentType(.password)
                    }
                    .padding(.horizontal, 18).frame(height: 54)
                    .glassEffect(.regular, in: .capsule)
                }
                .padding(.top, 20)
                if let error { Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center) }
                Button { Task { await login() } } label: {
                    Group { if busy { ProgressView() } else { Text(String(localized: "Anmelden")).font(.headline) } }
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.glassProminent)
                .disabled(busy || email.isEmpty || password.isEmpty)
                Spacer(); Spacer()
            }
            .padding(.horizontal, 28)
        }
    }

    private func field(_ title: String, text: Binding<String>, icon: String) -> some View {
        HStack {
            Image(systemName: icon).frame(width: 24).foregroundStyle(.secondary)
            TextField(title, text: text)
        }
        .padding(.horizontal, 18).frame(height: 54)
        .glassEffect(.regular, in: .capsule)
    }

    private func login() async {
        busy = true; error = nil; defer { busy = false }
        do {
            let r = try await ImmichClient.shared.login(server: server, email: email, password: password)
            app.userName = r.name
            app.loggedIn = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}
