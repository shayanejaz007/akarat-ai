// Canonical location records for Jordan + a SINGLE seed listing.
// Reference data only: canonical locations, amenity and type vocabularies,
// and source-confidence weights. No listings, no metrics, no people.

export const CITIES = [
  { id: 'amman',    en: 'Amman',     ar: 'عمان',        lat: 31.953, lng: 35.910, alt: ['ammaan'] },
  { id: 'zarqa',    en: 'Zarqa',     ar: 'الزرقاء',     lat: 32.072, lng: 36.088, alt: ['zarka'] },
  { id: 'irbid',    en: 'Irbid',     ar: 'إربد',        lat: 32.556, lng: 35.847, alt: ['erbid'] },
  { id: 'aqaba',    en: 'Aqaba',     ar: 'العقبة',      lat: 29.532, lng: 35.006, alt: ['akaba', 'aqabah'] },
  { id: 'salt',     en: 'Salt',      ar: 'السلط',       lat: 32.038, lng: 35.727, alt: ['as salt', 'al salt'] },
  { id: 'madaba',   en: 'Madaba',    ar: 'مأدبا',       lat: 31.716, lng: 35.795, alt: ['madabaa'] },
  { id: 'jerash',   en: 'Jerash',    ar: 'جرش',         lat: 32.282, lng: 35.896, alt: ['jarash'] },
  { id: 'mafraq',   en: 'Mafraq',    ar: 'المفرق',      lat: 32.343, lng: 36.208, alt: ['al mafraq'] },
  { id: 'ajloun',   en: 'Ajloun',    ar: 'عجلون',       lat: 32.333, lng: 35.752, alt: ['ajlun'] },
  { id: 'karak',    en: 'Karak',     ar: 'الكرك',       lat: 31.185, lng: 35.702, alt: ['al karak', 'kerak'] },
  { id: 'tafilah',  en: 'Tafilah',   ar: 'الطفيلة',     lat: 30.837, lng: 35.604, alt: ['tafila', 'at tafilah'] },
  { id: 'maan',     en: 'Ma’an',     ar: 'معان',        lat: 30.192, lng: 35.734, alt: ['maan', 'ma an'] },
  { id: 'ramtha',   en: 'Ramtha',    ar: 'الرمثا',      lat: 32.561, lng: 36.008, alt: ['ar ramtha'] },
  { id: 'russeifa', en: 'Russeifa',  ar: 'الرصيفة',     lat: 32.018, lng: 36.046, alt: ['rusaifa', 'ruseifa'] },
  { id: 'sahab',    en: 'Sahab',     ar: 'سحاب',        lat: 31.870, lng: 36.005, alt: [] },
  { id: 'fuheis',   en: 'Fuheis',    ar: 'الفحيص',      lat: 32.008, lng: 35.774, alt: ['fuhais'] },
  { id: 'mahis',    en: 'Mahis',     ar: 'ماحص',        lat: 31.995, lng: 35.760, alt: ['mahes'] },
  { id: 'deadsea',  en: 'Dead Sea',  ar: 'البحر الميت', lat: 31.502, lng: 35.583, alt: ['sweimeh', 'swemeh'] },
  { id: 'wadimusa', en: 'Wadi Musa', ar: 'وادي موسى',   lat: 30.322, lng: 35.478, alt: ['petra', 'البتراء'] },
  { id: 'wadirum',  en: 'Wadi Rum',  ar: 'وادي رم',     lat: 29.575, lng: 35.420, alt: [] },
  { id: 'azraq',    en: 'Azraq',     ar: 'الأزرق',      lat: 31.834, lng: 36.816, alt: ['al azraq'] },
  { id: 'dhiban',   en: 'Dhiban',    ar: 'ذيبان',       lat: 31.500, lng: 35.783, alt: ['diban'] }
];

