import SwiftUI
import Zoomable

struct CapturePreviewOverlay: View {
    let image: UIImage
    let onDismiss: () -> Void
    let onConfirm: () -> Void
    @GestureState private var magnifyBy = 1.0
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                        
                    }
                    
                    Spacer()
                    
                    Text("Review")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: onConfirm) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.green)
                    }
                }
                .padding()
                
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                    .zoomable()
                    .padding()
                
                Spacer()
            }
            .padding()
        }
    }
    
}
