import Foundation

/// A JSON value. Objects keep their original key order (arrays of pairs,
/// not a Dictionary) so formatting round-trips predictably.
public indirect enum JSONNode {
    case object([(String, JSONNode)])
    case array([JSONNode])
    case string(String)
    case number(String)
    case bool(Bool)
    case null
}
