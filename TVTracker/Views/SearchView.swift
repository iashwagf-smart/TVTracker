import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.modelContext) private var context
    @Query private var myShows: [Show]

    @State private var query = ""
    @State private var results: [TVMazeShow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var adding: Set<Int> = []

    private var myIDs: Set<Int> { Set(myShows.map(\.id)) }

    var body: some View {
        NavigationStack {
            List {
                ForEach(results) { show in
                    NavigationLink(value: show) {
                        SearchRow(show: show,
                                  isAdded: myIDs.contains(show.id),
                                  isAdding: adding.contains(show.id)) {
                            add(show)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("بحث")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "اسم المسلسل بالإنجليزي")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .task(id: query) { await search() }
            .navigationDestination(for: TVMazeShow.self) { RemoteShowView(remote: $0) }
            .navigationDestination(for: Show.self) { ShowDetailView(show: $0) }
            .overlay {
                if isLoading && results.isEmpty {
                    ProgressView()
                } else if let errorMessage {
                    EmptyStateView(icon: "wifi.exclamationmark", title: "صار خطأ", message: errorMessage)
                } else if query.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", title: "دوّر على مسلسل",
                                   message: "اكتب اسم المسلسل وضيفه لقائمتك")
                } else if results.isEmpty && !isLoading {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else {
            results = []
            errorMessage = nil
            return
        }
        // debounce
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard !Task.isCancelled else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let found = try await TVMazeAPI.search(q)
            guard !Task.isCancelled else { return }
            results = found
            errorMessage = nil
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            errorMessage = "تأكد من اتصالك بالإنترنت"
        }
    }

    private func add(_ show: TVMazeShow) {
        guard !adding.contains(show.id) else { return }
        adding.insert(show.id)
        Task {
            defer { adding.remove(show.id) }
            try? await Library.add(show, in: context)
        }
    }
}

private struct SearchRow: View {
    let show: TVMazeShow
    let isAdded: Bool
    let isAdding: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PosterView(url: show.image?.medium, cornerRadius: 6)
                .frame(width: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(show.name).font(.headline).lineLimit(2)
                HStack(spacing: 6) {
                    if let year = show.year { Text(year) }
                    if let ch = show.channelName { Text("· \(ch)") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let genres = show.genres, !genres.isEmpty {
                    Text(genres.prefix(3).joined(separator: "، "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Group {
                if isAdding {
                    ProgressView()
                } else if isAdded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                } else {
                    Button(action: onAdd) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.title)
            .frame(width: 36)
        }
        .padding(.vertical, 2)
    }
}

/// صفحة مسلسل ما أضفته بعد
struct RemoteShowView: View {
    let remote: TVMazeShow
    @Environment(\.modelContext) private var context
    @Query private var local: [Show]
    @State private var isAdding = false
    @State private var failed = false

    init(remote: TVMazeShow) {
        self.remote = remote
        let id = remote.id
        _local = Query(filter: #Predicate<Show> { $0.id == id })
    }

    var body: some View {
        // لو المسلسل مضاف نعرض صفحته الكاملة
        if let show = local.first {
            ShowDetailView(show: show)
        } else {
            preview
        }
    }

    private var preview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    PosterView(url: remote.image?.medium)
                        .frame(width: 130)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(remote.name).font(.title2.bold())
                        if let year = remote.year { Text(year).foregroundStyle(.secondary) }
                        if let ch = remote.channelName { Text(ch).foregroundStyle(.secondary) }
                        if let r = remote.rating?.average {
                            Label(String(format: "%.1f", r), systemImage: "star.fill")
                                .foregroundStyle(.yellow)
                        }
                    }
                    .font(.subheadline)
                }

                HStack {
                    ForEach([TrackingState.watching, .later], id: \.self) { state in
                        Button {
                            add(state)
                        } label: {
                            Label(state == .watching ? "أتابعه" : "أشوفه لاحقاً", systemImage: state.icon)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(state == .watching ? Color.accentColor : Color.gray)
                        .foregroundStyle(state == .watching ? Color.black : Color.white)
                    }
                }
                .disabled(isAdding)
                .overlay { if isAdding { ProgressView() } }

                if failed {
                    Text("ما قدرت أضيفه، جرب مرة ثانية").foregroundStyle(.red).font(.footnote)
                }

                if let summary = remote.summary?.strippingHTML, !summary.isEmpty {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func add(_ state: TrackingState) {
        isAdding = true
        failed = false
        Task {
            do {
                try await Library.add(remote, state: state, in: context)
            } catch {
                failed = true
            }
            isAdding = false
        }
    }
}
