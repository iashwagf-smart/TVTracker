# مسلسلاتي — TV Tracker

تطبيق آيفون شخصي لتتبع حلقات المسلسلات (على طريقة TV Show Time القديم).

## المزايا
- **المتابعة**: الحلقة التالية لكل مسلسل تتابعه، وتعلّمها بضغطة (أو سحب).
- **القادم**: الحلقات الجاية مرتبة حسب اليوم.
- **مسلسلاتي**: شبكة بوسترات مع نسبة التقدم، وفلاتر: أتابعه / محدّث / مكتمل / لاحقاً / توقفت / المفضلة.
- **صفحة المسلسل**: المواسم والحلقات، تعليم موسم كامل، ضغطة مطوّلة على حلقة ← "شاهدتها وكل اللي قبلها".
- **حسابي**: الوقت اللي قضيته، عدد الحلقات، آخر ما شاهدت، ونسخ احتياطي (تصدير/استيراد JSON).
- **ويدجت** للشاشة الرئيسية (صغير/متوسط/كبير) يعرض الحلقات التالية مع زر ✓ تعلّمها منه مباشرة.
- **إشعارات** وقت نزول الحلقات الجديدة للمسلسلات اللي تتابعها (فعّلها من تبويب حسابي).
- **استيراد من TV Time**: اطلب نسخة بياناتك من TV Time، واختر ملفات CSV من تبويب حسابي.
- بيانات المسلسلات من [TVmaze](https://www.tvmaze.com/api) (مجانية وبدون مفتاح). كل بياناتك محفوظة على الجهاز (SwiftData).

المتطلبات: iOS 17 أو أحدث.

---

## التثبيت مجاناً (بدون حساب مطوّر) — SideStore

كل ما ترفع تعديل على `main`، GitHub يبني التطبيق وينشر `TVTracker.ipa` في صفحة [Releases ← latest](../../releases/tag/latest).

1. ثبّت [SideStore](https://sidestore.io) على الآيفون مرة وحدة (يحتاج كمبيوتر ويندوز أو ماك أو لينكس للإعداد الأول فقط) وسجّل بـ Apple ID العادي.
2. من الآيفون افتح صفحة Releases ونزّل `TVTracker.ipa` ← مشاركة ← افتحه في SideStore.
3. قيود حساب Apple المجاني: التطبيق يحتاج **تجديد كل 7 أيام** (SideStore يجدده من الجوال نفسه بضغطة، أو تلقائياً)، وحد أقصى 3 تطبيقات مثبتة بهالطريقة.
4. بياناتك ما تنحذف عند التجديد، بس صدّر نسخة احتياطية بين فترة وفترة احتياطاً.

(بديل: [AltStore](https://altstore.io) — نفس الفكرة لكن التجديد يحتاج الكمبيوتر يكون شغال على نفس الواي فاي.)

---

## الرفع على TestFlight (يحتاج اشتراك 99$)

لازم يكون عندك **Apple Developer Program** (‏99$ بالسنة) — TestFlight ما يشتغل بدونه.

### الطريقة 1: عندك ماك
```bash
brew install xcodegen
xcodegen generate
open TVTracker.xcodeproj
```
1. غيّر `APP_BUNDLE_ID` في `project.yml` لشيء خاص فيك (مثلاً `com.yourname.tvtracker`) وأعد `xcodegen generate`، ثم في Xcode اختر الـ Team للتارقتين (TVTracker و TVTrackerWidget) من Signing & Capabilities. Xcode يسجل الـ App Group تلقائياً.
2. من [App Store Connect](https://appstoreconnect.apple.com) ← Apps ← ➕ New App، واستخدم نفس الـ Bundle ID.
3. في Xcode: ‏Product ← Archive ← Distribute App ← TestFlight Internal Only.
4. بعد دقائق يوصلك في تطبيق TestFlight على الآيفون.

### الطريقة 2: بدون ماك (GitHub Actions)
الملف `.github/workflows/testflight.yml` يبني التطبيق ويرفعه لوحده على سيرفر ماك من GitHub.

1. ارفع المشروع على مستودع GitHub (يُفضّل خاص/Private).
2. سجّل الـ Bundle ID وأنشئ التطبيق في App Store Connect (الخطوة 2 فوق). تسجيل الـ Bundle ID يكون من [developer.apple.com ← Identifiers](https://developer.apple.com/account/resources/identifiers/list).
3. سجّل **App Group** باسم `group.<الـ Bundle ID>` (مثلاً `group.com.yourname.tvtracker`) من developer.apple.com ← Identifiers ← App Groups، وفعّله على الـ App ID حق التطبيق وحق الويدجت (`<Bundle ID>.widget`). هذا يخلي الويدجت يقرأ بياناتك.
4. أنشئ مفتاح API: ‏App Store Connect ← Users and Access ← Integrations ← App Store Connect API ← ➕، بصلاحية **Admin**، ونزّل ملف `.p8`.
5. في GitHub ← Settings ← Secrets and variables ← Actions أضف:

   | النوع | الاسم | القيمة |
   |---|---|---|
   | Secret | `TEAM_ID` | الـ Team ID (من developer.apple.com ← Membership) |
   | Secret | `ASC_KEY_ID` | Key ID حق المفتاح |
   | Secret | `ASC_ISSUER_ID` | Issuer ID (فوق قائمة المفاتيح) |
   | Secret | `ASC_KEY_P8_BASE64` | ناتج الأمر `base64 -i AuthKey_XXXX.p8` |
   | Variable | `BUNDLE_ID` | نفس الـ Bundle ID اللي سجلته |

6. من تبويب Actions ← **Upload to TestFlight** ← Run workflow. كل تشغيل يرفع نسخة جديدة برقم بناء أعلى.

---

## بنية المشروع
```
TVTracker/
  App/          نقطة البداية والتبويبات
  Models/       Show و Episode (SwiftData)
  Services/     TVMazeAPI، Library، الإشعارات، استيراد TV Time
  Shared/       قاعدة البيانات المشتركة وزر الويدجت (مشتركة مع الويدجت)
  Views/        الشاشات
TVTrackerWidget/  الويدجت
project.yml     إعدادات XcodeGen (ملف ‎.xcodeproj يتولد منه)
```
