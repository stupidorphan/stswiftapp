import SwiftUI

/// Authenticated async image loader using STAPIClient's URLSession with auth headers.
struct STAuthAsyncImage: View {
    let avatar: String?
    let name: String
    let isGroup: Bool
    let cornerRadius: CGFloat
    let size: CGFloat

    @State private var imageData: Data?
    @State private var loadFailed = false

    init(avatar: String?, name: String, isGroup: Bool = false, cornerRadius: CGFloat = 8, size: CGFloat = 48) {
        self.avatar = avatar
        self.name = name
        self.isGroup = isGroup
        self.cornerRadius = cornerRadius
        self.size = size
    }

    var body: some View {
        Group {
            if let data = imageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if loadFailed {
                fallbackAvatar
            } else {
                ProgressView()
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task { await loadImage() }
    }

    private var fallbackAvatar: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.gray.opacity(0.3))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: isGroup ? "person.3.fill" : "person.fill")
                    .foregroundStyle(.gray)
                    .font(.system(size: size * 0.4))
            }
    }

    private func loadImage() async {
        guard let avatar = avatar else {
            loadFailed = true
            return
        }

        // Check cache first
        let cacheKey = "thumb_\(avatar)"
        if let cached = STImageCache.shared.get(for: cacheKey) {
            imageData = cached
            return
        }

        // Try thumbnail, fall back to character avatar, then user avatars
        let paths = [
            "/thumbnail/avatar/\(avatar)?type=avatar",
            "/thumbnail?type=persona&file=\(avatar)",
            "/characters/\(avatar)",
            "/User%20Avatars/\(avatar)"
        ]

        for path in paths {
            guard var req = STAPIClient.shared.authenticatedRequest(for: path) else { continue }
            req.timeoutInterval = 15

            do {
                let (data, resp) = try await STAPIClient.shared.urlSessionForImages.data(for: req)
                guard let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 else { continue }
                STImageCache.shared.set(data, for: cacheKey)
                await MainActor.run { imageData = data }
                return
            } catch {
                continue
            }
        }
        await MainActor.run { loadFailed = true }
    }
}

/// Circular variant for iMessage-style headers
struct STAuthCircularImage: View {
    let avatar: String?
    let name: String
    let size: CGFloat

    @State private var imageData: Data?
    @State private var loadFailed = false

    init(avatar: String?, name: String, size: CGFloat = 56) {
        self.avatar = avatar
        self.name = name
        self.size = size
    }

    var body: some View {
        Group {
            if let data = imageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if loadFailed {
                fallback
            } else {
                ProgressView()
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task { await loadImage() }
    }

    private var fallback: some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: size, height: size)
            .overlay {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.gray)
            }
    }

    private func loadImage() async {
        guard let avatar = avatar else {
            loadFailed = true
            return
        }
        let cacheKey = "circ_\(avatar)"
        if let cached = STImageCache.shared.get(for: cacheKey) {
            imageData = cached
            return
        }
        let paths = [
            "/thumbnail/avatar/\(avatar)?type=avatar",
            "/characters/\(avatar)",
            "/User%20Avatars/\(avatar)"
        ]
        for path in paths {
            guard var req = STAPIClient.shared.authenticatedRequest(for: path) else { continue }
            req.timeoutInterval = 15
            do {
                let (data, resp) = try await STAPIClient.shared.urlSessionForImages.data(for: req)
                guard let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 else { continue }
                STImageCache.shared.set(data, for: cacheKey)
                await MainActor.run { imageData = data }
                return
            } catch { continue }
        }
        await MainActor.run { loadFailed = true }
    }
}
