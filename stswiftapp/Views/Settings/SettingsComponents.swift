import SwiftUI
import UniformTypeIdentifiers

// MARK: - Collapsible Section

struct CollapsibleSection<Content: View>: View {
    let title: String
    let systemImage: String?
    @State private var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    init(title: String, systemImage: String? = nil, defaultExpanded: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        _isExpanded = State(initialValue: defaultExpanded)
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack {
                    if let img = systemImage {
                        Image(systemName: img).foregroundStyle(.secondary).frame(width: 20)
                    }
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Editable Slider

struct EditableSlider: View {
    let label: String
    let systemImage: String?
    let range: ClosedRange<Double>
    let step: Double
    @Binding var value: Double
    let helpText: String?
    let format: String

    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var focused: Bool

    init(label: String, systemImage: String? = nil, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 0.01, format: String = "%.2f", helpText: String? = nil) {
        self.label = label
        self.systemImage = systemImage
        _value = value
        self.range = range
        self.step = step
        self.format = format
        self.helpText = helpText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let img = systemImage {
                    Image(systemName: img).foregroundStyle(.secondary).frame(width: 20)
                }
                Text(label).font(.subheadline)

                if let help = helpText {
                    Button(action: {}) {
                        Image(systemName: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .help(help)
                }

                Spacer()

                if isEditing {
                    TextField("", text: $editText)
                        .keyboardType(.decimalPad)
                        .focused($focused)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { commitEdit() }
                        .onAppear { editText = String(format: format, value); focused = true }
                } else {
                    Button(String(format: format, value)) {
                        editText = String(format: format, value)
                        isEditing = true
                    }
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }

            Slider(value: $value, in: range, step: step)
                .onChange(of: value) { _, _ in
                    if isEditing { isEditing = false }
                }
        }
    }

    private func commitEdit() {
        if let v = Double(editText) {
            value = min(max(v, range.lowerBound), range.upperBound)
        }
        isEditing = false
    }
}

struct JSONFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

// MARK: - Defaults provider

protocol SettingsDefaultsProvider {
    static var defaults: [String: Any] { get }
}

struct DefaultSettings: SettingsDefaultsProvider {
    static var defaults: [String: Any] { [
        "temperature": 0.7,
        "max_tokens": 200,
        "top_p": 1.0,
        "top_k": 0,
        "frequency_penalty": 0.0,
        "presence_penalty": 0.0,
        "repetition_penalty": 1.0,
        "max_completion_tokens": 0,
        "stream": true,
        "chat_completion_source": ["type": "openai"],
        "power_user": ["personas": [:]]
    ]}
}
