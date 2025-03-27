/// Represents permission states
public enum PermissionStatus: Equatable {
    case unknown
    case checking
    case authorized
    case denied
    case restricted
    case limited
}
