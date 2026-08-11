import SwiftUI

struct SequenceEditorView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.hudStyle) private var style

    var body: some View {
        HUDScreen(title: "Sequence",
                  subtitle: "Build an ordered list of actions for Repeat Sequence and One-Shot modes. Drag to reorder.") {
            if let profile = appState.selectedProfileBinding {
                editorPanel(profile)
                validationPanel(profile.wrappedValue.sequence)
            } else {
                NoProfilePlaceholder()
            }
        }
    }

    private func editorPanel(_ profile: Binding<Profile>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HUDSectionHeader(title: "Timeline", systemImage: "list.number")
                addMenu(profile)
            }
            if profile.wrappedValue.sequence.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up.slash")
                        .font(.system(size: 26))
                        .foregroundStyle(style.palette.textDim)
                    Text("No actions yet — add one with the + menu.")
                        .font(.system(size: 11))
                        .foregroundStyle(style.palette.textDim)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                List {
                    ForEach(profile.wrappedValue.sequence) { step in
                        SequenceStepRow(
                            step: bindingForStep(profile, id: step.id),
                            depth: 0,
                            onDuplicate: { duplicate(profile, id: step.id) },
                            onDelete: { remove(profile, id: step.id) })
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                    }
                    .onMove { source, destination in
                        profile.wrappedValue.sequence.move(fromOffsets: source, toOffset: destination)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(minHeight: CGFloat(profile.wrappedValue.sequence.count) * 54 + 20,
                       maxHeight: 460)
            }
        }
        .hudPanel()
    }

    private func addMenu(_ profile: Binding<Profile>) -> some View {
        Menu {
            Section("Clicks") {
                Button("Left Click") { append(profile, .leftClick) }
                Button("Right Click") { append(profile, .rightClick) }
                Button("Middle Click") { append(profile, .middleClick) }
                Button("Double Click") { append(profile, .doubleClick) }
            }
            Section("Timing") {
                Button("Wait") { append(profile, .wait(ms: 250)) }
                Button("Random Delay") { append(profile, .randomDelay(minMS: 100, maxMS: 400)) }
            }
            Section("Cursor") {
                Button("Move Cursor") {
                    let loc = ScreenCoordinates.currentMouseLocationCG()
                    append(profile, .moveCursor(x: loc.x, y: loc.y))
                }
                Button("Return to Origin") { append(profile, .returnToOrigin) }
            }
            Section("Low Level") {
                Button("Mouse Down") { append(profile, .mouseDown(button: 0)) }
                Button("Mouse Up") { append(profile, .mouseUp(button: 0)) }
                Button("Repeat Group") {
                    append(profile, .repeatGroup(count: 3, steps: [SequenceStep(action: .leftClick)]))
                }
            }
        } label: {
            Label("Add Action", systemImage: "plus.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(style.accent)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Add sequence action")
    }

    // MARK: Step mutation helpers

    private func append(_ profile: Binding<Profile>, _ action: SequenceAction) {
        profile.wrappedValue.sequence.append(SequenceStep(action: action))
    }

    private func bindingForStep(_ profile: Binding<Profile>, id: UUID) -> Binding<SequenceStep> {
        Binding(
            get: {
                profile.wrappedValue.sequence.first { $0.id == id }
                    ?? SequenceStep(action: .leftClick)
            },
            set: { newValue in
                if let index = profile.wrappedValue.sequence.firstIndex(where: { $0.id == id }) {
                    profile.wrappedValue.sequence[index] = newValue
                }
            })
    }

    private func duplicate(_ profile: Binding<Profile>, id: UUID) {
        guard let index = profile.wrappedValue.sequence.firstIndex(where: { $0.id == id }) else { return }
        var copy = profile.wrappedValue.sequence[index]
        copy.id = UUID()
        profile.wrappedValue.sequence.insert(copy, at: index + 1)
    }

    private func remove(_ profile: Binding<Profile>, id: UUID) {
        profile.wrappedValue.sequence.removeAll { $0.id == id }
    }

    // MARK: Validation

    private func validationPanel(_ steps: [SequenceStep]) -> some View {
        let issues = SequenceValidator.validate(steps)
        return VStack(alignment: .leading, spacing: 8) {
            HUDSectionHeader(title: "Validation", systemImage: "checkmark.seal")
            if issues.isEmpty {
                StatusIndicator(state: .good, label: "Sequence is valid — \(SequenceValidator.expandedActionCount(steps)) actions per pass")
            } else {
                ForEach(issues) { issue in
                    Label(issue.message, systemImage: issue.severity == .error
                          ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(issue.severity == .error ? style.palette.danger : style.palette.warning)
                }
            }
        }
        .hudPanel()
    }
}

// MARK: - Step row

private struct SequenceStepRow: View {
    @Environment(\.hudStyle) private var style
    @Binding var step: SequenceStep
    var depth: Int
    var onDuplicate: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10))
                    .foregroundStyle(style.palette.textDim)
                    .accessibilityHidden(true)
                Image(systemName: step.action.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(style.accent)
                    .frame(width: 22)
                Text(step.action.displayName)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(style.palette.textPrimary)
                Spacer()
                parameterEditors
                Button(action: onDuplicate) {
                    Image(systemName: "plus.square.on.square")
                        .foregroundStyle(style.palette.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Duplicate action")
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(style.palette.danger.opacity(0.85))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete action")
            }
            nestedGroupEditor
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            AngularPanel(cut: 7)
                .fill(Color.white.opacity(0.03))
                .overlay(AngularPanel(cut: 7).stroke(Color.white.opacity(0.08), lineWidth: 1))
        )
        .padding(.leading, CGFloat(depth) * 22)
    }

    // Compact per-action parameter controls.
    @ViewBuilder
    private var parameterEditors: some View {
        switch step.action {
        case .wait(let ms):
            HUDNumberField(
                value: Binding(get: { ms }, set: { step.action = .wait(ms: $0) }),
                range: 0...3_600_000, unit: "ms")
        case .randomDelay(let minMS, let maxMS):
            HUDNumberField(
                value: Binding(get: { minMS }, set: { step.action = .randomDelay(minMS: $0, maxMS: maxMS) }),
                range: 0...3_600_000, unit: "min")
            HUDNumberField(
                value: Binding(get: { maxMS }, set: { step.action = .randomDelay(minMS: minMS, maxMS: $0) }),
                range: 0...3_600_000, unit: "max")
        case .moveCursor(let x, let y):
            HUDNumberField(
                value: Binding(get: { x }, set: { step.action = .moveCursor(x: $0, y: y) }),
                range: -20_000...20_000, unit: "x")
            HUDNumberField(
                value: Binding(get: { y }, set: { step.action = .moveCursor(x: x, y: $0) }),
                range: -20_000...20_000, unit: "y")
        case .mouseDown(let button):
            buttonPicker(button) { step.action = .mouseDown(button: $0) }
        case .mouseUp(let button):
            buttonPicker(button) { step.action = .mouseUp(button: $0) }
        case .repeatGroup(let count, let steps):
            HUDNumberField(
                value: Binding(
                    get: { Double(count) },
                    set: { step.action = .repeatGroup(count: Int($0), steps: steps) }),
                range: 1...10_000, unit: "×")
        default:
            EmptyView()
        }
    }

    private func buttonPicker(_ current: Int, set: @escaping (Int) -> Void) -> some View {
        Menu {
            ForEach([0, 1, 2, 3, 4], id: \.self) { n in
                Button(MouseButton(buttonNumber: n).displayName) { set(n) }
            }
        } label: {
            Text(MouseButton(buttonNumber: current).displayName)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(style.accent)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // One level of inline editing for repeat groups.
    @ViewBuilder
    private var nestedGroupEditor: some View {
        if case .repeatGroup(let count, let steps) = step.action, depth < 2 {
            VStack(spacing: 3) {
                ForEach(steps) { inner in
                    SequenceStepRow(
                        step: Binding(
                            get: {
                                steps.first { $0.id == inner.id } ?? inner
                            },
                            set: { newValue in
                                var updated = steps
                                if let i = updated.firstIndex(where: { $0.id == inner.id }) {
                                    updated[i] = newValue
                                }
                                step.action = .repeatGroup(count: count, steps: updated)
                            }),
                        depth: depth + 1,
                        onDuplicate: {
                            var updated = steps
                            if let i = updated.firstIndex(where: { $0.id == inner.id }) {
                                var copy = updated[i]
                                copy.id = UUID()
                                updated.insert(copy, at: i + 1)
                                step.action = .repeatGroup(count: count, steps: updated)
                            }
                        },
                        onDelete: {
                            var updated = steps
                            updated.removeAll { $0.id == inner.id }
                            step.action = .repeatGroup(count: count, steps: updated)
                        })
                }
                Menu {
                    Button("Left Click") { appendInner(.leftClick) }
                    Button("Right Click") { appendInner(.rightClick) }
                    Button("Double Click") { appendInner(.doubleClick) }
                    Button("Wait") { appendInner(.wait(ms: 250)) }
                    Button("Random Delay") { appendInner(.randomDelay(minMS: 100, maxMS: 400)) }
                } label: {
                    Label("Add to group", systemImage: "plus")
                        .font(.system(size: 10))
                        .foregroundStyle(style.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.leading, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 4)
        }
    }

    private func appendInner(_ action: SequenceAction) {
        if case .repeatGroup(let count, var steps) = step.action {
            steps.append(SequenceStep(action: action))
            step.action = .repeatGroup(count: count, steps: steps)
        }
    }
}
