import SwiftUI

struct FeedView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Metrics.cardSpacing) {
                    Text("Zatím tu nikdo není. Pošli pozvánku.")
                        .captionStyle()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 120)
                }
                .padding(.horizontal, Metrics.screenPadding)
            }
            .background(Color.app.bg)
            .navigationTitle("Feed")
        }
    }
}
