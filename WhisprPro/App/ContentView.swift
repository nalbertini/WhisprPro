import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            Text("Sidebar")
        } detail: {
            Text("Select a transcription")
        }
        .frame(minWidth: 800, minHeight: 500)
    }
}
