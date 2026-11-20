import Foundation
// usage: bench <assets dir> file...
let args = CommandLine.arguments
let assets = URL(fileURLWithPath: args[1])
print(Bench.header)
for p in args.dropFirst(2) {
    do { print(try Bench.run(URL(fileURLWithPath: p), where: "cli", assets: assets)) }
    catch { print("cli\t\(p)\terror \(error)") }
}
