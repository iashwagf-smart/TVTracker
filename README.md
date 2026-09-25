# مسلسلاتي — TV Tracker

تطبيق آيفون شخصي لتتبع حلقات المسلسلات (على طريقة TV Show Time القديم).

## المزايا
- **المتابعة**: الحلقة التالية لكل مسلسل تتابعه، وتعلّمها بضغطة (أو سحب).
- **القادم**: الحلقات الجاية مرتبة حسب اليوم.
- **مسلسلاتي**: شبكة بوسترات مع نسبة التقدم، وفلاتر: أتابعه / محدّث / مكتمل / لاحقاً / توقفت / المفضلة.
- **صفحة المسلسل**: المواسم والحلقات، تعليم موسم كامل، ضغطة مطوّلة على حلقة ← "شاهدتها وكل اللي قبلها".
- **حسابي**: الوقت اللي قضيته، عدد الحلقات، آخر ما شاهدت، ونسخ احتياطي (تصدير/استيراد JSON).
- بيانات المسلسلات من [TVmaze](https://www.tvmaze.com/api) (مجانية وبدون مفتاح). كل بياناتك محفوظة على الجهاز (SwiftData).

المتطلبات: iOS 17 أو أحدث.

---

## الرفع على TestFlight

لازم يكون عندك **Apple Developer Program** (‏99$ بالسنة) — TestFlight ما يشتغل بدونه.

### الطريقة 1: عندك ماك
```bash
brew install xcodegen
xcodegen generate
open TVTracker.xcodeproj
```
1. في Xcode: اختر التارقت ‎TVTracker ← Signing & Capabilities ← اختر الـ Team، وغيّر الـ Bundle Identifier لشيء خاص فيك (مثلاً `com.yourname.tvtracker`).
2. من [App Store Connect](https://appstoreconnect.apple.com) ← Apps ← ➕ New App، واستخدم نفس الـ Bundle ID.
3. في Xcode: ‏Product ← Archive ← Distribute App ← TestFlight Internal Only.
4. بعد دقائق يوصلك في تطبيق TestFlight على الآيفون.

### الطريقة 2: بدون ماك (GitHub Actions)
الملف `.github/workflows/testflight.yml` يبني التطبيق ويرفعه لوحده على سيرفر ماك من GitHub.

1. ارفع المشروع على مستودع GitHub (يُفضّل خاص/Private).
2. سجّل الـ Bundle ID وأنشئ التطبيق في App Store Connect (الخطوة 2 فوق). تسجيل الـ Bundle ID يكون من [developer.apple.com ← Identifiers](https://developer.apple.com/account/resources/identifiers/list).
3. أنشئ مفتاح API: ‏App Store Connect ← Users and Access ← Integrations ← App Store Connect API ← ➕، بصلاحية **Admin**، ونزّل ملف `.p8`.
4. في GitHub ← Settings ← Secrets and variables ← Actions أضف:

   | النوع | الاسم | القيمة |
   |---|---|---|
   | Secret | `TEAM_ID` | الـ Team ID (من developer.apple.com ← Membership) |
   | Secret | `ASC_KEY_ID` | Key ID حق المفتاح |
   | Secret | `ASC_ISSUER_ID` | Issuer ID (فوق قائمة المفاتيح) |
   | Secret | `ASC_KEY_P8_BASE64` | ناتج الأمر `base64 -i AuthKey_XXXX.p8` |
   | Variable | `BUNDLE_ID` | نفس الـ Bundle ID اللي سجلته |

5. من تبويب Actions ← **Upload to TestFlight** ← Run workflow. كل تشغيل يرفع نسخة جديدة برقم بناء أعلى.

---

## بنية المشروع
```
TVTracker/
  App/          نقطة البداية والتبويبات
  Models/       Show و Episode (SwiftData)
  Services/     TVMazeAPI (الشبكة) و Library (الإضافة/التحديث/النسخ الاحتياطي)
  Views/        الشاشات
project.yml     إعدادات XcodeGen (ملف ‎.xcodeproj يتولد منه)
```
