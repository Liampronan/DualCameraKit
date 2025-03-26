import SwiftUI

/// Defines different layouts for dual-camera display
public enum DualCameraLayout: Equatable, Hashable {
    
    case sideBySide
    case stackedVertical
    case piP(miniCamera: CameraSource, miniCameraPosition: MiniCameraPosition)
    
    /// Positions for mini camera
    public enum MiniCameraPosition: CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
        
        func alignment() -> Alignment {
            switch self {
            case .topLeading:     return .topLeading
            case .topTrailing:    return .topTrailing
            case .bottomLeading:  return .bottomLeading
            case .bottomTrailing: return .bottomTrailing
            }
        }
        
        var title: String {
            switch self {
            case .topLeading:     return "Top Left"
            case .topTrailing:    return "Top Right"
            case .bottomLeading:  return "Bottom Left"
            case .bottomTrailing: return "Bottom Right"
            }
        }
    }    
}

extension DualCameraLayout {
    
    public static var menuItems: [MenuItem] {
        let standardItems: [MenuItem] = [
            .entry(title: DualCameraLayout.sideBySide.title, layout: .sideBySide),
            .entry(title: DualCameraLayout.stackedVertical.title, layout: .stackedVertical)
        ]
        
        // PiP layouts grouped in a submenu
        var pipItems: [MenuItem] = []
        
        // Front camera options
        for position in MiniCameraPosition.allCases {
            let layout: DualCameraLayout = .piP(miniCamera: .front, miniCameraPosition: position)
            pipItems.append(.entry(title: layout.title, layout: layout))
        }
        
        // Back camera options
        for position in MiniCameraPosition.allCases {
            let layout: DualCameraLayout = .piP(miniCamera: .back, miniCameraPosition: position)
            pipItems.append(.entry(title: layout.title, layout: layout))
        }
        
        return standardItems + [.submenu(title: "PiP Mode", items: pipItems)]
    }
    
    public enum MenuItem: Identifiable {
        public var id: String {
            switch self {
            case .entry(let title, let layout):
                return "entry_\(title)_\(layout.idString)"
            case .submenu(let title, _):
                return "submenu_\(title)"
            }
        }
        
        case entry(title: String, layout: DualCameraLayout)
        case submenu(title: String, items: [MenuItem])
    }
    
    public var title: String {
        switch self {
        case .sideBySide:
            return "Side by Side"
        case .stackedVertical:
            return "Stacked Vertical"
        case .piP(let miniCamera, let position):
            let cameraText = miniCamera == .front ? "Front" : "Back"
            return "\(cameraText) Mini - \(position.title)"
        }
    }
    
    var idString: String {
        switch self {
        case .sideBySide:
            return "sideBySide"
        case .stackedVertical:
            return "stackedVertical"
        case .piP(let miniCamera, let position):
            return "fullScreenWithMini_\(miniCamera)_\(position)"
        }
    }
}
