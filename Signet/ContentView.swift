import SwiftUI

enum SignetTab: Hashable {
    case home, certificates, apps, settings
}

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedTab: SignetTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(SignetTab.home)

            CertificatesView()
                .tabItem { Label("Certificates", systemImage: "lock.shield.fill") }
                .tag(SignetTab.certificates)

            IPAsView()
                .tabItem { Label("Apps", systemImage: "square.stack.3d.up.fill") }
                .tag(SignetTab.apps)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(SignetTab.settings)
        }
        .tint(.blue)
    }
}
