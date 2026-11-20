import SwiftUI

/// "Log" tab: is checking alive, when was each product last / next checked,
/// and every check run of the last 24 hours.
struct LogView: View {
    @Environment(Store.self) private var store

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        statusCard(now: context.date)
                        metrics
                        schedule(now: context.date)
                        runs
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .background(Palette.page)
            .navigationTitle("Log")
            .refreshable { await store.reload() }
        }
    }

    // MARK: Status

    private func statusCard(now: Date) -> some View {
        let last = store.runs.first
        let stretch = store.settings?.loadStretch ?? 1
        let backoff = store.settings?.backoffUntil.flatMap { $0 > now ? $0 : nil }
        let late = backoff == nil
            && (last.map { now.timeIntervalSince($0.startedAt) > Double(store.checkInterval) * stretch + 45 } ?? true)
        let failing = last.map { !$0.isHealthy } ?? false
        let color: Color = backoff != nil ? Palette.soldOut : late ? Palette.warning : failing ? Palette.soldOut : Palette.inStock
        let next = store.items.filter(\.active).compactMap(\.nextCheckAt).min()
        let load = store.settings?.loadPerMinute ?? 0

        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    LiveDot(color: color, animated: !late && backoff == nil)
                    Text(backoff != nil ? "Kontroller duraklatıldı" : late ? "Kontrol gecikti" : failing ? "Bazı ürünler okunamadı" : "Kontrol çalışıyor")
                        .font(.headline)
                    Spacer()
                }
                HStack(alignment: .top) {
                    labeled("Son kontrol", agoText(last?.startedAt, now: now))
                    Spacer()
                    labeled("Sıradaki", backoff.map { untilText($0, now: now) } ?? next.map { untilText($0, now: now) } ?? "—")
                    Spacer()
                    labeled("Yük", "\(Int(load.rounded())) / \(Int(Store.requestBudget)) /dk")
                }
                if let backoff {
                    Label("Zara engelleme sinyali verdi (\(store.settings?.backoffReason ?? "bilinmiyor")). Hesabınızı ve IP'yi korumak için tüm kontroller \(backoff.formatted(date: .omitted, time: .shortened))'e kadar bekliyor.",
                          systemImage: "hand.raised.fill")
                        .font(.caption.weight(.medium)).foregroundStyle(Palette.soldOut)
                } else if stretch > 1.05 {
                    Label(String(format: "Yük sınırı aşıldı: normal aralıklar %.1f kat uzatıldı. Profil > Kontrol sıklığı'ndan azaltabilirsiniz.", stretch),
                          systemImage: "tortoise.fill")
                        .font(.caption).foregroundStyle(Palette.warning)
                }
                Text("Her ürün kendi grubunun aralığıyla kontrol edilir (Normal \(intervalText(store.checkInterval)), Öncelikli \(intervalText(store.hotInterval))). Sunucu dakikada en çok \(Int(Store.requestBudget)) istek atar; engellenirse 5 dakika bekler. Favori listeleri 5 dakikada bir yeniden okunur.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }

    private var metrics: some View {
        let runs = store.runs
        let avg = runs.isEmpty ? 0 : runs.map(\.durationMs).reduce(0, +) / runs.count
        return HStack(spacing: 10) {
            StatTile(value: "\(runs.count)", label: "Kontrol (24 sa)")
            StatTile(value: String(format: "%.1f sn", Double(avg) / 1000), label: "Ortalama süre")
            StatTile(value: "\(runs.filter { !$0.isHealthy }.count)", label: "Hatalı",
                     color: runs.contains { !$0.isHealthy } ? Palette.soldOut : .primary)
        }
    }

    // MARK: Per-item schedule

    private func schedule(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Ürünler")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    let items = store.items.sorted { ($0.nextCheckAt ?? .distantFuture) < ($1.nextCheckAt ?? .distantFuture) }
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 10) {
                            Image(systemName: item.lastError == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(item.lastError == nil ? Palette.inStock : Palette.warning)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? item.url)
                                    .font(.footnote.weight(.medium)).lineLimit(1)
                                if let error = item.lastError {
                                    Text(error).font(.caption2).foregroundStyle(Palette.warning).lineLimit(2)
                                } else if let reason = item.hotReasonText {
                                    Label(reason, systemImage: "bolt.fill").font(.caption2).foregroundStyle(Palette.priority)
                                } else if !item.active {
                                    Text("Duraklatıldı").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(agoText(item.lastCheckedAt, now: now)).font(.caption.monospacedDigit())
                                if item.active, let next = item.nextCheckAt {
                                    Text("sonraki \(untilText(next, now: now))")
                                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        if index < items.count - 1 { Divider().padding(.leading, 40) }
                    }
                    ForEach(store.watchlists) { list in
                        Divider().padding(.leading, 40)
                        HStack(spacing: 10) {
                            Image(systemName: "heart.fill").foregroundStyle(.pink)
                            Text("\(list.name ?? "Liste") · liste içeriği").font(.footnote.weight(.medium)).lineLimit(1)
                            Spacer()
                            Text(agoText(list.lastSyncedAt, now: now)).font(.caption.monospacedDigit())
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                    }
                }
            }
        }
    }

    // MARK: Runs

    private var runs: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Kontrol geçmişi") { Text("Son 24 saat").font(.caption).foregroundStyle(.secondary) }
            Card(padding: 0) {
                VStack(spacing: 0) {
                    if store.runs.isEmpty {
                        Text("Henüz kayıt yok").font(.footnote).foregroundStyle(.secondary).padding(14)
                    }
                    ForEach(Array(store.runs.enumerated()), id: \.element.id) { index, run in
                        HStack(spacing: 10) {
                            Image(systemName: run.isHealthy ? "checkmark.circle" : "xmark.circle")
                                .foregroundStyle(run.isHealthy ? Palette.inStock : Palette.soldOut)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(run.startedAt.formatted(date: .omitted, time: .standard))
                                    .font(.footnote.weight(.medium).monospacedDigit())
                                Text(details(run)).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            Text("\(run.durationMs) ms").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        if index < store.runs.count - 1 { Divider().padding(.leading, 40) }
                    }
                }
            }
        }
    }

    private func details(_ run: CheckRun) -> String {
        var parts = ["\(run.itemsChecked) ürün"]
        if run.listsSynced > 0 { parts.append("\(run.listsSynced) liste okundu") }
        if run.cameIn > 0 { parts.append("\(run.cameIn) beden stoğa girdi") }
        if run.itemsFailed > 0 { parts.append("\(run.itemsFailed) hata") }
        if let error = run.error { parts.append(error) }
        return parts.joined(separator: " · ")
    }

    private func untilText(_ date: Date, now: Date) -> String {
        let s = Int(date.timeIntervalSince(now))
        return s <= 0 ? "şimdi" : s < 60 ? "\(s) sn" : "\(s / 60) dk"
    }
}
