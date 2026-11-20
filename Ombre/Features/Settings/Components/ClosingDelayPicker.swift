import SwiftUI

/// Picks how long tabs not shown stay before they are closed: 12 hours,
/// 1 day, 2 days, 1 week, 1 month, Never, or Custom… (a number of hours,
/// days or weeks). A space's picker offers the general delay in place of Never.
struct ClosingDelayPicker: View {
    /// Seconds; nil: the general delay (a space's picker only).
    @Binding var seconds: TimeInterval?
    /// Set for a space: the choice that follows the general delay.
    var generalTitle: String?

    @State private var isEditingCustom = false
    /// As typed: read at each key, so OK takes the number shown.
    @State private var countText = "3"
    @State private var unit: TabClosingDelay.Unit = .days

    private enum Choice: Hashable {
        case general
        case never
        case delay(TimeInterval)
        case custom
    }

    private var current: Choice {
        guard let seconds else { return .general }
        return TabClosingDelay.isNever(seconds) ? .never : .delay(seconds)
    }

    private var selection: Binding<Choice> {
        Binding(
            get: { current },
            set: { choice in
                switch choice {
                case .general: seconds = nil
                case .never: seconds = TabClosingDelay.never
                case let .delay(value): seconds = value
                case .custom: editCustom()
                }
            }
        )
    }

    var body: some View {
        Picker("", selection: selection) {
            if let generalTitle {
                Text(generalTitle).tag(Choice.general)
                Divider()
            }
            ForEach(TabClosingDelay.presets, id: \.self) { value in
                Text(TabClosingDelay.title(value)).tag(Choice.delay(value))
            }
            // A custom delay chosen before shows as itself.
            if let seconds, !TabClosingDelay.isNever(seconds), !TabClosingDelay.presets.contains(seconds) {
                Text(TabClosingDelay.title(seconds)).tag(Choice.delay(seconds))
            }
            if generalTitle == nil {
                Text("Never").tag(Choice.never)
            }
            Divider()
            Text("Custom…").tag(Choice.custom)
        }
        .labelsHidden()
        .fixedSize()
        .popover(isPresented: $isEditingCustom, arrowEdge: .bottom) {
            customEditor
        }
    }

    private var customEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Close tabs not shown after:")
                .font(.system(size: 12, weight: .medium))
            HStack(spacing: 8) {
                TextField("", text: $countText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 56)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel(String(localized: "Number"))
                Stepper("", value: Binding(
                    get: { count ?? 1 },
                    set: { countText = String($0) }
                ), in: 1 ... 999)
                    .labelsHidden()
                Picker("", selection: $unit) {
                    Text("hours").tag(TabClosingDelay.Unit.hours)
                    Text("days").tag(TabClosingDelay.Unit.days)
                    Text("weeks").tag(TabClosingDelay.Unit.weeks)
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel(String(localized: "Unit"))
            }
            HStack {
                Spacer()
                Button("Cancel") { isEditingCustom = false }
                    .keyboardShortcut(.cancelAction)
                Button("OK") {
                    if let value = customValue { seconds = value }
                    isEditingCustom = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(customValue == nil)
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private var count: Int? {
        Int(countText.trimmingCharacters(in: .whitespaces))
    }

    private var customValue: TimeInterval? {
        count.flatMap { TabClosingDelay.custom($0, unit) }
    }

    /// Starts from the delay chosen now.
    private func editCustom() {
        if let seconds, !TabClosingDelay.isNever(seconds) {
            let parts = TabClosingDelay.parts(of: seconds)
            countText = String(parts.count)
            unit = parts.unit
        }
        isEditingCustom = true
    }
}
