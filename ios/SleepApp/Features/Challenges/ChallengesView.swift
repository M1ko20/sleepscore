import SwiftUI

struct ChallengesView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                Text("Žádná výzva. Někoho vyzvi.")
                    .captionStyle()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 120)
            }
            .background(Color.app.bg)
            .navigationTitle("Výzvy")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                    } label: {
                        Image(systemName: "plus").fontWeight(.medium)
                    }
                    .disabled(true)
                    .accessibilityLabel("Nová výzva")
                }
            }
        }
    }
}
