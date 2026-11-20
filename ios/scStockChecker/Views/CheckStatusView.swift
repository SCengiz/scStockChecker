import SwiftUI

/// Live "last check N s ago" bar shown at the top of the main list.
struct CheckStatusBar: View {
    @Environment(Store.self) private var store

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let last = store.runs.first
            let late = last.map { context.date.timeIntervalSince($0.startedAt) > Double(store.checkInterval) + 45 } ?? true
            let color: Color = late ? .orange : (last?.isHealthy == false ? .red : .green)
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 8, height: 8)
                    .shadow(color: color.opacity(0.7), radius: late ? 0 : 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(late ? "Kontrol gecikti" : "Kontrol çalışıyor")
                        .font(.caption.weight(.semibold))
                    Text(summary(last, now: context.date))
                        .font(.caption2).foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
            }
        }
    }

    private func summary(_ run: CheckRun?, now: Date) -> String {
        guard let run else { return "Henüz kontrol kaydı yok" }
        var parts = ["Son kontrol \(agoText(run.startedAt, now: now))", "\(run.itemsChecked) ürün",
                     String(format: "%.1f sn", Double(run.durationMs) / 1000)]
        if run.itemsFailed > 0 { parts.append("\(run.itemsFailed) hata") }
        return parts.joined(separator: " · ")
    }
}

/// Every check run of the last 24 hours plus each item's own last check.
struct CheckLogView: View {
    @Environment(Store.self) private var store

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            List {
                Section {
                    ForEach(store.items.sorted { ($0.lastCheckedAt ?? .distantPast) > ($1.lastCheckedAt ?? .distantPast) }) { item in
                        HStack {
                            Image(systemName: item.lastError == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(item.lastError == nil ? .green : .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? item.url).font(.footnote).lineLimit(1)
                                if let error = item.lastError {
                                    Text(error).font(.caption2).foregroundStyle(.orange).lineLimit(2)
                                }
                            }
                            Spacer()
                            Text(agoText(item.lastCheckedAt, now: context.date))
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    ForEach(store.watchlists) { list in
                        HStack {
                            Image(systemName: "heart.fill").foregroundStyle(.pink)
                            Text("\(list.name ?? "Liste") (liste okundu)").font(.footnote).lineLimit(1)
                            Spacer()
                            Text(agoText(list.lastSyncedAt, now: context.date))
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                } header: {
                    Text("Ürünler")
                } footer: {
                    Text("Ürün kontrol sıklığı: \(intervalText(store.checkInterval)) (Ayarlar'dan değiştirilebilir). Favori listelerinin içeriği 5 dakikada bir yeniden okunur.")
                }

                Section("Son 24 saat") {
                    ForEach(store.runs) { run in
                        HStack {
                            Image(systemName: run.isHealthy ? "checkmark.circle" : "xmark.circle")
                                .foregroundStyle(run.isHealthy ? .green : .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(run.startedAt.formatted(date: .omitted, time: .standard)).font(.footnote.monospacedDigit())
                                Text(details(run)).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(run.durationMs) ms").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Kontroller")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.reload() }
    }

    private func details(_ run: CheckRun) -> String {
        var parts = ["\(run.itemsChecked) ürün kontrol edildi"]
        if run.listsSynced > 0 { parts.append("\(run.listsSynced) liste okundu") }
        if run.cameIn > 0 { parts.append("\(run.cameIn) beden stoğa girdi") }
        if run.itemsFailed > 0 { parts.append("\(run.itemsFailed) hata") }
        if let error = run.error { parts.append(error) }
        return parts.joined(separator: " · ")
    }
}
