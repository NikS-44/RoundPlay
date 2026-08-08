import Testing
import Foundation
@testable import RoundPlayEngine

@Test("Course looks up holes by number")
func courseLooksUpHoles() throws {
    let course = Course.testPar72
    #expect(course.hole(1)?.par == 4)
    #expect(course.hole(18)?.par == 4)
    #expect(course.hole(19) == nil)
}

@Test("Course rejects a duplicate stroke index")
func courseValidatesStrokeIndexes() {
    let bad = (1...18).map { Hole(number: $0, par: 4, strokeIndex: 1) }
    #expect(throws: CourseValidationError.duplicateStrokeIndex) {
        try Course.validated(id: UUID(), name: "Bad", holes: bad)
    }
}

@Test("Course requires 18 holes")
func courseRequiresEighteenHoles() {
    let short = (1...9).map { Hole(number: $0, par: 4, strokeIndex: $0) }
    #expect(throws: CourseValidationError.wrongHoleCount) {
        try Course.validated(id: UUID(), name: "Short", holes: short)
    }
}
