# Design and UX audit

Method: every screen and state was rendered with the real fonts through
`test/visual/audit_test.dart` (now 67 renders: compact 360×740, phone 390×844,
large 430×932, tablet 820×1180, landscape 844×390; English and Arabic; light
and dark; loading, empty and error states; 1.6× text), then read screen by
screen. Interactions were exercised in widget tests. Findings were listed
before any fix; each now has a status.

Severity: **H** breaks or misleads · **M** visibly unpolished or inconsistent · **L** refinement.
Status: ✅ fixed and re-checked in the renders · ⏸ deliberately not done (reason given).

## System-wide

| # | Finding | Sev | Status |
|---|---|---|---|
| G1 | Page titles are inset 16 px while all content uses a 20 px gutter; small 18 px titles carry no hierarchy on tab roots | M | ✅ `LargeTitleBar` on every list root (Explore, Saved, Profile, My listings, Inquiries); titles start where the content starts, on phones and tablets; plain bars use the 20 pt gutter via the theme |
| G2 | Three different segmented controls: Material `SegmentedButton` (Home, Explore, appearance), underline `TabBar` (Saved, Inquiries), custom pill (language). Feels assembled, not designed | M | ✅ one `SegmentedPill` everywhere (Buy/Rent, Saved and Inquiries tabs, language, appearance) |
| G3 | Section headers place the "See all" / "Search for similar" action off the title's baseline | L | ✅ `SectionHeader` baseline-aligns its action |
| G4 | Tab-bar labels scale with Dynamic Type and truncate at 1.6× ("المحفوظ…"); iOS tab bars cap label size | M | ✅ capped at 1.15× in the bar only |
| G5 | No width discipline on tablets: cards, gallery, settings and buttons stretch to 820 px | H | ✅ reading width 720 for text and settings, card grid of 2–3 columns up to 1180, gallery capped at 560 px tall |
| G6 | Choice chips show Material checkmarks in some places and not others | L | ✅ no checkmarks; selection shown by fill and border |
| G7 | Dialogs, switches and pull-to-refresh are Material-only; on iOS they should look native | M | ✅ adaptive dialogs (`confirmAction`), action sheets (`showActionSheet`), switches, refresh and spinners |
| G8 | No continuity between a listing card and its detail page (the photo jumps) | L | ⏸ A shared-element Hero needs a tag unique across all five tab stacks, which stay alive off-screen; the same listing appears in several of them at once, and duplicate tags assert. Worth doing with per-origin tags; not worth the risk in this pass |
| G9 | *Found while fixing.* Arrows and chevrons point backwards in Arabic: code swapped glyphs for RTL by hand, and Flutter's glyphs already mirror themselves, so they flipped twice (details back arrow, every list chevron, Home's search arrow, wizard Back) | H | ✅ hand swaps removed; confirmed pixel by pixel in the Arabic renders |

## Screens

