// The privacy policy and the terms of use, in both languages.
//
// One source, read in two places: the in-app legal screen in Akarat.dc.html,
// and the server-rendered /[lang]/privacy and /[lang]/terms pages. Keeping two
// copies is how a policy ends up describing a product that no longer exists —
// which is what happened to the first draft. It promised "we do not collect
// your physical location" months before the listing form grew a map pin that
// records exactly that.
//
// NOT LEGAL ADVICE. What follows describes accurately what this software
// does, which is the half a lawyer cannot do for you. Whether it satisfies
// Jordan's Personal Data Protection Law No. 24 of 2023, or the rules of any
// other market listings are published into, needs a lawyer who practises
// there. Have it reviewed before relying on it.

export const LEGAL_UPDATED = {
  en: 'Last updated: October 2026',
  ar: 'آخر تحديث: تشرين الأول ٢٠٢٦'
};

export const PRIVACY_EMAIL = 'privacy@akarat.ai';

export const LEGAL = {
  privacy: {
    en: {
      kicker: 'Legal',
      title: 'Privacy policy',
      intro: 'What Akarat.ai records about you, why, and what you can do about it.',
      sections: [
        { h: 'Who we are', p: 'Akarat.ai is a property search and listing service for Jordan and the wider region. This policy covers akarat.ai and everything reachable from it. Any question, or any request about your own data, goes to privacy@akarat.ai.' },
        { h: 'What an account stores', p: 'Creating an account stores your email address and the name you give. Your profile can also hold a phone number, an agency name and a language preference, each entered by you and changeable or clearable from the dashboard.' },
        { h: 'Signing in with Google', p: 'If you use Continue with Google, Google tells us the email address, name and profile picture on that account, and nothing more. We never see your Google password. What Google does with the fact that you signed in is governed by Google’s own policy, not this one.' },
        { h: 'What a listing stores', p: 'A listing holds what you type about the property: title and description in either language, price, type, size, bedrooms, bathrooms, year built, city and area, the features you tick, and a contact phone number if you add one. Photographs and video you upload are stored too, and are resized in your browser before they leave it.' },
        { h: 'Location, and the part worth reading twice', p: 'If you place a pin on the map, we store the exact coordinate you chose. You decide what is published. Choose Exact pin and the real point and street address are shown to everyone. Choose Approximate circle, which is the default, and what is published is a point displaced by up to 300 metres, while the real one sits in a table only you can read. Nothing reads your device location, and we never ask the browser for it.' },
        { h: 'Enquiries', p: 'When someone enquires about a listing we store the name, the message, and any email or phone they provide, and show it to that listing’s owner. If you are signed in when you enquire, it is linked to your account so you can find it again.' },
        { h: 'What we never collect', p: 'We do not ask for a national ID number, a passport, a bank account or card details. We run no advertising, we do not sell or rent your data, and we do not share it with advertising networks or data brokers. The site carries no third-party analytics or tracking scripts.' },
        { h: 'What your browser keeps', p: 'Your language choice and your signed-in session are kept in your own browser, not as tracking cookies. Clearing site data signs you out and forgets the language, and loses nothing else.' },
        { h: 'Who processes data for us', p: 'Supabase hosts the database, the accounts and the uploaded files. Vercel hosts and serves the site. Google Maps is contacted only when you open the listing form with the map enabled, and Google then receives your IP address and the page you came from, as it would for any site embedding a map. Each acts on our instructions and for no other purpose.' },
        { h: 'Leaving for another portal', p: 'A result belonging to another portal opens on that portal’s own site in a new tab. From that moment their policy applies rather than ours, and we do not tell them who was searching.' },
        { h: 'How long we keep things', p: 'A listing stays until you delete it, and deleting removes the row, its exact coordinate and its photographs. A listing marked sold or rented stays visible, greyed out, until its owner deletes or archives it. Account data stays until you ask for the account to be closed.' },
        { h: 'Your rights', p: 'You can see, correct and delete your own listings from the dashboard at any time. For a copy of everything held about you, a correction you cannot make yourself, deletion of your account, or to object to a particular use, write to privacy@akarat.ai. Jordan’s Personal Data Protection Law gives you these rights, and we answer within its time limits.' },
        { h: 'Children', p: 'The service is for adults. We do not knowingly hold data about anyone under 18, and will delete it if we learn of it.' },
        { h: 'Changes', p: 'If this policy changes in a way that affects you, the date at the top changes and the new version appears here before it takes effect.' }
      ]
    },
    ar: {
      kicker: 'المستندات القانونية',
      title: 'سياسة الخصوصية',
      intro: 'ما الذي تحفظه أكارات عنك، ولماذا، وما الذي يمكنك فعله حياله.',
      sections: [
        { h: 'من نحن', p: 'أكارات منصة للبحث عن العقارات وعرضها في الأردن والمنطقة. تغطي هذه السياسة موقع akarat.ai وكل ما يتفرع عنه. ولأي سؤال أو طلب يخص بياناتك، راسلنا على privacy@akarat.ai.' },
        { h: 'ما يحفظه الحساب', p: 'إنشاء الحساب يحفظ بريدك الإلكتروني والاسم الذي تدخله. ويمكن أن يحتوي ملفك على رقم هاتف واسم مكتب ولغة مفضّلة، وكلها تدخلها بنفسك ويمكنك تعديلها أو حذفها من لوحة التحكم.' },
        { h: 'تسجيل الدخول عبر Google', p: 'إذا استخدمت المتابعة باستخدام Google، تخبرنا Google بالبريد الإلكتروني والاسم وصورة الحساب فقط. ولا نرى كلمة مرورك إطلاقاً. وما تفعله Google بواقعة تسجيل دخولك تحكمه سياستها هي لا هذه السياسة.' },
        { h: 'ما يحفظه الإعلان', p: 'الإعلان يحفظ ما تكتبه عن العقار: العنوان والوصف بأي من اللغتين، والسعر والنوع والمساحة وعدد الغرف والحمامات وسنة البناء والمدينة والمنطقة والمزايا، ورقم هاتف للتواصل إن أضفته. وتُحفظ الصور ومقاطع الفيديو التي ترفعها، وتُصغَّر في متصفحك قبل أن تغادره.' },
        { h: 'الموقع، وهذا الجزء يستحق قراءة متأنية', p: 'إذا وضعت دبوساً على الخريطة، نحفظ الإحداثية الدقيقة التي اخترتها. وأنت من يقرر ما يُنشر: اختر الموقع الدقيق فيظهر الموقع والعنوان للجميع، أو اختر الدائرة التقريبية وهي الخيار الافتراضي فيُنشر موقع يبعد حتى ٣٠٠ متر بينما يبقى الموقع الحقيقي في جدول لا يقرأه سواك. ولا نقرأ موقع جهازك ولا نطلبه من المتصفح.' },
        { h: 'الاستفسارات', p: 'حين يرسل أحدهم استفساراً عن إعلان، نحفظ الاسم والرسالة وأي بريد أو هاتف يضيفه، ونعرضها على صاحب الإعلان. وإذا كنت مسجّل الدخول وقت الإرسال، يُربط الاستفسار بحسابك لتجده لاحقاً.' },
        { h: 'ما لا نجمعه أبداً', p: 'لا نطلب رقم هوية ولا جواز سفر ولا حساباً بنكياً ولا بيانات بطاقة. ولا نعرض إعلانات، ولا نبيع بياناتك أو نؤجّرها، ولا نشاركها مع شبكات إعلانية أو وسطاء بيانات. ولا توجد في الموقع أدوات تحليل أو تتبّع من طرف ثالث.' },
        { h: 'ما يحفظه متصفحك', p: 'تُحفظ لغتك المفضّلة وجلسة دخولك في متصفحك أنت، لا كملفات تتبّع. ومسح بيانات الموقع يسجّل خروجك ويُنسي اللغة، ولا يضيع شيئاً غير ذلك.' },
        { h: 'من يعالج البيانات نيابة عنّا', p: 'Supabase تستضيف قاعدة البيانات والحسابات والملفات المرفوعة، وVercel تستضيف الموقع وتخدمه. ولا نتصل بخرائط Google إلا حين تفتح نموذج الإعلان والخريطة مفعّلة، وعندها تصل Google عنوان الـIP والصفحة التي أتيت منها، كأي موقع يضمّن خريطة. وكلٌّ منها يعمل بتعليماتنا ولغرض آخر لا شيء.' },
        { h: 'الانتقال إلى منصة أخرى', p: 'نتيجة البحث التي تخص منصة أخرى تُفتح على موقعها في تبويب جديد. ومن تلك اللحظة تنطبق سياستهم لا سياستنا، ونحن لا نخبرهم من كان يبحث.' },
        { h: 'مدة الاحتفاظ', p: 'يبقى الإعلان حتى تحذفه، وحذفه يزيل السجل وإحداثيته الدقيقة وصوره. والإعلان الذي تضع عليه مباع أو مؤجَّر يبقى ظاهراً بالأبيض والأسود حتى يحذفه صاحبه أو يؤرشفه. وتبقى بيانات الحساب حتى تطلب إغلاقه.' },
        { h: 'حقوقك', p: 'يمكنك الاطلاع على إعلاناتك وتصحيحها وحذفها من لوحة التحكم في أي وقت. وللحصول على نسخة من كل ما نحتفظ به عنك، أو تصحيح لا تستطيع إجراءه بنفسك، أو حذف حسابك، أو للاعتراض على استخدام معيّن، راسلنا على privacy@akarat.ai. وقانون حماية البيانات الشخصية الأردني يمنحك هذه الحقوق، ونلتزم بمهله.' },
        { h: 'الأطفال', p: 'الخدمة للبالغين. ولا نحتفظ عن علم ببيانات من هم دون الثامنة عشرة، ونحذفها فور علمنا بها.' },
        { h: 'التغييرات', p: 'إذا تغيّرت هذه السياسة بما يؤثر عليك، يتغيّر التاريخ في أعلاها وتُنشر النسخة الجديدة هنا قبل أن تسري.' }
      ]
    }
  },

  terms: {
    en: {
      kicker: 'Legal',
      title: 'Terms of use',
      intro: 'The rules for using Akarat.ai, and the limits of what it is.',
      sections: [
        { h: 'What Akarat is, and what it is not', p: 'Akarat is a place to search for property and to publish a listing. It is not a broker, an estate agent or an escrow service. We are not party to any agreement you reach, we hold no money, and we take no commission on any deal.' },
        { h: 'Using the service', p: 'Searching is open to anyone. Publishing a listing needs an account, and you are responsible for everything published under it. Keep your password to yourself: anything done through your account is treated as done by you.' },
        { h: 'What you may list', p: 'List only property you own or are authorised to market, one listing per property. Everything in it must be true on the day you publish: the price you would actually accept, the real size, the real location, and photographs of that property and no other.' },
        { h: 'What is not allowed', p: 'No listing for a property that is not real and available. No bait pricing, no duplicates, no photographs you have no right to use. Nothing unlawful, discriminatory or abusive, in a listing or an enquiry. No scraping, no automated bulk access, and no attempt to reach data that is not yours.' },
        { h: 'Your content stays yours', p: 'You keep ownership of your text and photographs. Publishing them here gives us permission to display and distribute them as part of the service, including in search results and previews, for as long as the listing is published. Delete the listing and that permission ends.' },
        { h: 'Moderation', p: 'We can remove a listing or suspend an account where either breaks these terms: a price that is not real, a property that is not available, a listing that is not yours. Where it is practical we will say why. A sold or rented listing stays visible, marked, until its owner deletes or archives it.' },
        { h: 'Results from other portals', p: 'Some results come from other portals and are shown as those portals published them, with a link to the source. We do not verify them, do not guarantee the property is still available or correctly priced, and have no control over the other site.' },
        { h: 'Verify before you pay', p: 'View the property. Check the title deed and the identity of whoever you are dealing with. Use a lawyer for the contract. Never send a deposit or any payment on the strength of a listing or a message alone. Most property fraud is a convincing listing and a request to pay quickly.' },
        { h: 'Availability', p: 'We try to keep the service running and accurate, but it is provided as it is. We do not promise it will be uninterrupted, nor that every listing on it is accurate: the accuracy of a listing is its owner’s responsibility.' },
        { h: 'Liability', p: 'To the extent the law allows, we are not liable for loss arising from a transaction between users, from reliance on a listing or an external result, or from the service being unavailable. Nothing here excludes liability that cannot lawfully be excluded.' },
        { h: 'Ending it', p: 'You can stop using the service and ask for your account to be closed at any time, by writing to privacy@akarat.ai. We may close an account that repeatedly breaks these terms.' },
        { h: 'Law', p: 'These terms are governed by the law of the Hashemite Kingdom of Jordan, and the courts of Amman have jurisdiction over any dispute.' },
        { h: 'Changes', p: 'If these terms change, the date at the top changes and the new version appears here. Continuing to use the service after that means accepting them.' }
      ]
    },
    ar: {
      kicker: 'المستندات القانونية',
      title: 'شروط الاستخدام',
      intro: 'قواعد استخدام أكارات، وحدود ما هي عليه.',
      sections: [
        { h: 'ما هي أكارات، وما ليست', p: 'أكارات مكان للبحث عن العقارات ولنشر الإعلانات. ليست وسيطاً ولا مكتباً عقارياً ولا جهة حفظ أموال. ولسنا طرفاً في أي اتفاق تصل إليه، ولا نحتفظ بأي مبلغ، ولا نتقاضى عمولة على أي صفقة.' },
        { h: 'استخدام الخدمة', p: 'البحث متاح للجميع. ونشر إعلان يحتاج حساباً، وأنت مسؤول عن كل ما يُنشر تحته. واحتفظ بكلمة مرورك لنفسك، فكل ما يتم عبر حسابك يُعدّ صادراً عنك.' },
        { h: 'ما الذي يجوز عرضه', p: 'اعرض فقط عقاراً تملكه أو مخوَّل بتسويقه، وإعلاناً واحداً لكل عقار. وكل ما فيه يجب أن يكون صحيحاً يوم نشره: السعر الذي تقبله فعلاً، والمساحة الحقيقية، والموقع الحقيقي، وصور ذلك العقار دون سواه.' },
        { h: 'ما الذي لا يجوز', p: 'لا إعلان لعقار غير حقيقي أو غير متاح. ولا أسعار طُعم، ولا تكرار، ولا صور لا تملك حق استخدامها. ولا شيء مخالف للقانون أو تمييزي أو مسيء، في إعلان أو استفسار. ولا كشط للبيانات ولا وصول آلي بالجملة ولا محاولة للوصول إلى بيانات ليست لك.' },
        { h: 'المحتوى يبقى ملكك', p: 'تبقى نصوصك وصورك ملكك. وبنشرها هنا تمنحنا إذناً بعرضها وتوزيعها ضمن الخدمة، بما في ذلك في نتائج البحث والمعاينات، ما دام الإعلان منشوراً. وبحذف الإعلان ينتهي هذا الإذن.' },
        { h: 'الإشراف', p: 'يحق لنا إزالة إعلان أو إيقاف حساب يخالف هذه الشروط: سعر غير حقيقي، أو عقار غير متاح، أو إعلان ليس لك. وسنوضّح السبب متى أمكن. والإعلان المباع أو المؤجَّر يبقى ظاهراً ومُعلَّماً حتى يحذفه صاحبه أو يؤرشفه.' },
        { h: 'النتائج من منصات أخرى', p: 'بعض النتائج تأتي من منصات أخرى وتُعرض كما نشرتها تلك المنصات مع رابط المصدر. ونحن لا نتحقق منها، ولا نضمن أن العقار ما زال متاحاً أو أن سعره صحيح، ولا سيطرة لنا على الموقع الآخر.' },
        { h: 'تحقّق قبل أن تدفع', p: 'عاين العقار، وتأكد من سند التسجيل ومن هوية من تتعامل معه، واستعن بمحامٍ للعقد. ولا ترسل عربوناً أو أي دفعة بناءً على إعلان أو رسالة وحدها، فأغلب الاحتيال العقاري إعلان مقنع وطلب دفع سريع.' },
        { h: 'التوافر', p: 'نسعى لإبقاء الخدمة عاملة ودقيقة، لكنها تُقدَّم كما هي. ولا نعد بأنها لن تنقطع، ولا بأن كل إعلان فيها دقيق، فدقة الإعلان مسؤولية صاحبه.' },
        { h: 'المسؤولية', p: 'في حدود ما يسمح به القانون، لا نتحمل مسؤولية خسارة ناشئة عن تعامل بين المستخدمين، أو عن الاعتماد على إعلان أو نتيجة خارجية، أو عن انقطاع الخدمة. ولا يستثني هذا أي مسؤولية لا يجوز قانوناً استثناؤها.' },
        { h: 'إنهاء الاستخدام', p: 'يمكنك التوقف عن استخدام الخدمة وطلب إغلاق حسابك في أي وقت بمراسلة privacy@akarat.ai. ولنا أن نغلق حساباً يخالف هذه الشروط تكراراً.' },
        { h: 'القانون', p: 'تخضع هذه الشروط لقوانين المملكة الأردنية الهاشمية، وتختص محاكم عمّان بأي نزاع.' },
        { h: 'التغييرات', p: 'إذا تغيّرت هذه الشروط، يتغيّر التاريخ في أعلاها وتُنشر النسخة الجديدة هنا. والاستمرار في استخدام الخدمة بعدها يعني قبولها.' }
      ]
    }
  }
};

