import Foundation
import Testing
@testable import InfiniviewCore

@Suite struct TakeoverTests {
    @Test func readsPluginkitState() {
        #expect(Takeover.isOn(pluginkitOutput: "+    com.mdrum.infiniview.takeover(1.0)\n") == true)
        #expect(Takeover.isOn(pluginkitOutput: "     com.mdrum.infiniview.takeover(1.0)\n") == true)
        #expect(Takeover.isOn(pluginkitOutput: "-    com.mdrum.infiniview.takeover(1.0)\n") == false)
        #expect(Takeover.isOn(pluginkitOutput: "  (no matches)\n") == nil)
    }

    @Test func switchArguments() {
        #expect(Takeover.arguments(on: false) == ["-e", "ignore", "-i", "com.mdrum.infiniview.takeover"])
        #expect(Takeover.arguments(on: true) == ["-e", "use", "-i", "com.mdrum.infiniview.takeover"])
    }
}

@Suite struct TakeoverTypeListTests {
    @Test func listLeavesVisualTypesToMacOS() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Resources/takeover-types.txt").standardized
        let types = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
        #expect(types.count > 40)
        #expect(Set(types).count == types.count)
        for never in ["public.html", "public.xhtml", "public.svg-image", "public.rtf", "public.comma-separated-values-text", "public.data"] {
            #expect(!types.contains(never), "\(never)")
        }
        #expect(types.allSatisfy { $0.range(of: #"^[A-Za-z0-9.-]+$"#, options: .regularExpression) != nil })
    }
}
