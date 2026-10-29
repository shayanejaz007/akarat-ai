// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Akarat.ai';

  @override
  String get brandTagline => 'Property search across Jordan';

  @override
  String get tabHome => 'Home';

  @override
  String get tabExplore => 'Explore';

  @override
  String get tabAiSearch => 'AI Search';

  @override
  String get tabSaved => 'Saved';

  @override
  String get tabProfile => 'Profile';

  @override
  String get actionRetry => 'Try again';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionSave => 'Save';

  @override
  String get actionDone => 'Done';

  @override
  String get actionContinue => 'Continue';

  @override
  String get actionBack => 'Back';

  @override
  String get actionClose => 'Close';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionEdit => 'Edit';

  @override
  String get actionShare => 'Share';

  @override
  String get actionClear => 'Clear';

  @override
  String get actionApply => 'Apply';

  @override
  String get actionSeeAll => 'See all';

  @override
  String get tourWelcomeTitle => 'Welcome to Akarat.ai';

  @override
  String tourWelcomeTitleName(String name) {
    return 'Welcome, $name';
  }

  @override
  String get tourWelcomeBody =>
      'Your account is ready. Here\'s a one-minute look at finding, saving and listing properties.';

  @override
  String get tourWelcomeAccountBody => 'Your account is ready. Here\'s where to find what it adds.';

  @override
  String get tourPhotosTitle => 'Every photo';

  @override
  String get tourPhotosBody =>
      'Tap the photo or this pill to see them all full screen. Map shows where the property is.';

  @override
  String get tourSaveTitle => 'Save it for later';

  @override
  String get tourSaveBody => 'Tap the heart to keep this property in Saved, ready to come back to.';

  @override
  String get tourContactTitle => 'Contact the owner';

  @override
  String get tourContactBody =>
      'Send an inquiry straight to the owner\'s dashboard. Chat and call are on the owner\'s card further down.';

  @override
  String get guideProperty => 'Viewing a property';

  @override
  String get guidePropertyNone => 'There are no listings to show the guide on yet.';

  @override
  String get settingsLicences => 'Open-source licences';

  @override
  String get mapViewSatellite => 'Satellite';

  @override
  String get mapViewMap => 'Map';

  @override
  String get a11yMapViewSatellite => 'Switch to satellite view';

  @override
  String get a11yMapViewMap => 'Switch to map view';

  @override
  String get detailsStreetView => 'Street View';

  @override
  String get tourMapLayerTitle => 'See it from above';

  @override
  String get tourMapLayerBody =>
      'Switch between the map and satellite view to see the buildings and streets around a property.';

  @override
  String get detailsMapPill => 'Map';

  @override
  String get specListed => 'Listed';

  @override
  String get specUpdated => 'Updated';

  @override
  String get viewerPhotos => 'Photos';

  @override
  String get homeMore => 'More to explore';

  @override
  String get actionSignIn => 'Sign in';

  @override
  String get actionSignOut => 'Sign out';

  @override
  String get actionNext => 'Next';

  @override
  String get actionSkip => 'Skip';

  @override
  String get actionGetStarted => 'Get started';

  @override
  String get actionMore => 'More';

  @override
  String previewMediaCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos and videos',
      one: '1 photo or video',
      zero: 'No photos yet',
    );
    return '$_temp0';
  }

  @override
  String get a11yDecrease => 'Decrease';

  @override
  String get a11yIncrease => 'Increase';

  @override
  String tourStepOf(int current, int total) {
    return '$current of $total';
  }

  @override
  String get tourSkip => 'Skip tour';

  @override
  String get tourDone => 'Got it';

  @override
  String get tourSearchTitle => 'Just describe it';

  @override
  String get tourSearchBody =>
      'Type what you’re after in English or Arabic, like “3 bedrooms in Abdoun under 150k”, or tap the microphone and say it. AI Search finds it and shows why each result fits.';

  @override
  String get tourDealTitle => 'Buying or renting?';

  @override
  String get tourDealBody => 'Switch here, and everything on Home follows.';

  @override
  String get tourCityTitle => 'Pick a city';

  @override
  String get tourCityBody => 'Focus on one city, or keep all of Jordan.';

  @override
  String get tourExploreTitle => 'See it on a map';

  @override
  String get tourExploreBody =>
      'Explore shows every property on a map — green for sale, gold for rent — with filters and a list view.';

  @override
  String get tourAiTitle => 'Ask for it';

  @override
  String get tourAiBody => 'Refine a search in plain words, save it, and come back to it any time.';

  @override
  String get tourSavedTitle => 'Keep the ones you like';

  @override
  String get tourSavedBody => 'Tap the heart on any property. It waits for you in Saved, next to your saved searches.';

  @override
  String get tourProfileTitle => 'List your own property';

  @override
  String get tourProfileBody =>
      'From Profile, list a property in a few guided steps, then answer inquiries from buyers and tenants.';

  @override
  String get tourProfileGuestBody =>
      'Log in here to list a property in a few guided steps, then answer inquiries from buyers and tenants.';

  @override
  String get tourMapDealTitle => 'All, sale or rent';

  @override
  String get tourMapDealBody => 'Choose what the map shows.';

  @override
  String get tourMapPinsTitle => 'Read the pins';

  @override
  String get tourMapPinsBody =>
      'Each pin shows the price. Green is for sale, gold is for rent; a number groups pins that are close together, so tap it to zoom in. A shaded circle means the owner shared an approximate location. Tap a pin to preview the property.';

  @override
  String get tourMapFiltersTitle => 'Narrow it down';

  @override
  String get tourMapFiltersBody => 'Filter by city, type, rooms, price and size.';

  @override
  String get tourMapToggleTitle => 'Prefer a list?';

  @override
  String get tourMapToggleBody => 'Switch between the map and a list of the same results.';

  @override
  String get tourStepsTitle => 'Nine short steps';

  @override
  String get tourStepsBody => 'Your progress is kept on this phone as you go, so you can stop and come back.';

  @override
  String get tourOneThingTitle => 'One thing at a time';

  @override
  String get tourOneThingBody =>
      'Only the city, the price and a title are required. Photos, a map pin and details make your listing stronger.';

  @override
  String get tourNextTitle => 'Move on';

  @override
  String get tourNextBody => 'Next checks this step. At the end you review everything, then publish or save a draft.';

  @override
  String get tourCloseTitle => 'Leave any time';

  @override
  String get tourCloseBody => 'Closing keeps your draft. Published listings appear in the app and on akarat.ai.';

  @override
  String get guidesSection => 'Guides';

  @override
  String get guideFinding => 'Finding a property';

  @override
  String get guideMap => 'Using the map';

  @override
  String get guideListing => 'Listing a property';

  @override
  String get mapAll => 'All';

  @override
  String mapCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count on the map',
      one: '1 on the map',
      zero: 'None on the map',
    );
    return '$_temp0';
  }

  @override
  String mapCluster(int count) {
    return '$count properties here. Tap to zoom in.';
  }

  @override
  String get mapNoLocation => 'Not on the map';

  @override
  String get a11yVoice => 'Search by voice';

  @override
  String get voiceListening => 'Listening…';

  @override
  String get voiceStarting => 'Getting the microphone ready…';

  @override
  String get voiceHint => 'Say what you’re looking for, like “three bedrooms in Abdoun under 150 thousand”.';

  @override
  String get voiceReviewTitle => 'Is this right?';

  @override
  String get voiceReviewBody => 'Edit anything before searching.';

  @override
  String get voiceUnderstood => 'Understood';

  @override
  String get voiceSearch => 'Search';

  @override
  String get voiceRetry => 'Speak again';

  @override
  String get voiceStop => 'Done';

  @override
  String get voiceTypeInstead => 'Type instead';

  @override
  String get voiceDenied =>
      'Microphone access is off. Allow it for Akarat.ai in your phone’s settings to search by voice.';

  @override
  String get voiceUnavailable => 'Voice search isn’t available on this device. You can type your search instead.';

  @override
  String get voiceNoArabic =>
      'This device can’t recognise speech in this language yet. Try the other language, or type instead.';

  @override
  String get voiceNoSpeech => 'I didn’t catch that.';

  @override
  String get voiceNetwork => 'Voice recognition needs a connection right now.';

  @override
  String get voiceOther => 'Voice search stopped unexpectedly.';

  @override
  String get aiSpeakTitle => 'Just say it';

  @override
  String get aiSpeakBody => 'Tap to search by voice, in English or Arabic.';

  @override
  String aiUnder(Object amount) {
    return 'Under $amount';
  }

  @override
  String aiUpTo(Object amount) {
    return 'Up to $amount';
  }

  @override
  String aiBedsPlus(int count) {
    return '$count+ beds';
  }

  @override
  String get aiTryInstead => 'Try instead';

  @override
  String aiAllOfCity(Object city) {
    return 'All of $city';
  }

  @override
  String get aiAnyType => 'Any type';

  @override
  String get aiBothDeals => 'Sale or rent';

  @override
  String get aiFewerFeatures => 'Fewer features';

  @override
  String aiFoundSummary(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'I found $count matches on Akarat.ai, closest first.',
      one: 'I found 1 match on Akarat.ai.',
      zero: 'Nothing on Akarat.ai matches all of that yet.',
    );
    return '$_temp0';
  }

  @override
  String get authAccountCreated => 'Account created';

  @override
  String authAccountCreatedName(Object name) {
    return 'Welcome, $name. Your account is ready.';
  }

  @override
  String get authWelcomeBack => 'Signed in';

  @override
  String get authCheckEmailTitle => 'Check your email';

  @override
  String authCheckEmailBody(Object email) {
    return 'Your account is created. We sent a confirmation link to $email. Open it to confirm your address, then sign in here.';
  }

  @override
  String get authCheckEmailSignIn => 'I’ve confirmed — sign in';

  @override
  String get authCheckEmailWrong => 'Wrong address? Go back';

  @override
  String get homeLocation => 'Location';

  @override
  String get detailsFacilities => 'Facilities';

  @override
  String get navLogIn => 'Log in';

  @override
  String get actionUndo => 'Undo';

  @override
  String get errorGeneric => 'Something went wrong. Please try again.';

  @override
  String get errorNetwork => 'You appear to be offline. Check your connection and try again.';

  @override
  String get errorTimeout => 'The server took too long to answer. Try again.';

  @override
  String get errorNotFound => 'We couldn\'t find that.';

  @override
  String get errorRateLimited => 'Too many searches. Try again shortly.';

  @override
  String get errorPermission => 'You don\'t have permission to do that.';

  @override
  String get errorSessionExpired => 'Your session has expired. Sign in again.';

  @override
  String get offlineBanner => 'You\'re offline. Showing what was already loaded.';

  @override
  String get notProvided => 'Not provided';

  @override
  String get routeNotFound => 'This page doesn\'t exist.';

  @override
  String get onboardingTitle1 => 'Property across Jordan, in one place';

  @override
  String get onboardingBody1 =>
      'Apartments in Abdoun, land in Madaba, chalets at the Dead Sea. Every listing here traces to a real record.';

  @override
  String get onboardingTitle2 => 'Search the way you speak';

  @override
  String get onboardingBody2 =>
      'Write it in English or Arabic, the way you\'d say it. We read the budget, the area and the bedrooms, and show you why each result fits.';

  @override
  String get onboardingTitle3 => 'Buy, rent, or list your own';

  @override
  String get onboardingBody3 =>
      'Save the places you like, send inquiries straight to owners, and publish a property in a few guided steps.';

  @override
  String get onboardingLanguage => 'Language';

  @override
  String get homeGreeting => 'Find your place in Jordan';

  @override
  String get homeSubtitle => 'Search the usual way, or just say what you\'re looking for.';

  @override
  String get homeSearchHint => 'A four-bedroom villa in Abdoun with a garden';

  @override
  String get homeSearchPrompt => 'Search or describe it…';

  @override
  String get homeAiCta => 'Search with AI';

  @override
  String get homeFeatured => 'Featured';

  @override
  String get homeRecent => 'Recently listed';

  @override
  String get homeCategories => 'Browse by type';

  @override
  String get homeCities => 'Explore by city';

  @override
  String get homeListCtaTitle => 'Own a property?';

  @override
  String get homeListCtaBody =>
      'List it in a few guided steps. Your inquiries and listings sit in one dashboard, on the app and the website.';

  @override
  String get homeListCtaButton => 'List your property';

  @override
  String get homeEmptyTitle => 'The marketplace is opening';

  @override
  String get homeEmptyBody =>
      'No listings match here yet. Nothing is invented to fill the space — check back soon, or be the first to list.';

  @override
  String get locationAllJordan => 'All of Jordan';

  @override
  String get locationPickerTitle => 'Choose a city';

  @override
  String get dealSale => 'Buy';

  @override
  String get dealRent => 'Rent';

  @override
  String get exploreTitle => 'Explore';

  @override
  String exploreResultsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count properties',
      one: '1 property',
      zero: 'No properties',
    );
    return '$_temp0';
  }

  @override
  String get exploreFilters => 'Filters';

  @override
  String get exploreSort => 'Sort';

  @override
  String get sortNewest => 'Newest';

  @override
  String get sortPriceLow => 'Price: low to high';

  @override
  String get sortPriceHigh => 'Price: high to low';

  @override
  String get filterCity => 'City';

  @override
  String get filterArea => 'Area';

  @override
  String get filterAnyCity => 'Any city';

  @override
  String get filterAnyArea => 'Any area';

  @override
  String get filterType => 'Property type';

  @override
  String get filterAnyType => 'Any type';

  @override
  String get filterBeds => 'Bedrooms';

  @override
  String get filterBaths => 'Bathrooms';

  @override
  String get filterAny => 'Any';

  @override
  String get filterPrice => 'Price (JOD)';

  @override
  String get filterMin => 'Min';

  @override
  String get filterMax => 'Max';

  @override
  String get filterSize => 'Built area (m²)';

  @override
  String get filterAvailableOnly => 'Hide sold and rented';

  @override
  String get filterShowResults => 'Show results';

  @override
  String get filterClearAll => 'Clear all';

  @override
  String get filterAmenitiesNote =>
      'Features such as a garden or a pool are matched by AI Search, which reads every listing\'s details.';

  @override
  String get exploreNoResultsTitle => 'Nothing matches these filters';

  @override
  String get exploreNoResultsBody => 'Try widening the area, or raising the budget.';

  @override
  String get exploreList => 'List';

  @override
  String get exploreMap => 'Map';

  @override
  String get exploreLoadMore => 'Loading more…';

  @override
  String get exploreEnd => 'That\'s everything that matches.';

  @override
  String get mapApproximateNote => 'Circles mark approximate locations the owner chose not to pin exactly.';

  @override
  String get mapNoPins => 'None of the loaded listings has a map location yet.';

  @override
  String get badgeForSale => 'For sale';

  @override
  String get badgeForRent => 'For rent';

  @override
  String get badgeSold => 'SOLD';

  @override
  String get badgeRented => 'RENTED';

  @override
  String get badgeVerified => 'Verified';

  @override
  String get badgeFeatured => 'Featured';

  @override
  String get noPhotos => 'No photos yet';

  @override
  String get a11ySave => 'Save property';

  @override
  String get a11yUnsave => 'Remove from saved';

  @override
  String a11yBeds(int count) {
    return '$count bedrooms';
  }

  @override
  String a11yBaths(int count) {
    return '$count bathrooms';
  }

  @override
  String get aiTitle => 'AI Search';

  @override
  String get aiKicker => 'Property intelligence';

  @override
  String get aiIdleTitle => 'Tell us what you are looking for.';

  @override
  String get aiIdleBody =>
      'Write it the way you would say it out loud. We pick out whether you are buying or renting, where, your budget, bedrooms, bathrooms and features, recognise Jordanian place names in either language, and search straight away.';

  @override
  String get aiIdleBodyShort =>
      'Describe it the way you’d say it, in English or Arabic. We read the area, budget, rooms and features, then show why each result fits.';

  @override
  String get aiRefineHintShort => 'Refine, e.g. “only Abdoun”';

  @override
  String get aiCoveragePartner => 'Licensed partner feeds aren’t connected yet, so they weren’t part of this search.';

  @override
  String get aiSharpen => 'Sharpen it';

  @override
  String get aiInputHint => 'Describe the property you want…';

  @override
  String get aiRefineHint => 'Change your search. Try “only Abdoun” or “raise the budget to 900,000”';

  @override
  String get aiTry => 'Try';

  @override
  String get aiExample1 => 'Find me a 3-bedroom apartment in Abdoun under 150,000 JOD';

  @override
  String get aiExample2 => 'Show me villas in Amman with a garden and parking';

  @override
  String get aiExample3 => 'بدي شقة بعمان غرفتين وبسعر أقل من ٨٠ ألف دينار';

  @override
  String get aiBrief => 'Search brief';

  @override
  String get aiBriefEmpty =>
      'What you asked for shows up here as soon as we read it. You can edit any of it, and we never change it without saying so.';

  @override
  String get aiReadingLive => 'We read:';

  @override
  String get aiWorking => 'Working through your request…';

  @override
  String get aiStageLang => 'Language detection';

  @override
  String get aiStageParse => 'Requirement extraction';

  @override
  String get aiStageLoc => 'Location resolution';

  @override
  String get aiStageInternal => 'Marketplace search';

  @override
  String get aiStageExternal => 'External market search';

  @override
  String get aiStageRank => 'Deterministic ranking';

  @override
  String get aiResultsInternal => 'On Akarat.ai';

  @override
  String get aiResultsExternal => 'Indexed from other portals';

  @override
  String get aiResultsExternalNote =>
      'Found on other Jordanian portals and indexed by our crawler. Availability is not confirmed — open the source to check.';

  @override
  String aiMatch(int score) {
    return '$score% match';
  }

  @override
  String get aiWhyMatches => 'Why this matches';

  @override
  String get aiNoMatchTitle => 'Nothing in our inventory matches that yet.';

  @override
  String get aiNoMatchBody =>
      'Try widening the area or raising the budget, or search the wider Jordanian market below.';

  @override
  String get aiWiderMarket => 'Wider Jordanian market';

  @override
  String get aiWiderBody =>
      'We turn your brief into a real search on each Jordanian portal. These open their own filtered results, so the listings you see are theirs and current. Nothing here is copied or invented.';

  @override
  String get aiOpensOutside => 'Opens outside Akarat.ai';

  @override
  String aiCoverageMissing(String sources) {
    return 'Not searched this time: $sources';
  }

  @override
  String get aiServedDirect => 'The search service didn\'t answer, so we searched the Akarat.ai database directly.';

  @override
  String get aiMissingDeal => 'Buying or renting? Say so and the ranking gets sharper.';

  @override
  String get aiMissingLocation => 'Name a city or an area to narrow it down.';

  @override
  String get aiSaveSearch => 'Save search';

  @override
  String get aiSearchSaved => 'Search saved';

  @override
  String get aiStartOver => 'Clear search';

  @override
  String get aiExternalBadge => 'Other portal';

  @override
  String aiSourcesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count sources', one: '1 source');
    return '$_temp0';
  }

  @override
  String get aiViewOnSource => 'View on source';

  @override
  String get aiSaveSearchTitle => 'Name this search';

  @override
  String get aiSearchedFor => 'You asked';

  @override
  String chipBedsMin(int count) {
    return '$count+ bedrooms';
  }

  @override
  String chipBathsMin(int count) {
    return '$count+ bathrooms';
  }

  @override
  String chipBudgetMax(String price) {
    return 'Up to $price';
  }

  @override
  String chipBudgetMin(String price) {
    return 'From $price';
  }

  @override
  String chipAreaMin(String area) {
    return '$area+ m²';
  }

  @override
  String get chipOnlyAkarat => 'Akarat.ai only';

  @override
  String chipRemove(String label) {
    return 'Remove $label';
  }

  @override
  String get detailsSpecs => 'Property details';

  @override
  String get detailsAmenities => 'Features and amenities';

  @override
  String get detailsAbout => 'About this property';

  @override
  String get detailsLocation => 'Location';

  @override
  String get detailsReadMore => 'Read more';

  @override
  String get detailsReadLess => 'Show less';

  @override
  String get specType => 'Type';

  @override
  String get specDeal => 'Listing';

  @override
  String get specBeds => 'Bedrooms';

  @override
  String get specBaths => 'Bathrooms';

  @override
  String get specArea => 'Built area';

  @override
  String get specLand => 'Land area';

  @override
  String get specYear => 'Year built';

  @override
  String get specRef => 'Reference';

  @override
  String get detailsApproxLocation =>
      'Approximate location, within about 300 m. The owner keeps the exact address private.';

  @override
  String get detailsExactLocation => 'Exact location published by the owner.';

  @override
  String get detailsOpenInMaps => 'Open in Maps';

  @override
  String get detailsNoLocation => 'The owner hasn\'t placed this property on the map.';

  @override
  String get detailsContact => 'Interested in this property?';

  @override
  String get detailsContactSub => 'Contact the owner directly, or send an inquiry to their dashboard.';

  @override
  String get detailsCall => 'Call';

  @override
  String get detailsWhatsApp => 'WhatsApp';

  @override
  String get detailsEnquire => 'Send inquiry';

  @override
  String get detailsCopyNumber => 'Copy number';

  @override
  String get detailsNumberCopied => 'Number copied';

  @override
  String get detailsNoPhone => 'No phone number was published. Send an inquiry instead.';

  @override
  String get detailsVerifiedListing => 'Verified listing';

  @override
  String get detailsOwnerListing => 'Listed by the owner';

  @override
  String get detailsClosedSold => 'This property has been sold. It stays here so links to it keep working.';

  @override
  String get detailsClosedRented => 'This property has been rented. It stays here so links to it keep working.';

  @override
  String get detailsSimilar => 'Similar properties';

  @override
  String detailsSimilarTurn(Object title) {
    return 'Like “$title”';
  }

  @override
  String get detailsFindSimilar => 'Search for similar';

  @override
  String get detailsNotFound => 'This listing is no longer available.';

  @override
  String detailsListedOn(String date) {
    return 'Listed $date';
  }

  @override
  String detailsUpdatedOn(String date) {
    return 'Updated $date';
  }

  @override
  String detailsMediaPosition(int index, int total) {
    return '$index of $total';
  }

  @override
  String get detailsVideo => 'Video';

  @override
  String get detailsYourListing => 'This is your listing';

  @override
  String get detailsManage => 'Manage';

  @override
  String get inquiryTitle => 'Send an inquiry';

  @override
  String get inquiryBody => 'Your message goes straight to the owner\'s dashboard on Akarat.ai.';

  @override
  String get inquiryName => 'Your name';

  @override
  String get inquiryEmail => 'Email';

  @override
  String get inquiryPhone => 'Phone';

  @override
  String get inquiryMessage => 'Message';

  @override
  String inquiryDefaultMessage(String title) {
    return 'Hello, I\'m interested in “$title”. Is it still available?';
  }

  @override
  String get inquirySend => 'Send inquiry';

  @override
  String get inquirySending => 'Sending…';

  @override
  String get inquirySent => 'Sent. The owner will see it in their dashboard.';

  @override
  String get inquiryNeedContact => 'Add an email or a phone number so the owner can reply.';

  @override
  String get inquiryClosed => 'This listing is no longer taking inquiries.';

  @override
  String get validationRequired => 'Required';

  @override
  String get validationEmail => 'Enter a valid email address';

  @override
  String get validationPhone => 'Enter a valid phone number';

  @override
  String validationPasswordShort(int count) {
    return 'Use at least $count characters';
  }

  @override
  String get validationNumber => 'Enter a whole number';

  @override
  String get validationPositive => 'Must be greater than zero';

  @override
  String validationYear(int max) {
    return 'Enter a year between 1900 and $max';
  }

  @override
  String get authSignInTitle => 'Welcome back';

  @override
  String get authSignInBody => 'Sign in with the same account you use on akarat.ai.';

  @override
  String get authSignUpTitle => 'Create your account';

  @override
  String get authSignUpBody =>
      'One account to list a property, track inquiries and save searches — on the app and the website.';

  @override
  String get fieldName => 'Full name';

  @override
  String get fieldEmail => 'Email address';

  @override
  String get fieldPassword => 'Password';

  @override
  String get fieldNewPassword => 'New password';

  @override
  String get authForgot => 'Forgot password?';

  @override
  String get authForgotTitle => 'Reset your password';

  @override
  String get authForgotBody =>
      'Enter the email you signed up with and we will send you a link to choose a new password.';

  @override
  String get authSendLink => 'Send reset link';

  @override
  String get authResetSent => 'If an account exists for that email, a reset link is on its way. Check your inbox.';

  @override
  String get authResetTitle => 'Choose a new password';

  @override
  String get authResetBody => 'Enter a new password for your account. Use at least 6 characters.';

  @override
  String get authSavePassword => 'Save password';

  @override
  String get authPasswordUpdated => 'Password updated.';

  @override
  String authAgreement(String terms, String privacy) {
    return 'By creating an account, you agree to the $terms and $privacy.';
  }

  @override
  String get authCreateAccount => 'Create account';

  @override
  String get authHaveAccount => 'Already have an account? Sign in';

  @override
  String get authNoAccount => 'New here? Create an account';

  @override
  String get authGoogle => 'Continue with Google';

  @override
  String get authOr => 'or';

  @override
  String get authCheckEmail => 'Account created. Check your email to confirm the address, then sign in.';

  @override
  String get authRequiredTitle => 'Sign in to continue';

  @override
  String get authRequiredBody => 'You need an account to list a property, see your inquiries and keep saved searches.';

  @override
  String get authGoogleDisabled => 'Google sign-in is not switched on yet. Use your email and password.';

  @override
  String get authInvalidCredentials => 'That email and password don\'t match an account.';

  @override
  String get authEmailNotConfirmed => 'Confirm your email address first. Check your inbox for the link.';

  @override
  String get authUserExists => 'An account with this email already exists. Sign in instead.';

  @override
  String get authWeakPassword => 'Choose a stronger password.';

  @override
  String get authLinkExpired => 'That link has expired or was already used. Ask for a new one.';

  @override
  String get authCallbackWorking => 'Signing you in…';

  @override
  String get authShowPassword => 'Show password';

  @override
  String get authHidePassword => 'Hide password';

  @override
  String get authPhoneButton => 'Continue with a phone number';

  @override
  String get authPhoneSignUpButton => 'Sign up with a phone number';

  @override
  String get authPhoneTitle => 'Sign in with your phone';

  @override
  String get authPhoneBody =>
      'Choose your country and enter your number. We’ll send you a code to sign in — no password needed.';

  @override
  String get authPhoneSignUpTitle => 'Create an account with your phone';

  @override
  String get authPhoneSignUpBody => 'Enter your name and number. We’ll send a code to confirm the number is yours.';

  @override
  String get authPhoneLinkTitle => 'Add a phone number';

  @override
  String get authPhoneChangeTitle => 'Change your phone number';

  @override
  String get authPhoneLinkBody =>
      'Sign in with a code sent to your phone instead of your password. We’ll send a code to confirm the number is yours.';

  @override
  String get authPhoneEmailNote =>
      'Signed up with email? Sign in with it, then add your number in Profile to sign in by phone next time.';

  @override
  String get authPhoneSignUpNote =>
      'Already have an account with email? Don’t make a second one: sign in, then add your number in Profile.';

  @override
  String get authPhoneCreateInstead => 'Create an account with this number';

  @override
  String get authUseEmail => 'Use email instead';

  @override
  String get fieldCountry => 'Country';

  @override
  String get fieldPhoneNumber => 'Phone number';

  @override
  String get fieldCode => 'Verification code';

  @override
  String authPhoneHint(String digits, String dial) {
    return 'Enter the $digits-digit number after +$dial, without the leading zero.';
  }

  @override
  String authPhoneCountryA11y(String country, String dial) {
    return 'Country code: $country, +$dial';
  }

  @override
  String get authSendCode => 'Send code';

  @override
  String get authSending => 'Sending…';

  @override
  String get authCodeTitle => 'Enter your code';

  @override
  String get authCodeBodySms => 'We sent a 6-digit code by text message. Use it soon: it expires quickly.';

  @override
  String get authCodeBodyWhatsapp => 'We sent a 6-digit code on WhatsApp. Use it soon: it expires quickly.';

  @override
  String get authCodeSentTo => 'Sent to';

  @override
  String get authChangeNumber => 'Change number';

  @override
  String get authVerifySignIn => 'Verify and sign in';

  @override
  String get authVerifySignUp => 'Verify and create account';

  @override
  String get authVerifyLink => 'Verify and add number';

  @override
  String get authVerifying => 'Checking…';

  @override
  String get authResend => 'Resend code';

  @override
  String authResendIn(int seconds) {
    return 'Resend code in ${seconds}s';
  }

  @override
  String get authCodeResent => 'A new code is on its way.';

  @override
  String get authCodeIncomplete => 'Enter the 6-digit code you were sent.';

  @override
  String get authCodeWrong => 'That code is wrong or has expired. Check it, or ask for a new one.';

  @override
  String get authCodeSendFailed => 'We couldn’t send a code to that number. Check it and try again.';

  @override
  String get authCodeTooMany => 'Too many codes asked for. Wait a few minutes, then try again.';

  @override
  String get authPhoneNoAccount =>
      'No account uses this number yet. If you signed up with email, sign in with it and add your number in Profile.';

  @override
  String get authPhoneTaken => 'That number is already used by another account.';

  @override
  String get authPhoneInvalid => 'That doesn’t look like a phone number. Check it and try again.';

  @override
  String get authPhoneUnavailable => 'Phone sign-in isn’t available right now. Use your email instead.';

  @override
  String get authPhoneLinked => 'Number added. You can sign in with it now.';

  @override
  String get profileSignInPhone => 'Sign-in phone number';

  @override
  String get profileSignInPhoneNone => 'Add one to sign in with a code';

  @override
  String get authFacebook => 'Continue with Facebook';

  @override
  String get authFacebookDisabled => 'Facebook sign-in isn’t switched on yet. Use your email or phone for now.';

  @override
  String get authCancelled => 'Sign-in was cancelled. Nothing was changed.';

  @override
  String get authCallbackFailedTitle => 'That didn’t go through';

  @override
  String get authBackToProfile => 'Back to profile';

  @override
  String get profileFacebook => 'Facebook';

  @override
  String get profileFacebookConnect => 'Connect it to sign in with Facebook';

  @override
  String get profileFacebookConnected => 'Connected: you can sign in with Facebook';

  @override
  String get profileFacebookOnly => 'Connected: the way this account signs in';

  @override
  String get facebookConnected => 'Facebook connected. You can sign in with it now.';

  @override
  String get facebookDisconnect => 'Disconnect';

  @override
  String get facebookDisconnectTitle => 'Disconnect Facebook?';

  @override
  String get facebookDisconnectBody =>
      'You won’t be able to sign in with Facebook any more. Your account, listings and saved homes stay as they are.';

  @override
  String get facebookDisconnected => 'Facebook disconnected';

  @override
  String get facebookLinkDisabled => 'Connecting accounts isn’t switched on yet. Try again later.';

  @override
  String get facebookTaken =>
      'That Facebook account already belongs to another Akarat.ai account. Sign in with Facebook to use that one.';

  @override
  String get facebookOnlyWayIn =>
      'Facebook is how this account signs in. Add a phone number first, then you can disconnect it.';

  @override
  String get authApple => 'Continue with Apple';

  @override
  String get authAppleDisabled => 'Sign in with Apple isn’t switched on yet. Use your email or phone for now.';

  @override
  String get authAppleFailed =>
      'Apple couldn’t sign you in. Check that this device is signed in to an Apple ID, or use your email or phone.';

  @override
  String get profileApple => 'Apple';

  @override
  String get profileAppleConnect => 'Connect it to sign in with Apple';

  @override
  String get profileAppleConnected => 'Connected: you can sign in with Apple';

  @override
  String get appleConnected => 'Apple connected. You can sign in with it now.';

  @override
  String get appleDisconnectTitle => 'Disconnect Apple?';

  @override
  String get appleDisconnectBody =>
      'You won’t be able to sign in with Apple any more. Your account, listings and saved homes stay as they are.';

  @override
  String get appleDisconnected => 'Apple disconnected';

  @override
  String get appleTaken =>
      'That Apple ID already belongs to another Akarat.ai account. Sign in with Apple to use that one.';

  @override
  String get appleOnlyWayIn =>
      'Apple is how this account signs in. Add a phone number first, then you can disconnect it.';

  @override
  String get deleteAccountAppleNote =>
      'You sign in with Apple, so Apple asks you to confirm next. Akarat.ai is then removed from your Apple ID too.';

  @override
  String get deleteAccountAppleCancelled => 'Nothing was deleted: Apple’s confirmation was cancelled.';

  @override
  String get detailsMore => 'More';

  @override
  String get reportListing => 'Report this listing';

  @override
  String get reportBody => 'Tell us what’s wrong. We review every report and remove listings that break the rules.';

  @override
  String get reportReasonScam => 'It’s a scam or fake';

  @override
  String get reportReasonWrong => 'Wrong price, photos or details';

  @override
  String get reportReasonUnavailable => 'Already sold or rented';

  @override
  String get reportReasonOffensive => 'Offensive or inappropriate';

  @override
  String get reportReasonOther => 'Something else';

  @override
  String get reportDetails => 'Anything else we should know (optional)';

  @override
  String get reportSend => 'Send report';

  @override
  String get reportThanks => 'Thanks. We’ll review this listing.';

  @override
  String get reportSignIn => 'Sign in to report a listing, so we can follow up with you.';

  @override
  String reportByEmail(String email) {
    return 'Reports aren’t switched on in the app yet. We’ve opened an email to $email instead.';
  }

  @override
  String get hideAdvertiser => 'Hide this advertiser';

  @override
  String get hideAdvertiserTitle => 'Hide this advertiser?';

  @override
  String get hideAdvertiserBody =>
      'You won’t see any of their listings again on this device. You can show them again from Profile.';

  @override
  String get hideAdvertiserAction => 'Hide';

  @override
  String get hideAdvertiserDone => 'Hidden. You won’t see their listings any more.';

  @override
  String profileHiddenAdvertisers(int count) {
    return 'Hidden advertisers: $count';
  }

  @override
  String get profileHiddenAdvertisersShow => 'Tap to show their listings again';

  @override
  String get showHiddenTitle => 'Show hidden advertisers again?';

  @override
  String get showHiddenBody => 'Their listings will appear in your results again.';

  @override
  String get showHiddenAction => 'Show again';

  @override
  String get showHiddenDone => 'Their listings will show again.';

  @override
  String get profilePhoto => 'Profile picture';

  @override
  String get profilePhotoChange => 'Change profile picture';

  @override
  String get profilePhotoChoose => 'Choose from your photos';

  @override
  String get profilePhotoTake => 'Take a photo';

  @override
  String get profilePhotoRemove => 'Remove picture';

  @override
  String get profilePhotoNote => 'Kept on this phone only: it isn’t uploaded, and no one else sees it.';

  @override
  String get profilePhotoUpdated => 'Profile picture updated';

  @override
  String get profilePhotoRemoved => 'Profile picture removed';

  @override
  String get profilePhotoFailed => 'That picture couldn’t be used. Try another one.';

  @override
  String get profilePhotoNoCamera => 'The camera isn’t available. Choose from your photos instead.';

  @override
  String get savedTitle => 'Saved';

  @override
  String get savedProperties => 'Properties';

  @override
  String get savedSearches => 'Searches';

  @override
  String get savedEmptyTitle => 'Nothing saved yet';

  @override
  String get savedEmptyBody => 'Tap the heart on any property to keep it here.';

  @override
  String get savedSearchesEmptyTitle => 'No saved searches';

  @override
  String get savedSearchesEmptyBody => 'Run an AI search, then save it to come back to it any time.';

  @override
  String get savedSearchesSignIn => 'Sign in to keep searches with your account.';

  @override
  String get savedDeviceOnly => 'Saved on this device. Sign in to keep them with your account.';

  @override
  String get savedSyncUnavailable =>
      'Your account can\'t store saved properties yet, so these are kept on this device.';

  @override
  String get savedRemoved => 'Removed from saved';

  @override
  String get savedAdded => 'Saved';

  @override
  String get savedSearchRun => 'Search again';

  @override
  String get savedSearchDeleted => 'Search removed';

  @override
  String get savedListingGone => 'No longer available';

  @override
  String get listingNewTitle => 'List your property';

  @override
  String get listingEditTitle => 'Edit listing';

  @override
  String stepOf(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get stepPurpose => 'What are you listing?';

  @override
  String get stepType => 'What kind of property?';

  @override
  String get stepLocation => 'Where is it?';

  @override
  String get stepDetails => 'The details';

  @override
  String get stepPrice => 'Price and contact';

  @override
  String get stepAmenities => 'Features';

  @override
  String get stepDescription => 'Title and description';

  @override
  String get stepMedia => 'Photos and video';

  @override
  String get stepPreview => 'Review and publish';

  @override
  String get purposeSale => 'For sale';

  @override
  String get purposeSaleBody => 'Sell the property outright.';

  @override
  String get purposeRent => 'For rent';

  @override
  String get purposeRentBody => 'Let it out monthly.';

  @override
  String get fieldCity => 'City';

  @override
  String get fieldNeighborhood => 'Area';

  @override
  String get fieldNeighborhoodNone => 'Other / not listed';

  @override
  String get fieldAddress => 'Street address (optional)';

  @override
  String get fieldAddressHelp => 'Published only if you choose to show the exact pin.';

  @override
  String get locationPinTitle => 'Pin it on the map';

  @override
  String get locationPinBody => 'Optional. Tap the map to drop the pin on the building. The city and area follow it.';

  @override
  String get locationPinPlace => 'Place a pin';

  @override
  String get locationPinEdit => 'Move the pin';

  @override
  String get locationPinRemove => 'Remove pin';

  @override
  String get locationPinNone => 'No pin placed yet';

  @override
  String get locationPinSnapped => 'Area set from the pin';

  @override
  String get precisionTitle => 'What buyers see';

  @override
  String get precisionApprox => 'Approximate circle';

  @override
  String get precisionApproxNote => 'Publishes a point up to 300 m away. The exact address stays yours alone.';

  @override
  String get precisionExact => 'Exact pin';

  @override
  String get precisionExactNote => 'Publishes the pin and the address exactly as you set them.';

  @override
  String get locationMapsOff => 'Map pins aren\'t enabled in this build. The city and area are enough to publish.';

  @override
  String get fieldBedrooms => 'Bedrooms';

  @override
  String get fieldBathrooms => 'Bathrooms';

  @override
  String get fieldAreaSqm => 'Built area (m²)';

  @override
  String get fieldLandSqm => 'Land area (m²)';

  @override
  String get fieldYearBuilt => 'Year built';

  @override
  String get fieldPrice => 'Price (JOD)';

  @override
  String get fieldPriceRent => 'Monthly rent (JOD)';

  @override
  String get fieldContactPhone => 'Contact phone';

  @override
  String get fieldContactPhoneHelp => 'Shown on the listing so people can call you or message you on WhatsApp.';

  @override
  String get fieldTitleEn => 'Title in English';

  @override
  String get fieldTitleAr => 'Title in Arabic';

  @override
  String get fieldTitleHelp =>
      'Write in Arabic or English. The other language is filled in automatically, and you can change it.';

  @override
  String get fieldDescEn => 'Description in English';

  @override
  String get fieldDescAr => 'Description in Arabic';

  @override
  String get listingTranslating => 'Translating…';

  @override
  String get listingTranslatedAr => 'Arabic filled in automatically. Check it before publishing.';

  @override
  String get listingTranslatedEn => 'English filled in automatically. Check it before publishing.';

  @override
  String get mediaAddPhotos => 'Add photos';

  @override
  String get mediaAddVideo => 'Add video';

  @override
  String get mediaHelp =>
      'Up to 8 files, including up to 2 video clips. Photos are resized before they upload. The first photo is the cover — drag to reorder.';

  @override
  String get mediaCover => 'Cover';

  @override
  String get mediaTooMany => 'Eight files is the maximum.';

  @override
  String get mediaTooManyVideos => 'Two video clips is the maximum.';

  @override
  String mediaTooLarge(String name, int size) {
    return '$name is larger than $size MB.';
  }

  @override
  String mediaUnsupported(String name) {
    return '$name isn\'t a supported format.';
  }

  @override
  String mediaUploading(int done, int total) {
    return 'Uploading file $done of $total';
  }

  @override
  String get mediaUploadFailed =>
      'A file didn\'t upload, so nothing was saved yet. Check your connection and try again — files that already uploaded won\'t be sent twice.';

  @override
  String get mediaRemove => 'Remove';

  @override
  String get previewPublish => 'Publish listing';

  @override
  String get previewSaveDraft => 'Save as draft';

  @override
  String get previewSaveChanges => 'Save changes';

  @override
  String get previewWorking => 'Saving…';

  @override
  String get previewDraftNote => 'A draft is saved to your account but hidden from everyone else until you publish it.';

  @override
  String get publishSuccess => 'Your listing is live.';

  @override
  String get draftSuccess => 'Saved as a draft. Publish it from My listings.';

  @override
  String get editSuccess => 'Changes saved.';

  @override
  String get listingMissingTitle => 'Add a title in English or Arabic.';

  @override
  String get listingMissingPrice => 'Add the price.';

  @override
  String get listingMissingCity => 'Choose the city.';

  @override
  String get listingDraftRestored => 'We kept your unfinished listing.';

  @override
  String get listingDraftDiscard => 'Start over';

  @override
  String get listingLeaveTitle => 'Leave this listing?';

  @override
  String get listingLeaveBody => 'Your progress is kept on this device, so you can carry on later.';

  @override
  String get listingLeaveEditBody => 'Changes you haven’t saved will be lost.';

  @override
  String get listingLeaveStay => 'Keep editing';

  @override
  String get listingLeaveGo => 'Leave';

  @override
  String get errorUnknownArea =>
      'This area is not set up in the database yet. Choose another area, or “Other”, and try again.';

  @override
  String get errorGeoColumns => 'Location pins aren\'t set up on the server yet. Remove the pin and try again.';

  @override
  String get errorStorageMissing =>
      'Photo storage isn\'t set up on the server yet. Remove the files and publish without them, or try later.';

  @override
  String get dashboardTitle => 'My listings';

  @override
  String get dashStatListings => 'Listings';

  @override
  String get dashStatLive => 'Live now';

  @override
  String get dashStatHidden => 'Hidden';

  @override
  String get dashStatInquiries => 'Inquiries';

  @override
  String get statusDraft => 'Draft';

  @override
  String get statusPending => 'In review';

  @override
  String get statusActive => 'Live';

  @override
  String get statusRejected => 'Rejected';

  @override
  String get statusPaused => 'Hidden';

  @override
  String get statusSold => 'Sold';

  @override
  String get statusRented => 'Rented';

  @override
  String get statusArchived => 'Archived';

  @override
  String get actionHide => 'Hide';

  @override
  String get actionPublish => 'Publish';

  @override
  String get actionMarkSold => 'Mark sold';

  @override
  String get actionMarkRented => 'Mark rented';

  @override
  String get actionRelist => 'Relist';

  @override
  String get actionView => 'View';

  @override
  String get deleteListingTitle => 'Delete this listing?';

  @override
  String get deleteListingBody =>
      'It will be removed from Akarat.ai on every device, along with its photos. This can\'t be undone.';

  @override
  String get dashEmptyTitle => 'No listings yet';

  @override
  String get dashEmptyBody => 'Add your first property to see it here. It appears on the website too.';

  @override
  String get dashAnalyticsNote => 'Views are not tracked yet. We show no numbers before they exist.';

  @override
  String get dashStatusUpdated => 'Listing updated';

  @override
  String get dashDeleted => 'Listing deleted';

  @override
  String get inquiriesTitle => 'Inquiries';

  @override
  String get inquiriesReceived => 'Received';

  @override
  String get inquiriesSent => 'Sent';

  @override
  String get inquiriesEmpty => 'No inquiries yet. They arrive here the moment someone contacts you about a property.';

  @override
  String get inquiriesSentEmpty => 'Inquiries you send to owners appear here.';

  @override
  String inquiryAbout(String title) {
    return 'About $title';
  }

  @override
  String get inquiryDeletedProperty => 'a deleted property';

  @override
  String get inquiryUnknownSender => 'Unknown';

  @override
  String get inquiryReplyEmail => 'Email';

  @override
  String get inquiryReplyCall => 'Call';

  @override
  String get profileTitle => 'Profile';

  @override
  String get profileGuestTitle => 'You\'re browsing as a guest';

  @override
  String get profileGuestBody =>
      'Sign in to list a property, keep saved searches with your account, and see inquiries.';

  @override
  String get profileMyListings => 'My listings';

  @override
  String get profileInquiries => 'Inquiries';

  @override
  String get profileSavedSearches => 'Saved searches';

  @override
  String get profileListProperty => 'List a property';

  @override
  String get profileEdit => 'Edit profile';

  @override
  String get profileSaved => 'Profile saved';

  @override
  String get profilePhone => 'Phone';

  @override
  String get profileVerified => 'Verified';

  @override
  String get settingsSection => 'Settings';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get settingsPrivacy => 'Privacy policy';

  @override
  String get settingsTerms => 'Terms of use';

  @override
  String get settingsHelp => 'Help and support';

  @override
  String get settingsHelpBody =>
      'Questions, a listing problem, or something not working? Write to us and a person will answer.';

  @override
  String get settingsEmailUs => 'Email support';

  @override
  String get settingsWebsite => 'Open the website';

  @override
  String settingsVersion(String version) {
    return 'Version $version';
  }

  @override
  String get settingsDeleteAccount => 'Delete account';

  @override
  String get signOutConfirmTitle => 'Sign out?';

  @override
  String get signOutConfirmBody => 'Your listings and saved searches stay in your account.';

  @override
  String get deleteAccountTitle => 'Delete your account?';

  @override
  String get deleteAccountBody =>
      'This permanently deletes your account, your listings and their photos, your saved searches and saved properties, on the app and the website. Messages you already sent to other owners stay in their inbox.';

  @override
  String get deleteAccountConfirmHint => 'Type DELETE to confirm';

  @override
  String get deleteAccountConfirmWord => 'DELETE';

  @override
  String deleteAccountUnavailable(String email) {
    return 'In-app deletion isn\'t switched on yet. We\'ve opened an email to $email so you can request it.';
  }

  @override
  String get deleteAccountDone => 'Your account has been deleted.';

  @override
  String get legalUpdated => 'Last updated: August 2026';

  @override
  String get privacyH1 => 'What we collect';

  @override
  String get privacyP1 =>
      'An account needs an email address and a name. If you list a property, we store what you write about it: location, price, specifications and descriptions. Search text is kept to improve how requests are read, and is not tied to your account.';

  @override
  String get privacyH2 => 'What we do not collect';

  @override
  String get privacyP2 =>
      'We do not ask for national ID numbers, banking details or your physical location. We run no advertising, we do not sell your data, and we do not share it with ad brokers.';

  @override
  String get privacyH3 => 'Links to other portals';

  @override
  String get privacyP3 =>
      'When you open a result from another Jordanian portal, you leave for their site. From that moment their privacy policy applies, not ours, and we do not tell them who was searching.';

  @override
  String get privacyH4 => 'Your rights';

  @override
  String get privacyP4 =>
      'You can edit or delete any listing from your dashboard at any time, and deleting removes it from our database. To request full account deletion, write to privacy@akarat.ai.';

  @override
  String get termsH1 => 'Using the platform';

  @override
  String get termsP1 =>
      'Searching is open to everyone. Listing a property requires an account, and you are responsible for what is published under it. Do not list a property you have no right to market. Nothing unlawful, discriminatory, offensive or abusive, in a listing or an enquiry: we remove it, and may close the account that posted it. Anyone can report a listing from its page.';

  @override
  String get termsH2 => 'Listing accuracy';

  @override
  String get termsP2 =>
      'What you write is what gets shown. Listing a property at a price, size or location that is not real is reason enough to remove it without notice.';

  @override
  String get termsH3 => 'External results';

  @override
  String get termsP3 =>
      'Results from other portals are what those portals published. We show them as they are, with a link to the source. We do not guarantee those properties are still available or correctly priced, and we take no commission on any deal.';

  @override
  String get termsH4 => 'Liability';

  @override
  String get termsP4 =>
      'Akarat is a search and listing tool, not a broker or an agent. View the property and verify ownership before any payment. Any agreement stays between you and the other party.';

  @override
  String get tabDaily => 'Daily';

  @override
  String get dailyTitle => 'Daily rentals';

  @override
  String get dailySubtitle =>
      'Places checked by our team, for a night or more. Pick dates to see only what is free, with the full price.';

  @override
  String get dailyDates => 'Dates';

  @override
  String get dailyAnyDates => 'Any dates';

  @override
  String get dailyAnyGuests => 'Any guests';

  @override
  String get dailyAllCities => 'All cities';

  @override
  String get dailyClear => 'Clear';

  @override
  String get dailyEmptyTitle => 'No daily rentals yet';

  @override
  String get dailyEmptyBody => 'The first places are on their way. Have one to let by the night? List it.';

  @override
  String get dailyNoMatchTitle => 'Nothing free for that';

  @override
  String get dailyNoMatchBody => 'Try other dates, fewer guests or another city.';

  @override
  String dailyGuests(int n) {
    String _temp0 = intl.Intl.pluralLogic(n, locale: localeName, other: '$n guests', one: '1 guest');
    return '$_temp0';
  }

  @override
  String dailyNights(int n) {
    String _temp0 = intl.Intl.pluralLogic(n, locale: localeName, other: '$n nights', one: '1 night');
    return '$_temp0';
  }

  @override
  String dailySleeps(int n) {
    return 'Sleeps $n';
  }

  @override
  String dailyMinStay(int n) {
    return '$n-night minimum';
  }

  @override
  String dailyTotalFor(String price, String nights) {
    return '$price for $nights';
  }

  @override
  String get dailyPerNight => 'per night';

  @override
  String get badgeDaily => 'Daily rental';

  @override
  String get bookingTitle => 'Request to book';

  @override
  String get bookingBody =>
      'Nothing is charged. The owner approves your request, then their number and a WhatsApp button appear here.';

  @override
  String get bookingCheckIn => 'Check-in';

  @override
  String get bookingCheckOut => 'Check-out';

  @override
  String get bookingPickDay => 'Pick a day';

  @override
  String get bookingTakenLegend => 'Crossed-out days are taken.';

  @override
  String get bookingMessage => 'A note for the owner (optional)';

  @override
  String get bookingMessageHint => 'Who is coming, and why';

  @override
  String get bookingTotal => 'Estimated total';

  @override
  String get bookingSend => 'Request to book';

  @override
  String get bookingSending => 'Sending…';

  @override
  String get bookingSignIn => 'Sign in to request';

  @override
  String get bookingSent => 'Request sent. We will let you know when the owner answers.';

  @override
  String get bookingCheckAvailability => 'Check availability';

  @override
  String get bookingYourRequest => 'Your request';

  @override
  String get bookingOwnListing => 'This is your listing. Booking requests arrive in Bookings.';

  @override
  String get bookingPickDates => 'Pick your check-in and check-out on the calendar.';

  @override
  String get bookingRangeTaken => 'Some nights in between are taken. Pick other dates.';

  @override
  String get bookingStatusPending => 'Waiting for the owner';

  @override
  String get bookingStatusApproved => 'Approved';

  @override
  String get bookingStatusConfirmed => 'Stay confirmed';

  @override
  String get bookingStatusRejected => 'Not accepted';

  @override
  String get bookingStatusCancelled => 'Cancelled';

  @override
  String get bookingStatusExpired => 'Expired';

  @override
  String get bookingPendingBody =>
      'Your request is with the owner. Their number appears here, with a WhatsApp button, as soon as they approve.';

  @override
  String get bookingApprovedBody =>
      'Contact the owner to arrange your stay. It is a request, not a confirmed booking, until you agree and the owner confirms it.';

  @override
  String get bookingConfirmedBody => 'The owner confirmed your stay for these nights.';

  @override
  String get bookingRejectedBody => 'The owner declined this request.';

  @override
  String get bookingDatesTakenBody => 'These nights went to another guest. Try other dates.';

  @override
  String get bookingCancelledByOwner => 'The owner cancelled this booking.';

  @override
  String get bookingCancelledByYou => 'You cancelled this request.';

  @override
  String get bookingWhatsApp => 'Contact on WhatsApp';

  @override
  String get bookingCancel => 'Cancel request';

  @override
  String get bookingCancelTitle => 'Cancel this request?';

  @override
  String get bookingCancelBody => 'The owner is told.';

  @override
  String get bookingKeep => 'Keep it';

  @override
  String bookingWhatsAppText(String name, String title, String from, String to, String nights, String guests) {
    return 'Hello, this is $name. You approved my Akarat.ai booking request for “$title” from $from to $to ($nights, $guests). Can we arrange the details?';
  }

  @override
  String get bookingsTitle => 'Bookings';

  @override
  String get bookingsRequests => 'For my places';

  @override
  String get bookingsMine => 'My bookings';

  @override
  String get bookingsRequestsEmpty =>
      'No booking requests yet. They arrive here the moment someone asks for one of your daily rentals.';

  @override
  String get bookingsMineEmpty => 'You have not asked for a stay yet. Pick dates on a place in Daily rentals.';

  @override
  String get bookingApprove => 'Approve';

  @override
  String get bookingApproveTitle => 'Approve and share your number';

  @override
  String bookingApproveBody(String name) {
    return '$name alone sees this number, with a WhatsApp button.';
  }

  @override
  String get bookingPhoneLabel => 'Your WhatsApp number';

  @override
  String get bookingReject => 'Decline';

  @override
  String get bookingRejectTitle => 'Decline this request?';

  @override
  String get bookingRejectNote => 'A reason for the guest (optional)';

  @override
  String get bookingConfirm => 'Confirm stay';

  @override
  String get bookingConfirmTitle => 'Confirm this stay?';

  @override
  String get bookingConfirmBody =>
      'Its nights close on your calendar, and other requests for the same nights are declined for you.';

  @override
  String get bookingOwnerCancel => 'Cancel booking';

  @override
  String get bookingOwnerCancelBody => 'The guest is told and the nights open again.';

  @override
  String bookingSharedPhone(String phone) {
    return 'Shown to the guest: $phone';
  }

  @override
  String get bookingAutoClosed => 'Closed for you: you confirmed another stay for these nights.';

  @override
  String get bookingUpdated => 'Updated.';

  @override
  String get availabilityTitle => 'Availability';

  @override
  String get availabilityBody =>
      'Tap a day to close it or open it again. Confirmed stays close their nights on their own.';

  @override
  String get availabilityOpen => 'Open';

  @override
  String get availabilityClosed => 'Closed by you';

  @override
  String get availabilityBooked => 'Confirmed stay';

  @override
  String get actionAvailability => 'Availability';

  @override
  String get previousMonth => 'Previous month';

  @override
  String get nextMonth => 'Next month';

  @override
  String get reviewPending => 'Waiting for review';

  @override
  String get reviewApproved => 'Verified';

  @override
  String get reviewRejected => 'Not approved';

  @override
  String get reviewSuspended => 'Suspended';

  @override
  String get reviewPendingBody =>
      'Our team checks every daily rental before it appears. It stays hidden until approved, and we will let you know.';

  @override
  String reviewRejectedBody(String note) {
    return 'Not approved: $note. Edit and save it to send it for review again.';
  }

  @override
  String reviewSuspendedBody(String note) {
    return 'Suspended: $note.';
  }

  @override
  String get purposeDaily => 'Daily rental';

  @override
  String get purposeDailyBody => 'Let it by the night: a chalet, a flat, a farm.';

  @override
  String get fieldPriceNight => 'Price per night (JOD)';

  @override
  String get fieldMaxGuests => 'Sleeps up to (guests)';

  @override
  String get fieldMinNights => 'Minimum stay (nights)';

  @override
  String get dailyPhonePrivate =>
      'Your number is not published on a daily rental. When you approve a booking request, you choose the number that guest alone sees, with a WhatsApp button.';

  @override
  String get dailyReviewNotice =>
      'Daily rentals are checked by our team before they appear. Yours carries a grey check until it is approved, then a green one.';

  @override
  String get listingMissingGuests => 'Enter how many guests it sleeps (1 to 50).';

  @override
  String get listingMinNightsRange => 'The minimum stay can be 1 to 30 nights.';

  @override
  String get publishSuccessDaily => 'Sent for review. We will let you know when it is approved.';

  @override
  String get errorDailyNotSetUp => 'Daily rentals are not set up on the server yet.';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsEmpty => 'No notifications yet.';

  @override
  String notifBookingNew(String name, String title) {
    return 'New booking request from $name for “$title”.';
  }

  @override
  String notifBookingApproved(String title) {
    return 'Your request for “$title” was approved. The owner’s number is in My bookings.';
  }

  @override
  String notifBookingRejected(String title) {
    return 'Your request for “$title” was declined.';
  }

  @override
  String notifBookingDatesTaken(String title) {
    return 'The dates you asked for at “$title” went to another guest.';
  }

  @override
  String notifBookingConfirmed(String title) {
    return 'Your stay at “$title” is confirmed.';
  }

  @override
  String notifBookingCancelledByRenter(String name, String title) {
    return '$name cancelled their request for “$title”.';
  }

  @override
  String notifBookingCancelledByOwner(String title) {
    return 'The owner cancelled your booking at “$title”.';
  }

  @override
  String notifListingApproved(String title) {
    return '“$title” was approved and is live in Daily rentals.';
  }

  @override
  String notifListingRejected(String title) {
    return '“$title” was not approved. Edit and save it to send it for review again.';
  }

  @override
  String notifListingSuspended(String title) {
    return '“$title” was suspended.';
  }

  @override
  String notifListingUnapproved(String title) {
    return '“$title” is back in review and hidden until it is approved again.';
  }

  @override
  String notifReason(String note) {
    return 'Reason: $note';
  }

  @override
  String get notifGuest => 'A guest';

  @override
  String get profileBookings => 'Bookings';

  @override
  String get profileNotifications => 'Notifications';

  @override
  String get dailyErrSignIn => 'Sign in to send a request.';

  @override
  String get dailyErrNotBookable => 'This place is not taking requests right now.';

  @override
  String get dailyErrOwn => 'This is your own listing.';

  @override
  String get dailyErrBadDates => 'Choose a check-out date after check-in.';

  @override
  String get dailyErrPast => 'Those dates have passed.';

  @override
  String get dailyErrTooFar => 'Requests can be made up to a year ahead.';

  @override
  String dailyErrMinNights(int n) {
    return 'This place needs a stay of at least $n nights.';
  }

  @override
  String dailyErrMaxNights(int n) {
    return 'Stays are up to $n nights.';
  }

  @override
  String dailyErrMaxGuests(int n) {
    return 'This place sleeps up to $n guests.';
  }

  @override
  String get dailyErrBadGuests => 'Choose how many guests.';

  @override
  String get dailyErrUnavailable => 'Some of those nights are no longer free. Pick other dates.';

  @override
  String get dailyErrOpenRequest => 'You already have an open request for this place.';

  @override
  String get dailyErrTooMany => 'You have sent many requests today. Try again tomorrow.';

  @override
  String get dailyErrPhoneNeeded => 'Enter the phone number to share with the guest.';

  @override
  String get dailyErrClosed => 'This request has already been answered.';

  @override
  String get dailyErrMissing => 'This request no longer exists.';

  @override
  String get dailyErrNotYours => 'Only the owner can do that.';

  @override
  String get dailyNotLiveYet => 'Not live yet';
}
