import SwiftUI

/// The look of the profile and people screens: plain system type in sentence case, grouped
/// rounded cards of rows, and capsule buttons (orange filled for the main action, grey for
/// the rest). The camera itself keeps its monospaced, uppercase controls.
enum ProfileStyle {
    static let background = Color(white: 0.09)
    static let card = Color(white: 0.13)
    static let field = Color(white: 0.16)
    static let button = Color(white: 0.17)
    static let divider = Color(white: 0.2)
    static let faint = Color(white: 0.4)
    static let destructive = Color(red: 1, green: 0.45, blue: 0.4)
}

/// A grouped card of rows (put `CardDivider()` between them).
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 14).fill(ProfileStyle.card))
    }
}

/// The hairline between rows in a `SettingsCard`.
struct CardDivider: View {
    var inset: CGFloat = 16

    var body: some View {
        Rectangle().fill(ProfileStyle.divider).frame(height: 0.5).padding(.leading, inset)
    }
}

/// A small grey heading over a card or field ("Photo", "Name", "Account").
struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
    }
}

/// A big section title ("People", "Your rolls").
struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
    }
}

/// The grey explanation under a field or card.
struct FootnoteText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.system(size: 13)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A capsule button: orange with black text for the main action, grey otherwise.
struct PillButton: View {
    let text: String
    var filled = false
    var accent: Color = Color(uiColor: Brand.orange)
    var compact = false
    var fullWidth = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PillLabel(text: text, filled: filled, accent: accent, compact: compact, fullWidth: fullWidth)
        }
        .buttonStyle(.plain)
    }
}

/// The look of `PillButton`, for labels inside a PhotosPicker, Menu or NavigationLink.
struct PillLabel: View {
    let text: String
    var filled = false
    var accent: Color = Color(uiColor: Brand.orange)
    var compact = false
    var fullWidth = true

    var body: some View {
        Text(text)
            .font(.system(size: compact ? 14 : 15, weight: .semibold))
            .lineLimit(1)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, compact ? 14 : 18)
            .padding(.vertical, compact ? 8 : 12)
            .background(Capsule().fill(filled ? accent : ProfileStyle.button))
            .foregroundStyle(filled ? .black : .white)
    }
}

/// A row of choices (tabs, or picking one of a few options): the chosen one in orange.
struct ChoicePills<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    var accent: Color = Color(uiColor: Brand.orange)
    var scrolls = false

    var body: some View {
        if scrolls {
            ScrollView(.horizontal, showsIndicators: false) { row }
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.0) { value, label in
                Button {
                    withAnimation(.snappy(duration: 0.15)) { selection = value }
                } label: {
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(selection == value ? accent : ProfileStyle.button))
                        .foregroundStyle(selection == value ? .black : .white)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
    }
}

/// A row in a `SettingsCard` with a switch.
struct ToggleRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool
    var accent: Color = Color(uiColor: Brand.orange)

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 16)).foregroundStyle(.white)
                if let detail {
                    Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(accent)
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

/// A row in a `SettingsCard` you tap: an optional icon, a label, an optional value, and a
/// chevron (or a checkmark when it's a choice).
struct NavRow: View {
    var icon: String?
    let title: String
    var value: String?
    var checked: Bool?
    var tint: Color = .white
    var accent: Color = Color(uiColor: Brand.orange)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 16, weight: .medium)).foregroundStyle(accent)
                        .frame(width: 24)
                }
                Text(title).font(.system(size: 16)).foregroundStyle(tint)
                Spacer(minLength: 8)
                if let value {
                    Text(value).font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(1)
                }
                if let checked {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent).opacity(checked ? 1 : 0)
                } else {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ProfileStyle.faint)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked == true ? .isSelected : [])
    }
}

/// When a list is empty: an icon, a line saying so, and what to do about it.
struct EmptyState: View {
    let icon: String
    let title: String
    var detail: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 34, weight: .regular)).foregroundStyle(ProfileStyle.faint)
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail).font(.system(size: 14)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }
}

/// A text field in the profile style: a rounded grey box, optional prefix ("@").
struct ProfileField: View {
    var prefix: String?
    let prompt: String
    @Binding var text: String
    var capitalization: TextInputAutocapitalization = .never
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 1) {
            if let prefix { Text(prefix).font(.system(size: 16, weight: .medium)).foregroundStyle(.secondary) }
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(ProfileStyle.faint))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 14).fill(ProfileStyle.card))
    }
}

/// A short message after something happened ("Saved", or what went wrong).
struct NoteText: View {
    let text: String
    var accent: Color = Color(uiColor: Brand.orange)

    var body: some View {
        Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(accent)
            .fixedSize(horizontal: false, vertical: true)
    }
}
