import SwiftUI

private enum LibraryFilter: Hashable {
    case all
    case source(WallpaperSource)
}

private struct ViewerRequest: Identifiable {
    let id = UUID()
    let items: [Wallpaper]
    let startID: String
}

struct LibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var filter = LibraryFilter.all
    @State private var portraitOnly = false
    @State private var viewer: ViewerRequest?
    @State private var selecting = false
    @State private var selection: Set<String> = []
    @State private var confirmingDelete = false
    let onImport: () -> Void
    let onAddLink: () -> Void

    init(onImport: @escaping () -> Void, onAddLink: @escaping () -> Void) {
        self.onImport = onImport
        self.onAddLink = onAddLink
    }

    private var items: [Wallpaper] {
        store.library.wallpapers.filter { wallpaper in
            if portraitOnly && !wallpaper.isPortrait { return false }
            switch filter {
            case .all: return true
            case .source(let source): return wallpaper.sources.contains(source)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.library.wallpapers.isEmpty {
                    EmptyLibrary(onImport: onImport, onAddLink: onAddLink)
                } else {
                    grid
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("خلفياتي")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !store.library.wallpapers.isEmpty {
                        Button(selecting ? "إلغاء" : "تحديد") {
                            selecting.toggle()
                            selection = []
                        }
                        .font(.cairo(16, .semibold))
                    }
                }
            }
            // The delete bar takes the tab bar's place while choosing.
            .toolbar(selecting ? .hidden : .visible, for: .tabBar)
            .safeAreaInset(edge: .bottom) {
                if selecting { selectionBar }
            }
        }
        .fullScreenCover(item: $viewer) { request in
            WallpaperViewer(items: request.items, startID: request.startID)
                .environmentObject(store)
                .appEnvironment()
        }
        .confirmationDialog("حذف \(selection.count) خلفية؟", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("حذف", role: .destructive) {
                store.delete(selection)
                selection = []
                selecting = false
            }
        } message: {
            Text("تنحذف من التطبيق بس، وتبقى في تويتر. ولو سحبت المفضلة مرة ثانية ما ترجع.")
        }
    }

    private var grid: some View {
        let visible = items
        return ScrollView {
            VStack(spacing: 14) {
                if store.library.pendingCount > 0 || store.library.failedCount > 0 {
                    DownloadBanner()
                }
                FilterBar(filter: $filter, portraitOnly: $portraitOnly)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(visible) { wallpaper in
                        WallpaperCell(wallpaper: wallpaper, selected: selecting ? selection.contains(wallpaper.id) : nil)
                            .onTapGesture { open(wallpaper, in: visible) }
                    }
                }
                .padding(.horizontal, 10)
                if visible.isEmpty {
                    Text("ما فيه خلفيات هنا")
                        .font(.cairo(15))
                        .foregroundColor(Theme.secondary)
                        .padding(.top, 40)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 12) {
            Button("الكل") { selection = Set(items.map(\.id)) }
                .font(.cairo(16, .semibold))
            Text("\(selection.count) محددة")
                .font(.cairo(15, .medium))
                .foregroundColor(Theme.secondary)
            Spacer()
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("حذف", systemImage: "trash")
                    .font(.cairo(16, .bold))
                    .foregroundColor(selection.isEmpty ? Theme.secondary : Theme.bad)
            }
            .disabled(selection.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }

    private func open(_ wallpaper: Wallpaper, in items: [Wallpaper]) {
        if selecting {
            if selection.contains(wallpaper.id) {
                selection.remove(wallpaper.id)
            } else {
                selection.insert(wallpaper.id)
            }
        } else if wallpaper.isDownloaded {
            viewer = ViewerRequest(items: items.filter(\.isDownloaded), startID: wallpaper.id)
        } else if wallpaper.failed {
            store.retryFailed()
        }
    }
}

private struct FilterBar: View {
    @EnvironmentObject private var store: LibraryStore
    @Binding var filter: LibraryFilter
    @Binding var portraitOnly: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(title: "الكل", count: store.library.wallpapers.count, isOn: filter == .all) {
                    filter = .all
                }
                ForEach(WallpaperSource.allCases, id: \.self) { source in
                    let count = store.library.count(of: source)
                    if count > 0 {
                        Chip(title: source.title, count: count, isOn: filter == .source(source)) {
                            filter = .source(source)
                        }
                    }
                }
                Rectangle()
                    .fill(Theme.line)
                    .frame(width: 1, height: 22)
                Chip(title: "طولية بس", systemImage: "iphone", isOn: portraitOnly) {
                    portraitOnly.toggle()
                }
            }
            .padding(.horizontal, 10)
        }
    }
}

