import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ConnectionSettingsView()
                .tabItem {
                    Label("Connection", systemImage: "network")
                }

            OutputSettingsView()
                .tabItem {
                    Label("Output", systemImage: "folder")
                }

            AdvancedSettingsView()
                .tabItem {
                    Label("Advanced", systemImage: "gearshape.2")
                }
        }
        .frame(width: 480, height: 400)
    }
}