| # | Screen | Finding | Sev | Status |
|---|---|---|---|---|
| O1 | Onboarding | Wordmark and language switch float mid-photo instead of the top (a stretched `Row` centres vertically) | H | ✅ |
| O2 | Onboarding | Dead gap between copy and controls; the photo could carry more of the screen | L | ✅ photo takes 54% (44% on short screens) |
| H1 | Home | Search field draws its shadow *inside* its fill, so the "white" field renders grey | M | ✅ |
| H2 | Home | Search hint truncates/wraps and competes with an inline "Search with AI" pill; tapping it opens AI Search without focusing the input | M | ✅ one-line prompt and a single arrow; AI Search opens with the keyboard up |
| H3 | Home | Type tiles truncate labels ("Apartm…") | M | ✅ label-sized pills |
| H4 | Home | City tiles cycle through off-palette blue, brown and mustard | M | ✅ one forest gradient, gold accent, Arabic-name watermark |
| H5 | Home | Large dead band between the header and the first section | L | ✅ |
| H6 | Home | Landscape: the hero fills the whole viewport | L | ✅ first section visible in landscape |
| E1 | Explore | Heavy header: small title, full-width Material segmented control, chips | M | ✅ large title, pill, one line of filter chips that shows only what is set; sort sheet marks the current choice |
| E2 | Explore | Tablet shows one 600 px-tall card per row | H | ✅ two columns at 600 px, three at 900 px |
| A1 | AI Search | Idle state is a five-line paragraph under an all-caps kicker | M | ✅ heading, two lines, three examples as a grouped list |
| A2 | AI Search | Live "we read" chips render at the top of the page, far from the field (hidden behind the keyboard) | M | ✅ directly above the field |
| A3 | AI Search | The brief (chips + clarification) fills the first screen; results start below the fold | H | ✅ one scrolling line of removable chips, one short "Sharpen it" line only when it helps; first result on the first screen |
| A4 | AI Search | "Not searched this time: Licensed partner feed" — internal wording shown above results | M | ✅ a quiet footnote after the results, in plain words |
| A5 | AI Search | Portal rows open with cryptic fractions ("0/1 · drops city…") | L | ✅ grouped rows: portal name, what its link drops, an "opens outside" mark |
| A6 | AI Search | Composer hint truncates over two lines | L | ✅ short hints; round send button |
| D1 | Details | Collapsed header keeps photo-style dark discs on a plain bar and shows no title | M | ✅ discs fade out, icons turn dark, the title appears, status-bar icons switch |
| D2 | Details | Call / WhatsApp / Send inquiry appear twice (contact card and sticky bar) | M | ✅ Call and Send inquiry in the bar; the card keeps the number, copy and WhatsApp |
| D3 | Details | Specs are a grid of bordered tiles — busy for six facts | L | ✅ grouped list, values on the trailing edge; amenities as a quiet two-column list |
| D4 | Details | "Search for similar" searches the listing's title text, which reads poorly as a query | M | ✅ searches the listing's facts (deal, area, type, bedrooms, ~15% price ceiling), each a removable chip |
| S1 | Saved | Opening Saved → Searches from Profile does not switch tabs once Saved has been visited | H | ✅ the link carries a token; covered by a widget test |
| S2 | Saved | "Search again" is a heavy filled button inside every card | L | ✅ the whole card runs the search; delete offers Undo |
| P1 | Profile | One flat list: account, preferences, support and destructive actions run together | M | ✅ account card, then four groups; language and appearance as full-width pills; native confirmations |
| DB1 | Dashboard | Four oversized stat tiles, shown even at all-zero for a new owner | M | ✅ one compact strip, hidden until there is a listing |
| DB2 | Dashboard | Each listing carries five action chips wrapping onto two lines | H | ✅ status, Edit, and a More button opening an action sheet; delete confirms |
| DB3 | Dashboard | FAB uses a pale container colour unlike every other primary action | L | ✅ forest pill, set in the theme |
| I1 | Inquiries | Reply actions wrap onto two lines | L | ✅ one row of equal reply actions under a hairline |
| W1 | Listing flow | Count fields typed as text; icons on some fields and not others | M | ✅ bedrooms and bathrooms are steppers (no keyboard; "not given" below zero); every single-line field has an icon; areas show m² |
| W2 | Listing flow | Review reads "0 Photos and video"; Back sits in the body while every other step uses the bottom bar | M | ✅ "No photos yet" (pluralised in both languages); Back in the bar on every step |
| AU1 | Auth | Google button uses a generic Material "G" glyph | M | ✅ Google's own mark |
| AU2 | Auth | Sign-up legal links are bare underlined words, not an agreement | L | ✅ one agreement sentence with both documents as links |

## Found while verifying the fixes

Re-rendering and the new widget tests turned up these; all fixed.

| # | Finding | Sev | How it showed up |
|---|---|---|---|
| V1 | Undo after removing a saved search used the removed card's `ref`, so it would have failed with a generic error | H | widget test |
| V2 | Two quick taps on a count stepper added one, not two (the second tap read a stale value) | M | widget test |
| V3 | The agreement sentence named Privacy before Terms in both languages: `gen-l10n` orders undeclared placeholders alphabetically. Every other multi-placeholder string was checked; only this one was affected | M | Arabic render |
| V4 | Profile's language row overflowed at phone width in Arabic | M | widget test |
| V5 | Material's large title left ~50 px more air above it than iOS; on tablets the Explore and Saved headers aligned to a different width than their cards | M | renders |
| V6 | "Create account" (guest card), "WhatsApp" (inquiry replies) and the area field labels truncated; the filters sheet clipped its first field's floating label | M | renders |

