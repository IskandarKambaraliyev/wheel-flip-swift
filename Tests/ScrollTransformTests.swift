import XCTest
@testable import WheelFlip

final class ScrollTransformTests: XCTestCase {

    // MARK: isMouseWheel

    func testLineBasedEventIsMouseWheelInBothDetections() {
        for detection in Detection.allCases {
            XCTAssertTrue(ScrollTransform.isMouseWheel(continuous: 0, phase: 0, momentum: 0, detection: detection))
        }
    }

    func testPhaselessContinuousEventIsMouseWheelOnlyInStandard() {
        XCTAssertTrue(ScrollTransform.isMouseWheel(continuous: 1, phase: 0, momentum: 0, detection: .standard))
        XCTAssertFalse(ScrollTransform.isMouseWheel(continuous: 1, phase: 0, momentum: 0, detection: .strict))
    }

    func testPhasedOrMomentumEventIsNeverMouseWheel() {
        for detection in Detection.allCases {
            for (phase, momentum) in [(1, 0), (2, 0), (4, 0), (0, 1), (0, 2), (2, 3)] as [(Int64, Int64)] {
                XCTAssertFalse(ScrollTransform.isMouseWheel(continuous: 1, phase: phase, momentum: momentum,
                                                            detection: detection),
                               "phase \(phase), momentum \(momentum), \(detection)")
            }
        }
    }

    // MARK: transform, invert only

    func testInvertNegatesAllThreeDeltas() {
        let out = ScrollTransform.transform(AxisDeltas(line: 3, fixed: 3.7, point: 37),
                                            invert: true, linear: false, lines: 3)
        XCTAssertEqual(out, AxisDeltas(line: -3, fixed: -3.7, point: -37))

        let back = ScrollTransform.transform(AxisDeltas(line: -1, fixed: -0.4, point: -4),
                                             invert: true, linear: false, lines: 3)
        XCTAssertEqual(back, AxisDeltas(line: 1, fixed: 0.4, point: 4))
    }

    func testInvertKeepsZeroAtZero() {
        let out = ScrollTransform.transform(AxisDeltas(line: 0, fixed: 0, point: 0),
                                            invert: true, linear: false, lines: 3)
        XCTAssertEqual(out, AxisDeltas(line: 0, fixed: 0, point: 0))
    }

    func testNoInvertNoLinearLeavesDeltasUntouched() {
        let input = AxisDeltas(line: 2, fixed: 2.5, point: 25)
        XCTAssertEqual(ScrollTransform.transform(input, invert: false, linear: false, lines: 3), input)
    }

    // MARK: transform, linear

    func testLinearReplacesSingleNotchWithLinesPerNotch() {
        let out = ScrollTransform.transform(AxisDeltas(line: 1, fixed: 1, point: 10),
                                            invert: false, linear: true, lines: 3)
        XCTAssertEqual(out, AxisDeltas(line: 3, fixed: 3, point: 30))
    }

    func testLinearRemovesAcceleration() {
        let out = ScrollTransform.transform(AxisDeltas(line: -7, fixed: -7.2, point: -72),
                                            invert: false, linear: true, lines: 3)
        XCTAssertEqual(out, AxisDeltas(line: -3, fixed: -3, point: -30))
    }

    func testLinearUsesFixedSignWhenLineDeltaIsZero() {
        let up = ScrollTransform.transform(AxisDeltas(line: 0, fixed: 0.3, point: 3),
                                           invert: false, linear: true, lines: 5)
        XCTAssertEqual(up, AxisDeltas(line: 5, fixed: 5, point: 50))

        let down = ScrollTransform.transform(AxisDeltas(line: 0, fixed: -0.3, point: -3),
                                             invert: false, linear: true, lines: 5)
        XCTAssertEqual(down, AxisDeltas(line: -5, fixed: -5, point: -50))
    }

    func testLinearPointDeltaIsTenTimesLineDelta() {
        for lines in Int64(1)...10 {
            let out = ScrollTransform.transform(AxisDeltas(line: 4, fixed: 4, point: 40),
                                                invert: false, linear: true, lines: lines)
            XCTAssertEqual(out.line, lines)
            XCTAssertEqual(out.point, out.line * 10)
        }
    }

    func testLinearLeavesIdleAxisAtZero() {
        let out = ScrollTransform.transform(AxisDeltas(line: 0, fixed: 0, point: 0),
                                            invert: false, linear: true, lines: 3)
        XCTAssertEqual(out, AxisDeltas(line: 0, fixed: 0, point: 0))
    }

    // MARK: transform, linear + invert

    func testLinearThenInvert() {
        let out = ScrollTransform.transform(AxisDeltas(line: 7, fixed: 7, point: 70),
                                            invert: true, linear: true, lines: 3)
        XCTAssertEqual(out, AxisDeltas(line: -3, fixed: -3, point: -30))

        let fixedOnly = ScrollTransform.transform(AxisDeltas(line: 0, fixed: -0.5, point: -5),
                                                  invert: true, linear: true, lines: 2)
        XCTAssertEqual(fixedOnly, AxisDeltas(line: 2, fixed: 2, point: 20))
    }

    // MARK: test host

    /// The tests run inside the app; it must recognise that and not prompt or install a tap.
    func testHostAppStaysInertUnderXCTest() {
        XCTAssertTrue(AppDelegate.isRunningTests)
        XCTAssertFalse(ScrollEngine.shared.isRunning)
    }
}
