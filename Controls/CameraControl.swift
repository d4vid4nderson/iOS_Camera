import AppIntents
import SwiftUI
import WidgetKit

@main
struct FilmExposuresControls: WidgetBundle {
    var body: some Widget {
        CameraControl()
    }
}

/// A camera button for Control Center and the two buttons at the bottom of the Lock
/// Screen. Tapping it opens Film Exposures on the viewfinder; from the Lock Screen the
/// phone asks for Face ID first.
struct CameraControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.davidanderson.retrocam.controls.camera") {
            ControlWidgetButton(action: OpenCameraIntent()) {
                Label("Film Exposures", systemImage: "camera.aperture")
            }
        }
        .displayName("Film Exposures")
        .description("Open the Film Exposures camera.")
    }
}
