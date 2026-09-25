import SwiftUI
import SwiftData

struct MyShowsView: View {
    @Query(sort: \Show.name) private var shows: [Show]

    enum Filter: String, CaseIterable, Identifiable {
        case watching = "أتابعه"
        case upToDate = "محدّث"
        case completed = "مكتمل"
        case later = "لاحقاً"
        case stopped = "توقفت"
        case favorites = "المفضلة"
        var id: String { rawValue }
    }

    @State private var filter: Filter = .watching
    @State private var searchText = ""

    private var filtered: [Show] {
        shows.filter { filter.matches($0) && (searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)) }
    }

    private let columns = [GridItem(.adaptive(minimum: 105), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Filter.allCases) { f in
                            let count = shows.filter(f.matches).count
                            Button {
                                withAnimation { filter = f }
                            } label: {
                                Text("\(f.rawValue) \(count)")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(filter == f ? Color.accentColor : Color.white.opacity(0.1), in: Capsule())
                                    .foregroundStyle(filter == f ? Color.black : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }

                if filtered.isEmpty {
                    Text("ما فيه مسلسلات هنا")
                        .foregroundStyle(.secondary)
                        .padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(filtered) { show in
                            NavigationLink(value: show) {
                                ShowGridCell(show: show)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("مسلسلاتي")
            .searchable(text: $searchText, prompt: "ابحث في مسلسلاتك")
            .navigationDestination(for: Show.self) { ShowDetailView(show: $0) }
        }
    }
}

extension MyShowsView.Filter {
    func matches(_ show: Show) -> Bool {
        switch self {
        case .watching: show.state == .watching && !show.isUpToDate && !show.isCompleted
        case .upToDate: show.state == .watching && show.isUpToDate
        case .completed: show.isCompleted
        case .later: show.state == .later
        case .stopped: show.state == .stopped
        case .favorites: show.isFavorite
        }
    }
}

private struct ShowGridCell: View {
    let show: Show

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterView(url: show.posterURL)
                .overlay(alignment: .topTrailing) {
                    if show.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .padding(6)
                            .foregroundStyle(.red)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(4)
                    }
                }
                .overlay(alignment: .bottom) {
                    if show.isCompleted {
                        Text("مكتمل ✓")
                            .font(.caption2.bold())
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.accentColor, in: Capsule())
                            .foregroundStyle(.black)
                            .padding(6)
                    }
                }
            ProgressBar(value: show.progress, height: 3)
            Text(show.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text("\(show.watchedCount)/\(show.airedCount)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
