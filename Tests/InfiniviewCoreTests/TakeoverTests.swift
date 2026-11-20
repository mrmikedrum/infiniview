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
