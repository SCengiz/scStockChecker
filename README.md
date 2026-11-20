# scStockChecker (Stok Takip)

Zara (ve ileride diğer Inditex markaları) ürünlerinde istediğin beden stoğa girince telefona bildirim gönderen kişisel bir iPhone uygulaması.

- Tekil ürün linki ekle, takip etmek istediğin bedenleri seç.
- Ya da bir favori listesinin paylaşım linkini ekle: listedeki tüm ürünler takip edilir.
- Stok kontrolü bulutta, birkaç dakikada bir çalışır; telefon kapalıyken de devam eder.
- Seçtiğin beden stoğa girince **ntfy** uygulaması üzerinden bildirim gelir.

## Nasıl çalışır

```
iPhone uygulaması ──(giriş, link ekleme)──► Supabase (Auth + Postgres)
                                                 │
                      pg_cron (5 dk) ──► check-stock fonksiyonu ──► zara.com ürün verisi
                                                 │
                                                 └──► ntfy.sh ──► ntfy iOS uygulaması (bildirim)
```

| Klasör | İçerik |
| --- | --- |
| `ios/` | SwiftUI uygulaması (Xcode projesi `ios/scStockChecker.xcodeproj`) |
| `supabase/migrations/` | Veritabanı şeması |
| `supabase/functions/check-stock/` | Zamanlanmış stok kontrolü ve bildirim |
| `supabase/functions/resolve-link/` | Uygulamanın yapıştırılan linki okumak için çağırdığı fonksiyon |
| `supabase/functions/_shared/brands/` | Marka adaptörleri (şimdilik Zara) |

## iPhone'a kurulum (kendi Mac'inde derleme)

Gerekenler: Xcode 16 veya üzeri, bir Apple ID (ücretsiz olabilir), iPhone ve kablo.

1. Depoyu klonla:
   ```bash
   git clone https://github.com/SCengiz/scStockChecker.git
   ```
2. `ios/Config/Local.xcconfig.example` dosyasını aynı klasörde `Local.xcconfig` adıyla kopyala ve doldur:
   - `DEVELOPMENT_TEAM`: Xcode → Settings → Accounts → Apple ID'n → Team ID (ücretsiz hesapta "Personal Team").
   - `BUNDLE_ID_PREFIX`: sana özel bir şey, örn. `com.adinsoyadin`.
3. `ios/scStockChecker.xcodeproj` dosyasını Xcode'da aç, üstten iPhone'unu seç ve ▶︎ (Run) bas.
4. İlk kurulumda iPhone'da: Ayarlar → Genel → VPN ve Cihaz Yönetimi → geliştirici uygulamasına "Güven". Ayrıca Ayarlar → Gizlilik ve Güvenlik → Geliştirici Modu açık olmalı.

> **Ücretsiz Apple ID notu:** Uygulama 7 gün sonra açılmaz hale gelir; Xcode'dan tekrar ▶︎ basarak yeniden kurman yeterli (veriler sunucuda olduğu için kaybolmaz). Ücretsiz hesapla aynı anda en fazla 3 kendi derlediğin uygulama kurulu olabilir.

### Bildirimleri açma

1. App Store'dan ücretsiz **ntfy** uygulamasını kur.
2. Stok Takip → Ayarlar → Bildirimler: "Yeni" ile bir kanal adı oluştur, Kaydet.
3. "ntfy uygulamasında abone ol"a dokun.

Kullanıcı hesapları sunucu sahibi tarafından açılır (dışarıdan kayıt kapalı).

## Sunucu kurulumu (sadece bir kez, sunucu sahibi için)

1. [supabase.com](https://supabase.com) üzerinde ücretsiz bir proje aç.
2. SQL Editor'de `supabase/migrations/` içindeki dosyaları sırayla çalıştır.
3. Fonksiyonları yükle ve gizli anahtarı ayarla:
   ```bash
   supabase link --project-ref <proje-ref>
   supabase functions deploy resolve-link
   supabase functions deploy check-stock --no-verify-jwt
   supabase secrets set CRON_SECRET=<uzun-rastgele-bir-metin>
   ```
4. Zamanlayıcıyı kur: `supabase/cron.sql` içindeki yer tutucuları doldurup SQL Editor'de çalıştır.
5. Authentication → Providers → Email: "Allow new users to sign up" kapalı. Kullanıcıları Authentication → Users → "Add user" ile ekle.
6. `ios/Config/App.xcconfig` içindeki `SUPABASE_URL` ve `SUPABASE_ANON_KEY` değerlerini (Project Settings → API) doldur.

## Geliştirme

```bash
deno test supabase/functions/_shared/
deno run --allow-net scripts/try-link.ts "https://www.zara.com/tr/tr/...-p12345678.html"
```

`ios/project.yml` değişirse Xcode projesini `xcodegen` ile yeniden üret (`cd ios && xcodegen`).

## Not

Kişisel kullanım için yazılmış bir projedir; markaların herkese açık ürün sayfalarındaki veriyi düşük sıklıkta okur. Markalarla bir bağlantısı yoktur.
