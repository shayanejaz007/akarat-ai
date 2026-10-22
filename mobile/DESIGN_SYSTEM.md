# Design system

All values live in `lib/app/theme/tokens.dart` and `app_theme.dart`. Screens
read tokens (`context.colors`, `Space`, `Radii`, `Motion`, `Shadows`) rather
than writing raw values.

## Visual language

Clean white pages, soft grey fills instead of outlines, generous rounding,
and the brand's deep forest green as the one dark accent (primary buttons, the
selected tab, the filter button). Modelled on the reference the owner chose
(a Dribbble real-estate concept): rounded-square icon buttons, white pills over
photos, cards that hold their photo inset, square facility tiles, and a sticky
price-and-action bar on listings.

## Colour

| Token | Light | Dark | Use |
|---|---|---|---|
| `forest` | `#123C34` | `#8FD3BF` | primary: headers, selected tab, primary buttons, prices |
| `emerald` | `#16836D` | `#3DB394` | action and positive states, focus rings, progress |
| `background` | `#FFFFFF` | `#0B0B0B` | screen background |
| `surface` | `#FFFFFF` | `#141414` | cards, sheets, bars |
| `surfaceMuted` | `#F4F5F3` | `#1C1C1C` | the soft grey fill: cards, grouped lists, fields, chips |
| `ink` | `#192421` | `#EDEDED` | primary text |
| `inkMuted` | `#5F6C67` | `#A6A6A6` | secondary text (darker than the brief's `#73807B` to keep 4.5:1 on ivory) |
| `inkFaint` | `#9AA49F` | `#6B6B6B` | placeholders, disabled icons — not for body text |
| `surfaceRaised` | `#FFFFFF` | `#1F1F1F` | what floats, in dark: the tab bar and tour cards (also Material's highest container) |
| `border` | `#E9EAE6` | `#262626` | hairlines (rarely; fills do the separating) |
| `sand` | `#DDD0B8` | `#332E26` | warm accents, empty-state discs, the list-your-property card |
| `gold` | `#B0832B` | `#D9B25E` | the brand mark's gold; owner banners, AI tab tint. Never body text |
| `red` | `#CE1126` | `#FF5A6A` | Jordan's flag red, sparingly: saved heart, SOLD/RENTED, destructive |

Dark mode is matte black: neutral, untinted greys a step apart from the
brand's `#0B0B0B` (the splash kit's black), separated by hairlines rather
than shadows, with the same green and gold as accents. Google's map has a
matching neutral dark style.

The brand mark (gold and charcoal on `#17170F`) is used as-is on the icon,
launch screens and headers; the forest palette sits around it.

## Type

One system in `lib/app/theme/typography.dart`; screens use roles, never their
own sizes or weights.

**Faces** (all SIL OFL, bundled in `assets/fonts`, listed under Profile →
Open-source licences):

- **Inter** for Latin, the closest openly licensed relative of Apple's San
  Francisco, in two optical sizes as SF has: *Inter* (text) below 20 px and
  *Inter Display* (finer, tighter) from 20 px up. Subset to Latin, ~103 KB a
  weight.
- **IBM Plex Sans Arabic** for Arabic (the website's Arabic face).
- **Poppins SemiBold** only for the "Akarat.ai" wordmark, which is part of
  the logo.

**Scale** (iOS sizes mapped onto Material roles):

| Role | Size / weight | Use |
|---|---|---|
| `headlineMedium` | 32 / 600, Display | a screen's large title |
| `headlineLarge` | 26 / 600, Display | a listing's own title |
| `headlineSmall` | 21 / 600, Display | every section title |
| `titleLarge` | 19 / 600 | dialog titles, folded bar titles |
| `titleMedium` | 17 / 600 | card titles, list headlines |
| `titleSmall` | 15 / 600 | small card titles |
| `bodyLarge` | 16 / 400 | reading text |
| `bodyMedium` | 15 / 400 | default text |
| `bodySmall` | 13 / 400, muted | secondary lines |
| `labelLarge` | 15 / 600 | buttons, tabs |
| `labelMedium` / `labelSmall` | 13 / 500, 11.5 / 500 | captions |
| `context.type.priceLarge` / `price` / `priceSmall` | 26 / 20 / 16, 700, tabular figures | listing page / cards / rows, small cards, results |
| `context.type.figure` | 19 / 600, tabular | dashboard counts |
| `context.type.pill` / `badge` | 13 / 600, 11.5 / 600 | pills and tags / badges on photos |

Weights stay light-handed: 600 for titles and labels, 700 only for prices.

**Tracking** (letter-spacing): Inter's own size curve: slightly open at caption
sizes, tighter as text grows (−0.2 px at 17, −0.6 px at 32), half that for the
display cut. **Never on Arabic**: letter-spacing breaks its joins.

**Line height**: tight for UI text (1.15 at large titles to 1.33 at small
titles), generous for reading (1.47–1.5). Arabic gets more in every role (1.4
at large titles, 1.7–1.75 for paragraphs) for its marks and dots.

**Mixed scripts**: an owner's Arabic title or description in the English app
is set in the Arabic face with no tracking, and English text in the Arabic
app in Inter (`styleForScript`, applied by `UserText`). Paragraphs also take
that script's line height; single lines keep theirs so cards keep their size.

**Text size**: honoured from 0.85× to 1.6×. Renders at 1.6× (listing page,
Explore list, Home, sign-in) and on a 360 px phone at 1.3× are part of the
visual audit; nothing may clip or overflow (widget tests fail on overflow).

## Space, shape, motion

Spacing: a 4-point scale (`Space.xxs` 4 … `xxxl` 48) plus two named
micro-gaps, `Space.hair` (2, between two lines that belong together) and
`Space.iconGap` (6, between an icon and its label). No bare numbers.

- Spacing on a 4-pt scale: 4, 8, 12, 16, 20, 24, 32, 48. Screen gutter 20.
- Radii: 8, 12, 16 (icon wells, square buttons), 18 (fields, buttons), 24 (cards), 30 (outer cards, sheets), pill.
- Elevation is mostly borders; one soft shadow (`Shadows.card`) for floating
  elements such as the home search entry.
- Motion: 150 / 260 / 420 ms, `easeOutCubic`. `Motion.of(context, d)` returns
  zero when the system asks to reduce motion; skeleton shimmer stops too.
- Haptics: selection click on tab change and choices, light impact on save,
  medium on publish, heavy on a blocked step.
- Width (`core/widgets/layout.dart`): text, forms and settings never run wider
  than 720 (`Layout.reading`); card lists become 2 columns at 600 px and 3 at
  900 px, up to 1180 (`Layout.grid`). A page's title starts where its content
  starts, on phones and tablets alike.

## Motion

- Listing photos fly from the card into the property page, and from the
  gallery into the full-screen viewer (Explore list and map cards, Home,
  Saved, similar listings, AI results). Tags are unique per place, so a
  listing shown twice never clashes.
- Tabs cross-fade (180 ms); lists and AI results fade up with a short stagger
  the first time they appear; map pins pop from their point; the AI progress
  line follows the real stages; success confirmations draw a check.
- A brief brand reveal hands over from the native launch screen. It never
  waits for anything: the app loads underneath it.
- Everything above respects the system's reduce-motion setting.

## Platform conventions

One design, native behaviour: confirmations are Cupertino alerts on iOS and
Material dialogs elsewhere (`confirmAction`); "more" menus are action sheets on
iOS and bottom sheets elsewhere (`showActionSheet`); switches, pull-to-refresh
and standalone spinners use the `.adaptive` constructors. Page transitions
follow the platform.

## Components

| Component | File | Notes |
|---|---|---|
| Tab bar | `app/router/scaffold_with_nav.dart` | floats over content as a near-white pill with dark icons (no live blur: it costs frames while scrolling); the chosen tab is a forest pill whose name slides out; others are icons; signed out, Profile's place is a green **Log in** pill; the chosen name shows only when it fits whole (else the icon alone, still read out); steps aside when the keyboard is up; screens keep clear of it through the bottom padding it reports |
| Buttons | `app/theme/app_theme.dart` | primary: forest fill; secondary (`OutlinedButton`): soft grey fill, no outline — on a grey card, give it the page colour; text buttons in emerald |
| Square icon button | `core/widgets/surfaces.dart` | rounded square: soft grey on pages, white with a shadow over photos, forest for the primary (filters); optional count badge |
| Info pill / spec pill / facility tile | same | white pills over photos (type, verified, photo count); outlined counts on cards; grey tiles, three across, for bedrooms, bathrooms and size |
| Listing page | `features/property_details/property_details_screen.dart` | inset rounded photo with square buttons and fact pills (photo position, clips, Map); type and deal pills; Facilities with See all; description with inline Read more; owner card with round chat/call; price bar with one dark button |
| Photo viewer | `features/property_details/media_viewer.dart` | photo full screen over a wash of its own colours; square back button and title; white sheet of photo tiles that jump and follow |
| Large title bar | `core/widgets/layout.dart` (`LargeTitleBar`) | every list root; big title on the content's start inset that folds into the bar; optional pinned `bottom` (segmented pill, filter line) |
| Segmented pill | `core/widgets/segmented_pill.dart` | the only "pick one of a few" control: quiet track, white thumb that slides; full width on phones, label-sized on tablets; `onDark` variant over photos |
| Grouped section / tile | `core/widgets/layout.dart` | iOS-style grouped rows on one rounded surface, hairlines inset past the icon; tile has title, optional subtitle, trailing value (end-aligned) or control, chevron when it navigates, destructive variant |
| Card list | same (`SliverCardList`) | 1/2/3 columns by window width; rows take their tallest card's height |
| Section header | `core/widgets/buttons.dart` | title with a baseline-aligned text action |
| Confirm / action sheet | `core/widgets/layout.dart` | `confirmAction` (optional typed confirmation, destructive styling) and `showActionSheet` |
| Map | `core/widgets/maps.dart`, `google_map_views.dart`, `map_pin_images.dart` | Google's map when keyed (Map / Satellite switch beside Explore's filters and on each listing's map and the pin picker; remembered), OpenStreetMap tiles otherwise. Same pins on both: price pins (forest = sale, gold = rent, grey = sold/rented) with a pointer on the point, drawn as images on Google's map; overlapping pins become numbered bubbles that zoom in on tap (gold ring when sale and rent mix); approximate locations get a 300 m circle; a dark style for the dark theme; Google's logo and attribution kept clear of the cards. Street View (Google Maps app) at exact pins |
| Phone sign-in | `features/authentication/presentation/phone_auth_screen.dart`, `phone_fields.dart` | two steps on the auth frame: a number (country button with flag and dialling code, then the number, left to right in both languages; the expected length shown under it before anything is refused), then the code (large, spaced, filled from the message where the keyboard offers it, checked at the sixth digit; "Sent to" the number with Change number; another code after a minute). Sign-in, sign-up (with a name and the terms) and adding a number from Profile share it. Offered under Google on sign-in and under the form on sign-up, only when the project has it switched on |
| Opening (splash) | `app/launch_splash.dart`, `core/widgets/akarat_logo_animated.dart`, `android/.../IntroPlayer.kt` | the launch screen (the logo on black) hands over to the first frame unseen; then the Akarat.ai intro video (the splash kit's Higgsfield reveal, take A, whole, fitted to the screen) plays once, muted, never interrupting the reader's audio, and fades (with a slight push) into the app. The app starts its work once the intro is playing and is put on screen behind it only once the reveal has settled, so the intro never stutters. On Android the clip is prepared natively as the engine starts. Tap or Skip ends it early. A clip that cannot play at once is replaced by the coded build of the same logo; one that is merely slow leaves the logo with a gold loading line until the app is ready. Reduced motion or a screen reader: the still logo, about a second. Launch images: `tool/make_launch_images.py` |
| Guided tour | `core/widgets/coach_marks.dart`, `features/tour/tour.dart`, `features/tour/tour_store.dart` | spotlight on the real control with two soft pulses as each step appears (none with reduced motion); a card with step count and Back / Next / Skip (the system back gesture skips too). The card stays inside the safe area, under, over or beside the control (the reading end first in Arabic), follows it through rotation and resizing, and scrolls its words when there is no room, so the buttons always show. Steps whose control is not on screen are left out. Four tours: finding (first Home visit; after sign-up a new account's welcome, by first name, shortened to what an account adds if the phone already showed the tour), the map, the listing form, a listing page (photos, saving, contacting the owner). The step reached is kept on the phone, so a tour cut short picks up where it was; finished or skipped tours are kept on the phone and in the account (`tours_done`, `tour_pending` in the user's auth metadata, read by nothing else), so they are not repeated after a reinstall, on another phone or after signing in again, and accounts that existed before are never treated as new. Replay from Profile → Guides |
| Voice search | `features/ai_search/voice/` | a sheet with a breathing orb that swells with the voice, a waveform from real input levels, live transcript, then review-and-edit with the parsed brief as chips; clear states for permission refused, unavailable, no Arabic recogniser, nothing heard |
| Motion kit | `core/widgets/motion.dart` | `Reveal` (fade-and-lift once, short stagger, off with reduced motion), `showSuccess` (a check that draws itself; never blocks a touch) |
| Owner-written text | `core/widgets/user_text.dart` | titles, descriptions and inquiries take their direction and alignment from their own first letter, as native text views do |
| Property card | `shared/widgets/property_card.dart` | grey card holding the photo inset (type pill, white heart, verified and photo-count pills only when true), then a white panel: title with a grey sale/rent pill, place, and bed/bath (or size) pills beside a large price |
| Compact card | same (`PropertyCardCompact`) | Home's "More to explore", two to a line: inset photo with type pill and heart, then title, place, price |
| Property row | same | dense list row for the dashboard, inside a grouped section; status, Edit and a More button underneath |
| Tag chip | `core/widgets/buttons.dart` | constraints and filters; optional remove with its own semantics label |
| Busy button | same | owns its spinner; ignores taps while running (no double submit) |
| Empty / error states | `core/widgets/state_views.dart` | honest copy, one next step, no invented content |
| Notice line | same | inline caveats: approximate location, device-only saves, served-directly |
| Skeletons | `core/widgets/skeleton.dart` | match the real card's proportions |
| Listing image | `core/widgets/listing_image.dart` | disk cache, decoded at displayed size, greyscale for closed listings |

## RTL

Layout uses `EdgeInsetsDirectional`, `AlignmentDirectional` and
`PositionedDirectional` throughout. Use `arrow_back`, `arrow_forward`,
`chevron_right` and `send` as they are: Flutter mirrors these glyphs in Arabic
by itself, so choosing a glyph by text direction flips them twice and points
them backwards (this happened, and was fixed — see DESIGN_AUDIT.md G9). Phone
numbers, coordinates and Latin titles are forced LTR inside Arabic text;
Arabic examples and conversation bubbles pick their own direction from their
script. Arabic is not translated English: copy was written for Jordanian
readers, with Arabic plural forms (zero/one/two/few/many/other).

## Icons and launch

Launcher icons and the Android adaptive icon (with monochrome layer) are
generated from `assets/akarat-mark.png` by `tool/gen_native_assets.py`. The
launch screens (Android before 12, the Android 12+ splash icon, the iOS
launch image) show the opening's first frame: the coded logo on black, cut by
`tool/make_launch_images.py` from `test/visual/launch_logo_test.dart`'s
render, so the hand-over to Flutter cannot be seen.
