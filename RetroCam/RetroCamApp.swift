import SwiftUI

@main
struct RetroCamApp: App {
    init() {
        // Signed out, no account details stay on the phone (your rolls do).
        Account.wipeIfSignedOut()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
