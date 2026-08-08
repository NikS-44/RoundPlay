import Testing
@testable import RoundPlayEngine

@Test("Engine module is importable and reports its version")
func engineVersionIsPresent() {
    #expect(RoundPlayEngineVersion.current == "0.1.0")
}
