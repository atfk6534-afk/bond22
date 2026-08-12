# BOND2 — تطبيق إدارة الدروس الخصوصية

تطبيق أندرويد offline-first لإدارة الطلاب، الحضور بالـQR، المدفوعات، المواد التعليمية،
والنسخ الاحتياطي — مبني بـ Flutter + Drift (SQLite)، بواجهة عربية RTL.

## البنية

```
lib/
  core/            قاعدة البيانات (Drift)، الثيم، التوجيه، الخدمات المشتركة (QR/واتساب/اتصال)
  features/        كل ميزة في مجلد مستقل: students, groups, lessons, attendance,
                   payments, materials, backup, settings, dashboard, onboarding
  shared/widgets/  عناصر واجهة مشتركة (حالة فارغة، شارة الحالة، القشرة الرئيسية)
android/           مشروع أندرويد قياسي (Gradle) — applicationId: com.bond2.tutor
test/              اختبارات وحدة حقيقية (منطق مالي، حضور، مواد، مجموعات، نسخ احتياطي)
integration_test/  اختبار تدفق كامل (يتطلب جهاز/محاكي حقيقي)
.github/workflows/ بناء APK تلقائيًا عبر GitHub Actions
```

## قاعدة البيانات (المصدر الوحيد للحقيقة)

كل الحسابات المالية تُشتق من جداول `Charges` + `Payments` + `PaymentAllocations` —
لا يوجد رقم إجمالي مخزَّن بشكل منفصل يمكن أن يتعارض مع الواقع. كل الأموال تُخزَّن
كأعداد صحيحة بالقرش (لا أرقام عشرية) في `lib/core/utils/money.dart`.

## كيف تبني APK حقيقي

### عبر GitHub Actions (الطريقة الموصى بها)
1. ادفع (push) هذا المستودع إلى GitHub.
2. اذهب إلى تبويب **Actions** — سيعمل workflow باسم **"Build BOND2 APK"** تلقائيًا.
3. بعد نجاحه، حمّل الملف الناتج من قسم **Artifacts** باسم `bond2-release-apk`.

الملف الكامل: [`.github/workflows/build-apk.yml`](.github/workflows/build-apk.yml). خطواته:
Checkout → إعداد Java 17 → إعداد Flutter (`subosito/flutter-action`) →
`flutter pub get` → توليد كود Drift (`build_runner`) → `flutter analyze` →
`flutter test` → إعادة توليد `gradle-wrapper.jar` (غير مرفوع في الـ repo، انظر
القسم أدناه) → `flutter build apk --release` → رفع الـ APK كـ Artifact.

### محليًا (إذا كان عندك Flutter SDK مثبت)
```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter build apk --release
```
الناتج: `build/app/outputs/flutter-apk/app-release.apk`

## ملاحظة مهمة: `gradle-wrapper.jar`

ملف `android/gradle/wrapper/gradle-wrapper.jar` هو ملف binary صغير عادة ما يكون
مرفوعًا داخل كل مشروع Flutter/Android. **لم يتم تضمينه هنا** لأن بيئة التطوير التي
كُتب فيها هذا المشروع لا تملك وصولًا شبكيًا لتحميله من `services.gradle.org`.
بدلًا من ذلك:
- في **GitHub Actions**: تتم إعادة توليده تلقائيًا بخطوة `gradle wrapper --gradle-version 8.7`
  قبل البناء (سطر موجود في الـ workflow).
- **محليًا**: شغّل مرة واحدة فقط:
  ```bash
  cd android && gradle wrapper --gradle-version 8.7
  ```
  (يتطلب وجود Gradle مثبت على جهازك، أو استخدم Android Studio الذي يوفره تلقائيًا).

## توقيع الإصدار (Release Signing)

بدون مفتاح توقيع حقيقي، يبني CI حاليًا APK موقّعًا بمفتاح الـ debug الافتراضي (صالح
للتجربة والتثبيت المباشر، **غير صالح لرفعه على Google Play**). لإضافة توقيع حقيقي:
1. أنشئ keystore: `keytool -genkey -v -keystore bond2.jks -keyalg RSA -keysize 2048 -validity 10000 -alias bond2`
2. أضف 4 GitHub Secrets: `BOND2_KEYSTORE_PATH` (أو ارفع الملف كـ secret base64 وفكّه في خطوة CI)،
   `BOND2_KEYSTORE_PASSWORD`، `BOND2_KEY_ALIAS`، `BOND2_KEY_PASSWORD`.
3. `android/app/build.gradle` يستخدم هذه المتغيرات تلقائيًا إن وُجدت (راجع `signingConfigs`).

## حالة تنفيذ المواصفة (95 قسمًا) — مُحدَّثة بعد جولة الإصلاحات الثانية