private struct Chip: View {
    let title: String
    var count: Int?
    var systemImage: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 12, weight: .semibold))
                }
                Text(title).font(.cairo(14, .semibold))
                if let count {
                    Text("\(count)")
                        .font(.cairo(12, .bold))
                        .monospacedDigit()
                        .opacity(0.7)
                }
            }
            .foregroundColor(isOn ? Theme.accentInk : Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Capsule().fill(isOn ? Theme.accent : Theme.surface))
        }
        .buttonStyle(PressableStyle())
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

private struct DownloadBanner: View {
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        let pending = store.library.pendingCount
        let failed = store.library.failedCount
        HStack(spacing: 12) {
            if pending > 0 {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Theme.accent)
                VStack(alignment: .leading, spacing: 6) {
                    Text("يتنزّل \(pending) خلفية بدقتها الأصلية")
                        .font(.cairo(14, .semibold))
                    ProgressView(value: store.batchProgress)
                        .tint(Theme.accent)
                }
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Theme.warn)
                Text("تعذّر تنزيل \(failed)")
                    .font(.cairo(14, .semibold))
                Spacer()
                Button("إعادة المحاولة") { store.retryFailed() }
                    .font(.cairo(14, .bold))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .padding(.horizontal, 10)
    }
}

private struct WallpaperCell: View {
    let wallpaper: Wallpaper
    /// nil when the grid isn't in selection mode.
    let selected: Bool?
    @EnvironmentObject private var store: LibraryStore
    @State private var image: UIImage?

    var body: some View {
        Theme.surface
            .aspectRatio(9.0 / 16.0, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if wallpaper.failed {
                    Image(systemName: "arrow.clockwise.circle")
                        .font(.system(size: 26))
                        .foregroundColor(Theme.warn)
                } else if !wallpaper.isDownloaded {
                    ProgressView().tint(Theme.secondary)
                } else {
                    Image(systemName: "photo")
                        .foregroundColor(Theme.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                if selected == true {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.accent, lineWidth: 3)
                }
            }
            .overlay(alignment: .topLeading) {
                if let selected {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(selected ? Theme.accent : .white)
                        .shadow(color: .black.opacity(0.4), radius: 3)
                        .padding(7)
                }
            }
            .opacity(selected == true ? 0.75 : 1)
            .contentShape(Rectangle())
            .task(id: wallpaper.isDownloaded) { await load() }
    }

    private func load() async {
        guard wallpaper.isDownloaded else {
            image = nil
            return
        }
        let key = "thumb-\(wallpaper.id)"
        if let cached = ImageCache.shared.image(key) {
            image = cached
            return
        }
        let file = store.thumbnailFile(wallpaper.id)
        let loaded = await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: file.path)?.preparingForDisplay()
        }.value
        if let loaded {
            ImageCache.shared.store(loaded, key)
        }
        image = loaded
    }
}

private struct EmptyLibrary: View {
    let onImport: () -> Void
    let onAddLink: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            StackedCards()
                .frame(height: 170)
                .padding(.bottom, 8)
            Text("خلفياتك من تويتر في مكان واحد")
                .font(.cairo(22, .bold))
                .multilineTextAlignment(.center)
            Text("اسحب كل الصور من العلامات المرجعية والإعجابات بدقتها الأصلية، أو أضف أي تغريدة برابطها.")
                .font(.cairo(15))
                .foregroundColor(Theme.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 10) {
                PrimaryButton(title: "استيراد من تويتر", systemImage: "arrow.down.circle.fill", action: onImport)
                SecondaryButton(title: "إضافة برابط", systemImage: "link", action: onAddLink)
            }
            .padding(.top, 8)
            Spacer()
        }
        .padding(24)
    }
}

/// Three phone-shaped cards, the same picture as the app icon.
private struct StackedCards: View {
    private let gradients: [[Color]] = [
        [Color(red: 0.36, green: 0.80, blue: 0.86), Color(red: 0.18, green: 0.35, blue: 0.78)],
        [Color(red: 1.0, green: 0.62, blue: 0.40), Color(red: 0.86, green: 0.25, blue: 0.55)],
        [Color(red: 0.72, green: 0.62, blue: 1.0), Color(red: 0.36, green: 0.24, blue: 0.82)],
    ]

    var body: some View {
        ZStack {
            card(gradients[0]).rotationEffect(.degrees(-14)).offset(x: -46, y: 10)
            card(gradients[2]).rotationEffect(.degrees(14)).offset(x: 46, y: 10)
            card(gradients[1])
        }
        // Drawn the same way round as the icon whatever the text direction.
        .environment(\.layoutDirection, .leftToRight)
    }

    private func card(_ colors: [Color]) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .frame(width: 84, height: 150)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
    }
}