The render harness itself drew elevation as solid outlines (flutter_test's
default), which made the button look black-ringed; it now draws real shadows.

## Found on a device

Tested on an Android 16 emulator against live data (read-only), screen by
screen, in English and Arabic, light and dark. All fixed and re-checked on
the device.

| # | Finding | Sev |
|---|---|---|
| T1 | Status-bar icons stayed dark over the onboarding and Home photos, so the clock and battery were barely visible | M |
| T2 | Home has no bar: once scrolled, listings ran under a bare status bar | M |
| T3 | Large-title screens showed no edge when content slid under the pinned header | L |
| T4 | Owner text in Arabic (most titles and descriptions) was laid out left-to-right in the English interface: left-aligned, punctuation on the wrong side, ellipsis at the wrong end | M |
| T5 | Map price pins clipped their last character ("73.5" for 73.5K, "3.5" for 3.5M) | H |
| T6 | Around Amman, twenty pins overlapped into an unreadable stack | H |
| T7 | Map filter chip centred instead of on the start edge; the same in the list header | L |
| T8 | The tour pointed at Home's search while Home was scrolled away, leaving its card mostly off screen | M |
| T9 | Spotlights on tab-bar items were oversized circles that ran off the screen | L |
| T10 | In the dark theme the segmented control's selected segment was nearly invisible | M |
| T11 | The tour card changed height on its last step (no Skip) | L |

## New in this pass (requested)

- **Explore is a map**: every listing with a location, forest pins for sale,
  gold for rent, grey when closed; overlapping pins cluster and zoom in on
  tap; a pin opens a preview card; All / Buy / Rent and filters float on top;
  a button switches to the list of the same results. Maps no longer need a
  Google key (OpenStreetMap tiles via `flutter_map`), which also turned on the
  map preview on property pages and the pin drop in the listing form.
- **Guided tours**: finding a property (7 steps, after onboarding), the map
  (4 steps, first visit to Explore), listing a property (4 steps, first new
  listing). Each spotlights the real control, can be skipped, runs once, and
  replays from Profile → Guides.

## Phase 2 (requested): motion, AI search, voice

- **Motion** as listed in DESIGN_SYSTEM.md → Motion.
- **AI Search**: the assistant answers in a sentence; results reveal with a
  match ring and a heart; "Sharpen it" now also offers a budget and bedroom
  count when missing; when nothing matches it offers one-step-looser
  searches (whole city, a quarter more budget, any type, sale or rent, fewer
  features), each a real search — never invented results.
- **Understanding**: spoken numbers ("مية وخمسين ألف", "ربع مليون",
  "eighty thousand"), dialect ("اجار", "ما يتجاوز", "جنينة", "شوفاج",
  "unfurnished"), "about 500 m" as a near size, more place spellings, mixed
  Arabic-English.
- **Voice**: on Home and in AI Search; the mic sits where send is until
  something is typed.

Found and fixed while testing this phase:

| # | Finding | Sev |
|---|---|---|
| P1 | First voice level would have crashed the voice sheet (fixed-length history) | H |
| P2 | Enter in the AI field added a new line instead of searching (multi-line keyboard) | M |
| P3 | A listing row with a non-text value in a text column made the whole map fail ("Something went wrong"); rows now read tolerantly and an unreadable one is skipped, not fatal | H |
| P4 | "Nothing matches" was said twice; the looser budget showed odd figures (113K) | L |

## Redesign to the chosen reference

The owner asked for the look of a specific real-estate concept on Dribbble.
Applied across the app, keeping the brand green as the dark accent:

- **Tab bar** floats as a white pill; the chosen tab is a green pill with its
  name; signed out, a green **Log in** button takes Profile's place.
- **Home**: location selector and account button on top, a bold title, a grey
  search pill with the microphone and a dark filter button (it opens Explore's
  filters), Buy/Rent, category chips with icon wells, then listings.
- **Cards**: grey card with the photo inset, white pills on the photo, a white
  panel with title, place, counts and price.
