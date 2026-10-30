/**
 * Listings and a stand-in database for the advisor's tool tests.
 *
 * FakeDb answers the way Row Level Security does: searches only see active
 * listings, a lookup by id also sees sold and rented ones, and anything else
 * (drafts, pending review, rejected) does not exist.
 */
import type { Listing, ListingsDb } from "../../lib/advisor/listings.ts";
import { Evidence } from "../../lib/advisor/evidence.ts";
import type { Card, ToolEnv } from "../../lib/advisor/tools.ts";

let n = 0;
export const uid = () => `0000000${++n}`.slice(-8) + "-1111-4111-8111-111111111111";

export function listing(over: Partial<Listing> = {}): Listing {
  return {
    id: uid(),
    status: "active",
    deal: "sale",
    type: "apartment",
    cityId: "amman",
    areaId: "abdoun",
    price: 140000,
    beds: 3,
    baths: 2,
    size: 160,
    land: null,
    yearBuilt: 2018,
    titleEn: "Bright corner apartment",
    titleAr: "شقة زاوية مشمسة",
    verified: true,
    amenities: ["parking", "elevator"],
    photos: 6,
    image: "https://demo.supabase.co/storage/v1/object/public/listing-photos/a.jpg",
    descriptionEn: "Third floor, south facing.",
    descriptionAr: "طابق ثالث، واجهة جنوبية.",
    listedDays: 4,
    maxGuests: null,
    minNights: null,
    ...over,
  };
}

export class FakeDb implements ListingsDb {
  calls: { method: string; arg: unknown }[] = [];
  rows: Listing[];
  constructor(rows: Listing[]) {
    this.rows = rows;
  }
  async find(q: Parameters<ListingsDb["find"]>[0], limit: number) {
    this.calls.push({ method: "find", arg: q });
    return this.rows
      .filter(r => r.status === "active")
      .filter(r => (q.deal === "any" ? r.deal === "sale" || r.deal === "rent" : r.deal === q.deal))
      .filter(r => !q.types.length || q.types.includes(r.type))
      .filter(r => !q.cityId || r.cityId === q.cityId)
      .filter(r => q.priceMax == null || r.price <= q.priceMax)
      .filter(r => q.priceMin == null || r.price >= q.priceMin)
      .filter(r => q.bedsMin == null || (r.beds ?? 0) >= q.bedsMin)
      .slice(0, limit);
  }
  async byIds(ids: string[]) {
    this.calls.push({ method: "byIds", arg: ids });
    return this.rows.filter(r => ids.includes(r.id) && ["active", "sold", "rented"].includes(r.status));
  }
  async prices(q: Parameters<ListingsDb["prices"]>[0]) {
    this.calls.push({ method: "prices", arg: q });
    return this.rows
      .filter(r => r.status === "active" && r.deal === q.deal)
      .filter(r => !q.type || r.type === q.type)
      .filter(r => (q.areaId ? r.areaId === q.areaId : !q.cityId || r.cityId === q.cityId))
      .map(r => ({ price: r.price, size: r.size }));
  }
}

export function env(db: ListingsDb, lang: "en" | "ar" = "en"): ToolEnv {
  return { db, lang, evidence: new Evidence(), today: "2026-10-29", cards: new Map<string, Card>(), shownThisTurn: [] };
}
