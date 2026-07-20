# Flare Scan

Diskinizin hansı qovluq və fayllarla dolduğunu göstərən **açıq mənbəli** (open-source) macOS tətbiqi. DaisyDisk kimi kommersiya alətlərinə pulsuz, şəffaf alternativ — bütün kod açıqdır, hər kəs yoxlaya bilər.

İki interaktiv görünüş:
- **Sunburst** — iç-içə həlqələr (DaisyDisk stili)
- **Treemap** — ölçüyə görə düzbucaqlı bloklar (WinDirStat stili)

Hər ikisində: üzərinə gələndə tam yol + ölçü göstərilir, kliklə içəri "zoom" edirsən, breadcrumb ilə geri qayıdırsan.

---

## Niyə təhlükəsizdir (vulnerability olmasın)

Bu tətbiqin təhlükəsizliyi dizaynla təmin olunub:

| Qoruma | Necə |
|--------|------|
| **App Sandbox** | Tətbiq macOS sandbox-ında işləyir — yalnız istifadəçinin verdiyi qovluqlara çıxışı var. |
| **Yalnız oxuma** | `user-selected.read-only` icazəsi. Tətbiq heç nəyi silə, dəyişə və ya yaza bilməz. |
| **Şəbəkə yoxdur** | Heç bir şəbəkə icazəsi yoxdur → tam offline. Heç bir məlumat kənara göndərilə bilmir. |
| **Açıq mənbə** | Bütün kod buradadır. Gizli davranış yoxdur; özün oxuyub, özün qura bilərsən. |
| **Xarici asılılıq yoxdur** | Sıfır üçüncü tərəf paketi — yalnız Apple-ın SwiftUI/Foundation çərçivəsi. |

Sandbox icazələri: [`packaging/DiskLens.entitlements`](packaging/DiskLens.entitlements)

---

## Tələblər

- macOS 14 (Sonoma) və ya daha yeni
- Yalnız mənbədən qurmaq üçün: Xcode / Swift 6 toolchain

## Quraşdırma (DMG-dən)

1. `Flare Scan.dmg` faylını aç.
2. `Flare Scan.app`-i `Applications` qovluğuna sürüklə.
3. **İlk açılış:** tətbiq Apple tərəfindən notarizasiya olunmadığı üçün ilk dəfə
   ikonuna **sağ klik → Aç** et, sonra çıxan pəncərədə yenə **Aç**. (Bu, yalnız
   ilk dəfə lazımdır. Notarizasiya üçün aşağıya bax.)

## Mənbədən qurmaq

```bash
# 1) .app bundle qur və sandbox icazələri ilə imzala
./scripts/build-app.sh

# 2) paylanabilən DMG yarat
./scripts/make-dmg.sh

# Nəticələr dist/ qovluğunda:
#   dist/Flare Scan.app
#   dist/Flare Scan.dmg

# Sadəcə işə salmaq üçün:
swift run          # (development)
open "dist/Flare Scan.app"
```

---

## Necə işləyir

- [`Models/Scanner.swift`](Sources/DiskLens/Models/Scanner.swift) — qovluq ağacını
  rekursiv gəzir, hər faylın **disk üzərindəki (allocated)** ölçüsünü toplayır,
  simlink-ləri izləmir (döngü/ikiqat sayımın qarşısını alır), icazə xətalarını
  səssiz keçir. Arxa planda (background task) işləyir, UI donmur.
- [`Layout/SunburstLayout.swift`](Sources/DiskLens/Layout/SunburstLayout.swift) —
  həlqəvi arc həndəsəsi + kliklə hit-testing.
- [`Layout/TreemapLayout.swift`](Sources/DiskLens/Layout/TreemapLayout.swift) —
  *squarified* treemap alqoritmi (bloklar mümkün qədər kvadrata yaxın, oxumaq asan).
- SwiftUI `Canvas` ilə çəkilir — GPU-sürətli, minlərlə element rəvan.

## Layihə strukturu

```
flare-scan/
├── Package.swift
├── packaging/DiskLens.entitlements     # sandbox icazələri
├── scripts/build-app.sh                # .app qur + imzala
├── scripts/make-dmg.sh                 # DMG yarat
└── Sources/DiskLens/
    ├── DiskLensApp.swift               # Flare Scan giriş nöqtəsi
    ├── Models/                         # FileNode, Scanner
    ├── ViewModel/AppState.swift        # tarama vəziyyəti + naviqasiya
    ├── Layout/                         # sunburst + treemap həndəsəsi
    ├── Views/                          # UI
    └── Util/                           # rəng palitrası, ölçü formatı
```

---

## Notarizasiya (istəyə bağlı, "sağ klik → Aç" olmadan paylamaq üçün)

DMG-nin istənilən Mac-də xəbərdarlıqsız açılması üçün Apple **notarization** lazımdır.
Bu, **Apple Developer Program** üzvlüyü (99$/il) tələb edir:

```bash
# Developer ID sertifikatı ilə imzala (ad-hoc "-" əvəzinə)
codesign --force --options runtime \
  --entitlements packaging/DiskLens.entitlements \
  --sign "Developer ID Application: <Adın> (<TeamID>)" "dist/Flare Scan.app"

# Notarizasiya et və "staple" ilə möhürlə
xcrun notarytool submit "dist/Flare Scan.dmg" --keychain-profile "<profil>" --wait
xcrun stapler staple "dist/Flare Scan.dmg"
```

## Yol xəritəsi (növbəti addımlar)

- [ ] Universal binary (Apple Silicon + Intel)
- [ ] Tətbiq ikonu (.icns)
- [ ] Fayl növünə görə filtrlər və axtarış
- [ ] "Finder-də göstər" düyməsi
- [ ] Notarizasiya olunmuş rəsmi buraxılış

## Lisenziya

MIT — bax [LICENSE](LICENSE). © 2026 Umud Hasanli.
