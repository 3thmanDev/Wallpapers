import SwiftUI
import WebKit

struct ImportView: View {
    @StateObject private var session: ImportSession
    /// Switches to the wallpapers tab.
    let onDone: () -> Void

    init(store: LibraryStore, onDone: @escaping () -> Void) {
        _session = StateObject(wrappedValue: ImportSession(store: store))
        self.onDone = onDone
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            WebViewContainer(webView: session.webView)
                .overlay(alignment: .top) {
                    if session.isLoading {
                        ProgressView()
                            .tint(Theme.accent)
                            .padding(10)
                            .background(Circle().fill(Theme.surface))
                            .padding(.top, 14)
                    }
                }
            panel
        }
        .background(Theme.background.ignoresSafeArea())
        .task { await session.begin() }
        .onChange(of: session.isRunning) { running in
            // A long list takes a few minutes; don't let the screen lock halfway.
            UIApplication.shared.isIdleTimerDisabled = running
        }
        .onDisappear {
            session.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                Text("استيراد من تويتر")
                    .font(.cairo(22, .black))
                Spacer()
                Menu {
                    Button { session.reload() } label: {
                        Label("تحديث الصفحة", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) {
                        Task { await session.signOut() }
                    } label: {
                        Label("تسجيل خروج من تويتر", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 44, height: 32)
                }
            }
            SourceSwitch(selection: session.source) { session.select($0) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var panel: some View {
        VStack(spacing: 14) {
            switch session.isLoggedIn {
            case .none:
                status(icon: "hourglass", title: "يفتح تويتر…", detail: nil)
            case .some(false):
                status(
                    icon: "person.crop.circle.badge.checkmark",
                    title: "سجّل دخولك بتويتر فوق",
                    detail: "مرة وحدة بس، ويبقى محفوظ داخل التطبيق. استخدم اليوزر والباسورد، الدخول بقوقل غالباً ما يشتغل هنا."
                )
            case .some(true):
                if session.isRunning {
                    HStack(spacing: 12) {
                        ProgressView().tint(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("يسحب \(session.source.title)…")
                                .font(.cairo(16, .bold))
                            Text("خلّ الصفحة مفتوحة لين يخلص")
                                .font(.cairo(13))
                                .foregroundColor(Theme.secondary)
                        }
                        Spacer()
                    }
                    counts
                    SecondaryButton(title: "إيقاف", systemImage: "pause.fill") { session.stop() }
                } else if session.reachedEnd {
                    if session.caughtUp {
                        status(
                            icon: "checkmark.circle.fill",
                            title: session.added > 0 ? "انضافت \(session.added) جديدة" : "ما فيه جديد",
                            detail: "وقف لما وصل للصور اللي عندك من قبل."
                        )
                    } else {
                        status(icon: "checkmark.circle.fill", title: "خلصت \(session.source.title)", detail: nil)
                        counts
                    }
                    let other: WallpaperSource = session.source == .bookmarks ? .likes : .bookmarks
                    PrimaryButton(title: "اسحب \(other.title)", systemImage: "arrow.down.circle.fill") {
                        session.select(other, startNow: true)
                    }
                    SecondaryButton(title: "شوف الخلفيات", systemImage: "photo.stack", action: onDone)
                    if session.caughtUp { fullScanButton }
                } else {
                    if session.found > 0 { counts }
                    if session.canImportNewOnly {
                        PrimaryButton(title: "اسحب الجديد من \(session.source.title)", systemImage: "arrow.down.circle.fill") {
                            session.start()
                        }
                        fullScanButton
                    } else {
                        PrimaryButton(title: "ابدأ سحب \(session.source.title)", systemImage: "arrow.down.circle.fill") {
                            session.start()
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            Theme.surface
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .ignoresSafeArea(edges: .bottom)
        )
        .animation(.easeOut(duration: 0.2), value: session.isRunning)
        .animation(.easeOut(duration: 0.2), value: session.reachedEnd)
    }

    /// For when an earlier import was stopped halfway and older photos are still missing.
    private var fullScanButton: some View {
        Button {
            session.start(fullScan: true)
        } label: {
            Text("سحب كامل لين آخر القائمة")
                .font(.cairo(14, .semibold))
                .foregroundColor(Theme.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
        }
        .buttonStyle(.plain)
    }

    private var counts: some View {
        HStack(spacing: 10) {
            CountPill(value: session.found, label: "صورة لقيتها")
            CountPill(value: session.added, label: "جديدة انضافت")
        }
    }

    private func status(icon: String, title: String, detail: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(Theme.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.cairo(16, .bold))
                if let detail {
                    Text(detail)
                        .font(.cairo(13))
                        .foregroundColor(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct SourceSwitch: View {
    let selection: WallpaperSource
    let onSelect: (WallpaperSource) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach([WallpaperSource.bookmarks, .likes], id: \.self) { source in
                Button {
                    onSelect(source)
                } label: {
                    Label(source.title, systemImage: source == .bookmarks ? "bookmark.fill" : "heart.fill")
                        .font(.cairo(14, .semibold))
                        .foregroundColor(selection == source ? Theme.accentInk : Theme.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(selection == source ? Theme.accent : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        .animation(.easeOut(duration: 0.2), value: selection)
    }
}

private struct CountPill: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 0) {
            Text("\(value)")
                .font(.cairo(22, .black))
                .monospacedDigit()
            Text(label)
                .font(.cairo(12, .medium))
                .foregroundColor(Theme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.raised))
    }
}

private struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
