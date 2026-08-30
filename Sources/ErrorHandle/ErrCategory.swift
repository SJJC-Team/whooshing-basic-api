@preconcurrency import AnyCodable

/// 系统的基础错误类别枚举。
/// - parameter: 表示提供给函数或接口的参数无效。
/// - internal: 表示系统在处理过程中出现了内部错误。
public enum ErrCategory: Sendable, Codable, Hashable, CustomStringConvertible {
    case external(suggestions: [String] = [], userdata: AnyCodable? = nil)
    case `internal`
    case inherit
    
    public var description: String {
        switch self {
        case .external(let suggestions, let data): "external(\(suggestions.joined(separator: " | ")))"
        case .internal: "internal"
        case .inherit: "inherit"
        }
    }
}
