import AppKit
import InfiniviewCore
import InfiniviewSystem

// `Infiniview --register`: register the Learned Type and the Folder Check helper, then exit.
// `Infiniview --unregister`: unregister the helper. Both are used by the scripts.
if CommandLine.arguments.contains("--register") {
    let learned = SharedSettings().learnedExtensions(builtIn: BuiltInList.extensions)
    let ok = LearnedTypeRegistrar.apply(learned.effective)
    if HelperAgent.register() == .needsApproval {
        print("Allow Infiniview under System Settings → General → Login Items to turn on Folder Checks.")
    }
    exit(ok ? 0 : 1)
}
if CommandLine.arguments.contains("--unregister") {
    HelperAgent.unregister()
    exit(0)
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
