import SwiftUI

// MARK: - Labeled rows

/// Standard settings row: label on the left, control on the right.
struct HUDRow<Content: View>: View {
    @Environment(\.hudStyle) private var style
    var label: String
    var detail: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(style.palette.textPrimary)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(style.palette.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            content
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Numeric field

/// Validated numeric entry with unit suffix. Commits on Enter / focus loss;
/// out-of-range values are clamped rather than rejected.
struct HUDNumberField: View {
    @Environment(\.hudStyle) private var style
    var value: Binding<Double>
    var range: ClosedRange<Double>
    var unit: String = ""
    var fractionDigits: Int = 0

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(style.accent)
                .frame(width: 64)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { isFocused in
                    if isFocused {
                        text = formatted(value.wrappedValue)
                    } else {
                        commit()
                    }
                }
                .onAppear { text = formatted(value.wrappedValue) }
                .onChange(of: value.wrappedValue) { newValue in
                    if !focused { text = formatted(newValue) }
                }
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(style.palette.textDim)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(focused ? style.accent.opacity(0.8) : style.accent.opacity(0.25),
                                lineWidth: 1)
                )
        )
        .accessibilityLabel(unit.isEmpty ? "value" : "value in \(unit)")
        .accessibilityValue(formatted(value.wrappedValue))
    }

    private func formatted(_ v: Double) -> String {
        String(format: "%.\(fractionDigits)f", v)
    }

    private func commit() {
        if let parsed = Double(text.replacingOccurrences(of: ",", with: ".")) {
            value.wrappedValue = parsed.clamped(to: range)
        }
        text = formatted(value.wrappedValue)
    }
}

// MARK: - Slider row

struct HUDSliderRow: View {
    @Environment(\.hudStyle) private var style
    var label: String
    var value: Binding<Double>
    var range: ClosedRange<Double>
    var unit: String = ""
    var fractionDigits: Int = 0
    var detail: String? = nil

    var body: some View {
        HUDRow(label: label, detail: detail) {
            HStack(spacing: 10) {
                Slider(value: value, in: range)
                    .controlSize(.small)
                    .tint(style.accent)
                    .frame(width: 140)
                    .accessibilityLabel(label)
                HUDNumberField(value: value, range: range, unit: unit, fractionDigits: fractionDigits)
            }
        }
    }
}

// MARK: - Toggle

struct HUDToggleStyle: ToggleStyle {
    @Environment(\.hudStyle) private var style

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                configuration.label
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? style.accent.opacity(0.35) : Color.black.opacity(0.4))
                        .overlay(
                            Capsule().stroke(
                                configuration.isOn ? style.accent : style.palette.textDim.opacity(0.5),
                                lineWidth: 1))
                        .frame(width: 34, height: 18)
                    Circle()
                        .fill(configuration.isOn ? style.accent : style.palette.textDim)
                        .frame(width: 12, height: 12)
                        .padding(.horizontal, 3)
                        .shadow(color: configuration.isOn ? style.accent.opacity(0.8 * style.glow) : .clear,
                                radius: style.glowRadius(4))
                }
                .animation(style.animationsEnabled ? .easeOut(duration: 0.15) : nil,
                           value: configuration.isOn)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Segmented picker

/// Angular segmented control for enums.
struct HUDSegmentedPicker<T: Hashable & Identifiable>: View {
    @Environment(\.hudStyle) private var style
    var options: [T]
    var selection: Binding<T>
    var label: (T) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let selected = selection.wrappedValue == option
                Button {
                    selection.wrappedValue = option
                } label: {
                    Text(label(option))
                        .font(.system(size: 10.5, weight: selected ? .bold : .regular, design: .monospaced))
                        .foregroundStyle(selected ? style.palette.background : style.palette.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            AngularPanel(cut: 5)
                                .fill(selected ? style.accent : Color.white.opacity(0.04))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(option))
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(
            AngularPanel(cut: 6)
                .stroke(style.accent.opacity(0.3), lineWidth: 1)
                .background(AngularPanel(cut: 6).fill(Color.black.opacity(0.3)))
        )
    }
}
