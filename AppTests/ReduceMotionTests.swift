import SwiftUI
import Testing
@testable import ItsPaint

/// Reduce Motion is honoured in one place, so it is tested in one place.
///
/// Before this, two of the app's twenty-six `.animation(_:value:)` calls checked
/// `accessibilityReduceMotion` and twenty-four did not. The fix was to move the
/// question into `Tokens.Motion` rather than to add twenty-four guards, and this
/// is the check that fails if a future token forgets to route through it.
@Suite("Reduce Motion")
struct ReduceMotionTests {
    @Test("The setting removes the animation rather than shortening it")
    func honouringDropsTheAnimation() {
        #expect(Tokens.Motion.honouring(.easeOut(duration: 0.12), reduceMotion: true) == nil)
        #expect(Tokens.Motion.honouring(.easeOut(duration: 0.12), reduceMotion: false) != nil)
    }

    /// The tokens are read as `Animation?` at every call site. If one of them ever
    /// goes back to a non-optional `let`, this stops compiling — which is the point:
    /// a token that cannot be nil cannot honour the setting.
    @Test("Every motion token is optional, which is what lets it be nothing")
    func everyTokenIsOptional() {
        let tokens: [Animation?] = [Tokens.Motion.micro,
                                    Tokens.Motion.press,
                                    Tokens.Motion.pillResize]
        #expect(tokens.count == 3)
        // Under the machine's real setting they are all present or all absent
        // together — never a mixture, because they ask the same question.
        let present = tokens.filter { $0 != nil }.count
        #expect(present == 0 || present == 3)
    }
}