### ✅ COMPLETE — منفّذ فعليًا (كود حقيقي، ليس واجهة وهمية)
Database كاملة · Students (إضافة/بحث/أرشفة/نقل مجموعة) · QR توليد+مشاركة ·
Groups · Lessons (عادية + متكررة + قائمة طلاب تلقائية) · Attendance (QR + يدوي +
منع التكرار + حالة "غير مسجل بالحصة") ·
**Payments — توزيع صارم 100%: لا يُقبل أي مبلغ غير موزَّع بالكامل على المستحقات
(fix #1)** · **Materials/Books — نموذج الإضافة يشمل السنة الدراسية والصف والمادة
(fix #2)** · **تخزين ملفات المواد: كل ملف يُنسخ فعليًا داخل تخزين BOND2 الخاص
(`bond2_files/materials/<materialId>.ext`)، لا يُعتمد على المسار الخارجي، وأسماء
الملفات مبنية على المعرّف الداخلي لا الاسم العربي (fix #3)** ·
**Backup/Restore — يُغلق اتصال قاعدة البيانات قبل الكتابة فوق الملف، يُعيد فتح
اتصال جديد تلقائيًا (بلا إعادة تشغيل يدوية)، يمسح ملفات المواد اليتيمة قبل
الاستعادة، والكتابة عبر ملف مؤقت + rename ذرّي (fix #4)** ·
**زر واتساب على شاشة QR أصبح صادقًا: "مشاركة QR واختيار واتساب من القائمة" بدل
الادّعاء بإرسال مباشر (fix #5)** ·
**شاشة Reports موحّدة: حضور/غياب، مدفوعات، مستحقات، مبيعات مواد، ملخص مالي لكل
طالب — بفلاتر تاريخ + سنة دراسية + مجموعة (fix #6)** ·
**تصدير CSV/PDF حقيقي فعليًا من كل قسم في شاشة التقارير (fix #7)** ·
App Lock (PIN بـ SHA-256) · Dark/Light/System theme · Dashboard · Onboarding
مبسّط · RTL عربي كامل · Android manifest/icon/splash/CI حقيقية ·
اختبارات وحدة حقيقية (60+ حالة اختبار عبر 8 ملفات، منها اختبارات مخصصة لكل
إصلاح من الإصلاحات التسعة أعلاه — fix #8).

### 🟡 PARTIAL — منفّذ جزئيًا / مبسّط
- **PDF export**: الـ PDF المُنتَج ملف حقيقي صالح بنيويًا (تم التحقق ببايتات
  `%PDF` وبيانات صحيحة في `test/report_export_test.dart`)، لكن مكتبة `pdf`
  الافتراضية (خط Helvetica) **لا تحتوي حروفًا عربية**، وبيئة التطوير هذه لا
  تملك وصولًا شبكيًا لتحميل خط عربي حقيقي (مثل Amiri أو Cairo) لتضمينه. النص
  العربي داخل الجدول قد يظهر كمربعات فارغة حتى تُضاف خطوط `assets/fonts/*.ttf`
  وتُحمَّل في `report_export_service.dart` (تعليق تفصيلي موجود في الكود يشرح
  كيف). **تصدير CSV غير متأثر بهذه المشكلة إطلاقًا** — يفتح بشكل صحيح بالعربية
  في Excel/Sheets (تم التحقق من BOM + المحتوى في الاختبارات).
- **قوالب رسائل واتساب قابلة للتخصيص من الإعدادات (قسم 57)**: الحقول موجودة في
  جدول `AppSettings` لكن لا توجد شاشة تعديل لها؛ الرسائل حاليًا نصوص ثابتة
  في الكود.
- **Database migrations (قسم 87)**: البنية جاهزة، غير مُختبرة عمليًا (طبيعي
  لأول إصدار `schemaVersion = 1`).
- **أداء التقارير مع آلاف الطلاب (قسم 71)**: `ReportsRepository` يستعلم لكل
  طالب على حدة (N+1) بدل استعلام SQL مجمّع واحد — صحيح وظيفيًا، لكن غير مُحسَّن
  لقواعد بيانات ضخمة جدًا. مقبول للاستخدام العادي (عشرات–مئات الطلاب)، يحتاج
  إعادة هيكلة لاحقًا لآلاف الطلاب.

### ❌ MISSING — لم يُنفَّذ
- فتح ملفات المواد داخل التطبيق مباشرة (`open_filex` معلن في `pubspec.yaml`
  لكن غير مُستخدم فعليًا بعد — لا يوجد زر "فتح" حاليًا في شاشة المواد).
  المستخدم يمكنه فتح الملف يدويًا لأن مساره داخل `bond2_files/materials/`
  معروف، لكن لا واجهة مخصصة لذلك.
- طلب صلاحية الكاميرا الصريح عبر `permission_handler` قبل فتح الماسح (حزمة
  `permission_handler` معلنة وغير مُستخدمة؛ `mobile_scanner` يتولى طلب
  الصلاحية داخليًا بشكل افتراضي، لكن لا تعامل مخصص مع رفض الصلاحية برسالة
  عربية واضحة).
- اختبارات integration_test الكاملة لكل الـ 8 تدفقات في القسم 80 (Flow 1 فقط
  مكتوب؛ يحتاج الباقي جلسة محاكي فعلية).
- خط عربي حقيقي مُضمَّن لتصدير PDF (انظر PARTIAL أعلاه).

## جولة الإصلاحات الثانية (2026) — ملخص فني للتغييرات

| # | الإصلاح | الملفات المتأثرة |
|---|---------|-------------------|
| 1 | Payment integrity: رفض أي دفعة غير موزَّعة بالكامل (`allocatedTotal == amountPiastres` إلزاميًا) | `payments_repository.dart`, `record_payment_screen.dart`, `test/payment_calculation_test.dart` |
| 2 | حقول السنة/الصف/المادة في شاشة إضافة مادة | `materials_screen.dart` |
| 3 | نسخ ملفات المواد فعليًا داخل `bond2_files/materials/<id>.ext` | `file_storage_service.dart` (جديد), `materials_repository.dart`, `materials_screen.dart`, `test/materials_file_storage_test.dart` |
| 4 | إغلاق اتصال DB قبل استبدال الملف + إعادة فتح تلقائي + مسح ملفات يتيمة + كتابة ذرّية | `backup_repository.dart`, `backup_screen.dart`, `test/backup_test.dart` |
| 5 | تسمية زر واتساب بصدق (مشاركة + اختيار، لا إرسال مباشر مضمون) | `student_qr_screen.dart` |
| 6 | شاشة Reports موحّدة بفلاتر | `reports_repository.dart` (جديد), `reports_screen.dart` (جديد), `app_router.dart`, `settings_screen.dart`, `test/reports_test.dart` |
| 7 | تصدير CSV/PDF حقيقي | `report_export_service.dart` (جديد), `reports_screen.dart`, `test/report_export_test.dart` |
| 8 | اختبارات لكل إصلاح أعلاه | 4 ملفات اختبار جديدة/محدَّثة (انظر الجدول) |
| — | إصلاح إضافي اكتُشف أثناء كتابة الاختبارات: `openTestDatabase()` لم يكن يُفعّل `PRAGMA foreign_keys`، فكانت قيود RESTRICT/CASCADE غير مُختبَرة فعليًا | `database.dart` |

## حدود بيئة التطوير التي أُنشئ بها هذا المشروع (شفافية كاملة)

الكود كله كُتب يدويًا وبعناية، لكن بيئة التطوير التي استُخدمت **لا تملك Flutter SDK
ولا Android SDK ولا وصولًا شبكيًا لـ `pub.dev` أو لمصادر الخطوط**. لذلك:
- **لم يتم تشغيل** `flutter pub get` / `flutter analyze` / `flutter test` /
  `flutter build apk` فعليًا في أي مرحلة من مراحل بناء هذا المشروع، بما فيها
  جولة الإصلاحات هذه. **لا أدّعي أن الاختبارات "نجحت" أو أن الـ APK "بُني
  بنجاح" — كلاهما لم يُنفَّذ فعليًا بعد في أي بيئة CI حقيقية حتى كتابة هذا
  السطر.**
- بدلًا من التنفيذ الفعلي، تمت مراجعة كل تغيير يدويًا عبر: فحص توازن الأقواس
  آليًا (سكربت Python) على جميع ملفات Dart، مطابقة كل استيراد حزمة مع
  `pubspec.yaml`، مطابقة كل استخدام Provider مع تعريفه، ومراجعة توقيعات
  Drift Companion يدويًا مقابل تعريفات الجداول.
- تم اكتشاف وإصلاح خطأ حقيقي أثناء هذه المراجعة اليدوية: `openTestDatabase()`
  كانت لا تُفعّل قيود المفاتيح الأجنبية، مما كان سيجعل بعض الاختبارات "تنجح"
  رغم أنها لا تختبر السلوك الفعلي المطلوب — تم إصلاحها في `database.dart`.
- **الخطوة التالية الصحيحة والوحيدة لتأكيد الجاهزية الفعلية**: ادفع المستودع
  إلى GitHub وشغّل الـ Actions. إذا ظهر أي خطأ في السجلّ (analyzer error أو
  build error أو فشل اختبار)، انسخه والصقه هنا وسأصلحه فورًا بدقة بدل التخمين.

## الترخيص / الأيقونة

أيقونة التطبيق (`assets/icon/bond2_icon.png` ومقاسات `mipmap-*`) تم توليدها برمجيًا
بألوان الهوية البصرية لـ BOND2 (لون تركوازي هادئ + رمز "علامات QR" + "B2") — تصميم
بسيط وظيفي وليس تصميمًا احترافيًا من مصمم جرافيك؛ يمكن استبداله بسهولة بوضع ملفات
PNG جديدة بنفس الأسماء في `android/app/src/main/res/mipmap-*/ic_launcher.png`.
