import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Query private var shows: [Show]
    @Query(filter: #Predicate<Episode> { $0.watchedAt != nil },
           sort: \Episode.watchedAt, order: .reverse)
    private var watched: [Episode]

    @State private var exportFile: ExportFile?
    @State private var showImporter = false
    @State private var message: String?
    @State private var isWorking = false

    private var totalMinutes: Int { watched.reduce(0) { $0 + $1.effectiveRuntime } }

    private var thisMonthCount: Int {
        let start = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
        return watched.filter { ($0.watchedAt ?? .distantPast) >= start }.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 6) {
                        Text("وقتك مع المسلسلات").font(.subheadline).foregroundStyle(.secondary)
                        Text(Formatters.duration(minutes: totalMinutes))
                            .font(.title.bold())
                            .foregroundStyle(Color.accentColor)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                    LazyVGrid(columns: [GridItem(), GridItem()], spacing: 12) {
                        StatTile(value: watched.count, label: "حلقة شاهدتها")
                        StatTile(value: thisMonthCount, label: "هالشهر")
                        StatTile(value: shows.count, label: "مسلسل")
                        StatTile(value: shows.filter(\.isCompleted).count, label: "مكتمل")
                    }
                    .padding(.vertical, 4)
                }

                Section("آخر ما شاهدت") {
                    if watched.isEmpty {
                        Text("لسا ما علّمت أي حلقة").foregroundStyle(.secondary)
                    }
                    ForEach(watched.prefix(25)) { ep in
                        HStack(spacing: 10) {
                            PosterView(url: ep.show?.posterURL, cornerRadius: 4).frame(width: 34)
                            VStack(alignment: .leading) {
                                Text(ep.show?.name ?? "").font(.subheadline.bold()).lineLimit(1)
                                Text("\(ep.code) · \(ep.name)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if let d = ep.watchedAt {
                                Text(Formatters.dayLabel(d)).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        do {
                            exportFile = ExportFile(url: try Library.exportBackup(from: context))
                        } catch {
                            message = "فشل التصدير"
                        }
                    } label: {
                        Label("تصدير نسخة احتياطية", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label("استيراد نسخة احتياطية", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        Task {
                            isWorking = true
                            await Library.refreshAll(in: context, force: true)
                            isWorking = false
                            message = "تم تحديث كل المسلسلات"
                        }
                    } label: {
                        Label("تحديث كل المسلسلات", systemImage: "arrow.clockwise")
                    }
                } header: {
                    Text("البيانات")
                } footer: {
                    Text("بياناتك محفوظة على جهازك فقط. صدّر نسخة احتياطية بين فترة وثانية واحفظها في ملفات iCloud.\nبيانات المسلسلات من TVmaze.")
                }
            }
            .navigationTitle("حسابي")
            .disabled(isWorking)
            .overlay { if isWorking { ProgressView().controlSize(.large) } }
            .sheet(item: $exportFile) { file in
                ShareSheet(items: [file.url])
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                guard case .success(let url) = result else { return }
                Task {
                    isWorking = true
                    defer { isWorking = false }
                    do {
                        let n = try await Library.importBackup(from: url, into: context)
                        message = "تم استيراد \(n) مسلسل"
                    } catch {
                        message = "الملف غير صالح أو ما فيه إنترنت"
                    }
                }
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("تمام", role: .cancel) {}
            }
        }
    }
}

private struct StatTile: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title2.bold().monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ExportFile: Identifiable {
    let url: URL
    var id: URL { url }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
