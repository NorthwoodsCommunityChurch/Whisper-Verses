import Foundation

struct SemanticVersion: Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int
    let preRelease: String?

    var description: String {
        var result = "\(major).\(minor).\(patch)"
        if let preRelease {
            result += "-\(preRelease)"
        }
        return result
    }

    init?(string: String) {
        var input = string
        if input.hasPrefix("v") || input.hasPrefix("V") {
            input = String(input.dropFirst())
        }

        let parts = input.split(separator: "-", maxSplits: 1)
        let versionPart = String(parts[0])
        let components = versionPart.split(separator: ".")

        guard components.count == 3,
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2])
        else { return nil }

        self.major = major
        self.minor = minor
        self.patch = patch
        self.preRelease = parts.count > 1 ? String(parts[1]) : nil
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        // Release (nil) beats any pre-release of the same version
        switch (lhs.preRelease, rhs.preRelease) {
        case (nil, nil): return false
        case (nil, _): return false   // lhs is release, rhs is pre-release → lhs is NOT less
        case (_, nil): return true    // lhs is pre-release, rhs is release → lhs IS less
        case let (l?, r?): return l < r  // Alphabetical: alpha < beta < rc
        }
    }
}