export const NEIGHBORHOODS = [
  // ── Amman ──────────────────────────────────────────────────────────────
  { id: 'abdoun',      city: 'amman', en: 'Abdoun',            ar: 'عبدون',            lat: 31.936, lng: 35.879, alt: ['abdon', 'abdoun al shamali', 'abdoon'] },
  { id: 'sweifieh',    city: 'amman', en: 'Sweifieh',          ar: 'الصويفية',         lat: 31.949, lng: 35.867, alt: ['swaifieh', 'sweifiyeh', 'swefieh'] },
  { id: 'khalda',      city: 'amman', en: 'Khalda',            ar: 'خلدا',             lat: 31.987, lng: 35.826, alt: ['khaldah', 'khalida'] },
  { id: 'dabouq',      city: 'amman', en: 'Dabouq',            ar: 'دابوق',            lat: 31.986, lng: 35.786, alt: ['daboug', 'dabuq', 'dabok'] },
  { id: 'jabalamman',  city: 'amman', en: 'Jabal Amman',       ar: 'جبل عمان',         lat: 31.951, lng: 35.925, alt: ['first circle', 'third circle'] },
  { id: 'deirghbar',   city: 'amman', en: 'Deir Ghbar',        ar: 'دير غبار',         lat: 31.945, lng: 35.858, alt: ['der ghbar', 'deir ghubar'] },
  { id: 'umuthaina',   city: 'amman', en: 'Um Uthaina',        ar: 'أم أذينة',         lat: 31.964, lng: 35.872, alt: ['umm uthaina', 'om uthaina'] },
  { id: 'shmeisani',   city: 'amman', en: 'Shmeisani',         ar: 'الشميساني',        lat: 31.968, lng: 35.905, alt: ['shmaisani', 'shmesani'] },
  { id: 'abdali',      city: 'amman', en: 'Abdali',            ar: 'العبدلي',          lat: 31.962, lng: 35.914, alt: ['al abdali', 'abdali boulevard'] },
  { id: 'airportrd',   city: 'amman', en: 'Airport Road',      ar: 'طريق المطار',      lat: 31.855, lng: 35.950, alt: ['airport street'] },
  { id: 'tlaalali',    city: 'amman', en: 'Tla’ Al Ali',       ar: 'تلاع العلي',       lat: 31.987, lng: 35.862, alt: ['tla al ali', 'tlaa al ali', 'telaa al ali'] },
  { id: 'jubaiha',     city: 'amman', en: 'Al Jubaiha',        ar: 'الجبيهة',          lat: 32.020, lng: 35.874, alt: ['jubeiha', 'jbeiha'] },
  { id: 'marj',        city: 'amman', en: 'Marj Al Hamam',     ar: 'مرج الحمام',       lat: 31.888, lng: 35.836, alt: ['marj el hamam'] },
  { id: 'rabieh',      city: 'amman', en: 'Al Rabieh',         ar: 'الرابية',          lat: 31.971, lng: 35.870, alt: ['rabiah', 'rabya', 'al rabiyeh'] },
  { id: 'jabalhussein',city: 'amman', en: 'Jabal Al Hussein',  ar: 'جبل الحسين',       lat: 31.968, lng: 35.917, alt: ['jabal hussein'] },
  { id: 'weibdeh',     city: 'amman', en: 'Jabal Al Weibdeh',  ar: 'جبل اللويبدة',     lat: 31.957, lng: 35.921, alt: ['lweibdeh', 'luweibdeh', 'weibdeh'] },
  { id: 'wadisaqra',   city: 'amman', en: 'Wadi Saqra',        ar: 'وادي صقرة',        lat: 31.960, lng: 35.900, alt: ['wadi sakra'] },
  { id: 'gardens',     city: 'amman', en: 'Gardens Street',    ar: 'شارع الجاردنز',    lat: 31.977, lng: 35.879, alt: ['wasfi al tal', 'wasfi el tal', 'garden street'] },
  { id: 'meccast',     city: 'amman', en: 'Mecca Street',      ar: 'شارع مكة',         lat: 31.972, lng: 35.850, alt: ['makkah street', 'mecca st'] },
  { id: 'umsummaq',    city: 'amman', en: 'Um Al Summaq',      ar: 'أم السماق',        lat: 31.976, lng: 35.845, alt: ['umm al summaq', 'om al summaq'] },
  { id: 'sportcity',   city: 'amman', en: 'Sports City',       ar: 'المدينة الرياضية', lat: 31.983, lng: 35.900, alt: ['sport city', 'al medina al riyadiya'] },
  { id: 'shafabadran', city: 'amman', en: 'Shafa Badran',      ar: 'شفا بدران',        lat: 32.043, lng: 35.895, alt: ['shafabadran', 'shafa badran'] },
  { id: 'sweileh',     city: 'amman', en: 'Sweileh',           ar: 'صويلح',            lat: 32.028, lng: 35.836, alt: ['suweileh', 'swaileh'] },
  { id: 'abunsair',    city: 'amman', en: 'Abu Nsair',         ar: 'أبو نصير',         lat: 32.056, lng: 35.856, alt: ['abu nseir', 'abu naseer'] },
  { id: 'tabarbour',   city: 'amman', en: 'Tabarbour',         ar: 'طبربور',           lat: 32.020, lng: 35.925, alt: ['tabarbor'] },
  { id: 'wadiseer',    city: 'amman', en: 'Wadi Al Seer',      ar: 'وادي السير',       lat: 31.949, lng: 35.795, alt: ['wadi seer', 'wadi es seer'] },
  { id: 'bayader',     city: 'amman', en: 'Bayader Wadi Seer', ar: 'بيادر وادي السير', lat: 31.951, lng: 35.815, alt: ['bayader', 'al bayader'] },
  { id: 'kursi',       city: 'amman', en: 'Al Kursi',          ar: 'الكرسي',           lat: 31.968, lng: 35.836, alt: ['kursi'] },
  { id: 'dahiyatrashid',city:'amman', en: 'Dahiyat Al Rashid', ar: 'ضاحية الرشيد',     lat: 32.006, lng: 35.876, alt: ['dahyat al rashid', 'al rashid suburb'] },
  { id: 'dahiyathussein',city:'amman',en: 'Dahiyat Al Hussein',ar: 'ضاحية الحسين',     lat: 31.989, lng: 35.899, alt: ['dahyat al hussein'] },
  { id: 'qweismeh',    city: 'amman', en: 'Al Qweismeh',       ar: 'القويسمة',         lat: 31.909, lng: 35.966, alt: ['quweismeh', 'qwaismeh'] },
  { id: 'muqablain',   city: 'amman', en: 'Al Muqablain',      ar: 'المقابلين',        lat: 31.905, lng: 35.885, alt: ['mqablain', 'muqabalain'] },
  { id: 'naour',       city: 'amman', en: 'Naour',             ar: 'ناعور',            lat: 31.869, lng: 35.822, alt: ['naor', 'na our'] },
  { id: 'marka',       city: 'amman', en: 'Marka',             ar: 'ماركا',            lat: 31.972, lng: 35.981, alt: ['marqa'] },
  { id: 'hashmi',      city: 'amman', en: 'Al Hashmi',         ar: 'الهاشمي',          lat: 31.968, lng: 35.945, alt: ['hashmi shamali', 'al hashimi'] },
  { id: 'nazzal',      city: 'amman', en: 'Al Nazzal',         ar: 'النزهة',           lat: 31.930, lng: 35.925, alt: ['nazzal'] },
  { id: 'downtown',    city: 'amman', en: 'Downtown',          ar: 'وسط البلد',        lat: 31.951, lng: 35.935, alt: ['al balad', 'balad', 'city centre', 'city center'] },
  { id: 'jandaweel',   city: 'amman', en: 'Jandaweel',         ar: 'الجندويل',         lat: 31.941, lng: 35.849, alt: ['jandweel', 'jandawil'] },
  { id: 'khreibetsouq',city: 'amman', en: 'Khreibet Al Souq',  ar: 'خريبة السوق',      lat: 31.878, lng: 35.928, alt: ['khraibet al souq'] },
  { id: 'yadudeh',     city: 'amman', en: 'Al Yadudeh',        ar: 'اليادودة',         lat: 31.855, lng: 35.885, alt: ['yadoudeh', 'yadodeh'] },

  // ── Aqaba ──────────────────────────────────────────────────────────────
  { id: 'southbeach',  city: 'aqaba', en: 'South Beach',       ar: 'الشاطئ الجنوبي',   lat: 29.451, lng: 34.986, alt: [] },
  { id: 'talabay',     city: 'aqaba', en: 'Tala Bay',          ar: 'تالا باي',         lat: 29.396, lng: 34.977, alt: ['talabay'] },
  { id: 'ayla',        city: 'aqaba', en: 'Ayla',              ar: 'أيلة',             lat: 29.539, lng: 34.985, alt: ['ayla oasis'] },
  { id: 'aqabacentre', city: 'aqaba', en: 'Aqaba Town',        ar: 'وسط العقبة',       lat: 29.529, lng: 35.006, alt: ['aqaba downtown'] },

  // ── Irbid ──────────────────────────────────────────────────────────────
  { id: 'irbidcentre', city: 'irbid', en: 'Irbid Centre',      ar: 'وسط إربد',         lat: 32.553, lng: 35.851, alt: ['irbid center', 'irbid downtown'] },
  { id: 'hayjameaa',   city: 'irbid', en: 'University Area',   ar: 'حي الجامعة',       lat: 32.531, lng: 35.855, alt: ['hay al jameaa', 'yarmouk university'] },
  { id: 'aidoun',      city: 'irbid', en: 'Aidoun',            ar: 'عيدون',            lat: 32.542, lng: 35.881, alt: ['aydoun', 'eidoun'] },

  // ── Zarqa ──────────────────────────────────────────────────────────────
  { id: 'zarqacentre', city: 'zarqa', en: 'Zarqa Centre',      ar: 'وسط الزرقاء',      lat: 32.073, lng: 36.089, alt: ['zarqa center'] },
  { id: 'jabaltaj',    city: 'zarqa', en: 'Jabal Tareq',       ar: 'جبل طارق',         lat: 32.060, lng: 36.100, alt: ['jabal tariq'] },

  // ── Dead Sea / Madaba / Salt ───────────────────────────────────────────
  { id: 'sweimeh',     city: 'deadsea', en: 'Sweimeh',         ar: 'سويمة',            lat: 31.510, lng: 35.585, alt: ['swemeh', 'suweimeh'] },
  { id: 'madabacentre',city: 'madaba',  en: 'Madaba Centre',   ar: 'وسط مأدبا',        lat: 31.716, lng: 35.794, alt: ['madaba center'] },
  { id: 'safut',       city: 'salt',    en: 'Safut',           ar: 'صافوط',            lat: 32.028, lng: 35.815, alt: ['safoot'] }
];

