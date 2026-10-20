import Foundation
/// Relative calendar-aging stress from BU-808 Table 3 (capacity lost after one year of storage).
/// General Li-ion research, not validated for any specific cell; used only for comparisons.
public enum StressModel {
    static let table: [(t: Double, low: Double, high: Double)] = [(0, 2, 6), (25, 4, 20), (40, 15, 35)]
    static let reference = 4.0
    public static func rate(soc: Double, temperature: Double) -> Double {
        let s = min(max(soc, 40), 100), t = min(max(temperature, 0), 60)
        func loss(_ row: (t: Double, low: Double, high: Double)) -> Double { row.low + (row.high - row.low) * (s - 40) / 60 }
        let (a, b) = t <= 25 ? (table[0], table[1]) : (table[1], table[2])
        let f = (t - a.t) / (b.t - a.t)
        return exp(log(loss(a)) + (log(loss(b)) - log(loss(a))) * f) / reference
    }
}
