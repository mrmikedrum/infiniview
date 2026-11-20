import AppKit
import InfiniviewCore

// `Infiniview --register`: write and register the Learned Type, then exit (used by the installer).
if CommandLine.arguments.contains("--register") {
    let learned = SharedSettings().learnedExtensions(builtIn: BuiltInList.extensions)
    exit(LearnedTypeRegistrar.apply(learned.effective) ? 0 : 1)
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
