import SwiftUI

/// Avatar: profilovka ze Storage, dokud se nenačte (nebo když není) iniciála.
struct Avatar: View {
    let name: String
    var path: String? = nil
    var size: CGFloat = 28

    init(name: String, path: String? = nil, size: CGFloat = 28) {
        self.name = name
        self.path = path
        self.size = size
    }

    init(profile: ProfileLite, size: CGFloat = 28) {
        self.init(name: profile.displayName, path: profile.avatarPath, size: size)
    }

    var body: some View {
        Circle()
            .fill(Color.app.surfaceRaised)
            .overlay(
                Text(name.prefix(1).uppercased())
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Color.app.textPrimary)
            )
            .overlay {
                if let path {
                    StorageImage(bucket: .avatars, path: path) { $0.resizable().scaledToFill() }
                        .clipShape(Circle())
                }
            }
            .overlay(Circle().strokeBorder(Color.app.hairline, lineWidth: 1))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Obrázek ze Storage přes `ImageStore` (disková cache). Dokud není, nic nekreslí.
struct StorageImage<Content: View>: View {
    let bucket: Bucket
    let path: String
    @ViewBuilder var content: (Image) -> Content

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image = image ?? ImageStore.shared.cached(bucket, path) {
                content(Image(uiImage: image))
            } else {
                Color.clear
            }
        }
        .task(id: path) {
            image = await ImageStore.shared.image(bucket, path)
        }
    }
}

/// Fotka ke kartě: 4:5, rádius 10, bez filtru (design.md).
struct PostPhoto: View {
    let path: String

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.app.surfaceRaised)
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .overlay {
                StorageImage(bucket: .nightPhotos, path: path) { $0.resizable().scaledToFill() }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel("Fotka")
    }
}

/// Popisek + hodnota (sportovní statistika).
struct StatBlock: View {
    let value: String
    let label: String
    var font: Font = Font.app.stat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(font).foregroundStyle(Color.app.textPrimary).lineLimit(1)
            Text(label).statLabel()
        }
        .accessibilityElement(children: .combine)
    }
}
