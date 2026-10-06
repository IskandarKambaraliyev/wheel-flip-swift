enum Detection: Int, Codable, CaseIterable { case standard = 0, strict = 1 }

/// Plain value type copied into the tap thread. Keep it POD (no classes, no strings).
struct EngineConfig: Equatable {
    var enabled = true
    var invertVertical = true
    var invertHorizontal = false
    var linear = false
    var linesPerNotch: Int64 = 3
    var detection: Detection = .standard
    var inspect = false
}

let kWheelFlipMarker: Int64 = 0x57464C50   // "WFLP"
