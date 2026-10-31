import Photos
import SwiftUI

struct WallpaperViewer: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var items: [Wallpaper]
    @State private var currentID: String
    @State private var chromeVisible = true
    @State private var lockPreview = false
    @State private var saving = false
    @State private var confirmingDelete = false
    @State private var toast: String?

    init(items: [Wallpaper], startID: String) {
        _items = State(initialValue: items)
        _currentID = State(initialValue: startID)
    }

    private var current: Wallpaper? {
        items.first { $0.id == currentID }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $currentID) {
                ForEach(items) { wallpaper in
                    FullImage(wallpaper: wallpaper, fill: lockPreview)
                        .tag(wallpaper.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.2)) { chromeVisible.toggle() }
            }

            if lockPreview {
                LockScreenOverlay()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            if chromeVisible {
                controls.transition(.opacity)
            }
        }
        .statusBarHidden(!chromeVisible)
        .toast($toast)
        .confirmationDialog("حذف الخلفية؟", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("حذف", role: .destructive) { deleteCurrent() }
        } message: {
            Text("تنحذف من التطبيق بس، وتبقى في تويتر.")
        }
    }

    private var controls: some View {
        VStack {
            HStack {
                RoundButton(systemImage: "xmark") { dismiss() }
                Spacer()
                if let index = items.firstIndex(where: { $0.id == currentID }) {
                    Text("\(index + 1) من \(items.count)")
                        .font(.cairo(14, .semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassBackground(Capsule())
                }
                Spacer()
                RoundButton(systemImage: "trash") { confirmingDelete = true }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()

            HStack(spacing: 0) {
                ActionButton(title: "حفظ بالصور", systemImage: saving ? "hourglass" : "square.and.arrow.down") {
                    saveCurrent()
                }
                ActionButton(title: lockPreview ? "إخفاء المعاينة" : "معاينة", systemImage: lockPreview ? "lock.open.fill" : "lock.fill") {
                    withAnimation(.easeInOut(duration: 0.25)) { lockPreview.toggle() }
                }
                if let current {
                    ShareLink(item: store.originalFile(current)) {
                        ActionLabel(title: "مشاركة", systemImage: "square.and.arrow.up")
                    }
                    .frame(maxWidth: .infinity)
                    if let tweetURL = current.tweetURL {
                        Link(destination: tweetURL) {
                            ActionLabel(title: "التغريدة", systemImage: "arrow.up.forward.app")
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.vertical, 10)
            .glassBackground(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
        .foregroundColor(.white)
    }

    private func saveCurrent() {
        guard let current, !saving else { return }
        saving = true
        Task {
            do {
                try await PhotoSaver.save(store.originalFile(current))
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                toast = "انحفظت بالصور ✓\nتحطها خلفية من: الصور ← مشاركة ← استخدام كخلفية"
            } catch PhotoSaver.Failure.denied {
                toast = "اسمح للتطبيق يضيف للصور من الإعدادات ← خلفياتي ← الصور"
            } catch {
                toast = "ما قدرت أحفظها، جرّب مرة ثانية"
            }
            saving = false
        }
    }

    private func deleteCurrent() {
        guard let index = items.firstIndex(where: { $0.id == currentID }) else { return }
        let removed = items.remove(at: index)
        store.delete([removed.id])
        if items.isEmpty {
            dismiss()
        } else {
            currentID = items[min(index, items.count - 1)].id
        }
    }
}

private struct FullImage: View {
    let wallpaper: Wallpaper
    let fill: Bool
    @EnvironmentObject private var store: LibraryStore
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: fill ? .fill : .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .task(id: wallpaper.id) { await load() }
    }

    private func load() async {
        let key = "full-\(wallpaper.id)"
        if let cached = ImageCache.shared.image(key) {
            image = cached
            return
        }
        let file = store.originalFile(wallpaper)
        let loaded = await Task.detached(priority: .userInitiated) {
            ImageTools.image(at: file, maxPixel: 2800)
        }.value
        if let loaded {
            ImageCache.shared.store(loaded, key)
        }
        image = loaded
    }
}

/// Roughly what the iPhone lock screen draws over the wallpaper: date, big clock, the two corner buttons.
private struct LockScreenOverlay: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: 0) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .padding(.bottom, 10)
                Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(AppLocale.locale)))
                    .font(.system(size: 21, weight: .semibold))
                Text(context.date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute().locale(AppLocale.locale)))
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Spacer()
                HStack {
                    corner("flashlight.off.fill")
                    Spacer()
                    corner("camera.fill")
                }
                .padding(.horizontal, 44)
                .padding(.bottom, 34)
            }
            .foregroundColor(.white.opacity(0.94))
            .shadow(color: .black.opacity(0.25), radius: 12)
            .padding(.top, 54)
        }
        .ignoresSafeArea()
    }

    private func corner(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 20, weight: .medium))
            .frame(width: 50, height: 50)
            .background(Circle().fill(.ultraThinMaterial))
    }
}

private struct RoundButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 40, height: 40)
                .glassBackground(Circle())
        }
        .buttonStyle(PressableStyle())
    }
}

private struct ActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ActionLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(PressableStyle())
        .frame(maxWidth: .infinity)
    }
}

private struct ActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .frame(height: 24)
            Text(title)
                .font(.cairo(12, .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

enum PhotoSaver {
    enum Failure: Error {
        case denied
    }

    /// Adds the original file itself, so Photos gets every pixel X kept.
    static func save(_ file: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.denied }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: file, options: nil)
        }
    }
}
