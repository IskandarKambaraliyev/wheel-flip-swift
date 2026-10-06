import CoreGraphics

struct AxisDeltas: Equatable {
    var line: Int64
    var fixed: Double
    var point: Int64
}

enum ScrollTransform {
    @inline(__always)
    static func isMouseWheel(continuous: Int64, phase: Int64, momentum: Int64, detection: Detection) -> Bool {
        if continuous == 0 { return true }
        if detection == .strict { return false }
        return phase == 0 && momentum == 0
    }

    @inline(__always)
    static func transform(_ d: AxisDeltas, invert: Bool, linear: Bool, lines: Int64) -> AxisDeltas {
        var out = d
        if linear {
            let s: Int64 = d.line != 0 ? (d.line > 0 ? 1 : -1)
                         : (d.fixed > 0 ? 1 : (d.fixed < 0 ? -1 : 0))
            if s != 0 {
                out = AxisDeltas(line: s * lines, fixed: Double(s * lines), point: s * lines * 10)
            }
        }
        if invert {
            out = AxisDeltas(line: -out.line, fixed: -out.fixed, point: -out.point)
        }
        return out
    }
}
