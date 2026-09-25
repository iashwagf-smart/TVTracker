import SwiftUI

struct PosterView: View {
    let url: String?
    var cornerRadius: CGFloat = 8

    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                ZStack {
                    Color(white: 0.15)
                    Image(systemName: "tv")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .aspectRatio(2/3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct ProgressBar: View {
    let value: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule().fill(Color.accentColor)
                    .frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: height)
    }
}

struct WatchButton: View {
    let isWatched: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isWatched ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isWatched ? Color.accentColor : .secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: isWatched) { _, new in new }
    }
}

enum Formatters {
    static let arabicDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ar")
        f.dateStyle = .medium
        return f
    }()

    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ar")
        f.unitsStyle = .full
        return f
    }()

    static func date(_ d: Date?) -> String {
        guard let d else { return "غير معروف" }
        return arabicDate.string(from: d)
    }

    /// "اليوم"، "بكرة"، "بعد ٣ أيام"…
    static func dayLabel(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "اليوم" }
        if cal.isDateInTomorrow(d) { return "بكرة" }
        if cal.isDateInYesterday(d) { return "أمس" }
        return relative.localizedString(for: cal.startOfDay(for: d), relativeTo: cal.startOfDay(for: Date()))
    }

    /// يحول الدقائق إلى "٣ أيام ٤ ساعات"
    static func duration(minutes: Int) -> String {
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        let mins = minutes % 60
        var parts: [String] = []
        if days > 0 { parts.append("\(days) يوم") }
        if hours > 0 { parts.append("\(hours) ساعة") }
        if days == 0 && mins > 0 { parts.append("\(mins) دقيقة") }
        return parts.isEmpty ? "٠ دقيقة" : parts.joined(separator: " و")
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        }
    }
}
