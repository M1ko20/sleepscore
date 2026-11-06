import Foundation
import Supabase
import UIKit

enum Bucket: String, Sendable {
    case avatars
    case nightPhotos = "night-photos"
}

/// Obrázky ze Storage s cache v paměti i na disku.
/// Cesty jsou unikátní (nový soubor = nové jméno), takže obsah pod cestou se nikdy nemění
/// → stáhne se jednou a pak už nikdy (šetří egress i requesty na Free tarifu).
actor ImageStore {
    static let shared = ImageStore()

    private let memory = MemoryCache()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("storage-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    init() {}

    private func key(_ bucket: Bucket, _ path: String) -> String { "\(bucket.rawValue)/\(path)" }

    private func fileURL(_ key: String) -> URL {
        dir.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_"))
    }

    /// Okamžitě z paměti (bez čekání) – aby se avatar při scrollu neprobliknul.
    nonisolated func cached(_ bucket: Bucket, _ path: String) -> UIImage? {
        memory.get("\(bucket.rawValue)/\(path)")
    }

    func image(_ bucket: Bucket, _ path: String) async -> UIImage? {
        let k = key(bucket, path)
        if let img = memory.get(k) { return img }
        if let task = inFlight[k] { return await task.value }

        let url = fileURL(k)
        let task = Task<UIImage?, Never> {
            if let data = try? Data(contentsOf: url), let img = UIImage(data: data) { return img }
            do {
                let data = try await Backend.client.storage.from(bucket.rawValue).download(path: path)
                guard let img = UIImage(data: data) else { return nil }
                try? data.write(to: url, options: .atomic)
                return img
            } catch {
                log.error("image download failed \(k, privacy: .public): \(String(describing: error))")
                return nil
            }
        }
        inFlight[k] = task
        let img = await task.value
        inFlight[k] = nil
        if let img { memory.set(img, k) }
        return img
    }

    /// Po nahrání vlastní fotky: rovnou do cache, ať se znovu nestahuje.
    func store(_ data: Data, _ bucket: Bucket, _ path: String) {
        let k = key(bucket, path)
        try? data.write(to: fileURL(k), options: .atomic)
        if let img = UIImage(data: data) { memory.set(img, k) }
    }

    func remove(_ bucket: Bucket, _ path: String) {
        let k = key(bucket, path)
        memory.remove(k)
        try? FileManager.default.removeItem(at: fileURL(k))
    }
}

/// NSCache je thread-safe → obal jako Sendable, ať jde číst synchronně i mimo actor.
final class MemoryCache: @unchecked Sendable {
    private let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 200
        return c
    }()
    func get(_ k: String) -> UIImage? { cache.object(forKey: k as NSString) }
    func set(_ img: UIImage, _ k: String) { cache.setObject(img, forKey: k as NSString) }
    func remove(_ k: String) { cache.removeObject(forKey: k as NSString) }
}

/// Zmenšení na telefonu: profilovka 256 px čtverec, fotka karty max. 1280 px a ~200 kB.
enum ImageResize {
    static func avatar(_ image: UIImage) -> Data? {
        let side = min(image.size.width, image.size.height)
        let crop = CGRect(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2,
                          width: side, height: side)
        let target = CGSize(width: 256, height: 256)
        let img = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            let scale = target.width / side
            image.draw(in: CGRect(x: -crop.minX * scale, y: -crop.minY * scale,
                                  width: image.size.width * scale, height: image.size.height * scale))
        }
        return jpeg(img, maxBytes: 60_000)
    }

    static func photo(_ image: UIImage) -> Data? {
        let maxSide: CGFloat = 1280
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let target = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let img = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return jpeg(img, maxBytes: 200_000)
    }

    /// Kvalitu snižuje, dokud se soubor nevejde (server má strop 150 / 400 kB).
    private static func jpeg(_ img: UIImage, maxBytes: Int) -> Data? {
        var q: CGFloat = 0.8
        while q >= 0.3 {
            if let d = img.jpegData(compressionQuality: q), d.count <= maxBytes { return d }
            q -= 0.1
        }
        return img.jpegData(compressionQuality: 0.25)
    }

    /// 1 bod = 1 pixel (jinak by @3x obrazovka ztrojnásobila rozměr).
    private static var format: UIGraphicsImageRendererFormat {
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        f.opaque = true
        return f
    }
}
