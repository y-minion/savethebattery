import Testing
import MacBridge
struct PowerUIBridgeTests {
    // Never pass 80...100 here: that would change this Mac's real charge limit.
    @Test func outOfRangeLimitsAreRejectedBeforeCallingMacOS() {
        #expect(vb_mcl_set_limit(79) == -3);#expect(vb_mcl_set_limit(101) == -3);#expect(vb_mcl_set_limit(-1) == -3);#expect(vb_mcl_set_limit(83) == -3)
    }
}
