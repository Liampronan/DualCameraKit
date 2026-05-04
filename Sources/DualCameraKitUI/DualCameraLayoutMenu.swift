import DualCameraKit

public extension DualCameraLayout {
    static var menuItems: [MenuItem] {
        let standardItems: [MenuItem] = [
            .entry(title: DualCameraLayout.sideBySide.title, layout: .sideBySide),
            .entry(title: DualCameraLayout.stackedVertical.title, layout: .stackedVertical)
        ]

        let pipItems = DualCameraSource.allCases.flatMap { source in
            MiniCameraPosition.allCases.map { position in
                let layout = DualCameraLayout.piP(miniCamera: source, miniCameraPosition: position)
                return MenuItem.entry(title: layout.title, layout: layout)
            }
        }

        return standardItems + [.submenu(title: "PiP Mode", items: pipItems)]
    }

    enum MenuItem: Identifiable {
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

    var title: String {
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
}

private extension DualCameraLayout.MiniCameraPosition {
    var title: String {
        switch self {
        case .topLeading:     return "Top Left"
        case .topTrailing:    return "Top Right"
        case .bottomLeading:  return "Bottom Left"
        case .bottomTrailing: return "Bottom Right"
        }
    }
}

private extension DualCameraLayout {
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