/* ──────────────── deleting an account ────────────────
   Its own document because Facebook asks for a Data Deletion URL before an
   app can go Live, Google Play and the App Store ask for the same, and
   Jordan's Personal Data Protection Law gives the right this page describes.
   One page satisfies all of them, and it has to say what actually happens
   rather than only who to email. */

LEGAL.deletion = {
  en: {
    kicker: 'Legal',
    title: 'Deleting your data',
    intro: 'How to remove a listing, close your account, or ask for everything we hold about you to be erased.',
    sections: [
      { h: 'Delete one listing, yourself, now', p: 'Sign in, open your dashboard, and use Delete on the listing. That removes the row, the exact coordinate stored with it, and the photographs from our storage. It is immediate and it is permanent — there is no recycle bin, so take a copy of anything you want to keep first.' },
      { h: 'Take a listing down without deleting it', p: 'If you only want it off the marketplace, Hide puts it back to a draft that nobody else can see, and Archive keeps it out of public view for good. Both keep your text and photographs so you can republish later. Delete is the one that destroys them.' },
      { h: 'Close your account entirely', p: 'Write to privacy@akarat.ai from the email address on the account, or use the address linked to your Google or Facebook sign-in, and ask for the account to be closed. We will confirm it is you before acting, because an account-deletion request is the one message worth being certain about.' },
      { h: 'What closing the account removes', p: 'Your profile, every listing you published, the exact coordinates held against them, your uploaded photographs and video, the enquiries you sent, and the record of how you signed in — email, Google or Facebook. Once it is done, none of it is recoverable by us or by you.' },
      { h: 'What survives, and why', p: 'An enquiry you sent to another owner stays in that owner’s inbox: it is their record of a conversation, not only yours, and the name and message in it are already theirs. Anything we are required to keep by law is kept for exactly as long as that requires and no longer.' },
      { h: 'If you signed in with Facebook or Google', p: 'Removing the app from your Facebook or Google account stops us receiving anything further from them, but it does not delete what we already hold. Use the email above for that. You can also disconnect either provider from Ways to sign in on your dashboard, provided you still have another way to sign in.' },
      { h: 'How long it takes', p: 'We aim to action a deletion request within seven days, and will confirm by email when it is done. Jordan’s Personal Data Protection Law sets the outer limit and we answer within it.' },
      { h: 'Something gone wrong?', p: 'If a deletion did not happen, or you cannot reach the account you want closed, write to privacy@akarat.ai and say what you tried. A request from an address we cannot match to an account needs more checking, not less, so expect us to ask a question or two before we act.' }
    ]
  },
  ar: {
    kicker: 'المستندات القانونية',
    title: 'حذف بياناتك',
    intro: 'كيف تحذف إعلاناً، أو تغلق حسابك، أو تطلب محو كل ما نحتفظ به عنك.',
    sections: [
      { h: 'احذف إعلاناً واحداً بنفسك الآن', p: 'سجّل الدخول، وافتح لوحة التحكم، واضغط حذف على الإعلان. هذا يزيل السجل والإحداثية الدقيقة المحفوظة معه والصور من مساحة التخزين. وهو فوري ونهائي — لا توجد سلة محذوفات، فاحتفظ بنسخة مما يهمك قبل ذلك.' },
      { h: 'إخفاء الإعلان دون حذفه', p: 'إن أردت إخراجه من المنصة فقط، فخيار إخفاء يعيده مسودة لا يراها أحد، والأرشفة تبقيه خارج العرض العام نهائياً. وكلاهما يحتفظ بنصّك وصورك لتعيد نشرها لاحقاً. الحذف وحده هو الذي يتلفها.' },
      { h: 'إغلاق الحساب بالكامل', p: 'راسلنا على privacy@akarat.ai من البريد المسجّل على الحساب، أو من العنوان المرتبط بتسجيل دخولك عبر Google أو Facebook، واطلب إغلاق الحساب. وسنتحقق من هويتك قبل التنفيذ، لأن طلب حذف حساب هو أجدر الرسائل بالتثبّت.' },
      { h: 'ما الذي يُحذف مع الحساب', p: 'ملفك الشخصي، وكل إعلان نشرته، والإحداثيات الدقيقة المحفوظة معها، وصورك ومقاطعك، والاستفسارات التي أرسلتها، وسجل طريقة دخولك سواء بالبريد أو Google أو Facebook. وبعد التنفيذ لا يمكن استرجاع أي منها، لا منّا ولا منك.' },
      { h: 'ما الذي يبقى، ولماذا', p: 'الاستفسار الذي أرسلته إلى مالك آخر يبقى في بريده: فهو سجلّ محادثة تخصّه هو أيضاً لا أنت وحدك، والاسم والرسالة فيه صارا لديه. وما يلزمنا القانون بالاحتفاظ به نحتفظ به للمدة المطلوبة تماماً لا أكثر.' },
      { h: 'إذا سجّلت الدخول عبر Facebook أو Google', p: 'إزالة التطبيق من حسابك على Facebook أو Google توقف وصول أي شيء جديد منهما، لكنها لا تحذف ما نحتفظ به بالفعل؛ لذلك استخدم البريد أعلاه. ويمكنك أيضاً فك ربط أيٍّ منهما من «طرق تسجيل الدخول» في لوحة التحكم، ما دامت لديك طريقة أخرى للدخول.' },
      { h: 'كم تستغرق', p: 'نسعى لتنفيذ طلب الحذف خلال سبعة أيام، ونؤكد لك بالبريد عند إتمامه. وقانون حماية البيانات الشخصية الأردني يحدد السقف الزمني ونلتزم به.' },
      { h: 'إن حدث خطأ', p: 'إذا لم يتم الحذف، أو تعذّر عليك الوصول إلى الحساب الذي تريد إغلاقه، راسلنا على privacy@akarat.ai واشرح ما جرّبته. والطلب الوارد من عنوان لا نستطيع مطابقته بحساب يحتاج تحققاً أكثر لا أقل، فتوقّع منّا سؤالاً أو اثنين قبل التنفيذ.' }
    ]
  }
};

/** The one document a page needs, in the language it is rendering. */
export function legalDoc(which, lang) {
  const doc = LEGAL[which] || LEGAL.privacy;
  return doc[lang === 'ar' ? 'ar' : 'en'];
}
