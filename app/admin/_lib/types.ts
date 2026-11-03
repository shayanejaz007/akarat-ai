/* What /api/admin/* returns. The routes are the source of truth; these
   types follow them (app/api/admin). */

export type Day = { day: string; views: number; inquiries: number; signups: number; listings: number; viewers: number };

export type Ranked = { id: string; title_en: string; title_ar: string | null; status: string; n: number };

// What each answer recorded it cost, and which model and effort answered
// (0022_ai_cost.sql). Null before that migration runs.
export type Measured = { today: number; month: number; mix: { route: string; n: number }[] } | null;

export type AssistantUse = {
  model: string;
  today: { turns: number; people: number; searches: number; fetches: number; flagged: number; cost: number | null };
  month: { turns: number; cost: number };
  days: { day: string; turns: number; cost: number | null }[];
  flags: { kind: string; count: number }[];
  measured: Measured;
};

export type LegalFeedback = {
  id: number;
  at: string;
  kind: string;
  reviewer: boolean;
  note: string | null;
  snapshot: {
    question: string;
    answer: string;
    sources: { kind: string; title: string; url: string; status: string | null }[];
    unverified: string[];
  } | null;
};

export type Overview = {
  live: { total: number; web: number; android: number; ios: number; signedIn: number };
  active: { today: number; week: number; month: number };
  users: { total: number; week: number; admins: number; owners: number };
  listings: { total: number; week: number; byStatus: Record<string, number> };
  inquiries: { total: number; today: number; week: number; new: number };
  views: { total: number; today: number; week: number };
  saves: number;
  openReports: number;
  daily: Day[];
  topViewed: Ranked[];
  topInquired: Ranked[];
  byCity: { city: string; n: number }[];
  generatedAt: string;
  // Listings per deal; a deal is null when its count could not be read.
  byDeal: { sale: number | null; rent: number | null; daily: number | null } | null;
  // Null until 0019_daily_rentals.sql has been run.
  dailyRentals: {
    review: { pending: number; approved: number; rejected: number; suspended: number; changed: number; live: number };
    requests: { total: number; pending: number; approved: number; confirmed: number; week: number; nightsConfirmed: number };
  } | null;
  // Null until 0020_ai_advisor.sql has been run. Costs are estimates in USD.
  advisor: (AssistantUse & { limits: { perDaySignedIn: number; perDayAnonymous: number; perDayTotal: number } }) | null;
  // Null until 0021_legal_ai.sql has been run. Costs are estimates in USD.
  legal: (AssistantUse & {
    access: "public" | "reviewers";
    reviewers: number;
    limits: { perDay: number; perDayTotal: number };
    answers: { total: number; withCitations: number; withUnverified: number; cited: number; unverified: number };
    library: {
      sources: number; verified: number; judgments: number; legislation: number; commentary: number;
      repealed: number; stale: number; oldestCheck: string | null; passages: number; embedded: number;
    };
    feedback: { counts: { kind: string; count: number }[]; recent: LegalFeedback[] };
  }) | null;
};

export type Person = { id: string; name: string | null; email: string | null; phone: string | null; verified: boolean; joined: string | null };

export type ListingRow = {
  id: string; status: string; deal: string; property_type: string; city_id: string | null; neighborhood_id: string | null;
  price_jod: number; bedrooms: number | null; bathrooms: number | null; area_sqm: number | null;
  title_en: string; title_ar: string | null; views: number; saves: number; inquiries_count: number;
  featured: boolean; verified: boolean; owner_id: string; created_at: string; updated_at: string | null;
  cover: string | null; media: number; phone: string | null;
  views7d: number; views30d: number; lastInquiry: string | null;
  owner: { id: string; full_name: string | null; phone: string | null; role: string | null; verified: boolean } | null;
};

export type Review = "pending" | "approved" | "rejected" | "suspended";

export type DailyRow = {
  id: string; status: string; property_type: string; city_id: string | null; neighborhood_id: string | null;
  lat: number | null; lng: number | null; location_precision: string | null; address: string | null;
  price_jod: number; max_guests: number | null; min_nights: number | null;
  bedrooms: number | null; bathrooms: number | null; area_sqm: number | null;
  title_en: string; title_ar: string | null; views: number; saves: number; created_at: string; updated_at: string | null;
  daily_review: Review; daily_review_note: string | null; daily_reviewed_at: string | null; daily_changed_at: string | null;
  media: { url: string; video: boolean }[]; description_en: string; description_ar: string; amenities: string[];
  publicPhone: string | null; owner: Person | null; requests: Record<string, number>;
};

export type BookingRow = {
  id: string; property_id: string; renter_name: string; check_in: string; check_out: string; nights: number; guests: number;
  message: string | null; nightly_price: number; total_price: number; status: string; owner_phone: string | null;
  response_note: string | null; closed_reason: string | null; cancelled_by: string | null; responded_at: string | null; created_at: string;
  properties: { title_en: string; title_ar: string | null; city_id: string | null; status: string; daily_review: string | null } | null;
  owner: Person | null; renter: Person | null;
};

export type InquiryRow = {
  id: string; property_id: string; sender_id: string | null; name: string; email: string | null; phone: string | null;
  message: string; status: string; created_at: string;
  properties: { title_en: string; title_ar: string | null; status: string } | null;
  owner: { full_name: string | null; phone: string | null } | null;
};

export type UserRow = {
  id: string; email: string | null; phone: string | null; name: string | null; role: string; verified: boolean;
  agency: string | null; providers: string[]; createdAt: string; lastSignIn: string | null; lastSeen: string | null;
  lastPlatform: string | null; listings: { total: number; active: number };
};

export type ReportRow = {
  id: string; property_id: string; reason: string; details: string | null; status: string; created_at: string;
  properties: { title_en: string; title_ar: string | null; status: string } | null;
};
