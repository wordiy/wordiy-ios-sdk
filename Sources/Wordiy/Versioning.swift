import Foundation

/// Tolerant semantic-version comparison used to decide which version the SDK reports as
/// `current_version`. Handles an optional leading `v`, dotted numeric components of differing length,
/// and ignores any pre-release/build suffix (after `-` or `+`).
enum SemVer {

    /// Returns whichever of `a` / `b` is the higher version (or `a` if equal).
    static func higher(_ a: String, _ b: String) -> String {
        compare(a, b) == .orderedAscending ? b : a
    }

    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let pa = components(a)
        let pb = components(b)
        let count = Swift.max(pa.count, pb.count)
        for i in 0..<count {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private static func components(_ s: String) -> [Int] {
        var trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first, first == "v" || first == "V" { trimmed.removeFirst() }
        // Drop pre-release / build metadata.
        let core = trimmed.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? trimmed
        return core.split(separator: ".").map { Int($0) ?? 0 }
    }
}
