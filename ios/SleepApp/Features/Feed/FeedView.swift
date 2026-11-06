import SwiftUI

struct FeedView: View {
    @Environment(Session.self) private var session

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Metrics.cardSpacing) {
                    Text(session.profile?.invitedBy != nil
                         ? "První noc se ukáže zítra ráno."
                         : "Zatím tu nikdo není. Pošli pozvánku.")
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
