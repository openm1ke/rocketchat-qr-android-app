import SwiftUI
import WidgetKit

struct PassEntry: TimelineEntry {
    let date: Date
    let pass: StoredWidgetPass?
}

struct PassTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> PassEntry {
        PassEntry(date: Date(), pass: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (PassEntry) -> Void) {
        completion(PassEntry(date: Date(), pass: WidgetPassStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PassEntry>) -> Void) {
        let now = Date()
        let pass = WidgetPassStore.read(at: now)
        var entries = [PassEntry(date: now, pass: pass)]
        if let pass = pass {
            // The expired entry contains no image. WidgetKit changes the
            // presentation at expiry without needing to open the application.
            entries.append(PassEntry(date: pass.expiry, pass: nil))
        }
        completion(Timeline(entries: entries, policy: .never))
    }
}

struct PassWidgetView: View {
    let entry: PassEntry
    private let ink = Color(red: 17/255, green: 19/255, blue: 24/255)
    private let lime = Color(red: 141/255, green: 248/255, blue: 107/255)

    @ViewBuilder
    private func qrImage(_ image: UIImage) -> some View {
        if #available(iOS 18.0, *) {
            Image(uiImage: image).resizable().interpolation(.none)
                .widgetAccentedRenderingMode(.fullColor)
                .scaledToFit()
        } else {
            Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("QR-ПРОПУСК").font(.system(size: 12, weight: .semibold))
                Spacer()
                Image(systemName: "house.fill").font(.system(size: 12))
            }
            .foregroundStyle(lime)
            if let pass = entry.pass, pass.isValid(at: entry.date),
               let image = WidgetPassStore.qrTile(pass.image) {
                qrImage(image)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .privacySensitive()
                    .accessibilityLabel("QR-пропуск")
                if let expiry = pass.expiresOn {
                    Text("До \(Date(timeIntervalSince1970: Double(expiry)/1000).formatted(date: .numeric, time: .omitted))")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.8))
                } else {
                    Text("Временный QR").font(.system(size: 11)).foregroundStyle(.white.opacity(0.8))
                }
            } else {
                Spacer()
                Image(systemName: "qrcode").font(.system(size: 56)).foregroundStyle(lime)
                Text("Обновите QR в приложении")
                    .font(.system(size: 16, weight: .medium))
                    .multilineTextAlignment(.center).foregroundStyle(.white)
                Spacer()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .background(ink)
        .widgetURL(WidgetPassStore.openPassURL)
        .containerBackground(ink, for: .widget)
    }
}

@main
struct CampusPassWidget: Widget {
    let kind = WidgetPassStore.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PassTimelineProvider()) { entry in
            PassWidgetView(entry: entry)
        }
        .configurationDisplayName("QR-пропуск")
        .description("Нажмите, чтобы показать QR на весь экран или обновить пропуск.")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(false)
    }
}
