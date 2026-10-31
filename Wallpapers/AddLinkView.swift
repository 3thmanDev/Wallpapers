import SwiftUI

/// Gets a tweet's photos from its link, without signing in.
enum LinkImporter {
    static func wallpapers(statusID: String) async -> [Wallpaper] {
        let now = Date()
        if let data = await fetch(TweetLookup.fxURL(statusID: statusID)) {
            let found = TweetLookup.wallpapers(fromFx: data, statusID: statusID, addedAt: now)
            if !found.isEmpty { return found }
        }
        if let data = await fetch(TweetLookup.syndicationURL(statusID: statusID)) {
            return TweetLookup.wallpapers(fromSyndication: data, statusID: statusID, addedAt: now)
        }
        return []
    }

    private static func fetch(_ url: URL) async -> Data? {
        let request = URLRequest(url: url, timeoutInterval: 20)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}

struct AddLinkView: View {
    private enum Status: Equatable {
        case idle
        case working
        case done(String)
        case failed(String)
    }

    @EnvironmentObject private var store: LibraryStore
    @State private var text = ""
    @State private var status = Status.idle
    @FocusState private var fieldFocused: Bool
    /// Switches to the wallpapers tab.
    let onDone: () -> Void

    init(onDone: @escaping () -> Void) {
        self.onDone = onDone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("إضافة برابط")
                .font(.cairo(22, .black))
            Text("من تويتر اضغط مشاركة ← نسخ الرابط، وبعدها الصقه هنا. تقدر تلصق كذا رابط مرة وحدة.")
                .font(.cairo(14))
                .foregroundColor(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            PasteButton(payloadType: String.self) { strings in
                let pasted = strings.joined(separator: "\n")
                Task { @MainActor in await importLinks(pasted) }
            }
            .buttonBorderShape(.capsule)
            .labelStyle(.titleAndIcon)
            .tint(Theme.accent)
            .frame(maxWidth: .infinity)
            .disabled(status == .working)

            HStack(spacing: 8) {
                TextField("أو اكتب الرابط هنا", text: $text)
                    .font(.cairo(15))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($fieldFocused)
                    .onSubmit { Task { await importLinks(text) } }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.raised))
                Button {
                    Task { await importLinks(text) }
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(Theme.accent)
                }
                .disabled(text.isEmpty || status == .working)
            }

            statusView
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Theme.background.ignoresSafeArea())
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .idle:
            EmptyView()
        case .working:
            HStack(spacing: 10) {
                ProgressView().tint(Theme.accent)
                Text("يجيب الصور…").font(.cairo(15, .semibold))
            }
        case .done(let message):
            VStack(alignment: .leading, spacing: 14) {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.cairo(15, .semibold))
                    .foregroundColor(Theme.accent)
                SecondaryButton(title: "شوف الخلفيات", systemImage: "photo.stack", action: onDone)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.cairo(15, .semibold))
                .foregroundColor(Theme.warn)
        }
    }

    private func importLinks(_ input: String) async {
        let ids = TweetLink.statusIDs(in: input)
        guard !ids.isEmpty else {
            status = .failed("ما لقيت رابط تغريدة. انسخه من زر المشاركة بتويتر.")
            return
        }
        fieldFocused = false
        status = .working
        var photos = 0
        var added = 0
        var empty = 0
        for id in ids {
            let found = await LinkImporter.wallpapers(statusID: id)
            if found.isEmpty { empty += 1 }
            photos += found.count
            added += store.add(found, reviveDeleted: true)
        }
        text = ""
        if photos == 0 {
            status = .failed(ids.count == 1 ? "ما لقيت صور بالتغريدة، أو الحساب خاص." : "ما لقيت صور بهالتغريدات، أو الحسابات خاصة.")
        } else if added == 0 {
            status = .done("موجودة عندك من قبل")
        } else {
            let skipped = empty > 0 ? " · \(empty) رابط بدون صور" : ""
            status = .done("انضافت \(added) خلفية\(skipped)")
        }
    }
}
