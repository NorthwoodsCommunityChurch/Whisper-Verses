import SwiftUI

/// Reusable broadcast-cockpit-style section header — ALL-CAPS label with
/// a leading brand-blue 14×2 rule. Used as the divider between groups in
/// the Settings window so they harmonize with the main app's Transcript /
/// Catch Feed headers.
struct SettingsSectionHeader: View {
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: Theme.Space.small) {
            Rectangle()
                .fill(Theme.Brand.blue)
                .frame(width: 14, height: 2)
            Text(title)
                .font(Theme.Typography.sectionHeader(10))
                .tracking(1.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Foreground.secondary)
            Spacer()
            trailing
        }
    }
}

/// A grouped settings panel — section header above, content below in a
/// rounded warm-black card. Replaces the system `Form` / `Section` look.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var trailing: AnyView? = nil

    init(_ title: String, trailing: AnyView? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.med) {
            SettingsSectionHeader(title: title, trailing: trailing)
            VStack(alignment: .leading, spacing: Theme.Space.med) {
                content()
            }
            .padding(Theme.Space.med)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Surface.panel)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.white.opacity(0.04), lineWidth: 1)
            }
        }
    }
}

/// A label + control row inside a SettingsSection. Tiny ALL-CAPS label
/// over the field, broadcast-style — keeps eye lines clean.
struct SettingsRow<Control: View>: View {
    let label: String
    @ViewBuilder var control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Theme.Typography.statusPill(9))
                .tracking(1.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Foreground.tertiary)
            control()
        }
    }
}

/// Settings primary action — small ALL-CAPS button on a brand-blue fill.
/// Used for "Connect", "Index", "Add Folder" type affordances.
struct SettingsActionButton: View {
    enum Style { case primary, secondary }
    let title: String
    var style: Style = .primary
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.statusPill(10))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(foregroundColor)
                .padding(.horizontal, Theme.Space.med)
                .padding(.vertical, 6)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay {
                    if style == .secondary {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Theme.Foreground.tertiary.opacity(0.4), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1.0)
    }

    private var foregroundColor: Color {
        switch style {
        case .primary:   return .white
        case .secondary: return Theme.Foreground.secondary
        }
    }
    private var backgroundColor: Color {
        switch style {
        case .primary:   return Theme.Brand.blue
        case .secondary: return Color.clear
        }
    }
}

/// Broadcast-style text field — mono digit-friendly, dark fill, brand-light-blue focus.
struct SettingsTextField: View {
    @Binding var text: String
    let placeholder: String
    var width: CGFloat? = nil
    var disabled: Bool = false
    var monospaced: Bool = false

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(monospaced ? .system(size: 12, weight: .regular).monospaced() : .system(size: 12))
            .foregroundStyle(Theme.Foreground.primary)
            .padding(.horizontal, Theme.Space.small)
            .padding(.vertical, 5)
            .frame(width: width)
            .background(Theme.Surface.window)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Theme.Surface.divider, lineWidth: 1)
            }
            .disabled(disabled)
    }
}