- **Listing page**: rounded photo header with white square buttons, soft
  badges, facility tiles, the owner card with round chat and call buttons, and
  a sticky bar with the price and one action.
- **Map**: the same floating controls — Buy/Rent beside a dark filter button
  with a count, white legend pills, cards with inset photos.
- **Everywhere**: grouped lists and cards are soft grey fills, not outlines.

Found while redesigning, fixed:

| # | Finding | Sev |
|---|---|---|
| R1 | Sign-up gave no confirmation: with email confirmation off (as in production) the app moved to Profile silently; with it on, the note sat above the fold | H |
| R2 | The "Inquiries" title sat further in than every other title (Material's large title shifts with a back button); large titles are now drawn by the app | M |
| R3 | The floating bar overflowed on 360 px phones and cut the chosen tab's name when signed out | M |
| R4 | Carousel cards stretched to the row height, leaving a grey band | L |
| R5 | Launch screen background (ivory) no longer matched the white app | L |

Found on the device after the redesign (release build, signed in as the owner's
test account and signed out; nothing published, saved to the account or sent):

| # | Finding | Sev |
|---|---|---|
| R6 | **Signing in from the green Log in button showed the check, then left the sign-in page open.** Every entry point pushes the auth page, and the router's redirect does not re-route a pushed page, so it lingered (sign-up too: the likely cause of "no success message"). Both pages now close themselves: back to where the reader was, or on to where they were headed | H |
| R7 | The cards under the map began with a listing that has no pin, so the first card matched nothing on the map. Cards now follow the pins, then the listings without a location | M |
| R8 | Signed out, the chosen tab's name was cut ("AI Sear…") beside Log in. The bar now measures: the whole name when it fits, otherwise the icon alone in its dark pill (still read out); slightly tighter spacing fits every name at 390 px and short ones at 360 px | M |
| R9 | "For rent · Not on the m…" cut off on map cards; the note now has its own line with an icon | L |
| R10 | The tour's last step said "From Profile…" while pointing at the Log in button; guests now get their own wording | L |
| R11 | The listing page's heart was a circle beside square back/share buttons | L |
| R12 | The listing form and secondary buttons (Back, Add photos, Save as draft, Google) still had outlines; now soft grey fills like the rest of the app | L |

## Second pass against the reference

The owner said the app still did not look like the reference, the listing page
("property viewer") above all. Compared screen by screen with the shot and
brought into line:

- **Listing page**: the photo is an inset card with rounded corners, white
  square buttons, and white pills along its bottom edge: which photo of how
  many, the number of clips, and **Map** (scrolls to the location). Under it,
  the kind of place and the deal as grey pills on either side, a larger title,
  the place, **Facilities** with "See all" (three tiles across, as in the
  reference; the rest are under Property details and Features), the
  description cut at three lines with an inline **Read more**, then the owner
  card (round avatar, name with a verified tick, round chat and call buttons),
  moved up from the bottom. The bar is the price, large, and one dark button.
  Amenities are grey pills; the listing date moved into Property details.
  The reference shows likes and views on the photo; those columns exist but
  nothing ever counts them (all zero), so the pills show real facts instead.
- **Photo viewer** (the reference's "virtual tour"): the photo full screen over
  a soft wash of its own colours (no black bars), a square back button and the
  title on top, and a white sheet with every photo as a tile; tapping a tile
  jumps to it, and the strip follows as you swipe.
- **Home**: no big title; location, then search with the filter button, then
  one row of grey pills starting with Buy/Rent, then the large cards and, as in
  the reference, **More to explore**: smaller cards two to a line. "See all" is
  grey, section titles larger.
- **Cards**: the deal as a grey pill beside the title (where the reference has
  its rating), larger price, saved hearts filled dark rather than red, a
  loading placeholder in the card's own shape.
- **Tab bar**: dark icons on a near-white pane, as in the reference.

Found while doing it:

| # | Finding | Sev |
|---|---|---|
| R13 | The new photo viewer first drew its tile sheet at the top and no photo: the stack took its size from the top bar, its only unplaced layer. Caught on the device; fixed, and `media_viewer_test.dart` now checks the layout | H |
| R14 | Facility labels broke mid-word ("4 bathroo / ms") when a fourth tile squeezed the row; now three across with a label size that fits | M |
| R15 | A real frosted blur behind the tab bar (as in the reference) cost about 8 points of slow frames while scrolling Home on the emulator; replaced by a near-opaque pane that looks the same | M |

## Third pass: animations

Checked on the device with frame timing and with frame-by-frame screen
recordings, plus a code review of every animation.

- **Reduced motion**: every looping or entrance animation (launch reveal,
  section reveals, skeleton shimmer, AI thinking mark, voice orb, tours, map
  pins, tab fade) stops or is skipped when the phone asks for less motion.
- **Transitions measured** (slow frames): opening a listing and going back
  7 %, opening and closing the photo viewer 9 %, scrolling 2–3 %.

| # | Finding | Sev |
|---|---|---|
| A1 | **The first time a listing opened, the photo flew in as a blank grey placeholder**: the flight used the gallery's own copy, decoded at a different size and not loaded yet. It looked fine only for listings opened before. Now the card's photo (already on screen) makes the flight, rounding from the card's corners to the gallery's, and the gallery shows any copy already in memory while its sharper one loads | H |
| A2 | The flying photo had square corners and snapped round on landing | M |
| A3 | Switching tabs faded two full screens at once (out and in); now only the incoming tab fades over the outgoing one, which halves the work. Slow frames per switch went from 22 % to 0–19 % (the first frame of a tab shown again still costs one or two frames on the emulator) | M |
| A4 | Photos were decoded by the frame's width only, so wide photos cropped to fill a tall frame were stretched (2× on the listing page). Decoding now accounts for the frame's height. Some listing photos remain soft because the stored file is small (1600 × 720 at 71 KB): that is the upload, not the app | M |

## Speed

Measured on the Android emulator from SurfaceFlinger's present times (release
build, 60 Hz, images warm). An emulator is not a phone, so treat these as
relative, not as what a customer's phone will show.

| | Median frame | 90th pct | Frames over 25 ms |
|---|---|---|---|
| Home, scrolling (second pass, with the grid of smaller cards) | 16.7 ms | 19.3–19.5 ms | 1.6–3.2 % |
| Listing page, scrolling | 16.8–16.9 ms | 18.5–19.3 ms | 1.6–3.2 % |
| Photo viewer, swiping | 17.1 ms | 19.0 ms | 0.8 % |
| Map, panning (first pass) | 16.6 ms | 20.7 ms | 5 % |
| Map cards, swiping (first pass; map flies to each pin, new tiles load) | 17.3 ms | 29.7 ms | 16 % |

The first pass measured Home at 3–5 %. Numbers drift as an emulator runs for
hours (a control screen went from about 2 % to 9–10 %), so each comparison
above was made on a freshly booted emulator.

Cold start: 1.1–2.8 s (the first launch after installing is slower while
Android compiles the app). Blurred shadows that were redrawn on every frame
(photo pills, the heart on cards, map pins, the tab bar) were removed or
lightened; photos were already decoded at their displayed size.

An earlier run had looked much worse (median 27–36 ms, even on the plain
Profile list); that emulator had 2 GB of RAM and was swapping. With 4 GB the
same build ran at the numbers above.

## Interactions verified

Widget tests (`test/widget/`), all passing:

- Favourites with rollback; filter sheet round trip; wizard step validation and
  Arabic numerals; inquiry validation and delivery; sold listings refusing
  inquiries; language switch keeping the session; AI search live preview,
  refine, chip removal, rate limit.
- New in this pass (`design_flows_test.dart`): Saved tab links switch tabs every
  time (S1); saved-search delete and Undo (V1); dashboard actions behind More,
  and delete asking first (DB2); no all-zero stats for a new owner (DB1);
  count steppers including "not given" and rapid taps (W1, V2); review step's
  bar and media wording (W2); "Search for similar" sending the listing's facts
  (D4); Call and inquiry appearing once (D2).

Not verified here: the screens on physical iOS and Android devices (no device
or simulator was run in this pass), VoiceOver/TalkBack walkthroughs, and the
website, which was out of scope.
