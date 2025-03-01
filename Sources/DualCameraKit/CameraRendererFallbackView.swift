import UIKit

/// Fallback view displayed when camera rendering fails
final class CameraRendererFallbackView: UIView {
    
    // MARK: - Constants
    private enum ViewMetrics {
        static let iconSize: CGFloat = 48
        static let stackSpacing: CGFloat = 12
        static let backgroundAlpha: CGFloat = 0.7
        static let fontSize: CGFloat = 16
        static let fontWeight: UIFont.Weight = .medium
    }
    
    private enum LocalizedStrings {
        static let defaultMessage = "Camera preview unavailable"
        static let defaultIconName = "video.slash.fill"
    }
    
    // MARK: - UI Components
    
    private let iconView: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: LocalizedStrings.defaultIconName))
        view.tintColor = .white
        view.contentMode = .scaleAspectFit
        return view
    }()
    
    private let messageLabel: UILabel = {
        let label = UILabel()
        label.text = LocalizedStrings.defaultMessage
        label.textAlignment = .center
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: ViewMetrics.fontSize, weight: ViewMetrics.fontWeight)
        return label
    }()
    
    private lazy var stackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [iconView, messageLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = ViewMetrics.stackSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    // MARK: - Setup
    
    private func setupView() {
        backgroundColor = UIColor.black.withAlphaComponent(ViewMetrics.backgroundAlpha)
        addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.heightAnchor.constraint(equalToConstant: ViewMetrics.iconSize),
            iconView.widthAnchor.constraint(equalToConstant: ViewMetrics.iconSize)
        ])
    }
    
    // MARK: - Configuration
    
    /// Updates the message displayed in the fallback view
    func updateMessage(_ message: String) {
        messageLabel.text = message
    }
    
    /// Updates the icon displayed in the fallback view
    func updateIcon(systemName: String) {
        iconView.image = UIImage(systemName: systemName)
    }
}
