// Development tool: renders a file through the Preview code (in-process, not via Quick Look)
// to a PNG, for checking how the Preview looks.
//   swift run PreviewRender <file> <out.png> [light|dark] [width] [height]
import AppKit
import InfiniviewPreview

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: PreviewRender <file> <out.png> [light|dark] [width] [height]\n".utf8))
    exit(2)
}
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../..").standardized
let dark = args.count > 3 && args[3] == "dark"
let size = NSSize(width: args.count > 4 ? Double(args[4]) ?? 720 : 720, height: args.count > 5 ? Double(args[5]) ?? 480 : 480)

MainActor.assumeIsolated {
    _ = NSApplication.shared
    NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSApp.appearance
    let controller = try! PreviewController(assets: root.appendingPathComponent("Vendor/highlighting"))
    controller.view.frame = NSRect(origin: .zero, size: size)
    window.contentView = controller.view
    controller.view.wantsLayer = true
    try! controller.load(URL(fileURLWithPath: args[1]))
    // Let background highlighting and layout finish.
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    controller.view.layoutSubtreeIfNeeded()
    controller.view.displayIfNeeded()
    // TextKit 2 draws text in sublayers, which cacheDisplay misses: render the layer tree.
    let scale: CGFloat = 2
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.scaleBy(x: scale, y: scale)
    window.contentView!.layer!.render(in: ctx)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
}
