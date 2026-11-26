import Foundation

/// How a frame was shot: the film, the lens and everything set on the camera at the
/// moment of the shutter. Kept with the roll (settings.json) and shown under the frame
/// in the roll viewer.
///
/// Every field but the film is optional, so frames saved by an older build still load
/// when new settings are added.
struct FrameSettings: Codable, Equatable {
    /// The film's name, as it was called then.
    var film: String
    var iso: Int?
    /// The film had been adjusted from how it shipped (or was last saved).
    var filmEdited: Bool?
    /// 35 mm-equivalent focal length.
    var lens: Int?
    /// The lens was a crop of a wider camera.
    var lensCropped: Bool?
    var front: Bool?
    /// The open aperture's f-number; nil when it was stopped right down (no blur).
    var aperture: Double?
    /// Aperture blades; 0 is round.
    var blades: Int?
    /// The format's label ("35MM", "6×6").
    var format: String?
    /// "landscape" or "portrait".
    var orientation: String?
    var megapixels: Int?
    /// Exposure compensation in stops.
    var exposure: Double?
    /// "off", "auto" or "on".
    var flash: String?
    /// The GRAIN dial, in percent.
    var grain: Int?
    /// "none", "white", "black" or "slide".
    var border: String?
    /// Border width in percent of the print's short side.
    var borderWidth: Int?
    /// "off", "date" or "dateTime".
    var stamp: String?
    /// "instant", "rollEnd" or "nextMorning".
    var develop: String?
    var date: Date?

    private static let shotFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// The settings as label and value pairs, in the order they're shown. Anything that
    /// wasn't recorded is left out.
    var rows: [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        var filmText = film
        if let iso { filmText += " · ISO \(iso)" }
        if filmEdited == true { filmText += " · edited" }
        rows.append(("Film", filmText))

        if let lens {
            var text = "\(lens)mm"
            if lensCropped == true { text += " crop" }
            if front == true { text += " · front" }
            rows.append(("Lens", text))
        }
        if let aperture {
            let stop = Aperture(fNumber: aperture).label
            let shape = (blades ?? 0) >= 3 ? "\(blades ?? 0) blades" : "round"
            rows.append(("Aperture", "\(stop) · \(shape)"))
        } else if lens != nil {
            rows.append(("Aperture", Aperture(fNumber: Aperture.closed).label))
        }
        if let format {
            var text = format
            if let orientation { text += " · \(orientation)" }
            if let megapixels { text += " · \(megapixels) MP" }
            rows.append(("Format", text))
        }
        if let exposure {
            let thirds = (exposure * 3).rounded() / 3
            rows.append(("Exposure", thirds == 0 ? "0 EV" : String(format: "%+.1f EV", thirds)))
        }
        if let flash { rows.append(("Flash", flash.capitalized)) }
        if let grain { rows.append(("Grain", "\(grain)%")) }
        if let border {
            var text = border.capitalized
            if border != "none", let borderWidth { text += " · \(borderWidth)%" }
            rows.append(("Border", text))
        }
        if let stamp {
            let names = ["off": "Off", "date": "Date", "dateTime": "Date and time"]
            rows.append(("Date back", names[stamp] ?? stamp.capitalized))
        }
        if let develop {
            let names = ["instant": "Instant", "rollEnd": "Roll end", "nextMorning": "Next morning"]
            rows.append(("Develops", names[develop] ?? develop.capitalized))
        }
        if let date { rows.append(("Shot", Self.shotFormat.string(from: date))) }
        return rows
    }
}
