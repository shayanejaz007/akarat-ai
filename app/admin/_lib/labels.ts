/* Words for the values the database stores, and the tone each one wears.
   A tone is a badge colour that always comes with its words, never alone. */

export type Tone = "good" | "warn" | "bad" | "info" | "neutral" | "gold";
export type Labelled = { label: string; tone: Tone };

export const LISTING_STATUS: Record<string, Labelled> = {
  active: { label: "Active", tone: "good" },
  pending: { label: "Pending review", tone: "warn" },
  draft: { label: "Draft", tone: "neutral" },
  paused: { label: "Paused", tone: "warn" },
  sold: { label: "Sold", tone: "info" },
  rented: { label: "Rented", tone: "info" },
  rejected: { label: "Rejected", tone: "bad" },
  archived: { label: "Archived", tone: "neutral" },
};

export const DEAL: Record<string, string> = { sale: "For sale", rent: "For rent", daily: "Daily rental" };

export const REVIEW: Record<string, Labelled> = {
  pending: { label: "Waiting for review", tone: "warn" },
  approved: { label: "Approved · verified", tone: "good" },
  rejected: { label: "Rejected", tone: "bad" },
  suspended: { label: "Suspended", tone: "bad" },
};

export const BOOKING_STATUS: Record<string, Labelled> = {
  pending: { label: "Waiting for the owner", tone: "warn" },
  approved: { label: "Approved · number shared", tone: "info" },
  confirmed: { label: "Confirmed stay", tone: "good" },
  rejected: { label: "Rejected", tone: "bad" },
  cancelled: { label: "Cancelled", tone: "neutral" },
};

export const INQUIRY_STATUS: Record<string, Labelled> = {
  new: { label: "New", tone: "info" },
  read: { label: "Read", tone: "neutral" },
  replied: { label: "Replied", tone: "good" },
  closed: { label: "Closed", tone: "neutral" },
};

export const ROLES: Record<string, Labelled> = {
  user: { label: "User", tone: "neutral" },
  property_owner: { label: "Owner", tone: "info" },
  agent: { label: "Agent", tone: "gold" },
  admin: { label: "Admin", tone: "bad" },
};

export const PLATFORM: Record<string, string> = { web: "Website", android: "Android", ios: "iPhone" };

export const PROVIDER: Record<string, string> = { email: "Email", google: "Google", apple: "Apple", facebook: "Facebook", phone: "Phone" };

export const REPORT_REASON: Record<string, string> = {
  scam: "Scam or fraud",
  wrong_details: "Wrong details",
  unavailable: "No longer available",
  offensive: "Offensive",
  other: "Other",
};

export const REPORT_STATUS: Record<string, Labelled> = {
  open: { label: "Open", tone: "bad" },
  reviewed: { label: "Reviewed", tone: "good" },
  removed: { label: "Taken down", tone: "neutral" },
  dismissed: { label: "Dismissed", tone: "neutral" },
};

/* What the AI advisor (POST /api/ai/advisor) flags for a look. Flags are
   things worth checking, never anyone's words. */
export const ADVISOR_FLAG: Record<string, string> = {
  prompt_leak: "Reply withdrawn: recited its instructions",
  refusal: "Request declined by the model",
  unverified_link: "External link not backed by a search",
  unknown_listing: "Listing not returned by a search",
  invalid_tool_input: "Tool input refused",
  unknown_tool: "Unknown tool called",
  answer_retry: "Answer asked for again (none was visible)",
  unbacked_research_claim: "Said it searched when nothing was searched",
};

export const LEGAL_FLAG: Record<string, string> = {
  prompt_leak: "Answer withdrawn: recited its instructions",
  refusal: "Request declined by the model",
  unverified_reference: "Answer named a reference no source supported",
  library_unavailable: "Legal library could not be searched",
  bad_tool_input: "Tool input refused",
  unknown_tool: "Unknown tool called",
  tool_failed: "A tool failed",
  answer_retry: "Answer asked for again (none was visible)",
  unbacked_research_claim: "Said it searched when nothing was searched",
};

export const FEEDBACK: Record<string, Labelled> = {
  good: { label: "Helpful", tone: "good" },
  wrong_law: { label: "Wrong law", tone: "bad" },
  wrong_citation: { label: "Wrong article or citation", tone: "bad" },
  outdated: { label: "Out of date", tone: "warn" },
  fabricated: { label: "Cites something that doesn't exist", tone: "bad" },
  missing: { label: "Missed something important", tone: "warn" },
  unclear: { label: "Unclear", tone: "warn" },
  other: { label: "Something else", tone: "neutral" },
};

export const labelOf = (map: Record<string, Labelled>, key: string): Labelled =>
  map[key] ?? { label: key ? key[0].toUpperCase() + key.slice(1).replace(/_/g, " ") : "—", tone: "neutral" };