export const AMENITIES = [
  { id: 'garden',    en: 'Garden',             ar: 'حديقة' },
  { id: 'pool',      en: 'Swimming pool',      ar: 'مسبح' },
  { id: 'parking',   en: 'Parking',            ar: 'موقف سيارات' },
  { id: 'balcony',   en: 'Balcony',            ar: 'شرفة' },
  { id: 'elevator',  en: 'Elevator',           ar: 'مصعد' },
  { id: 'furnished', en: 'Furnished',          ar: 'مفروش' },
  { id: 'security',  en: '24/7 security',      ar: 'حراسة ٢٤ ساعة' },
  { id: 'heating',   en: 'Central heating',    ar: 'تدفئة مركزية' },
  { id: 'ac',        en: 'Air conditioning',   ar: 'تكييف' },
  { id: 'solar',     en: 'Solar water heater', ar: 'سخان شمسي' },
  { id: 'storage',   en: 'Storage room',       ar: 'غرفة تخزين' },
  { id: 'smart',     en: 'Smart home',         ar: 'منزل ذكي' },
  { id: 'seaview',   en: 'Sea view',           ar: 'إطلالة بحرية' },
  { id: 'roof',      en: 'Private roof',       ar: 'رووف خاص' }
];

export const TYPES = [
  { id: 'apartment', en: 'Apartment', ar: 'شقة' },
  { id: 'villa',     en: 'Villa',     ar: 'فيلا' },
  { id: 'house',     en: 'House',     ar: 'بيت مستقل' },
  { id: 'land',      en: 'Land',      ar: 'أرض' },
  { id: 'office',    en: 'Office',    ar: 'مكتب' },
  { id: 'shop',      en: 'Shop',      ar: 'محل تجاري' },
  { id: 'building',  en: 'Building',  ar: 'بناية' },
  { id: 'chalet',    en: 'Chalet',    ar: 'شاليه' },
  { id: 'warehouse', en: 'Warehouse', ar: 'مستودع' },
  { id: 'farm',      en: 'Farm',      ar: 'مزرعة' }
];

// Marketplace inventory comes from Postgres, not from this file. Nothing is
// seeded here: an empty marketplace shows an empty state, never a stand-in.
export const INTERNAL = [];

// External market adapters exist in architecture only until credentials are supplied.
export const EXTERNAL = [];

export const PROVIDERS = [
  { name: 'Jordan Property Portal',  kind: 'known_marketplace', env: 'JPP_API_KEY' },
  { name: 'Levant Agency Network',   kind: 'agency_website',    env: 'LEVANT_FEED_URL' },
  { name: 'Amman Developers Group',  kind: 'developer_website', env: 'ADG_FEED_URL' },
  { name: 'Aqaba Coast Listings',    kind: 'known_marketplace', env: 'ACL_API_KEY' },
  { name: 'Search API discovery',    kind: 'general_web_result', env: 'SEARCH_API_KEY' }
];

export const SOURCE_CONFIDENCE = {
  verified_partner: 1.0, licensed_feed: 0.92, known_marketplace: 0.86,
  agency_website: 0.74, developer_website: 0.78, general_web_result: 0.42
};
