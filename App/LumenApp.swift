import SwiftUI

@main
struct LumenApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    IncomingURLStore.shared.enqueue(url.absoluteString)
                }
        }
    }
}
