import Foundation

public enum JSONFlatten {
    /// {"user":{"name":"x","tags":["a","b"]}} -> {"user.name":"x","user.tags.0":"a","user.tags.1":"b"}
    public static func flatten(_ node: JSONNode) -> JSONNode {
        switch node {
        case .object, .array:
            break // flatten below
        default:
            return node // scalars have nothing to flatten
        }
        var result: [(String, JSONNode)] = []

        func walk(_ node: JSONNode, prefix: String) {
            switch node {
            case .object(let pairs):
                if pairs.isEmpty {
                    result.append((prefix, .object([])))
                    return
                }
                for (key, value) in pairs {
                    walk(value, prefix: prefix.isEmpty ? key : "\(prefix).\(key)")
                }
            case .array(let items):
                if items.isEmpty {
                    result.append((prefix, .array([])))
                    return
                }
                for (i, value) in items.enumerated() {
                    walk(value, prefix: prefix.isEmpty ? "\(i)" : "\(prefix).\(i)")
                }
            default:
                result.append((prefix, node))
            }
        }

        walk(node, prefix: "")
        return .object(result)
    }

    /// Reverses flatten(): {"user.name":"x","user.tags.0":"a"} -> {"user":{"name":"x","tags":["a"]}}
    public static func unflatten(_ node: JSONNode) -> JSONNode {
        guard case .object(let pairs) = node else { return node }

        final class TreeNode {
            var children: [(String, TreeNode)] = []
            var value: JSONNode?

            func child(_ key: String) -> TreeNode {
                if let idx = children.firstIndex(where: { $0.0 == key }) {
                    return children[idx].1
                }
                let n = TreeNode()
                children.append((key, n))
                return n
            }
        }

        let root = TreeNode()
        for (path, value) in pairs {
            let segments = path.isEmpty ? [] : path.split(separator: ".").map(String.init)
            if segments.isEmpty {
                root.value = value
                continue
            }
            var cur = root
            for seg in segments { cur = cur.child(seg) }
            cur.value = value
        }

        func build(_ node: TreeNode) -> JSONNode {
            if node.children.isEmpty {
                return node.value ?? .null
            }
            let keys = node.children.map { $0.0 }
            let allIndices = keys.compactMap { Int($0) }
            let isArray = allIndices.count == keys.count
                && Set(allIndices) == Set(0..<keys.count)
            if isArray {
                let sorted = node.children.sorted { Int($0.0)! < Int($1.0)! }
                return .array(sorted.map { build($0.1) })
            }
            return .object(node.children.map { ($0.0, build($0.1)) })
        }

        return build(root)
    }
}
