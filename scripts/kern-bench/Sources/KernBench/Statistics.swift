import Foundation

struct Stats: Codable {
    let n: Int
    let min: Double
    let max: Double
    let median: Double
    let mean: Double
    let std: Double
    let cvPct: Double
    let p25: Double
    let p75: Double
    let iqr: Double
    let p95: Double
    let p99: Double
    let ciLower: Double
    let ciUpper: Double

    enum CodingKeys: String, CodingKey {
        case n, min, max, median, mean, std, p25, p75, iqr, p95, p99
        case cvPct = "cv_pct"
        case ciLower = "ci_lower"
        case ciUpper = "ci_upper"
    }
}

func computeStats(_ values: [Double]) -> Stats {
    guard !values.isEmpty else {
        return Stats(n: 0, min: 0, max: 0, median: 0, mean: 0, std: 0,
                     cvPct: 0, p25: 0, p75: 0, iqr: 0, p95: 0, p99: 0,
                     ciLower: 0, ciUpper: 0)
    }

    let sorted = values.sorted()
    let n = sorted.count

    // No outlier removal — report raw percentiles.
    let med = percentile(sorted, p: 0.5)
    let sum = sorted.reduce(0, +)
    let avg = sum / Double(n)
    let variance = sorted.reduce(0) { $0 + ($1 - avg) * ($1 - avg) } / Double(Swift.max(n - 1, 1))
    let sd = sqrt(variance)
    let cv = avg > 0 ? (sd / avg) * 100 : 0

    let q1 = percentile(sorted, p: 0.25)
    let q3 = percentile(sorted, p: 0.75)

    // Bootstrap 95% CI for the median: 10,000 resamples, seeded PRNG.
    let (ciLo, ciHi) = bootstrapMedianCI(sorted, resamples: 10_000, seed: 42)

    return Stats(
        n: n,
        min: sorted.first ?? 0,
        max: sorted.last ?? 0,
        median: round(med * 100) / 100,
        mean: round(avg * 100) / 100,
        std: round(sd * 100) / 100,
        cvPct: round(cv * 10) / 10,
        p25: round(q1 * 100) / 100,
        p75: round(q3 * 100) / 100,
        iqr: round((q3 - q1) * 100) / 100,
        p95: round(percentile(sorted, p: 0.95) * 100) / 100,
        p99: round(percentile(sorted, p: 0.99) * 100) / 100,
        ciLower: round(ciLo * 100) / 100,
        ciUpper: round(ciHi * 100) / 100
    )
}

/// R Type 7 linear interpolation percentile (same as numpy default).
func percentile(_ sorted: [Double], p: Double) -> Double {
    guard sorted.count > 1 else { return sorted.first ?? 0 }
    let index = p * Double(sorted.count - 1)
    let lower = Int(floor(index))
    let upper = Int(ceil(index))
    if lower == upper { return sorted[lower] }
    let frac = index - Double(lower)
    return sorted[lower] * (1 - frac) + sorted[upper] * frac
}

/// Bootstrap 95% CI for the median using percentile method.
/// Uses a simple seeded LCG for reproducibility without importing GameplayKit.
private func bootstrapMedianCI(_ sorted: [Double], resamples: Int, seed: UInt64) -> (lower: Double, upper: Double) {
    guard sorted.count >= 2 else {
        let val = sorted.first ?? 0
        return (val, val)
    }

    var rng = SeededLCG(seed: seed)
    let n = sorted.count
    var bootstrapMedians: [Double] = []
    bootstrapMedians.reserveCapacity(resamples)

    for _ in 0..<resamples {
        // Resample with replacement.
        var sample = [Double]()
        sample.reserveCapacity(n)
        for _ in 0..<n {
            let idx = Int(rng.next() % UInt64(n))
            sample.append(sorted[idx])
        }
        sample.sort()
        bootstrapMedians.append(percentile(sample, p: 0.5))
    }

    bootstrapMedians.sort()
    let lo = percentile(bootstrapMedians, p: 0.025)
    let hi = percentile(bootstrapMedians, p: 0.975)
    return (lo, hi)
}

/// Simple seeded linear congruential generator for reproducible bootstrap.
private struct SeededLCG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        // LCG constants from Numerical Recipes.
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
