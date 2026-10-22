// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'أكارات';

  @override
  String get brandTagline => 'البحث العقاري في جميع أنحاء الأردن';

  @override
  String get tabHome => 'الرئيسية';

  @override
  String get tabExplore => 'تصفّح';

  @override
  String get tabAiSearch => 'البحث الذكي';

  @override
  String get tabSaved => 'المحفوظات';

  @override
  String get tabProfile => 'حسابي';

  @override
  String get actionRetry => 'أعد المحاولة';

  @override
  String get actionCancel => 'إلغاء';

  @override
  String get actionSave => 'حفظ';

  @override
  String get actionDone => 'تم';

  @override
  String get actionContinue => 'متابعة';

  @override
  String get actionBack => 'رجوع';

  @override
  String get actionClose => 'إغلاق';

  @override
  String get actionDelete => 'حذف';

  @override
  String get actionEdit => 'تعديل';

  @override
  String get actionShare => 'مشاركة';

  @override
  String get actionClear => 'مسح';

  @override
  String get actionApply => 'تطبيق';

  @override
  String get actionSeeAll => 'عرض الكل';

  @override
  String get tourWelcomeTitle => 'أهلاً بك في Akarat.ai';

  @override
  String tourWelcomeTitleName(String name) {
    return 'أهلاً بك يا $name';
  }

  @override
  String get tourWelcomeBody => 'حسابك جاهز. إليك جولة سريعة لدقيقة واحدة في البحث عن العقارات وحفظها وعرضها.';

  @override
  String get tourWelcomeAccountBody => 'حسابك جاهز. إليك أين تجد ما يضيفه لك.';

  @override
  String get tourPhotosTitle => 'كل الصور';

  @override
  String get tourPhotosBody => 'اضغط على الصورة أو هنا لترى كل الصور بملء الشاشة، و«الخريطة» تريك موقع العقار.';

  @override
  String get tourSaveTitle => 'احفظه لوقت لاحق';

  @override
  String get tourSaveBody => 'اضغط على القلب ليبقى هذا العقار في المحفوظات وتعود إليه متى شئت.';

  @override
  String get tourContactTitle => 'تواصل مع المالك';

  @override
  String get tourContactBody =>
      'أرسل استفساراً يصل مباشرة إلى لوحة المالك. المحادثة والاتصال في بطاقة المالك في الأسفل.';

  @override
  String get guideProperty => 'عرض عقار';

  @override
  String get guidePropertyNone => 'لا توجد إعلانات بعد لعرض الدليل عليها.';

  @override
  String get settingsLicences => 'تراخيص البرمجيات مفتوحة المصدر';

  @override
  String get mapViewSatellite => 'قمر صناعي';

  @override
  String get mapViewMap => 'خريطة';

  @override
  String get a11yMapViewSatellite => 'التبديل إلى صور القمر الصناعي';

  @override
  String get a11yMapViewMap => 'التبديل إلى الخريطة';

  @override
  String get detailsStreetView => 'التجوّل الافتراضي';

  @override
  String get tourMapLayerTitle => 'شاهده من الأعلى';

  @override
  String get tourMapLayerBody => 'بدّل بين الخريطة وصور القمر الصناعي لترى المباني والشوارع حول العقار.';

  @override
  String get detailsMapPill => 'الخريطة';

  @override
  String get specListed => 'تاريخ النشر';

  @override
  String get specUpdated => 'آخر تحديث';

  @override
  String get viewerPhotos => 'الصور';

  @override
  String get homeMore => 'المزيد لتستكشفه';

  @override
  String get actionSignIn => 'تسجيل الدخول';

  @override
  String get actionSignOut => 'تسجيل الخروج';

  @override
  String get actionNext => 'التالي';

  @override
  String get actionSkip => 'تخطّي';

  @override
  String get actionGetStarted => 'ابدأ';

  @override
  String get actionMore => 'المزيد';

  @override
  String previewMediaCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'الصور والفيديو: $count',
      zero: 'بلا صور بعد',
    );
    return '$_temp0';
  }

  @override
  String get a11yDecrease => 'إنقاص';

  @override
  String get a11yIncrease => 'زيادة';

  @override
  String tourStepOf(int current, int total) {
    return '$current من $total';
  }

  @override
  String get tourSkip => 'تخطَّ الجولة';

  @override
  String get tourDone => 'فهمت';

  @override
  String get tourSearchTitle => 'اكتب ما تريده فقط';

  @override
  String get tourSearchBody =>
      'اكتب طلبك بالعربية أو الإنجليزية، مثل «3 غرف في عبدون بأقل من 150 ألف»، أو اضغط على الميكروفون وقله. يجد البحث الذكي العقارات ويوضح لماذا يناسبك كل منها.';

  @override
  String get tourDealTitle => 'شراء أم إيجار؟';

  @override
  String get tourDealBody => 'بدّل من هنا، وتتغير الصفحة الرئيسية كلها حسب اختيارك.';

  @override
  String get tourCityTitle => 'اختر مدينة';

  @override
  String get tourCityBody => 'ركّز على مدينة واحدة، أو اترك الأردن كله.';

  @override
  String get tourExploreTitle => 'شاهدها على الخريطة';

  @override
  String get tourExploreBody =>
      'يعرض «تصفّح» كل العقارات على الخريطة — الأخضر للبيع والذهبي للإيجار — مع الفلاتر وعرض القائمة.';

  @override
  String get tourAiTitle => 'اطلبه بكلماتك';

  @override
  String get tourAiBody => 'عدّل بحثك بكلمات بسيطة، واحفظه، وارجع إليه متى شئت.';

  @override
  String get tourSavedTitle => 'احتفظ بما يعجبك';

  @override
  String get tourSavedBody => 'اضغط القلب على أي عقار، وستجده في «المحفوظات» إلى جانب عمليات البحث التي حفظتها.';

  @override
  String get tourProfileTitle => 'اعرض عقارك';

  @override
  String get tourProfileBody =>
      'من «حسابي» اعرض عقارك بخطوات قليلة موجّهة، ثم رُدّ على استفسارات المشترين والمستأجرين.';

  @override
  String get tourProfileGuestBody =>
      'سجّل الدخول من هنا لتعرض عقارك بخطوات قليلة موجّهة، ثم رُدّ على استفسارات المشترين والمستأجرين.';

  @override
  String get tourMapDealTitle => 'الكل أو للبيع أو للإيجار';

  @override
  String get tourMapDealBody => 'اختر ما تعرضه الخريطة.';

  @override
  String get tourMapPinsTitle => 'اقرأ الدبابيس';

  @override
  String get tourMapPinsBody =>
      'يظهر السعر على كل دبوس. الأخضر للبيع والذهبي للإيجار، والرقم يجمع الدبابيس المتقاربة، فاضغط عليه للتكبير. الدائرة المظللة تعني أن المالك شارك موقعاً تقريبياً. اضغط على دبوس لمعاينة العقار.';

  @override
  String get tourMapFiltersTitle => 'ضيّق النتائج';

  @override
  String get tourMapFiltersBody => 'صفِّ حسب المدينة والنوع والغرف والسعر والمساحة.';

  @override
  String get tourMapToggleTitle => 'تفضّل القائمة؟';

  @override
  String get tourMapToggleBody => 'بدّل بين الخريطة وقائمة بالنتائج نفسها.';

  @override
  String get tourStepsTitle => 'تسع خطوات قصيرة';

  @override
  String get tourStepsBody => 'يُحفظ تقدّمك على هذا الهاتف أولاً بأول، فيمكنك التوقف والعودة لاحقاً.';

  @override
  String get tourOneThingTitle => 'شيء واحد في كل مرة';

  @override
  String get tourOneThingBody => 'المطلوب فقط المدينة والسعر والعنوان. الصور وموقع الخريطة والتفاصيل تقوّي إعلانك.';

  @override
  String get tourNextTitle => 'تابع';

  @override
  String get tourNextBody => 'يتحقق «التالي» من هذه الخطوة. في النهاية تراجع كل شيء، ثم تنشر أو تحفظ مسودة.';

  @override
  String get tourCloseTitle => 'اخرج متى شئت';

  @override
  String get tourCloseBody => 'عند الإغلاق تبقى مسودتك محفوظة. تظهر الإعلانات المنشورة في التطبيق وعلى akarat.ai.';

  @override
  String get guidesSection => 'جولات إرشادية';

  @override
  String get guideFinding => 'العثور على عقار';

  @override
  String get guideMap => 'استخدام الخريطة';

  @override
  String get guideListing => 'عرض عقار';

  @override
  String get mapAll => 'الكل';

  @override
  String mapCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عقار على الخريطة',
      many: '$count عقاراً على الخريطة',
      few: '$count عقارات على الخريطة',
      two: 'عقاران على الخريطة',
      one: 'عقار واحد على الخريطة',
      zero: 'لا شيء على الخريطة',
    );
    return '$_temp0';
  }

  @override
  String mapCluster(int count) {
    return 'عدد العقارات هنا: $count. اضغط للتكبير.';
  }

  @override
  String get mapNoLocation => 'ليس على الخريطة';

  @override
  String get a11yVoice => 'البحث بالصوت';

  @override
  String get voiceListening => 'أستمع إليك…';

  @override
  String get voiceStarting => 'نجهّز الميكروفون…';

  @override
  String get voiceHint => 'قل ما تبحث عنه، مثل «ثلاث غرف في عبدون بأقل من ١٥٠ ألف».';

  @override
  String get voiceReviewTitle => 'هل هذا ما قصدته؟';

  @override
  String get voiceReviewBody => 'عدّل أي شيء قبل البحث.';

  @override
  String get voiceUnderstood => 'فهمت';

  @override
  String get voiceSearch => 'ابحث';

  @override
  String get voiceRetry => 'تحدّث مجدداً';

  @override
  String get voiceStop => 'تم';

  @override
  String get voiceTypeInstead => 'اكتب بدلاً من ذلك';

  @override
  String get voiceDenied => 'الوصول إلى الميكروفون متوقف. اسمح به لتطبيق عقارات من إعدادات هاتفك للبحث بالصوت.';

  @override
  String get voiceUnavailable => 'البحث الصوتي غير متاح على هذا الجهاز. يمكنك كتابة طلبك بدلاً من ذلك.';

  @override
  String get voiceNoArabic => 'لا يستطيع هذا الجهاز التعرف على الكلام بهذه اللغة بعد. جرّب اللغة الأخرى أو اكتب طلبك.';

  @override
  String get voiceNoSpeech => 'لم ألتقط ما قلته.';

  @override
  String get voiceNetwork => 'يحتاج التعرف على الصوت إلى اتصال بالإنترنت الآن.';

  @override
  String get voiceOther => 'توقف البحث الصوتي بشكل غير متوقع.';

  @override
  String get aiSpeakTitle => 'قلها فقط';

  @override
  String get aiSpeakBody => 'اضغط للبحث بصوتك، بالعربية أو الإنجليزية.';

  @override
  String aiUnder(Object amount) {
    return 'أقل من $amount';
  }

  @override
  String aiUpTo(Object amount) {
    return 'حتى $amount';
  }

  @override
  String aiBedsPlus(int count) {
    return '$count+ غرف';
  }

  @override
  String get aiTryInstead => 'جرّب بدلاً من ذلك';

  @override
  String aiAllOfCity(Object city) {
    return 'كل $city';
  }

  @override
  String get aiAnyType => 'أي نوع';

  @override
  String get aiBothDeals => 'بيع أو إيجار';

  @override
  String get aiFewerFeatures => 'ميزات أقل';

  @override
  String aiFoundSummary(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'وجدت $count عقار مطابق على عقارات، الأقرب أولاً.',
      many: 'وجدت $count عقاراً مطابقاً على عقارات، الأقرب أولاً.',
      few: 'وجدت $count عقارات مطابقة على عقارات، الأقرب أولاً.',
      two: 'وجدت عقارين مطابقين على عقارات، الأقرب أولاً.',
      one: 'وجدت عقاراً واحداً مطابقاً على عقارات.',
      zero: 'لا يوجد على عقارات ما يطابق كل ذلك بعد.',
    );
    return '$_temp0';
  }

  @override
  String get authAccountCreated => 'تم إنشاء الحساب';

  @override
  String authAccountCreatedName(Object name) {
    return 'أهلاً $name، حسابك جاهز.';
  }

  @override
  String get authWelcomeBack => 'تم تسجيل الدخول';

  @override
  String get authCheckEmailTitle => 'تحقق من بريدك';

  @override
  String authCheckEmailBody(Object email) {
    return 'تم إنشاء حسابك. أرسلنا رابط تأكيد إلى $email. افتحه لتأكيد عنوانك، ثم سجّل الدخول هنا.';
  }

  @override
  String get authCheckEmailSignIn => 'أكّدت — تسجيل الدخول';

  @override
  String get authCheckEmailWrong => 'العنوان خطأ؟ ارجع';

  @override
  String get homeLocation => 'الموقع';

  @override
  String get detailsFacilities => 'المرافق';

  @override
  String get navLogIn => 'دخول';

  @override
  String get actionUndo => 'تراجع';

  @override
  String get errorGeneric => 'حدث خطأ ما. حاول مرة أخرى.';

  @override
  String get errorNetwork => 'يبدو أنك غير متصل بالإنترنت. تحقق من اتصالك وحاول مجدداً.';

  @override
  String get errorTimeout => 'تأخر الخادم في الرد. حاول مرة أخرى.';

  @override
  String get errorNotFound => 'لم نجد ما تبحث عنه.';

  @override
  String get errorRateLimited => 'عمليات بحث كثيرة. حاول بعد قليل.';

  @override
  String get errorPermission => 'لا تملك صلاحية القيام بذلك.';

  @override
  String get errorSessionExpired => 'انتهت جلستك. سجّل الدخول من جديد.';

  @override
  String get offlineBanner => 'أنت غير متصل. نعرض ما تم تحميله مسبقاً.';

  @override
  String get notProvided => 'غير متوفر';

  @override
  String get routeNotFound => 'هذه الصفحة غير موجودة.';

  @override
  String get onboardingTitle1 => 'عقارات الأردن في مكان واحد';

  @override
  String get onboardingBody1 =>
      'شقق في عبدون، أراضٍ في مأدبا، شاليهات في البحر الميت. كل إعلان هنا يعود إلى سجل حقيقي.';

  @override
  String get onboardingTitle2 => 'ابحث كما تتكلم';

  @override
  String get onboardingBody2 =>
      'اكتب طلبك بالعربية أو الإنجليزية كما تقوله. نلتقط الميزانية والمنطقة وعدد الغرف، ونوضح لك سبب مناسبة كل نتيجة.';

  @override
  String get onboardingTitle3 => 'اشترِ، استأجر، أو اعرض عقارك';

  @override
  String get onboardingBody3 => 'احفظ ما يعجبك، وأرسل استفساراتك مباشرة إلى المالكين، وانشر عقارك بخطوات موجّهة قليلة.';

  @override
  String get onboardingLanguage => 'اللغة';

  @override
  String get homeGreeting => 'ابحث عن مكانك في الأردن';

  @override
  String get homeSubtitle => 'ابحث بالطريقة المعتادة، أو اكتب ما تريده ببساطة.';

  @override
  String get homeSearchHint => 'فيلا بأربع غرف نوم في عبدون مع حديقة';

  @override
  String get homeSearchPrompt => 'ابحث أو صف ما تريد…';

  @override
  String get homeAiCta => 'البحث الذكي';

  @override
  String get homeFeatured => 'عقارات مميزة';

  @override
  String get homeRecent => 'أضيف حديثاً';

  @override
  String get homeCategories => 'تصفّح حسب النوع';

  @override
  String get homeCities => 'استكشف حسب المدينة';

  @override
  String get homeListCtaTitle => 'تملك عقاراً؟';

  @override
  String get homeListCtaBody => 'اعرضه بخطوات موجّهة قليلة. إعلاناتك واستفساراتك في لوحة واحدة، على التطبيق والموقع.';

  @override
  String get homeListCtaButton => 'أضف عقارك';

  @override
  String get homeEmptyTitle => 'المنصة على وشك الانطلاق';

  @override
  String get homeEmptyBody =>
      'لا توجد إعلانات مطابقة هنا بعد. لا نختلق شيئاً لملء الفراغ — عُد قريباً، أو كن أول من يعرض عقاره.';

  @override
  String get locationAllJordan => 'كل الأردن';

  @override
  String get locationPickerTitle => 'اختر المدينة';

  @override
  String get dealSale => 'شراء';

  @override
  String get dealRent => 'إيجار';

  @override
  String get exploreTitle => 'تصفّح';

  @override
  String exploreResultsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عقار',
      many: '$count عقاراً',
      few: '$count عقارات',
      two: 'عقاران',
      one: 'عقار واحد',
      zero: 'لا توجد عقارات',
    );
    return '$_temp0';
  }

  @override
  String get exploreFilters => 'الفلاتر';

  @override
  String get exploreSort => 'الترتيب';

  @override
  String get sortNewest => 'الأحدث';

  @override
  String get sortPriceLow => 'السعر: من الأقل';

  @override
  String get sortPriceHigh => 'السعر: من الأعلى';

  @override
  String get filterCity => 'المدينة';

  @override
  String get filterArea => 'المنطقة';

  @override
  String get filterAnyCity => 'أي مدينة';

  @override
  String get filterAnyArea => 'أي منطقة';

  @override
  String get filterType => 'نوع العقار';

  @override
  String get filterAnyType => 'أي نوع';

  @override
  String get filterBeds => 'غرف النوم';

  @override
  String get filterBaths => 'الحمامات';

  @override
  String get filterAny => 'الكل';

  @override
  String get filterPrice => 'السعر (دينار)';

  @override
  String get filterMin => 'من';

  @override
  String get filterMax => 'إلى';

  @override
  String get filterSize => 'مساحة البناء (م²)';

  @override
  String get filterAvailableOnly => 'إخفاء المباع والمؤجَّر';

  @override
  String get filterShowResults => 'عرض النتائج';

  @override
  String get filterClearAll => 'مسح الكل';

  @override
  String get filterAmenitiesNote => 'المزايا مثل الحديقة أو المسبح يطابقها البحث الذكي، فهو يقرأ تفاصيل كل إعلان.';

  @override
  String get exploreNoResultsTitle => 'لا شيء يطابق هذه الفلاتر';

  @override
  String get exploreNoResultsBody => 'جرّب توسيع المنطقة أو رفع الميزانية.';

  @override
  String get exploreList => 'قائمة';

  @override
  String get exploreMap => 'خريطة';

  @override
  String get exploreLoadMore => 'جارٍ تحميل المزيد…';

  @override
  String get exploreEnd => 'هذا كل ما يطابق بحثك.';

  @override
  String get mapApproximateNote => 'الدوائر تشير إلى مواقع تقريبية اختار أصحابها عدم تحديدها بدقة.';

  @override
  String get mapNoPins => 'لا يوجد موقع على الخريطة لأي من الإعلانات المحمّلة بعد.';

  @override
  String get badgeForSale => 'للبيع';

  @override
  String get badgeForRent => 'للإيجار';

  @override
  String get badgeSold => 'مباع';

  @override
  String get badgeRented => 'مؤجَّر';

  @override
  String get badgeVerified => 'موثّق';

  @override
  String get badgeFeatured => 'مميز';

  @override
  String get noPhotos => 'لا توجد صور بعد';

  @override
  String get a11ySave => 'احفظ العقار';

  @override
  String get a11yUnsave => 'أزله من المحفوظات';

  @override
  String a11yBeds(int count) {
    return '$count غرف نوم';
  }

  @override
  String a11yBaths(int count) {
    return '$count حمامات';
  }

  @override
  String get aiTitle => 'البحث الذكي';

  @override
  String get aiKicker => 'ذكاء عقاري';

  @override
  String get aiIdleTitle => 'صف العقار الذي تريده.';

  @override
  String get aiIdleBody =>
      'اكتبه كما تقوله. نلتقط نوع العملية والمنطقة والسعر وعدد الغرف والحمامات والمزايا، ونعرف أسماء المناطق الأردنية بأي من اللغتين، ونبحث فوراً.';

  @override
  String get aiIdleBodyShort =>
      'اكتبه كما تقوله، بالعربية أو الإنجليزية. نقرأ المنطقة والميزانية والغرف والمزايا، ونوضح سبب مناسبة كل نتيجة.';

  @override
  String get aiRefineHintShort => 'عدّل، مثلاً «فقط عبدون»';

  @override
  String get aiCoveragePartner => 'موجزات الشركاء المرخّصة غير موصولة بعد، لذا لم يشملها هذا البحث.';

  @override
  String get aiSharpen => 'لنتائج أدق';

  @override
  String get aiInputHint => 'صف العقار الذي تبحث عنه…';

  @override
  String get aiRefineHint => 'عدّل بحثك: «فقط عبدون» أو «ارفع الميزانية إلى ٩٠٠٬٠٠٠»';

  @override
  String get aiTry => 'جرّب';

  @override
  String get aiExample1 => 'شقة ٣ غرف نوم في عبدون بأقل من ١٥٠ ألف دينار';

  @override
  String get aiExample2 => 'فلل في عمان مع حديقة وموقف سيارات';

  @override
  String get aiExample3 => 'بدي شقة بعمان غرفتين وبسعر أقل من ٨٠ ألف دينار';

  @override
  String get aiBrief => 'ملخص الطلب';

  @override
  String get aiBriefEmpty => 'تظهر متطلباتك هنا فور قراءتها، ويمكنك تعديل أي منها. ولا نغيّر شيئاً دون أن نخبرك.';

  @override
  String get aiReadingLive => 'فهمنا:';

  @override
  String get aiWorking => 'جارٍ تنفيذ طلبك…';

  @override
  String get aiStageLang => 'تحديد اللغة';

  @override
  String get aiStageParse => 'استخراج المتطلبات';

  @override
  String get aiStageLoc => 'تحديد الموقع';

  @override
  String get aiStageInternal => 'البحث في المنصة';

  @override
  String get aiStageExternal => 'البحث في السوق الخارجي';

  @override
  String get aiStageRank => 'الترتيب المحسوب';

  @override
  String get aiResultsInternal => 'على أكارات';

  @override
  String get aiResultsExternal => 'مفهرسة من منصات أخرى';

  @override
  String get aiResultsExternalNote =>
      'وُجدت على منصات أردنية أخرى وفهرسها زاحفنا. التوفر غير مؤكد — افتح المصدر للتحقق.';

  @override
  String aiMatch(int score) {
    return 'تطابق $score٪';
  }

  @override
  String get aiWhyMatches => 'لماذا يطابق طلبك';

  @override
  String get aiNoMatchTitle => 'لا يوجد في معروضنا ما يطابق ذلك بعد.';

  @override
  String get aiNoMatchBody => 'جرّب توسيع المنطقة أو رفع الميزانية، أو ابحث في السوق الأردني الأوسع أدناه.';

  @override
  String get aiWiderMarket => 'السوق الأردني الأوسع';

  @override
  String get aiWiderBody =>
      'نحوّل طلبك إلى بحث حقيقي على كل منصة أردنية. تفتح هذه الروابط نتائجها المفلترة، فالإعلانات التي تراها منها وحديثة. لا شيء هنا منسوخ أو مُختلق.';

  @override
  String get aiOpensOutside => 'يفتح خارج أكارات';

  @override
  String aiCoverageMissing(String sources) {
    return 'لم يشمله البحث هذه المرة: $sources';
  }

  @override
  String get aiServedDirect => 'لم تستجب خدمة البحث، فبحثنا في قاعدة بيانات أكارات مباشرة.';

  @override
  String get aiMissingDeal => 'شراء أم إيجار؟ اذكر ذلك ليصبح الترتيب أدق.';

  @override
  String get aiMissingLocation => 'اذكر مدينة أو منطقة لتضييق النتائج.';

  @override
  String get aiSaveSearch => 'احفظ البحث';

  @override
  String get aiSearchSaved => 'تم حفظ البحث';

  @override
  String get aiStartOver => 'مسح البحث';

  @override
  String get aiExternalBadge => 'منصة أخرى';

  @override
  String aiSourcesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مصدر',
      many: '$count مصدراً',
      few: '$count مصادر',
      two: 'مصدران',
      one: 'مصدر واحد',
    );
    return '$_temp0';
  }

  @override
  String get aiViewOnSource => 'اعرض على المصدر';

  @override
  String get aiSaveSearchTitle => 'سمِّ هذا البحث';

  @override
  String get aiSearchedFor => 'طلبك';

  @override
  String chipBedsMin(int count) {
    return '$count+ غرف نوم';
  }

  @override
  String chipBathsMin(int count) {
    return '$count+ حمامات';
  }

  @override
  String chipBudgetMax(String price) {
    return 'حتى $price';
  }

  @override
  String chipBudgetMin(String price) {
    return 'من $price';
  }

  @override
  String chipAreaMin(String area) {
    return '$area+ م²';
  }

  @override
  String get chipOnlyAkarat => 'أكارات فقط';

  @override
  String chipRemove(String label) {
    return 'أزل $label';
  }

  @override
  String get detailsSpecs => 'تفاصيل العقار';

  @override
  String get detailsAmenities => 'المزايا والخدمات';

  @override
  String get detailsAbout => 'عن العقار';

  @override
  String get detailsLocation => 'الموقع';

  @override
  String get detailsReadMore => 'اقرأ المزيد';

  @override
  String get detailsReadLess => 'عرض أقل';

  @override
  String get specType => 'النوع';

  @override
  String get specDeal => 'الإعلان';

  @override
  String get specBeds => 'غرف النوم';

  @override
  String get specBaths => 'الحمامات';

  @override
  String get specArea => 'مساحة البناء';

  @override
  String get specLand => 'مساحة الأرض';

  @override
  String get specYear => 'سنة البناء';

  @override
  String get specRef => 'رقم العقار';

  @override
  String get detailsApproxLocation => 'موقع تقريبي ضمن نحو ٣٠٠ متر. يحتفظ المالك بالعنوان الدقيق.';

  @override
  String get detailsExactLocation => 'موقع دقيق نشره المالك.';

  @override
  String get detailsOpenInMaps => 'افتح في الخرائط';

  @override
  String get detailsNoLocation => 'لم يحدد المالك موقع العقار على الخريطة.';

  @override
  String get detailsContact => 'مهتم بهذا العقار؟';

  @override
  String get detailsContactSub => 'تواصل مع المالك مباشرة، أو أرسل استفساراً إلى لوحة تحكمه.';

  @override
  String get detailsCall => 'اتصل';

  @override
  String get detailsWhatsApp => 'واتساب';

  @override
  String get detailsEnquire => 'أرسل استفساراً';

  @override
  String get detailsCopyNumber => 'نسخ الرقم';

  @override
  String get detailsNumberCopied => 'تم نسخ الرقم';

  @override
  String get detailsNoPhone => 'لم يُنشر رقم هاتف. أرسل استفساراً بدلاً من ذلك.';

  @override
  String get detailsVerifiedListing => 'إعلان موثّق';

  @override
  String get detailsOwnerListing => 'إعلان من المالك';

  @override
  String get detailsClosedSold => 'تم بيع هذا العقار. يبقى هنا حتى تستمر الروابط المشتركة بالعمل.';

  @override
  String get detailsClosedRented => 'تم تأجير هذا العقار. يبقى هنا حتى تستمر الروابط المشتركة بالعمل.';

  @override
  String get detailsSimilar => 'عقارات مشابهة';

  @override
  String detailsSimilarTurn(Object title) {
    return 'مثل «$title»';
  }

  @override
  String get detailsFindSimilar => 'ابحث عن عقارات مشابهة';

  @override
  String get detailsNotFound => 'هذا الإعلان لم يعد متاحاً.';

  @override
  String detailsListedOn(String date) {
    return 'أُضيف $date';
  }

  @override
  String detailsUpdatedOn(String date) {
    return 'حُدّث $date';
  }

  @override
  String detailsMediaPosition(int index, int total) {
    return '$index من $total';
  }

  @override
  String get detailsVideo => 'فيديو';

  @override
  String get detailsYourListing => 'هذا إعلانك';

  @override
  String get detailsManage => 'إدارة';

  @override
  String get inquiryTitle => 'أرسل استفساراً';

  @override
  String get inquiryBody => 'تصل رسالتك مباشرة إلى لوحة تحكم المالك على أكارات.';

  @override
  String get inquiryName => 'اسمك';

  @override
  String get inquiryEmail => 'البريد الإلكتروني';

  @override
  String get inquiryPhone => 'الهاتف';

  @override
  String get inquiryMessage => 'الرسالة';

  @override
  String inquiryDefaultMessage(String title) {
    return 'مرحباً، أنا مهتم بـ «$title». هل ما زال متاحاً؟';
  }

  @override
  String get inquirySend => 'أرسل الاستفسار';

  @override
  String get inquirySending => 'جارٍ الإرسال…';

  @override
  String get inquirySent => 'تم الإرسال. سيظهر للمالك في لوحة تحكمه.';

  @override
  String get inquiryNeedContact => 'أضف بريداً إلكترونياً أو رقم هاتف ليتمكن المالك من الرد.';

  @override
  String get inquiryClosed => 'هذا الإعلان لم يعد يستقبل استفسارات.';

  @override
  String get validationRequired => 'حقل مطلوب';

  @override
  String get validationEmail => 'أدخل بريداً إلكترونياً صحيحاً';

  @override
  String get validationPhone => 'أدخل رقم هاتف صحيحاً';

  @override
  String validationPasswordShort(int count) {
    return 'استخدم $count أحرف على الأقل';
  }

  @override
  String get validationNumber => 'أدخل رقماً صحيحاً';

  @override
  String get validationPositive => 'يجب أن يكون أكبر من صفر';

  @override
  String validationYear(int max) {
    return 'أدخل سنة بين 1900 و$max';
  }

  @override
  String get authSignInTitle => 'أهلاً بعودتك';

  @override
  String get authSignInBody => 'سجّل الدخول بالحساب نفسه الذي تستخدمه على موقع أكارات.';

  @override
  String get authSignUpTitle => 'أنشئ حسابك';

  @override
  String get authSignUpBody => 'حساب واحد لعرض عقارك ومتابعة الاستفسارات وحفظ عمليات البحث — على التطبيق والموقع.';

  @override
  String get fieldName => 'الاسم الكامل';

  @override
  String get fieldEmail => 'البريد الإلكتروني';

  @override
  String get fieldPassword => 'كلمة المرور';

  @override
  String get fieldNewPassword => 'كلمة المرور الجديدة';

  @override
  String get authForgot => 'نسيت كلمة المرور؟';

  @override
  String get authForgotTitle => 'إعادة تعيين كلمة المرور';

  @override
  String get authForgotBody => 'أدخل البريد الإلكتروني الذي سجّلت به وسنرسل لك رابطاً لاختيار كلمة مرور جديدة.';

  @override
  String get authSendLink => 'إرسال الرابط';

  @override
  String get authResetSent => 'إذا كان هناك حساب بهذا البريد فسيصلك رابط إعادة التعيين. تحقق من بريدك.';

  @override
  String get authResetTitle => 'اختر كلمة مرور جديدة';

  @override
  String get authResetBody => 'أدخل كلمة مرور جديدة لحسابك، ستة أحرف على الأقل.';

  @override
  String get authSavePassword => 'حفظ كلمة المرور';

  @override
  String get authPasswordUpdated => 'تم تحديث كلمة المرور.';

  @override
  String authAgreement(String terms, String privacy) {
    return 'بإنشائك حسابًا، فإنك توافق على $terms و$privacy.';
  }

  @override
  String get authCreateAccount => 'إنشاء حساب';

  @override
  String get authHaveAccount => 'لديك حساب؟ سجّل الدخول';

  @override
  String get authNoAccount => 'جديد هنا؟ أنشئ حساباً';

  @override
  String get authGoogle => 'المتابعة باستخدام Google';

  @override
  String get authOr => 'أو';

  @override
  String get authCheckEmail => 'تم إنشاء الحساب. تحقق من بريدك لتأكيد العنوان ثم سجّل الدخول.';

  @override
  String get authRequiredTitle => 'سجّل الدخول للمتابعة';

  @override
  String get authRequiredBody => 'تحتاج إلى حساب لعرض عقار ورؤية استفساراتك وحفظ عمليات البحث.';

  @override
  String get authGoogleDisabled => 'تسجيل الدخول عبر Google غير مفعّل بعد. استخدم بريدك وكلمة المرور.';

  @override
  String get authInvalidCredentials => 'البريد الإلكتروني وكلمة المرور لا يطابقان أي حساب.';

  @override
  String get authEmailNotConfirmed => 'أكّد بريدك الإلكتروني أولاً. تحقق من الرابط في بريدك.';

  @override
  String get authUserExists => 'يوجد حساب بهذا البريد الإلكتروني. سجّل الدخول بدلاً من ذلك.';

  @override
  String get authWeakPassword => 'اختر كلمة مرور أقوى.';

  @override
  String get authLinkExpired => 'انتهت صلاحية الرابط أو استُخدم مسبقاً. اطلب رابطاً جديداً.';

  @override
  String get authCallbackWorking => 'جارٍ تسجيل دخولك…';

  @override
  String get authShowPassword => 'إظهار كلمة المرور';

  @override
  String get authHidePassword => 'إخفاء كلمة المرور';

  @override
  String get authPhoneButton => 'المتابعة برقم الهاتف';

  @override
  String get authPhoneSignUpButton => 'إنشاء حساب برقم الهاتف';

  @override
  String get authPhoneTitle => 'سجّل الدخول برقم هاتفك';

  @override
  String get authPhoneBody => 'اختر الدولة وأدخل رقمك، وسنرسل لك رمزاً لتسجيل الدخول دون كلمة مرور.';

  @override
  String get authPhoneSignUpTitle => 'أنشئ حساباً برقم هاتفك';

  @override
  String get authPhoneSignUpBody => 'أدخل اسمك ورقمك، وسنرسل رمزاً لتأكيد أن الرقم لك.';

  @override
  String get authPhoneLinkTitle => 'أضف رقم هاتف';

  @override
  String get authPhoneChangeTitle => 'غيّر رقم هاتفك';

  @override
  String get authPhoneLinkBody =>
      'سجّل الدخول برمز يصل إلى هاتفك بدلاً من كلمة المرور. سنرسل رمزاً لتأكيد أن الرقم لك.';

  @override
  String get authPhoneEmailNote =>
      'سجّلت بالبريد الإلكتروني؟ سجّل الدخول به، ثم أضف رقمك من الملف الشخصي لتدخل بالهاتف في المرة القادمة.';

  @override
  String get authPhoneSignUpNote =>
      'لديك حساب بالبريد الإلكتروني؟ لا تنشئ حساباً ثانياً: سجّل الدخول ثم أضف رقمك من الملف الشخصي.';

  @override
  String get authPhoneCreateInstead => 'أنشئ حساباً بهذا الرقم';

  @override
  String get authUseEmail => 'استخدم البريد الإلكتروني بدلاً من ذلك';

  @override
  String get fieldCountry => 'الدولة';

  @override
  String get fieldPhoneNumber => 'رقم الهاتف';

  @override
  String get fieldCode => 'رمز التحقق';

  @override
  String authPhoneHint(String digits, String dial) {
    return 'أدخل الرقم المكوّن من $digits أرقام بعد ⁦+$dial⁩، بدون الصفر الأول.';
  }

  @override
  String authPhoneCountryA11y(String country, String dial) {
    return 'رمز الدولة: $country، ⁦+$dial⁩';
  }

  @override
  String get authSendCode => 'إرسال الرمز';

  @override
  String get authSending => 'جارٍ الإرسال…';

  @override
  String get authCodeTitle => 'أدخل رمز التحقق';

  @override
  String get authCodeBodySms => 'أرسلنا رمزاً من ستة أرقام برسالة نصية. استخدمه سريعاً، فصلاحيته قصيرة.';

  @override
  String get authCodeBodyWhatsapp => 'أرسلنا رمزاً من ستة أرقام عبر واتساب. استخدمه سريعاً، فصلاحيته قصيرة.';

  @override
  String get authCodeSentTo => 'أُرسل إلى';

  @override
  String get authChangeNumber => 'تغيير الرقم';

  @override
  String get authVerifySignIn => 'تحقق وسجّل الدخول';

  @override
  String get authVerifySignUp => 'تحقق وأنشئ الحساب';

  @override
  String get authVerifyLink => 'تحقق وأضف الرقم';

  @override
  String get authVerifying => 'جارٍ التحقق…';

  @override
  String get authResend => 'أعد إرسال الرمز';

  @override
  String authResendIn(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'إعادة الإرسال خلال $seconds ثانية',
      few: 'إعادة الإرسال خلال $seconds ثوانٍ',
      two: 'إعادة الإرسال خلال ثانيتين',
      one: 'إعادة الإرسال خلال ثانية',
    );
    return '$_temp0';
  }

  @override
  String get authCodeResent => 'أرسلنا رمزاً جديداً.';

  @override
  String get authCodeIncomplete => 'أدخل الرمز المكوّن من ستة أرقام الذي أرسلناه إليك.';

  @override
  String get authCodeWrong => 'الرمز غير صحيح أو انتهت صلاحيته. تحقق منه أو اطلب رمزاً جديداً.';

  @override
  String get authCodeSendFailed => 'تعذّر إرسال رمز إلى هذا الرقم. تحقق منه وحاول مجدداً.';

  @override
  String get authCodeTooMany => 'طلبات كثيرة للرمز. انتظر بضع دقائق ثم حاول مجدداً.';

  @override
  String get authPhoneNoAccount =>
      'لا يوجد حساب بهذا الرقم بعد. إن سجّلت بالبريد الإلكتروني، فسجّل الدخول به ثم أضف رقمك من الملف الشخصي.';

  @override
  String get authPhoneTaken => 'هذا الرقم مستخدم في حساب آخر.';

  @override
  String get authPhoneInvalid => 'لا يبدو هذا رقم هاتف. تحقق منه وحاول مجدداً.';

  @override
  String get authPhoneUnavailable => 'تسجيل الدخول بالهاتف غير متاح الآن. استخدم بريدك الإلكتروني.';

  @override
  String get authPhoneLinked => 'تمت إضافة الرقم. يمكنك تسجيل الدخول به الآن.';

  @override
  String get profileSignInPhone => 'رقم الهاتف لتسجيل الدخول';

  @override
  String get profileSignInPhoneNone => 'أضفه لتسجّل الدخول برمز';

  @override
  String get authFacebook => 'المتابعة باستخدام فيسبوك';

  @override
  String get authFacebookDisabled => 'تسجيل الدخول عبر فيسبوك غير مفعّل بعد. استخدم بريدك الإلكتروني أو هاتفك حالياً.';

  @override
  String get authCancelled => 'أُلغي تسجيل الدخول. لم يتغيّر شيء.';

  @override
  String get authCallbackFailedTitle => 'لم تكتمل العملية';

  @override
  String get authBackToProfile => 'العودة إلى الملف الشخصي';

  @override
  String get profileFacebook => 'فيسبوك';

  @override
  String get profileFacebookConnect => 'اربطه لتسجّل الدخول عبر فيسبوك';

  @override
  String get profileFacebookConnected => 'مرتبط: يمكنك تسجيل الدخول عبر فيسبوك';

  @override
  String get profileFacebookOnly => 'مرتبط: هذه طريقة الدخول إلى هذا الحساب';

  @override
  String get facebookConnected => 'تم ربط فيسبوك. يمكنك تسجيل الدخول به الآن.';

  @override
  String get facebookDisconnect => 'إلغاء الربط';

  @override
  String get facebookDisconnectTitle => 'إلغاء ربط فيسبوك؟';

  @override
  String get facebookDisconnectBody =>
      'لن تتمكن من تسجيل الدخول عبر فيسبوك بعد الآن. يبقى حسابك وعقاراتك والمنازل المحفوظة كما هي.';

  @override
  String get facebookDisconnected => 'تم إلغاء ربط فيسبوك';

  @override
  String get facebookLinkDisabled => 'ربط الحسابات غير مفعّل بعد. حاول لاحقاً.';

  @override
  String get facebookTaken => 'حساب فيسبوك هذا مرتبط بحساب آخر على Akarat.ai. سجّل الدخول عبر فيسبوك لاستخدامه.';

  @override
  String get facebookOnlyWayIn => 'فيسبوك هو طريقة الدخول إلى هذا الحساب. أضف رقم هاتف أولاً، ثم يمكنك إلغاء ربطه.';

  @override
  String get authApple => 'المتابعة باستخدام Apple';

  @override
  String get authAppleDisabled => 'تسجيل الدخول عبر Apple غير مفعّل بعد. استخدم بريدك الإلكتروني أو هاتفك حالياً.';

  @override
  String get authAppleFailed =>
      'تعذّر على Apple تسجيل دخولك. تأكّد أن هذا الجهاز مسجّل الدخول بمعرّف Apple، أو استخدم بريدك أو هاتفك.';

  @override
  String get profileApple => 'Apple';

  @override
  String get profileAppleConnect => 'اربطه لتسجّل الدخول عبر Apple';

  @override
  String get profileAppleConnected => 'مرتبط: يمكنك تسجيل الدخول عبر Apple';

  @override
  String get appleConnected => 'تم ربط Apple. يمكنك تسجيل الدخول به الآن.';

  @override
  String get appleDisconnectTitle => 'إلغاء ربط Apple؟';

  @override
  String get appleDisconnectBody =>
      'لن تتمكن من تسجيل الدخول عبر Apple بعد الآن. يبقى حسابك وعقاراتك والمنازل المحفوظة كما هي.';

  @override
  String get appleDisconnected => 'تم إلغاء ربط Apple';

  @override
  String get appleTaken => 'معرّف Apple هذا مرتبط بحساب آخر على Akarat.ai. سجّل الدخول عبر Apple لاستخدامه.';

  @override
  String get appleOnlyWayIn => 'Apple هو طريقة الدخول إلى هذا الحساب. أضف رقم هاتف أولاً، ثم يمكنك إلغاء ربطه.';

  @override
  String get deleteAccountAppleNote =>
      'تسجّل الدخول عبر Apple، لذا سيطلب منك Apple التأكيد بعد ذلك. ثم يُزال Akarat.ai من معرّف Apple الخاص بك أيضاً.';

  @override
  String get deleteAccountAppleCancelled => 'لم يُحذف شيء: أُلغي تأكيد Apple.';

  @override
  String get detailsMore => 'المزيد';

  @override
  String get reportListing => 'الإبلاغ عن هذا الإعلان';

  @override
  String get reportBody => 'أخبرنا بالمشكلة. نراجع كل بلاغ ونزيل الإعلانات المخالفة للقواعد.';

  @override
  String get reportReasonScam => 'احتيال أو إعلان وهمي';

  @override
  String get reportReasonWrong => 'سعر أو صور أو تفاصيل غير صحيحة';

  @override
  String get reportReasonUnavailable => 'بيع أو أُجّر بالفعل';

  @override
  String get reportReasonOffensive => 'مسيء أو غير لائق';

  @override
  String get reportReasonOther => 'شيء آخر';

  @override
  String get reportDetails => 'أي شيء آخر يجب أن نعرفه (اختياري)';

  @override
  String get reportSend => 'إرسال البلاغ';

  @override
  String get reportThanks => 'شكراً. سنراجع هذا الإعلان.';

  @override
  String get reportSignIn => 'سجّل الدخول للإبلاغ عن إعلان، لنتمكن من متابعة البلاغ معك.';

  @override
  String reportByEmail(String email) {
    return 'البلاغات غير مفعّلة في التطبيق بعد. فتحنا رسالة إلى $email بدلاً من ذلك.';
  }

  @override
  String get hideAdvertiser => 'إخفاء هذا المعلن';

  @override
  String get hideAdvertiserTitle => 'إخفاء هذا المعلن؟';

  @override
  String get hideAdvertiserBody =>
      'لن ترى أيّاً من إعلاناته مجدداً على هذا الجهاز. يمكنك إظهارها مرة أخرى من الملف الشخصي.';

  @override
  String get hideAdvertiserAction => 'إخفاء';

  @override
  String get hideAdvertiserDone => 'تم الإخفاء. لن ترى إعلاناته بعد الآن.';

  @override
  String profileHiddenAdvertisers(int count) {
    return 'المعلنون المخفيّون: $count';
  }

  @override
  String get profileHiddenAdvertisersShow => 'اضغط لإظهار إعلاناتهم مجدداً';

  @override
  String get showHiddenTitle => 'إظهار المعلنين المخفيين مجدداً؟';

  @override
  String get showHiddenBody => 'ستظهر إعلاناتهم في نتائجك مجدداً.';

  @override
  String get showHiddenAction => 'إظهار';

  @override
  String get showHiddenDone => 'ستظهر إعلاناتهم مجدداً.';

  @override
  String get savedTitle => 'المحفوظات';

  @override
  String get savedProperties => 'العقارات';

  @override
  String get savedSearches => 'عمليات البحث';

  @override
  String get savedEmptyTitle => 'لا شيء محفوظ بعد';

  @override
  String get savedEmptyBody => 'اضغط على القلب في أي عقار ليبقى هنا.';

  @override
  String get savedSearchesEmptyTitle => 'لا توجد عمليات بحث محفوظة';

  @override
  String get savedSearchesEmptyBody => 'نفّذ بحثاً ذكياً، ثم احفظه لتعود إليه في أي وقت.';

  @override
  String get savedSearchesSignIn => 'سجّل الدخول لحفظ عمليات البحث في حسابك.';

  @override
  String get savedDeviceOnly => 'محفوظة على هذا الجهاز. سجّل الدخول لتبقى مع حسابك.';

  @override
  String get savedSyncUnavailable => 'لا يستطيع حسابك حفظ العقارات بعد، لذا نحتفظ بها على هذا الجهاز.';

  @override
  String get savedRemoved => 'أُزيل من المحفوظات';

  @override
  String get savedAdded => 'تم الحفظ';

  @override
  String get savedSearchRun => 'ابحث مجدداً';

  @override
  String get savedSearchDeleted => 'تم حذف البحث';

  @override
  String get savedListingGone => 'لم يعد متاحاً';

  @override
  String get listingNewTitle => 'أضف عقارك';

  @override
  String get listingEditTitle => 'تعديل الإعلان';

  @override
  String stepOf(int current, int total) {
    return 'الخطوة $current من $total';
  }

  @override
  String get stepPurpose => 'ماذا تعرض؟';

  @override
  String get stepType => 'ما نوع العقار؟';

  @override
  String get stepLocation => 'أين يقع؟';

  @override
  String get stepDetails => 'المواصفات';

  @override
  String get stepPrice => 'السعر ووسيلة التواصل';

  @override
  String get stepAmenities => 'المزايا';

  @override
  String get stepDescription => 'العنوان والوصف';

  @override
  String get stepMedia => 'الصور والفيديو';

  @override
  String get stepPreview => 'المراجعة والنشر';

  @override
  String get purposeSale => 'للبيع';

  @override
  String get purposeSaleBody => 'بيع العقار بالكامل.';

  @override
  String get purposeRent => 'للإيجار';

  @override
  String get purposeRentBody => 'تأجيره شهرياً.';

  @override
  String get fieldCity => 'المدينة';

  @override
  String get fieldNeighborhood => 'المنطقة';

  @override
  String get fieldNeighborhoodNone => 'أخرى / غير مدرجة';

  @override
  String get fieldAddress => 'عنوان الشارع (اختياري)';

  @override
  String get fieldAddressHelp => 'يُنشر فقط إذا اخترت إظهار الموقع الدقيق.';

  @override
  String get locationPinTitle => 'حدّده على الخريطة';

  @override
  String get locationPinBody => 'اختياري. اضغط على الخريطة لوضع الدبوس على المبنى. المدينة والمنطقة تتبعانه.';

  @override
  String get locationPinPlace => 'ضع دبوساً';

  @override
  String get locationPinEdit => 'حرّك الدبوس';

  @override
  String get locationPinRemove => 'أزل الدبوس';

  @override
  String get locationPinNone => 'لم يُحدَّد موقع بعد';

  @override
  String get locationPinSnapped => 'حُدّدت المنطقة من الدبوس';

  @override
  String get precisionTitle => 'ما الذي يراه الآخرون';

  @override
  String get precisionApprox => 'دائرة تقريبية';

  @override
  String get precisionApproxNote => 'يُنشر موقع يبعد حتى ٣٠٠ متر. العنوان الدقيق يبقى لك وحدك.';

  @override
  String get precisionExact => 'الموقع الدقيق';

  @override
  String get precisionExactNote => 'يُنشر الموقع والعنوان كما حدّدتهما.';

  @override
  String get locationMapsOff => 'دبابيس الخريطة غير مفعّلة في هذه النسخة. المدينة والمنطقة كافيتان للنشر.';

  @override
  String get fieldBedrooms => 'غرف النوم';

  @override
  String get fieldBathrooms => 'الحمامات';

  @override
  String get fieldAreaSqm => 'مساحة البناء (م²)';

  @override
  String get fieldLandSqm => 'مساحة الأرض (م²)';

  @override
  String get fieldYearBuilt => 'سنة البناء';

  @override
  String get fieldPrice => 'السعر (دينار)';

  @override
  String get fieldPriceRent => 'الإيجار الشهري (دينار)';

  @override
  String get fieldContactPhone => 'هاتف التواصل';

  @override
  String get fieldContactPhoneHelp => 'يظهر في الإعلان ليتمكن المهتمون من الاتصال بك أو مراسلتك على واتساب.';

  @override
  String get fieldTitleEn => 'العنوان بالإنجليزية';

  @override
  String get fieldTitleAr => 'العنوان بالعربية';

  @override
  String get fieldTitleHelp => 'أضف واحداً على الأقل. تعرض اللغة الأخرى هذا العنوان إلى أن تضيفه.';

  @override
  String get fieldDescEn => 'الوصف بالإنجليزية';

  @override
  String get fieldDescAr => 'الوصف بالعربية';

  @override
  String get mediaAddPhotos => 'أضف صوراً';

  @override
  String get mediaAddVideo => 'أضف فيديو';

  @override
  String get mediaHelp =>
      'حتى ٨ ملفات، منها مقطعا فيديو كحد أقصى. تُصغَّر الصور قبل رفعها. الصورة الأولى هي الغلاف — اسحب لإعادة الترتيب.';

  @override
  String get mediaCover => 'الغلاف';

  @override
  String get mediaTooMany => 'الحد الأقصى ثمانية ملفات.';

  @override
  String get mediaTooManyVideos => 'مقطعا فيديو كحد أقصى.';

  @override
  String mediaTooLarge(String name, int size) {
    return '$name أكبر من $size ميغابايت.';
  }

  @override
  String mediaUnsupported(String name) {
    return 'صيغة $name غير مدعومة.';
  }

  @override
  String mediaUploading(int done, int total) {
    return 'يجري رفع الملف $done من $total';
  }

  @override
  String get mediaUploadFailed =>
      'لم يُرفع أحد الملفات، لذا لم يُحفظ شيء بعد. تحقق من اتصالك وحاول مجدداً — الملفات التي رُفعت لن تُرسل مرتين.';

  @override
  String get mediaRemove => 'إزالة';

  @override
  String get previewPublish => 'انشر الإعلان';

  @override
  String get previewSaveDraft => 'احفظ كمسودة';

  @override
  String get previewSaveChanges => 'احفظ التغييرات';

  @override
  String get previewWorking => 'جارٍ الحفظ…';

  @override
  String get previewDraftNote => 'تُحفظ المسودة في حسابك لكنها تبقى مخفية عن الجميع حتى تنشرها.';

  @override
  String get publishSuccess => 'إعلانك منشور الآن.';

  @override
  String get draftSuccess => 'حُفظ كمسودة. انشره من «إعلاناتي».';

  @override
  String get editSuccess => 'تم حفظ التغييرات.';

  @override
  String get listingMissingTitle => 'أضف عنواناً بالعربية أو الإنجليزية.';

  @override
  String get listingMissingPrice => 'أضف السعر.';

  @override
  String get listingMissingCity => 'اختر المدينة.';

  @override
  String get listingDraftRestored => 'احتفظنا بإعلانك غير المكتمل.';

  @override
  String get listingDraftDiscard => 'ابدأ من جديد';

  @override
  String get listingLeaveTitle => 'مغادرة هذا الإعلان؟';

  @override
  String get listingLeaveBody => 'يبقى تقدّمك محفوظاً على هذا الجهاز لتكمل لاحقاً.';

  @override
  String get listingLeaveEditBody => 'ستفقد التغييرات التي لم تحفظها.';

  @override
  String get listingLeaveStay => 'تابع التعديل';

  @override
  String get listingLeaveGo => 'غادر';

  @override
  String get errorUnknownArea =>
      'هذه المنطقة غير مضافة في قاعدة البيانات بعد. اختر منطقة أخرى أو «أخرى» وأعد المحاولة.';

  @override
  String get errorGeoColumns => 'دبابيس الموقع غير مهيّأة على الخادم بعد. أزل الدبوس وأعد المحاولة.';

  @override
  String get errorStorageMissing => 'تخزين الصور غير مهيّأ على الخادم بعد. أزل الملفات وانشر بدونها، أو حاول لاحقاً.';

  @override
  String get dashboardTitle => 'إعلاناتي';

  @override
  String get dashStatListings => 'الإعلانات';

  @override
  String get dashStatLive => 'منشور الآن';

  @override
  String get dashStatHidden => 'مخفي';

  @override
  String get dashStatInquiries => 'الاستفسارات';

  @override
  String get statusDraft => 'مسودة';

  @override
  String get statusPending => 'قيد المراجعة';

  @override
  String get statusActive => 'منشور';

  @override
  String get statusRejected => 'مرفوض';

  @override
  String get statusPaused => 'مخفي';

  @override
  String get statusSold => 'مباع';

  @override
  String get statusRented => 'مؤجَّر';

  @override
  String get statusArchived => 'مؤرشف';

  @override
  String get actionHide => 'إخفاء';

  @override
  String get actionPublish => 'نشر';

  @override
  String get actionMarkSold => 'تم البيع';

  @override
  String get actionMarkRented => 'تم التأجير';

  @override
  String get actionRelist => 'أعد النشر';

  @override
  String get actionView => 'عرض';

  @override
  String get deleteListingTitle => 'حذف هذا الإعلان؟';

  @override
  String get deleteListingBody => 'سيُزال من أكارات على كل الأجهزة مع صوره. لا يمكن التراجع عن ذلك.';

  @override
  String get dashEmptyTitle => 'لا توجد إعلانات بعد';

  @override
  String get dashEmptyBody => 'أضف عقارك الأول ليظهر هنا. ويظهر على الموقع أيضاً.';

  @override
  String get dashAnalyticsNote => 'المشاهدات غير مُحتسبة بعد. لا نعرض أرقاماً قبل وجودها.';

  @override
  String get dashStatusUpdated => 'تم تحديث الإعلان';

  @override
  String get dashDeleted => 'تم حذف الإعلان';

  @override
  String get inquiriesTitle => 'الاستفسارات';

  @override
  String get inquiriesReceived => 'الواردة';

  @override
  String get inquiriesSent => 'المرسلة';

  @override
  String get inquiriesEmpty => 'لا توجد استفسارات بعد. تصلك هنا فور تواصل أحدهم بشأن عقار.';

  @override
  String get inquiriesSentEmpty => 'تظهر هنا الاستفسارات التي ترسلها إلى المالكين.';

  @override
  String inquiryAbout(String title) {
    return 'بخصوص $title';
  }

  @override
  String get inquiryDeletedProperty => 'عقار محذوف';

  @override
  String get inquiryUnknownSender => 'مجهول';

  @override
  String get inquiryReplyEmail => 'بريد';

  @override
  String get inquiryReplyCall => 'اتصال';

  @override
  String get profileTitle => 'حسابي';

  @override
  String get profileGuestTitle => 'أنت تتصفح كزائر';

  @override
  String get profileGuestBody => 'سجّل الدخول لعرض عقار، وحفظ عمليات البحث في حسابك، ورؤية الاستفسارات.';

  @override
  String get profileMyListings => 'إعلاناتي';

  @override
  String get profileInquiries => 'الاستفسارات';

  @override
  String get profileSavedSearches => 'عمليات البحث المحفوظة';

  @override
  String get profileListProperty => 'أضف عقاراً';

  @override
  String get profileEdit => 'تعديل الملف الشخصي';

  @override
  String get profileSaved => 'تم حفظ الملف الشخصي';

  @override
  String get profilePhone => 'الهاتف';

  @override
  String get profileVerified => 'موثّق';

  @override
  String get settingsSection => 'الإعدادات';

  @override
  String get settingsLanguage => 'اللغة';

  @override
  String get settingsAppearance => 'المظهر';

  @override
  String get themeSystem => 'حسب النظام';

  @override
  String get themeLight => 'فاتح';

  @override
  String get themeDark => 'داكن';

  @override
  String get settingsPrivacy => 'سياسة الخصوصية';

  @override
  String get settingsTerms => 'شروط الاستخدام';

  @override
  String get settingsHelp => 'المساعدة والدعم';

  @override
  String get settingsHelpBody => 'سؤال، أو مشكلة في إعلان، أو شيء لا يعمل؟ راسلنا وسيرد عليك شخص حقيقي.';

  @override
  String get settingsEmailUs => 'راسل الدعم';

  @override
  String get settingsWebsite => 'افتح الموقع';

  @override
  String settingsVersion(String version) {
    return 'الإصدار $version';
  }

  @override
  String get settingsDeleteAccount => 'حذف الحساب';

  @override
  String get signOutConfirmTitle => 'تسجيل الخروج؟';

  @override
  String get signOutConfirmBody => 'تبقى إعلاناتك وعمليات البحث المحفوظة في حسابك.';

  @override
  String get deleteAccountTitle => 'حذف حسابك؟';

  @override
  String get deleteAccountBody =>
      'سيُحذف حسابك نهائياً مع إعلاناتك وصورها وعمليات البحث والعقارات المحفوظة، على التطبيق والموقع. الرسائل التي أرسلتها لمالكين آخرين تبقى في بريدهم.';

  @override
  String get deleteAccountConfirmHint => 'اكتب «حذف» للتأكيد';

  @override
  String get deleteAccountConfirmWord => 'حذف';

  @override
  String deleteAccountUnavailable(String email) {
    return 'الحذف من داخل التطبيق غير مفعّل بعد. فتحنا رسالة إلى $email لتطلبه.';
  }

  @override
  String get deleteAccountDone => 'تم حذف حسابك.';

  @override
  String get legalUpdated => 'آخر تحديث: آب ٢٠٢٦';

  @override
  String get privacyH1 => 'ما الذي نجمعه';

  @override
  String get privacyP1 =>
      'حسابك يحتاج بريداً إلكترونياً واسماً. وإذا عرضت عقاراً، نحفظ ما تكتبه عنه: الموقع والسعر والمواصفات والوصف. وتُحفظ نصوص بحثك لتحسين قراءة الطلبات، دون ربطها بحسابك.';

  @override
  String get privacyH2 => 'ما الذي لا نجمعه';

  @override
  String get privacyP2 =>
      'لا نطلب رقم هوية ولا بيانات بنكية ولا موقعك الجغرافي. ولا نضع إعلانات، ولا نبيع بياناتك، ولا نشاركها مع وسطاء إعلان.';

  @override
  String get privacyH3 => 'روابط المنصات الأخرى';

  @override
  String get privacyP3 =>
      'حين تفتح نتيجة من منصة أردنية أخرى، تنتقل إلى موقعها. من تلك اللحظة تنطبق سياسة خصوصيتهم لا سياستنا، ونحن لا نمرر لهم من هو الباحث.';

  @override
  String get privacyH4 => 'حقوقك';

  @override
  String get privacyP4 =>
      'يمكنك تعديل أو حذف أي إعلان من لوحة التحكم في أي وقت، وحذفه يزيله من قاعدة بياناتنا. ولطلب حذف الحساب بالكامل، راسلنا على privacy@akarat.ai.';

  @override
  String get termsH1 => 'استخدام المنصة';

  @override
  String get termsP1 =>
      'البحث متاح للجميع. أما عرض عقار فيحتاج حساباً، وأنت مسؤول عمّا يُنشر تحته. لا تعرض عقاراً لا تملك حق تسويقه. لا يُسمح بأي محتوى مخالف للقانون أو تمييزي أو مسيء، في إعلان أو استفسار: نزيله، وقد نغلق الحساب الذي نشره. يمكن لأي شخص الإبلاغ عن إعلان من صفحته.';

  @override
  String get termsH2 => 'دقة الإعلانات';

  @override
  String get termsP2 =>
      'المعلومات التي تكتبها هي التي تُعرض. عرض عقار بسعر أو مساحة أو موقع غير صحيح سبب كافٍ لإزالة الإعلان دون إشعار.';

  @override
  String get termsH3 => 'النتائج الخارجية';

  @override
  String get termsP3 =>
      'ما يظهر من منصات أخرى هو ما نشرته تلك المنصات، ونعرضه كما هو مع رابط مصدره. نحن لا نضمن توفر تلك العقارات ولا صحة أسعارها، ولا نتقاضى عمولة على أي صفقة.';

  @override
  String get termsH4 => 'المسؤولية';

  @override
  String get termsP4 =>
      'أكارات أداة بحث وعرض، لا وسيط ولا وكيل عقاري. عاين العقار ووثّق الملكية قبل أي دفعة. أي اتفاق يبقى بينك وبين الطرف الآخر.';
}
