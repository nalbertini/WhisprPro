import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Text("Models").tabItem { Label("Models", systemImage: "cpu") }
            Text("General").tabItem { Label("General", systemImage: "gear") }
            Text("Export").tabItem { Label("Export", systemImage: "square.and.arrow.up") }
        }
        .frame(width: 500, height: 300)
    }
}
