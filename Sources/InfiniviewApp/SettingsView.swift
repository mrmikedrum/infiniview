import InfiniviewCore
import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
    private let settings = SharedSettings()
    @Published private(set) var learned: LearnedExtensions
    @Published var takeover: Bool?
    @Published private(set) var editors: [EditorThemes.Editor] = []
    /// Nil for the bundled pair, else the editor's name.
    @Published var themeChoice: String?
    // View state lives here rather than in @State: SwiftUI's @State is a compiler macro, and the
    // Command Line Tools don't ship SwiftUI's macro plugin.
    @Published var newExtension = ""
    @Published var selection: String?

    init() {
        learned = settings.learnedExtensions(builtIn: BuiltInList.extensions)
        themeChoice = settings.themeSource == .editor ? settings.editorName : nil
    }

    func reload() {
        learned = settings.learnedExtensions(builtIn: BuiltInList.extensions)
        takeover = TakeoverSwitch.isOn()
        editors = EditorThemeStore.editors()
        if let choice = themeChoice, !editors.contains(where: { $0.name == choice }) { themeChoice = nil }
    }

    func learn(_ ext: String) {
        learned.learn(ext)
        save()
    }

    func forget(_ ext: String) {
        learned.forget(ext)
        save()
    }

    func setTakeover(_ on: Bool) {
        TakeoverSwitch.set(on)
        takeover = TakeoverSwitch.isOn()
    }

    func setTheme(_ editorName: String?) {
        themeChoice = editorName
        EditorThemeStore.use(editors.first { $0.name == editorName })
    }

    private func save() {
        settings.save(learned)
        LearnedTypeRegistrar.apply(learned.effective)
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("Takeover", isOn: Binding(get: { model.takeover ?? false }, set: { model.setTakeover($0) }))
                    .disabled(model.takeover == nil)
                Text(model.takeover == nil
                     ? "The Takeover extension isn't registered. Reinstall Infiniview."
                     : "Infiniview previews source code, JSON, YAML, XML, Markdown and other types macOS shows as plain text. Off: macOS shows its own preview for them.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Learned Extensions") {
                List(model.learned.effective, id: \.self, selection: $model.selection) { ext in
                    HStack {
                        Text("." + ext).font(.body.monospaced())
                        Spacer()
                        if let owner = LearnedTypeRegistrar.otherOwner(of: ext) {
                            Text("macOS: \(owner)").font(.caption).foregroundStyle(.tertiary)
                        } else if model.learned.builtIn.contains(ext) {
                            Text("built in").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(minHeight: 180)
                HStack {
                    TextField("Extension", text: $model.newExtension, prompt: Text("xyz"))
                        .onSubmit(add)
                    Button("Add", action: add).disabled(ExtensionList.normalize(model.newExtension) == nil)
                    Button("Remove") { if let s = model.selection { model.forget(s); model.selection = nil } }
                        .disabled(model.selection == nil)
                }
                Text("Files with these extensions preview as text. In Finder you can also right-click a file and choose Quick Actions → Always Preview as Text. Extensions macOS already has a type for keep their own preview.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Theme") {
                Picker("Colours", selection: Binding(get: { model.themeChoice }, set: { model.setTheme($0) })) {
                    Text("Infiniview (2026 Light and Dark)").tag(String?.none)
                    ForEach(model.editors, id: \.name) { editor in
                        Text("\(editor.name)'s themes").tag(Optional(editor.name))
                    }
                }
                Text(model.editors.isEmpty
                     ? "No VS Code-family editor found in Applications."
                     : "An editor's themes follow its light and dark theme settings, and are read again each time Infiniview opens.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 520)
        .onAppear { model.reload() }
    }

    private func add() {
        guard let e = ExtensionList.normalize(model.newExtension) else { return }
        model.learn(e)
        model.newExtension = ""
    }
}
