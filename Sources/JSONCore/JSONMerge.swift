import Foundation

public enum JSONMerge {
    /// Deep-merges `overlay` into `base`: when both sides have an object at
    /// the same key, it recurses; otherwise overlay wins outright (replacing
    /// base's value, including for arrays and scalars). Keys only in base
    /// are kept untouched; keys only in overlay are appended.
    ///
    /// This is the typical "settings + secrets" merge: appsecrets.json's
    /// values fill in or override matching paths in appsettings.json
    /// without discarding settings that have no secret counterpart.
    public static func merge(base: JSONNode, overlay: JSONNode) -> JSONNode {
        guard case .object(let baseObj) = base, case .object(let overlayObj) = overlay else {
            return overlay
        }
        var result = baseObj
        for (key, overlayValue) in overlayObj {
            if let index = result.firstIndex(where: { $0.0 == key }) {
                result[index] = (key, merge(base: result[index].1, overlay: overlayValue))
            } else {
                result.append((key, overlayValue))
            }
        }
        return .object(result)
    }
}
