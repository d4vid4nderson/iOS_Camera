import AppIntents
import Foundation

/// Opens Film Exposures on the camera. The action behind the Control Center and Lock
/// Screen control (and a Shortcuts action). It's built into both the app and the controls
/// extension: the control names it, and the app is what runs it, after opening.
struct OpenCameraIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Film Exposures"
    static let description = IntentDescription("Opens the Film Exposures camera.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // The app closes whatever's open over the viewfinder (your rolls, your profile, a
        // shared roll), so the control always lands on the camera.
        NotificationCenter.default.post(name: .showCamera, object: nil)
        return .result()
    }
}

extension Notification.Name {
    /// Posted when the camera control opens the app.
    static let showCamera = Notification.Name("FilmExposures.showCamera")
}
