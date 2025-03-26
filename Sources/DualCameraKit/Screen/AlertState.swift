import UIKit

struct AlertState: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let primaryButton: AlertButton
    var secondaryButton: AlertButton? = nil
    
    struct AlertButton: Equatable {        
        let id = UUID()
        let text: String
        let action: () -> Void
        
        static func == (lhs: AlertState.AlertButton, rhs: AlertState.AlertButton) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    // Helper for simple OK alerts
    static func info(title: String, message: String, onDismiss: @escaping () -> Void = {}) -> AlertState {
        AlertState(
            title: title,
            message: message,
            primaryButton: AlertButton(text: "OK", action: onDismiss)
        )
    }
    
    // Helper for permission denied alerts
    static func permissionDenied(message: String, onTapOpenSettings: @escaping () -> Void = {
        Task { @MainActor in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }) -> AlertState {
        AlertState(
            title: "Permission Required",
            message: message,
            primaryButton: AlertButton(text: "Open Settings", action: onTapOpenSettings),
            secondaryButton: AlertButton(text: "Cancel", action: {})
        )
    }
    
}
