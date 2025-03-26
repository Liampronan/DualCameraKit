import SwiftUI

struct SheetStyle: ViewModifier {
    let title: String
    @Environment(\.dismiss) private var dismiss
    
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.leading)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .padding(.trailing)
            }
            .padding(.top)
            .background(Color(.systemBackground))
            
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
        }
    }
}

// Extension to make it easy to use
extension View {
    func sheetStyle(title: String) -> some View {
        modifier(SheetStyle(title: title))
    }
}
