import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('ar'), Locale('en')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Akarat.ai'**
  String get appTitle;

  /// No description provided for @brandTagline.
  ///
  /// In en, this message translates to:
  /// **'Property search across Jordan'**
  String get brandTagline;

  /// No description provided for @tabHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get tabHome;

  /// No description provided for @tabExplore.
  ///
  /// In en, this message translates to:
  /// **'Explore'**
  String get tabExplore;

  /// No description provided for @tabAiSearch.
  ///
  /// In en, this message translates to:
  /// **'AI Search'**
  String get tabAiSearch;

  /// No description provided for @tabSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get tabSaved;

  /// No description provided for @tabProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get tabProfile;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get actionRetry;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @actionDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get actionDone;

  /// No description provided for @actionContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get actionContinue;

  /// No description provided for @actionBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get actionBack;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @actionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// No description provided for @actionEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get actionEdit;

  /// No description provided for @actionShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get actionShare;

  /// No description provided for @actionClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get actionClear;

  /// No description provided for @actionApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get actionApply;

  /// No description provided for @actionSeeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get actionSeeAll;

  /// No description provided for @tourWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Akarat.ai'**
  String get tourWelcomeTitle;

  /// No description provided for @tourWelcomeTitleName.
  ///
  /// In en, this message translates to:
  /// **'Welcome, {name}'**
  String tourWelcomeTitleName(String name);

  /// No description provided for @tourWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Your account is ready. Here\'s a one-minute look at finding, saving and listing properties.'**
  String get tourWelcomeBody;

  /// No description provided for @tourWelcomeAccountBody.
  ///
  /// In en, this message translates to:
  /// **'Your account is ready. Here\'s where to find what it adds.'**
  String get tourWelcomeAccountBody;

  /// No description provided for @tourPhotosTitle.
  ///
  /// In en, this message translates to:
  /// **'Every photo'**
  String get tourPhotosTitle;

  /// No description provided for @tourPhotosBody.
  ///
  /// In en, this message translates to:
  /// **'Tap the photo or this pill to see them all full screen. Map shows where the property is.'**
  String get tourPhotosBody;

  /// No description provided for @tourSaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Save it for later'**
  String get tourSaveTitle;

  /// No description provided for @tourSaveBody.
  ///
  /// In en, this message translates to:
  /// **'Tap the heart to keep this property in Saved, ready to come back to.'**
  String get tourSaveBody;

  /// No description provided for @tourContactTitle.
  ///
  /// In en, this message translates to:
  /// **'Contact the owner'**
  String get tourContactTitle;

  /// No description provided for @tourContactBody.
  ///
  /// In en, this message translates to:
  /// **'Send an inquiry straight to the owner\'s dashboard. Chat and call are on the owner\'s card further down.'**
  String get tourContactBody;

  /// No description provided for @guideProperty.
  ///
  /// In en, this message translates to:
  /// **'Viewing a property'**
  String get guideProperty;

  /// No description provided for @guidePropertyNone.
  ///
  /// In en, this message translates to:
  /// **'There are no listings to show the guide on yet.'**
  String get guidePropertyNone;

  /// No description provided for @settingsLicences.
  ///
  /// In en, this message translates to:
  /// **'Open-source licences'**
  String get settingsLicences;

  /// No description provided for @mapViewSatellite.
  ///
  /// In en, this message translates to:
  /// **'Satellite'**
  String get mapViewSatellite;

  /// No description provided for @mapViewMap.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get mapViewMap;

  /// No description provided for @a11yMapViewSatellite.
  ///
  /// In en, this message translates to:
  /// **'Switch to satellite view'**
  String get a11yMapViewSatellite;

  /// No description provided for @a11yMapViewMap.
  ///
  /// In en, this message translates to:
  /// **'Switch to map view'**
  String get a11yMapViewMap;

  /// No description provided for @detailsStreetView.
  ///
  /// In en, this message translates to:
  /// **'Street View'**
  String get detailsStreetView;

  /// No description provided for @tourMapLayerTitle.
  ///
  /// In en, this message translates to:
  /// **'See it from above'**
  String get tourMapLayerTitle;

  /// No description provided for @tourMapLayerBody.
  ///
  /// In en, this message translates to:
  /// **'Switch between the map and satellite view to see the buildings and streets around a property.'**
  String get tourMapLayerBody;

  /// No description provided for @detailsMapPill.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get detailsMapPill;

  /// No description provided for @specListed.
  ///
  /// In en, this message translates to:
  /// **'Listed'**
  String get specListed;

  /// No description provided for @specUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get specUpdated;

  /// No description provided for @viewerPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get viewerPhotos;

  /// No description provided for @homeMore.
  ///
  /// In en, this message translates to:
  /// **'More to explore'**
  String get homeMore;

  /// No description provided for @actionSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get actionSignIn;

  /// No description provided for @actionSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get actionSignOut;

  /// No description provided for @actionNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get actionNext;

  /// No description provided for @actionSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get actionSkip;

  /// No description provided for @actionGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get actionGetStarted;

  /// No description provided for @actionMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get actionMore;

  /// No description provided for @previewMediaCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No photos yet} =1{1 photo or video} other{{count} photos and videos}}'**
  String previewMediaCount(num count);

  /// No description provided for @a11yDecrease.
  ///
  /// In en, this message translates to:
  /// **'Decrease'**
  String get a11yDecrease;

  /// No description provided for @a11yIncrease.
  ///
  /// In en, this message translates to:
  /// **'Increase'**
  String get a11yIncrease;

  /// No description provided for @tourStepOf.
  ///
  /// In en, this message translates to:
  /// **'{current} of {total}'**
  String tourStepOf(int current, int total);

  /// No description provided for @tourSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip tour'**
  String get tourSkip;

  /// No description provided for @tourDone.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get tourDone;

  /// No description provided for @tourSearchTitle.
  ///
  /// In en, this message translates to:
  /// **'Just describe it'**
  String get tourSearchTitle;

  /// No description provided for @tourSearchBody.
  ///
  /// In en, this message translates to:
  /// **'Type what you’re after in English or Arabic, like “3 bedrooms in Abdoun under 150k”, or tap the microphone and say it. AI Search finds it and shows why each result fits.'**
  String get tourSearchBody;

  /// No description provided for @tourDealTitle.
  ///
  /// In en, this message translates to:
  /// **'Buying or renting?'**
  String get tourDealTitle;

  /// No description provided for @tourDealBody.
  ///
  /// In en, this message translates to:
  /// **'Switch here, and everything on Home follows.'**
  String get tourDealBody;

  /// No description provided for @tourCityTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick a city'**
  String get tourCityTitle;

  /// No description provided for @tourCityBody.
  ///
  /// In en, this message translates to:
  /// **'Focus on one city, or keep all of Jordan.'**
  String get tourCityBody;

  /// No description provided for @tourExploreTitle.
  ///
  /// In en, this message translates to:
  /// **'See it on a map'**
  String get tourExploreTitle;

  /// No description provided for @tourExploreBody.
  ///
  /// In en, this message translates to:
  /// **'Explore shows every property on a map — green for sale, gold for rent — with filters and a list view.'**
  String get tourExploreBody;

  /// No description provided for @tourAiTitle.
  ///
  /// In en, this message translates to:
  /// **'Ask for it'**
  String get tourAiTitle;

  /// No description provided for @tourAiBody.
  ///
  /// In en, this message translates to:
  /// **'Refine a search in plain words, save it, and come back to it any time.'**
  String get tourAiBody;

  /// No description provided for @tourSavedTitle.
  ///
  /// In en, this message translates to:
  /// **'Keep the ones you like'**
  String get tourSavedTitle;

  /// No description provided for @tourSavedBody.
  ///
  /// In en, this message translates to:
  /// **'Tap the heart on any property. It waits for you in Saved, next to your saved searches.'**
  String get tourSavedBody;

  /// No description provided for @tourProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'List your own property'**
  String get tourProfileTitle;

  /// No description provided for @tourProfileBody.
  ///
  /// In en, this message translates to:
  /// **'From Profile, list a property in a few guided steps, then answer inquiries from buyers and tenants.'**
  String get tourProfileBody;

  /// No description provided for @tourProfileGuestBody.
  ///
  /// In en, this message translates to:
  /// **'Log in here to list a property in a few guided steps, then answer inquiries from buyers and tenants.'**
  String get tourProfileGuestBody;

  /// No description provided for @tourMapDealTitle.
  ///
  /// In en, this message translates to:
  /// **'All, sale or rent'**
  String get tourMapDealTitle;

  /// No description provided for @tourMapDealBody.
  ///
  /// In en, this message translates to:
  /// **'Choose what the map shows.'**
  String get tourMapDealBody;

  /// No description provided for @tourMapPinsTitle.
  ///
  /// In en, this message translates to:
  /// **'Read the pins'**
  String get tourMapPinsTitle;

  /// No description provided for @tourMapPinsBody.
  ///
  /// In en, this message translates to:
  /// **'Each pin shows the price. Green is for sale, gold is for rent; a number groups pins that are close together, so tap it to zoom in. A shaded circle means the owner shared an approximate location. Tap a pin to preview the property.'**
  String get tourMapPinsBody;

  /// No description provided for @tourMapFiltersTitle.
  ///
  /// In en, this message translates to:
  /// **'Narrow it down'**
  String get tourMapFiltersTitle;

  /// No description provided for @tourMapFiltersBody.
  ///
  /// In en, this message translates to:
  /// **'Filter by city, type, rooms, price and size.'**
  String get tourMapFiltersBody;

  /// No description provided for @tourMapToggleTitle.
  ///
  /// In en, this message translates to:
  /// **'Prefer a list?'**
  String get tourMapToggleTitle;

  /// No description provided for @tourMapToggleBody.
  ///
  /// In en, this message translates to:
  /// **'Switch between the map and a list of the same results.'**
  String get tourMapToggleBody;

  /// No description provided for @tourStepsTitle.
  ///
  /// In en, this message translates to:
  /// **'Nine short steps'**
  String get tourStepsTitle;

  /// No description provided for @tourStepsBody.
  ///
  /// In en, this message translates to:
  /// **'Your progress is kept on this phone as you go, so you can stop and come back.'**
  String get tourStepsBody;

  /// No description provided for @tourOneThingTitle.
  ///
  /// In en, this message translates to:
  /// **'One thing at a time'**
  String get tourOneThingTitle;

  /// No description provided for @tourOneThingBody.
  ///
  /// In en, this message translates to:
  /// **'Only the city, the price and a title are required. Photos, a map pin and details make your listing stronger.'**
  String get tourOneThingBody;

  /// No description provided for @tourNextTitle.
  ///
  /// In en, this message translates to:
  /// **'Move on'**
  String get tourNextTitle;

  /// No description provided for @tourNextBody.
  ///
  /// In en, this message translates to:
  /// **'Next checks this step. At the end you review everything, then publish or save a draft.'**
  String get tourNextBody;

  /// No description provided for @tourCloseTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave any time'**
  String get tourCloseTitle;

  /// No description provided for @tourCloseBody.
  ///
  /// In en, this message translates to:
  /// **'Closing keeps your draft. Published listings appear in the app and on akarat.ai.'**
  String get tourCloseBody;

  /// No description provided for @guidesSection.
  ///
  /// In en, this message translates to:
  /// **'Guides'**
  String get guidesSection;

  /// No description provided for @guideFinding.
  ///
  /// In en, this message translates to:
  /// **'Finding a property'**
  String get guideFinding;

  /// No description provided for @guideMap.
  ///
  /// In en, this message translates to:
  /// **'Using the map'**
  String get guideMap;

  /// No description provided for @guideListing.
  ///
  /// In en, this message translates to:
  /// **'Listing a property'**
  String get guideListing;

  /// No description provided for @mapAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get mapAll;

  /// No description provided for @mapCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{None on the map} =1{1 on the map} other{{count} on the map}}'**
  String mapCount(num count);

  /// No description provided for @mapCluster.
  ///
  /// In en, this message translates to:
  /// **'{count} properties here. Tap to zoom in.'**
  String mapCluster(int count);

  /// No description provided for @mapNoLocation.
  ///
  /// In en, this message translates to:
  /// **'Not on the map'**
  String get mapNoLocation;

  /// No description provided for @a11yVoice.
  ///
  /// In en, this message translates to:
  /// **'Search by voice'**
  String get a11yVoice;

  /// No description provided for @voiceListening.
  ///
  /// In en, this message translates to:
  /// **'Listening…'**
  String get voiceListening;

  /// No description provided for @voiceStarting.
  ///
  /// In en, this message translates to:
  /// **'Getting the microphone ready…'**
  String get voiceStarting;

  /// No description provided for @voiceHint.
  ///
  /// In en, this message translates to:
  /// **'Say what you’re looking for, like “three bedrooms in Abdoun under 150 thousand”.'**
  String get voiceHint;

  /// No description provided for @voiceReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Is this right?'**
  String get voiceReviewTitle;

  /// No description provided for @voiceReviewBody.
  ///
  /// In en, this message translates to:
  /// **'Edit anything before searching.'**
  String get voiceReviewBody;

  /// No description provided for @voiceUnderstood.
  ///
  /// In en, this message translates to:
  /// **'Understood'**
  String get voiceUnderstood;

  /// No description provided for @voiceSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get voiceSearch;

  /// No description provided for @voiceRetry.
  ///
  /// In en, this message translates to:
  /// **'Speak again'**
  String get voiceRetry;

  /// No description provided for @voiceStop.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get voiceStop;

  /// No description provided for @voiceTypeInstead.
  ///
  /// In en, this message translates to:
  /// **'Type instead'**
  String get voiceTypeInstead;

  /// No description provided for @voiceDenied.
  ///
  /// In en, this message translates to:
  /// **'Microphone access is off. Allow it for Akarat.ai in your phone’s settings to search by voice.'**
  String get voiceDenied;

  /// No description provided for @voiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Voice search isn’t available on this device. You can type your search instead.'**
  String get voiceUnavailable;

  /// No description provided for @voiceNoArabic.
  ///
  /// In en, this message translates to:
  /// **'This device can’t recognise speech in this language yet. Try the other language, or type instead.'**
  String get voiceNoArabic;

  /// No description provided for @voiceNoSpeech.
  ///
  /// In en, this message translates to:
  /// **'I didn’t catch that.'**
  String get voiceNoSpeech;

  /// No description provided for @voiceNetwork.
  ///
  /// In en, this message translates to:
  /// **'Voice recognition needs a connection right now.'**
  String get voiceNetwork;

  /// No description provided for @voiceOther.
  ///
  /// In en, this message translates to:
  /// **'Voice search stopped unexpectedly.'**
  String get voiceOther;

  /// No description provided for @aiSpeakTitle.
  ///
  /// In en, this message translates to:
  /// **'Just say it'**
  String get aiSpeakTitle;

  /// No description provided for @aiSpeakBody.
  ///
  /// In en, this message translates to:
  /// **'Tap to search by voice, in English or Arabic.'**
  String get aiSpeakBody;

  /// No description provided for @aiUnder.
  ///
  /// In en, this message translates to:
  /// **'Under {amount}'**
  String aiUnder(Object amount);

  /// No description provided for @aiUpTo.
  ///
  /// In en, this message translates to:
  /// **'Up to {amount}'**
  String aiUpTo(Object amount);

  /// No description provided for @aiBedsPlus.
  ///
  /// In en, this message translates to:
  /// **'{count}+ beds'**
  String aiBedsPlus(int count);

  /// No description provided for @aiTryInstead.
  ///
  /// In en, this message translates to:
  /// **'Try instead'**
  String get aiTryInstead;

  /// No description provided for @aiAllOfCity.
  ///
  /// In en, this message translates to:
  /// **'All of {city}'**
  String aiAllOfCity(Object city);

  /// No description provided for @aiAnyType.
  ///
  /// In en, this message translates to:
  /// **'Any type'**
  String get aiAnyType;

  /// No description provided for @aiBothDeals.
  ///
  /// In en, this message translates to:
  /// **'Sale or rent'**
  String get aiBothDeals;

  /// No description provided for @aiFewerFeatures.
  ///
  /// In en, this message translates to:
  /// **'Fewer features'**
  String get aiFewerFeatures;

  /// No description provided for @aiFoundSummary.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Nothing on Akarat.ai matches all of that yet.} =1{I found 1 match on Akarat.ai.} other{I found {count} matches on Akarat.ai, closest first.}}'**
  String aiFoundSummary(num count);

  /// No description provided for @authAccountCreated.
  ///
  /// In en, this message translates to:
  /// **'Account created'**
  String get authAccountCreated;

  /// No description provided for @authAccountCreatedName.
  ///
  /// In en, this message translates to:
  /// **'Welcome, {name}. Your account is ready.'**
  String authAccountCreatedName(Object name);

  /// No description provided for @authWelcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get authWelcomeBack;

  /// No description provided for @authCheckEmailTitle.
  ///
  /// In en, this message translates to:
  /// **'Check your email'**
  String get authCheckEmailTitle;

  /// No description provided for @authCheckEmailBody.
  ///
  /// In en, this message translates to:
  /// **'Your account is created. We sent a confirmation link to {email}. Open it to confirm your address, then sign in here.'**
  String authCheckEmailBody(Object email);

  /// No description provided for @authCheckEmailSignIn.
  ///
  /// In en, this message translates to:
  /// **'I’ve confirmed — sign in'**
  String get authCheckEmailSignIn;

  /// No description provided for @authCheckEmailWrong.
  ///
  /// In en, this message translates to:
  /// **'Wrong address? Go back'**
  String get authCheckEmailWrong;

  /// No description provided for @homeLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get homeLocation;

  /// No description provided for @detailsFacilities.
  ///
  /// In en, this message translates to:
  /// **'Facilities'**
  String get detailsFacilities;

  /// No description provided for @navLogIn.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get navLogIn;

  /// No description provided for @actionUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get actionUndo;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get errorGeneric;

  /// No description provided for @errorNetwork.
  ///
  /// In en, this message translates to:
  /// **'You appear to be offline. Check your connection and try again.'**
  String get errorNetwork;

  /// No description provided for @errorTimeout.
  ///
  /// In en, this message translates to:
  /// **'The server took too long to answer. Try again.'**
  String get errorTimeout;

  /// No description provided for @errorNotFound.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find that.'**
  String get errorNotFound;

  /// No description provided for @errorRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many searches. Try again shortly.'**
  String get errorRateLimited;

  /// No description provided for @errorPermission.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to do that.'**
  String get errorPermission;

  /// No description provided for @errorSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Sign in again.'**
  String get errorSessionExpired;

  /// No description provided for @offlineBanner.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Showing what was already loaded.'**
  String get offlineBanner;

  /// No description provided for @notProvided.
  ///
  /// In en, this message translates to:
  /// **'Not provided'**
  String get notProvided;

  /// No description provided for @routeNotFound.
  ///
  /// In en, this message translates to:
  /// **'This page doesn\'t exist.'**
  String get routeNotFound;

  /// No description provided for @onboardingTitle1.
  ///
  /// In en, this message translates to:
  /// **'Property across Jordan, in one place'**
  String get onboardingTitle1;

  /// No description provided for @onboardingBody1.
  ///
  /// In en, this message translates to:
  /// **'Apartments in Abdoun, land in Madaba, chalets at the Dead Sea. Every listing here traces to a real record.'**
  String get onboardingBody1;

  /// No description provided for @onboardingTitle2.
  ///
  /// In en, this message translates to:
  /// **'Search the way you speak'**
  String get onboardingTitle2;

  /// No description provided for @onboardingBody2.
  ///
  /// In en, this message translates to:
  /// **'Write it in English or Arabic, the way you\'d say it. We read the budget, the area and the bedrooms, and show you why each result fits.'**
  String get onboardingBody2;

  /// No description provided for @onboardingTitle3.
  ///
  /// In en, this message translates to:
  /// **'Buy, rent, or list your own'**
  String get onboardingTitle3;

  /// No description provided for @onboardingBody3.
  ///
  /// In en, this message translates to:
  /// **'Save the places you like, send inquiries straight to owners, and publish a property in a few guided steps.'**
  String get onboardingBody3;

  /// No description provided for @onboardingLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get onboardingLanguage;

  /// No description provided for @homeGreeting.
  ///
  /// In en, this message translates to:
  /// **'Find your place in Jordan'**
  String get homeGreeting;

  /// No description provided for @homeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Search the usual way, or just say what you\'re looking for.'**
  String get homeSubtitle;

  /// No description provided for @homeSearchHint.
  ///
  /// In en, this message translates to:
  /// **'A four-bedroom villa in Abdoun with a garden'**
  String get homeSearchHint;

  /// No description provided for @homeSearchPrompt.
  ///
  /// In en, this message translates to:
  /// **'Search or describe it…'**
  String get homeSearchPrompt;

  /// No description provided for @homeAiCta.
  ///
  /// In en, this message translates to:
  /// **'Search with AI'**
  String get homeAiCta;

  /// No description provided for @homeFeatured.
  ///
  /// In en, this message translates to:
  /// **'Featured'**
  String get homeFeatured;

  /// No description provided for @homeRecent.
  ///
  /// In en, this message translates to:
  /// **'Recently listed'**
  String get homeRecent;

  /// No description provided for @homeCategories.
  ///
  /// In en, this message translates to:
  /// **'Browse by type'**
  String get homeCategories;

  /// No description provided for @homeCities.
  ///
  /// In en, this message translates to:
  /// **'Explore by city'**
  String get homeCities;

  /// No description provided for @homeListCtaTitle.
  ///
  /// In en, this message translates to:
  /// **'Own a property?'**
  String get homeListCtaTitle;

  /// No description provided for @homeListCtaBody.
  ///
  /// In en, this message translates to:
  /// **'List it in a few guided steps. Your inquiries and listings sit in one dashboard, on the app and the website.'**
  String get homeListCtaBody;

  /// No description provided for @homeListCtaButton.
  ///
  /// In en, this message translates to:
  /// **'List your property'**
  String get homeListCtaButton;

  /// No description provided for @homeEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'The marketplace is opening'**
  String get homeEmptyTitle;

  /// No description provided for @homeEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'No listings match here yet. Nothing is invented to fill the space — check back soon, or be the first to list.'**
  String get homeEmptyBody;

  /// No description provided for @locationAllJordan.
  ///
  /// In en, this message translates to:
  /// **'All of Jordan'**
  String get locationAllJordan;

  /// No description provided for @locationPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a city'**
  String get locationPickerTitle;

  /// No description provided for @dealSale.
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get dealSale;

  /// No description provided for @dealRent.
  ///
  /// In en, this message translates to:
  /// **'Rent'**
  String get dealRent;

  /// No description provided for @exploreTitle.
  ///
  /// In en, this message translates to:
  /// **'Explore'**
  String get exploreTitle;

  /// No description provided for @exploreResultsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No properties} =1{1 property} other{{count} properties}}'**
  String exploreResultsCount(int count);

  /// No description provided for @exploreFilters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get exploreFilters;

  /// No description provided for @exploreSort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get exploreSort;

  /// No description provided for @sortNewest.
  ///
  /// In en, this message translates to:
  /// **'Newest'**
  String get sortNewest;

  /// No description provided for @sortPriceLow.
  ///
  /// In en, this message translates to:
  /// **'Price: low to high'**
  String get sortPriceLow;

  /// No description provided for @sortPriceHigh.
  ///
  /// In en, this message translates to:
  /// **'Price: high to low'**
  String get sortPriceHigh;

  /// No description provided for @filterCity.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get filterCity;

  /// No description provided for @filterArea.
  ///
  /// In en, this message translates to:
  /// **'Area'**
  String get filterArea;

  /// No description provided for @filterAnyCity.
  ///
  /// In en, this message translates to:
  /// **'Any city'**
  String get filterAnyCity;

  /// No description provided for @filterAnyArea.
  ///
  /// In en, this message translates to:
  /// **'Any area'**
  String get filterAnyArea;

  /// No description provided for @filterType.
  ///
  /// In en, this message translates to:
  /// **'Property type'**
  String get filterType;

  /// No description provided for @filterAnyType.
  ///
  /// In en, this message translates to:
  /// **'Any type'**
  String get filterAnyType;

  /// No description provided for @filterBeds.
  ///
  /// In en, this message translates to:
  /// **'Bedrooms'**
  String get filterBeds;

  /// No description provided for @filterBaths.
  ///
  /// In en, this message translates to:
  /// **'Bathrooms'**
  String get filterBaths;

  /// No description provided for @filterAny.
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get filterAny;

  /// No description provided for @filterPrice.
  ///
  /// In en, this message translates to:
  /// **'Price (JOD)'**
  String get filterPrice;

  /// No description provided for @filterMin.
  ///
  /// In en, this message translates to:
  /// **'Min'**
  String get filterMin;

  /// No description provided for @filterMax.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get filterMax;

  /// No description provided for @filterSize.
  ///
  /// In en, this message translates to:
  /// **'Built area (m²)'**
  String get filterSize;

  /// No description provided for @filterAvailableOnly.
  ///
  /// In en, this message translates to:
  /// **'Hide sold and rented'**
  String get filterAvailableOnly;

  /// No description provided for @filterShowResults.
  ///
  /// In en, this message translates to:
  /// **'Show results'**
  String get filterShowResults;

  /// No description provided for @filterClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get filterClearAll;

  /// No description provided for @filterAmenitiesNote.
  ///
  /// In en, this message translates to:
  /// **'Features such as a garden or a pool are matched by AI Search, which reads every listing\'s details.'**
  String get filterAmenitiesNote;

  /// No description provided for @exploreNoResultsTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches these filters'**
  String get exploreNoResultsTitle;

  /// No description provided for @exploreNoResultsBody.
  ///
  /// In en, this message translates to:
  /// **'Try widening the area, or raising the budget.'**
  String get exploreNoResultsBody;

  /// No description provided for @exploreList.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get exploreList;

  /// No description provided for @exploreMap.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get exploreMap;

  /// No description provided for @exploreLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Loading more…'**
  String get exploreLoadMore;

  /// No description provided for @exploreEnd.
  ///
  /// In en, this message translates to:
  /// **'That\'s everything that matches.'**
  String get exploreEnd;

  /// No description provided for @mapApproximateNote.
  ///
  /// In en, this message translates to:
  /// **'Circles mark approximate locations the owner chose not to pin exactly.'**
  String get mapApproximateNote;

  /// No description provided for @mapNoPins.
  ///
  /// In en, this message translates to:
  /// **'None of the loaded listings has a map location yet.'**
  String get mapNoPins;

  /// No description provided for @badgeForSale.
  ///
  /// In en, this message translates to:
  /// **'For sale'**
  String get badgeForSale;

  /// No description provided for @badgeForRent.
  ///
  /// In en, this message translates to:
  /// **'For rent'**
  String get badgeForRent;

  /// No description provided for @badgeSold.
  ///
  /// In en, this message translates to:
  /// **'SOLD'**
  String get badgeSold;

  /// No description provided for @badgeRented.
  ///
  /// In en, this message translates to:
  /// **'RENTED'**
  String get badgeRented;

  /// No description provided for @badgeVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get badgeVerified;

  /// No description provided for @badgeFeatured.
  ///
  /// In en, this message translates to:
  /// **'Featured'**
  String get badgeFeatured;

  /// No description provided for @noPhotos.
  ///
  /// In en, this message translates to:
  /// **'No photos yet'**
  String get noPhotos;

  /// No description provided for @a11ySave.
  ///
  /// In en, this message translates to:
  /// **'Save property'**
  String get a11ySave;

  /// No description provided for @a11yUnsave.
  ///
  /// In en, this message translates to:
  /// **'Remove from saved'**
  String get a11yUnsave;

  /// No description provided for @a11yBeds.
  ///
  /// In en, this message translates to:
  /// **'{count} bedrooms'**
  String a11yBeds(int count);

  /// No description provided for @a11yBaths.
  ///
  /// In en, this message translates to:
  /// **'{count} bathrooms'**
  String a11yBaths(int count);

  /// No description provided for @aiTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Search'**
  String get aiTitle;

  /// No description provided for @aiKicker.
  ///
  /// In en, this message translates to:
  /// **'Property intelligence'**
  String get aiKicker;

  /// No description provided for @aiIdleTitle.
  ///
  /// In en, this message translates to:
  /// **'Tell us what you are looking for.'**
  String get aiIdleTitle;

  /// No description provided for @aiIdleBody.
  ///
  /// In en, this message translates to:
  /// **'Write it the way you would say it out loud. We pick out whether you are buying or renting, where, your budget, bedrooms, bathrooms and features, recognise Jordanian place names in either language, and search straight away.'**
  String get aiIdleBody;

  /// No description provided for @aiIdleBodyShort.
  ///
  /// In en, this message translates to:
  /// **'Describe it the way you’d say it, in English or Arabic. We read the area, budget, rooms and features, then show why each result fits.'**
  String get aiIdleBodyShort;

  /// No description provided for @aiRefineHintShort.
  ///
  /// In en, this message translates to:
  /// **'Refine, e.g. “only Abdoun”'**
  String get aiRefineHintShort;

  /// No description provided for @aiCoveragePartner.
  ///
  /// In en, this message translates to:
  /// **'Licensed partner feeds aren’t connected yet, so they weren’t part of this search.'**
  String get aiCoveragePartner;

  /// No description provided for @aiSharpen.
  ///
  /// In en, this message translates to:
  /// **'Sharpen it'**
  String get aiSharpen;

  /// No description provided for @aiInputHint.
  ///
  /// In en, this message translates to:
  /// **'Describe the property you want…'**
  String get aiInputHint;

  /// No description provided for @aiRefineHint.
  ///
  /// In en, this message translates to:
  /// **'Change your search. Try “only Abdoun” or “raise the budget to 900,000”'**
  String get aiRefineHint;

  /// No description provided for @aiTry.
  ///
  /// In en, this message translates to:
  /// **'Try'**
  String get aiTry;

  /// No description provided for @aiExample1.
  ///
  /// In en, this message translates to:
  /// **'Find me a 3-bedroom apartment in Abdoun under 150,000 JOD'**
  String get aiExample1;

  /// No description provided for @aiExample2.
  ///
  /// In en, this message translates to:
  /// **'Show me villas in Amman with a garden and parking'**
  String get aiExample2;

  /// No description provided for @aiExample3.
  ///
  /// In en, this message translates to:
  /// **'بدي شقة بعمان غرفتين وبسعر أقل من ٨٠ ألف دينار'**
  String get aiExample3;

  /// No description provided for @aiBrief.
  ///
  /// In en, this message translates to:
  /// **'Search brief'**
  String get aiBrief;

  /// No description provided for @aiBriefEmpty.
  ///
  /// In en, this message translates to:
  /// **'What you asked for shows up here as soon as we read it. You can edit any of it, and we never change it without saying so.'**
  String get aiBriefEmpty;

  /// No description provided for @aiReadingLive.
  ///
  /// In en, this message translates to:
  /// **'We read:'**
  String get aiReadingLive;

  /// No description provided for @aiWorking.
  ///
  /// In en, this message translates to:
  /// **'Working through your request…'**
  String get aiWorking;

  /// No description provided for @aiStageLang.
  ///
  /// In en, this message translates to:
  /// **'Language detection'**
  String get aiStageLang;

  /// No description provided for @aiStageParse.
  ///
  /// In en, this message translates to:
  /// **'Requirement extraction'**
  String get aiStageParse;

  /// No description provided for @aiStageLoc.
  ///
  /// In en, this message translates to:
  /// **'Location resolution'**
  String get aiStageLoc;

  /// No description provided for @aiStageInternal.
  ///
  /// In en, this message translates to:
  /// **'Marketplace search'**
  String get aiStageInternal;

  /// No description provided for @aiStageExternal.
  ///
  /// In en, this message translates to:
  /// **'External market search'**
  String get aiStageExternal;

  /// No description provided for @aiStageRank.
  ///
  /// In en, this message translates to:
  /// **'Deterministic ranking'**
  String get aiStageRank;

  /// No description provided for @aiResultsInternal.
  ///
  /// In en, this message translates to:
  /// **'On Akarat.ai'**
  String get aiResultsInternal;

  /// No description provided for @aiResultsExternal.
  ///
  /// In en, this message translates to:
  /// **'Indexed from other portals'**
  String get aiResultsExternal;

  /// No description provided for @aiResultsExternalNote.
  ///
  /// In en, this message translates to:
  /// **'Found on other Jordanian portals and indexed by our crawler. Availability is not confirmed — open the source to check.'**
  String get aiResultsExternalNote;

  /// No description provided for @aiMatch.
  ///
  /// In en, this message translates to:
  /// **'{score}% match'**
  String aiMatch(int score);

  /// No description provided for @aiWhyMatches.
  ///
  /// In en, this message translates to:
  /// **'Why this matches'**
  String get aiWhyMatches;

  /// No description provided for @aiNoMatchTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing in our inventory matches that yet.'**
  String get aiNoMatchTitle;

  /// No description provided for @aiNoMatchBody.
  ///
  /// In en, this message translates to:
  /// **'Try widening the area or raising the budget, or search the wider Jordanian market below.'**
  String get aiNoMatchBody;

  /// No description provided for @aiWiderMarket.
  ///
  /// In en, this message translates to:
  /// **'Wider Jordanian market'**
  String get aiWiderMarket;

  /// No description provided for @aiWiderBody.
  ///
  /// In en, this message translates to:
  /// **'We turn your brief into a real search on each Jordanian portal. These open their own filtered results, so the listings you see are theirs and current. Nothing here is copied or invented.'**
  String get aiWiderBody;

  /// No description provided for @aiOpensOutside.
  ///
  /// In en, this message translates to:
  /// **'Opens outside Akarat.ai'**
  String get aiOpensOutside;

  /// No description provided for @aiCoverageMissing.
  ///
  /// In en, this message translates to:
  /// **'Not searched this time: {sources}'**
  String aiCoverageMissing(String sources);

  /// No description provided for @aiServedDirect.
  ///
  /// In en, this message translates to:
  /// **'The search service didn\'t answer, so we searched the Akarat.ai database directly.'**
  String get aiServedDirect;

  /// No description provided for @aiMissingDeal.
  ///
  /// In en, this message translates to:
  /// **'Buying or renting? Say so and the ranking gets sharper.'**
  String get aiMissingDeal;

  /// No description provided for @aiMissingLocation.
  ///
  /// In en, this message translates to:
  /// **'Name a city or an area to narrow it down.'**
  String get aiMissingLocation;

  /// No description provided for @aiSaveSearch.
  ///
  /// In en, this message translates to:
  /// **'Save search'**
  String get aiSaveSearch;

  /// No description provided for @aiSearchSaved.
  ///
  /// In en, this message translates to:
  /// **'Search saved'**
  String get aiSearchSaved;

  /// No description provided for @aiStartOver.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get aiStartOver;

  /// No description provided for @aiExternalBadge.
  ///
  /// In en, this message translates to:
  /// **'Other portal'**
  String get aiExternalBadge;

  /// No description provided for @aiSourcesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 source} other{{count} sources}}'**
  String aiSourcesCount(int count);

  /// No description provided for @aiViewOnSource.
  ///
  /// In en, this message translates to:
  /// **'View on source'**
  String get aiViewOnSource;

  /// No description provided for @aiSaveSearchTitle.
  ///
  /// In en, this message translates to:
  /// **'Name this search'**
  String get aiSaveSearchTitle;

  /// No description provided for @aiSearchedFor.
  ///
  /// In en, this message translates to:
  /// **'You asked'**
  String get aiSearchedFor;

  /// No description provided for @chipBedsMin.
  ///
  /// In en, this message translates to:
  /// **'{count}+ bedrooms'**
  String chipBedsMin(int count);

  /// No description provided for @chipBathsMin.
  ///
  /// In en, this message translates to:
  /// **'{count}+ bathrooms'**
  String chipBathsMin(int count);

  /// No description provided for @chipBudgetMax.
  ///
  /// In en, this message translates to:
  /// **'Up to {price}'**
  String chipBudgetMax(String price);

  /// No description provided for @chipBudgetMin.
  ///
  /// In en, this message translates to:
  /// **'From {price}'**
  String chipBudgetMin(String price);

  /// No description provided for @chipAreaMin.
  ///
  /// In en, this message translates to:
  /// **'{area}+ m²'**
  String chipAreaMin(String area);

  /// No description provided for @chipOnlyAkarat.
  ///
  /// In en, this message translates to:
  /// **'Akarat.ai only'**
  String get chipOnlyAkarat;

  /// No description provided for @chipRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove {label}'**
  String chipRemove(String label);

  /// No description provided for @detailsSpecs.
  ///
  /// In en, this message translates to:
  /// **'Property details'**
  String get detailsSpecs;

  /// No description provided for @detailsAmenities.
  ///
  /// In en, this message translates to:
  /// **'Features and amenities'**
  String get detailsAmenities;

  /// No description provided for @detailsAbout.
  ///
  /// In en, this message translates to:
  /// **'About this property'**
  String get detailsAbout;

  /// No description provided for @detailsLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get detailsLocation;

  /// No description provided for @detailsReadMore.
  ///
  /// In en, this message translates to:
  /// **'Read more'**
  String get detailsReadMore;

  /// No description provided for @detailsReadLess.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get detailsReadLess;

  /// No description provided for @specType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get specType;

  /// No description provided for @specDeal.
  ///
  /// In en, this message translates to:
  /// **'Listing'**
  String get specDeal;

  /// No description provided for @specBeds.
  ///
  /// In en, this message translates to:
  /// **'Bedrooms'**
  String get specBeds;

  /// No description provided for @specBaths.
  ///
  /// In en, this message translates to:
  /// **'Bathrooms'**
  String get specBaths;

  /// No description provided for @specArea.
  ///
  /// In en, this message translates to:
  /// **'Built area'**
  String get specArea;

  /// No description provided for @specLand.
  ///
  /// In en, this message translates to:
  /// **'Land area'**
  String get specLand;

  /// No description provided for @specYear.
  ///
  /// In en, this message translates to:
  /// **'Year built'**
  String get specYear;

  /// No description provided for @specRef.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get specRef;

  /// No description provided for @detailsApproxLocation.
  ///
  /// In en, this message translates to:
  /// **'Approximate location, within about 300 m. The owner keeps the exact address private.'**
  String get detailsApproxLocation;

  /// No description provided for @detailsExactLocation.
  ///
  /// In en, this message translates to:
  /// **'Exact location published by the owner.'**
  String get detailsExactLocation;

  /// No description provided for @detailsOpenInMaps.
  ///
  /// In en, this message translates to:
  /// **'Open in Maps'**
  String get detailsOpenInMaps;

  /// No description provided for @detailsNoLocation.
  ///
  /// In en, this message translates to:
  /// **'The owner hasn\'t placed this property on the map.'**
  String get detailsNoLocation;

  /// No description provided for @detailsContact.
  ///
  /// In en, this message translates to:
  /// **'Interested in this property?'**
  String get detailsContact;

  /// No description provided for @detailsContactSub.
  ///
  /// In en, this message translates to:
  /// **'Contact the owner directly, or send an inquiry to their dashboard.'**
  String get detailsContactSub;

  /// No description provided for @detailsCall.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get detailsCall;

  /// No description provided for @detailsWhatsApp.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp'**
  String get detailsWhatsApp;

  /// No description provided for @detailsEnquire.
  ///
  /// In en, this message translates to:
  /// **'Send inquiry'**
  String get detailsEnquire;

  /// No description provided for @detailsCopyNumber.
  ///
  /// In en, this message translates to:
  /// **'Copy number'**
  String get detailsCopyNumber;

  /// No description provided for @detailsNumberCopied.
  ///
  /// In en, this message translates to:
  /// **'Number copied'**
  String get detailsNumberCopied;

  /// No description provided for @detailsNoPhone.
  ///
  /// In en, this message translates to:
  /// **'No phone number was published. Send an inquiry instead.'**
  String get detailsNoPhone;

  /// No description provided for @detailsVerifiedListing.
  ///
  /// In en, this message translates to:
  /// **'Verified listing'**
  String get detailsVerifiedListing;

  /// No description provided for @detailsOwnerListing.
  ///
  /// In en, this message translates to:
  /// **'Listed by the owner'**
  String get detailsOwnerListing;

  /// No description provided for @detailsClosedSold.
  ///
  /// In en, this message translates to:
  /// **'This property has been sold. It stays here so links to it keep working.'**
  String get detailsClosedSold;

  /// No description provided for @detailsClosedRented.
  ///
  /// In en, this message translates to:
  /// **'This property has been rented. It stays here so links to it keep working.'**
  String get detailsClosedRented;

  /// No description provided for @detailsSimilar.
  ///
  /// In en, this message translates to:
  /// **'Similar properties'**
  String get detailsSimilar;

  /// No description provided for @detailsSimilarTurn.
  ///
  /// In en, this message translates to:
  /// **'Like “{title}”'**
  String detailsSimilarTurn(Object title);

  /// No description provided for @detailsFindSimilar.
  ///
  /// In en, this message translates to:
  /// **'Search for similar'**
  String get detailsFindSimilar;

  /// No description provided for @detailsNotFound.
  ///
  /// In en, this message translates to:
  /// **'This listing is no longer available.'**
  String get detailsNotFound;

  /// No description provided for @detailsListedOn.
  ///
  /// In en, this message translates to:
  /// **'Listed {date}'**
  String detailsListedOn(String date);

  /// No description provided for @detailsUpdatedOn.
  ///
  /// In en, this message translates to:
  /// **'Updated {date}'**
  String detailsUpdatedOn(String date);

  /// No description provided for @detailsMediaPosition.
  ///
  /// In en, this message translates to:
  /// **'{index} of {total}'**
  String detailsMediaPosition(int index, int total);

  /// No description provided for @detailsVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get detailsVideo;

  /// No description provided for @detailsYourListing.
  ///
  /// In en, this message translates to:
  /// **'This is your listing'**
  String get detailsYourListing;

  /// No description provided for @detailsManage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get detailsManage;

  /// No description provided for @inquiryTitle.
  ///
  /// In en, this message translates to:
  /// **'Send an inquiry'**
  String get inquiryTitle;

  /// No description provided for @inquiryBody.
  ///
  /// In en, this message translates to:
  /// **'Your message goes straight to the owner\'s dashboard on Akarat.ai.'**
  String get inquiryBody;

  /// No description provided for @inquiryName.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get inquiryName;

  /// No description provided for @inquiryEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get inquiryEmail;

  /// No description provided for @inquiryPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get inquiryPhone;

  /// No description provided for @inquiryMessage.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get inquiryMessage;

  /// No description provided for @inquiryDefaultMessage.
  ///
  /// In en, this message translates to:
  /// **'Hello, I\'m interested in “{title}”. Is it still available?'**
  String inquiryDefaultMessage(String title);

  /// No description provided for @inquirySend.
  ///
  /// In en, this message translates to:
  /// **'Send inquiry'**
  String get inquirySend;

  /// No description provided for @inquirySending.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get inquirySending;

  /// No description provided for @inquirySent.
  ///
  /// In en, this message translates to:
  /// **'Sent. The owner will see it in their dashboard.'**
  String get inquirySent;

  /// No description provided for @inquiryNeedContact.
  ///
  /// In en, this message translates to:
  /// **'Add an email or a phone number so the owner can reply.'**
  String get inquiryNeedContact;

  /// No description provided for @inquiryClosed.
  ///
  /// In en, this message translates to:
  /// **'This listing is no longer taking inquiries.'**
  String get inquiryClosed;

  /// No description provided for @validationRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get validationRequired;

  /// No description provided for @validationEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address'**
  String get validationEmail;

  /// No description provided for @validationPhone.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid phone number'**
  String get validationPhone;

  /// No description provided for @validationPasswordShort.
  ///
  /// In en, this message translates to:
  /// **'Use at least {count} characters'**
  String validationPasswordShort(int count);

  /// No description provided for @validationNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a whole number'**
  String get validationNumber;

  /// No description provided for @validationPositive.
  ///
  /// In en, this message translates to:
  /// **'Must be greater than zero'**
  String get validationPositive;

  /// No description provided for @validationYear.
  ///
  /// In en, this message translates to:
  /// **'Enter a year between 1900 and {max}'**
  String validationYear(int max);

  /// No description provided for @authSignInTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get authSignInTitle;

  /// No description provided for @authSignInBody.
  ///
  /// In en, this message translates to:
  /// **'Sign in with the same account you use on akarat.ai.'**
  String get authSignInBody;

  /// No description provided for @authSignUpTitle.
  ///
  /// In en, this message translates to:
  /// **'Create your account'**
  String get authSignUpTitle;

  /// No description provided for @authSignUpBody.
  ///
  /// In en, this message translates to:
  /// **'One account to list a property, track inquiries and save searches — on the app and the website.'**
  String get authSignUpBody;

  /// No description provided for @fieldName.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get fieldName;

  /// No description provided for @fieldEmail.
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get fieldEmail;

  /// No description provided for @fieldPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get fieldPassword;

  /// No description provided for @fieldNewPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get fieldNewPassword;

  /// No description provided for @authForgot.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get authForgot;

  /// No description provided for @authForgotTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset your password'**
  String get authForgotTitle;

  /// No description provided for @authForgotBody.
  ///
  /// In en, this message translates to:
  /// **'Enter the email you signed up with and we will send you a link to choose a new password.'**
  String get authForgotBody;

  /// No description provided for @authSendLink.
  ///
  /// In en, this message translates to:
  /// **'Send reset link'**
  String get authSendLink;

  /// No description provided for @authResetSent.
  ///
  /// In en, this message translates to:
  /// **'If an account exists for that email, a reset link is on its way. Check your inbox.'**
  String get authResetSent;

  /// No description provided for @authResetTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a new password'**
  String get authResetTitle;

  /// No description provided for @authResetBody.
  ///
  /// In en, this message translates to:
  /// **'Enter a new password for your account. Use at least 6 characters.'**
  String get authResetBody;

  /// No description provided for @authSavePassword.
  ///
  /// In en, this message translates to:
  /// **'Save password'**
  String get authSavePassword;

  /// No description provided for @authPasswordUpdated.
  ///
  /// In en, this message translates to:
  /// **'Password updated.'**
  String get authPasswordUpdated;

  /// No description provided for @authAgreement.
  ///
  /// In en, this message translates to:
  /// **'By creating an account, you agree to the {terms} and {privacy}.'**
  String authAgreement(String terms, String privacy);

  /// No description provided for @authCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authCreateAccount;

  /// No description provided for @authHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Sign in'**
  String get authHaveAccount;

  /// No description provided for @authNoAccount.
  ///
  /// In en, this message translates to:
  /// **'New here? Create an account'**
  String get authNoAccount;

  /// No description provided for @authGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get authGoogle;

  /// No description provided for @authOr.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get authOr;

  /// No description provided for @authCheckEmail.
  ///
  /// In en, this message translates to:
  /// **'Account created. Check your email to confirm the address, then sign in.'**
  String get authCheckEmail;

  /// No description provided for @authRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to continue'**
  String get authRequiredTitle;

  /// No description provided for @authRequiredBody.
  ///
  /// In en, this message translates to:
  /// **'You need an account to list a property, see your inquiries and keep saved searches.'**
  String get authRequiredBody;

  /// No description provided for @authGoogleDisabled.
  ///
  /// In en, this message translates to:
  /// **'Google sign-in is not switched on yet. Use your email and password.'**
  String get authGoogleDisabled;

  /// No description provided for @authInvalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'That email and password don\'t match an account.'**
  String get authInvalidCredentials;

  /// No description provided for @authEmailNotConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirm your email address first. Check your inbox for the link.'**
  String get authEmailNotConfirmed;

  /// No description provided for @authUserExists.
  ///
  /// In en, this message translates to:
  /// **'An account with this email already exists. Sign in instead.'**
  String get authUserExists;

  /// No description provided for @authWeakPassword.
  ///
  /// In en, this message translates to:
  /// **'Choose a stronger password.'**
  String get authWeakPassword;

  /// No description provided for @authLinkExpired.
  ///
  /// In en, this message translates to:
  /// **'That link has expired or was already used. Ask for a new one.'**
  String get authLinkExpired;

  /// No description provided for @authCallbackWorking.
  ///
  /// In en, this message translates to:
  /// **'Signing you in…'**
  String get authCallbackWorking;

  /// No description provided for @authShowPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get authShowPassword;

  /// No description provided for @authHidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get authHidePassword;

  /// No description provided for @authPhoneButton.
  ///
  /// In en, this message translates to:
  /// **'Continue with a phone number'**
  String get authPhoneButton;

  /// No description provided for @authPhoneSignUpButton.
  ///
  /// In en, this message translates to:
  /// **'Sign up with a phone number'**
  String get authPhoneSignUpButton;

  /// No description provided for @authPhoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in with your phone'**
  String get authPhoneTitle;

  /// No description provided for @authPhoneBody.
  ///
  /// In en, this message translates to:
  /// **'Choose your country and enter your number. We’ll send you a code to sign in — no password needed.'**
  String get authPhoneBody;

  /// No description provided for @authPhoneSignUpTitle.
  ///
  /// In en, this message translates to:
  /// **'Create an account with your phone'**
  String get authPhoneSignUpTitle;

  /// No description provided for @authPhoneSignUpBody.
  ///
  /// In en, this message translates to:
  /// **'Enter your name and number. We’ll send a code to confirm the number is yours.'**
  String get authPhoneSignUpBody;

  /// No description provided for @authPhoneLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Add a phone number'**
  String get authPhoneLinkTitle;

  /// No description provided for @authPhoneChangeTitle.
  ///
  /// In en, this message translates to:
  /// **'Change your phone number'**
  String get authPhoneChangeTitle;

  /// No description provided for @authPhoneLinkBody.
  ///
  /// In en, this message translates to:
  /// **'Sign in with a code sent to your phone instead of your password. We’ll send a code to confirm the number is yours.'**
  String get authPhoneLinkBody;

  /// No description provided for @authPhoneEmailNote.
  ///
  /// In en, this message translates to:
  /// **'Signed up with email? Sign in with it, then add your number in Profile to sign in by phone next time.'**
  String get authPhoneEmailNote;

  /// No description provided for @authPhoneSignUpNote.
  ///
  /// In en, this message translates to:
  /// **'Already have an account with email? Don’t make a second one: sign in, then add your number in Profile.'**
  String get authPhoneSignUpNote;

  /// No description provided for @authPhoneCreateInstead.
  ///
  /// In en, this message translates to:
  /// **'Create an account with this number'**
  String get authPhoneCreateInstead;

  /// No description provided for @authUseEmail.
  ///
  /// In en, this message translates to:
  /// **'Use email instead'**
  String get authUseEmail;

  /// No description provided for @fieldCountry.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get fieldCountry;

  /// No description provided for @fieldPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get fieldPhoneNumber;

  /// No description provided for @fieldCode.
  ///
  /// In en, this message translates to:
  /// **'Verification code'**
  String get fieldCode;

  /// No description provided for @authPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the {digits}-digit number after +{dial}, without the leading zero.'**
  String authPhoneHint(String digits, String dial);

  /// No description provided for @authPhoneCountryA11y.
  ///
  /// In en, this message translates to:
  /// **'Country code: {country}, +{dial}'**
  String authPhoneCountryA11y(String country, String dial);

  /// No description provided for @authSendCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get authSendCode;

  /// No description provided for @authSending.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get authSending;

  /// No description provided for @authCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your code'**
  String get authCodeTitle;

  /// No description provided for @authCodeBodySms.
  ///
  /// In en, this message translates to:
  /// **'We sent a 6-digit code by text message. Use it soon: it expires quickly.'**
  String get authCodeBodySms;

  /// No description provided for @authCodeBodyWhatsapp.
  ///
  /// In en, this message translates to:
  /// **'We sent a 6-digit code on WhatsApp. Use it soon: it expires quickly.'**
  String get authCodeBodyWhatsapp;

  /// No description provided for @authCodeSentTo.
  ///
  /// In en, this message translates to:
  /// **'Sent to'**
  String get authCodeSentTo;

  /// No description provided for @authChangeNumber.
  ///
  /// In en, this message translates to:
  /// **'Change number'**
  String get authChangeNumber;

  /// No description provided for @authVerifySignIn.
  ///
  /// In en, this message translates to:
  /// **'Verify and sign in'**
  String get authVerifySignIn;

  /// No description provided for @authVerifySignUp.
  ///
  /// In en, this message translates to:
  /// **'Verify and create account'**
  String get authVerifySignUp;

  /// No description provided for @authVerifyLink.
  ///
  /// In en, this message translates to:
  /// **'Verify and add number'**
  String get authVerifyLink;

  /// No description provided for @authVerifying.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get authVerifying;

  /// No description provided for @authResend.
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get authResend;

  /// No description provided for @authResendIn.
  ///
  /// In en, this message translates to:
  /// **'Resend code in {seconds}s'**
  String authResendIn(int seconds);

  /// No description provided for @authCodeResent.
  ///
  /// In en, this message translates to:
  /// **'A new code is on its way.'**
  String get authCodeResent;

  /// No description provided for @authCodeIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code you were sent.'**
  String get authCodeIncomplete;

  /// No description provided for @authCodeWrong.
  ///
  /// In en, this message translates to:
  /// **'That code is wrong or has expired. Check it, or ask for a new one.'**
  String get authCodeWrong;

  /// No description provided for @authCodeSendFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn’t send a code to that number. Check it and try again.'**
  String get authCodeSendFailed;

  /// No description provided for @authCodeTooMany.
  ///
  /// In en, this message translates to:
  /// **'Too many codes asked for. Wait a few minutes, then try again.'**
  String get authCodeTooMany;

  /// No description provided for @authPhoneNoAccount.
  ///
  /// In en, this message translates to:
  /// **'No account uses this number yet. If you signed up with email, sign in with it and add your number in Profile.'**
  String get authPhoneNoAccount;

  /// No description provided for @authPhoneTaken.
  ///
  /// In en, this message translates to:
  /// **'That number is already used by another account.'**
  String get authPhoneTaken;

  /// No description provided for @authPhoneInvalid.
  ///
  /// In en, this message translates to:
  /// **'That doesn’t look like a phone number. Check it and try again.'**
  String get authPhoneInvalid;

  /// No description provided for @authPhoneUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Phone sign-in isn’t available right now. Use your email instead.'**
  String get authPhoneUnavailable;

  /// No description provided for @authPhoneLinked.
  ///
  /// In en, this message translates to:
  /// **'Number added. You can sign in with it now.'**
  String get authPhoneLinked;

  /// No description provided for @profileSignInPhone.
  ///
  /// In en, this message translates to:
  /// **'Sign-in phone number'**
  String get profileSignInPhone;

  /// No description provided for @profileSignInPhoneNone.
  ///
  /// In en, this message translates to:
  /// **'Add one to sign in with a code'**
  String get profileSignInPhoneNone;

  /// No description provided for @authFacebook.
  ///
  /// In en, this message translates to:
  /// **'Continue with Facebook'**
  String get authFacebook;

  /// No description provided for @authFacebookDisabled.
  ///
  /// In en, this message translates to:
  /// **'Facebook sign-in isn’t switched on yet. Use your email or phone for now.'**
  String get authFacebookDisabled;

  /// No description provided for @authCancelled.
  ///
  /// In en, this message translates to:
  /// **'Sign-in was cancelled. Nothing was changed.'**
  String get authCancelled;

  /// No description provided for @authCallbackFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'That didn’t go through'**
  String get authCallbackFailedTitle;

  /// No description provided for @authBackToProfile.
  ///
  /// In en, this message translates to:
  /// **'Back to profile'**
  String get authBackToProfile;

  /// No description provided for @profileFacebook.
  ///
  /// In en, this message translates to:
  /// **'Facebook'**
  String get profileFacebook;

  /// No description provided for @profileFacebookConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect it to sign in with Facebook'**
  String get profileFacebookConnect;

  /// No description provided for @profileFacebookConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected: you can sign in with Facebook'**
  String get profileFacebookConnected;

  /// No description provided for @profileFacebookOnly.
  ///
  /// In en, this message translates to:
  /// **'Connected: the way this account signs in'**
  String get profileFacebookOnly;

  /// No description provided for @facebookConnected.
  ///
  /// In en, this message translates to:
  /// **'Facebook connected. You can sign in with it now.'**
  String get facebookConnected;

  /// No description provided for @facebookDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get facebookDisconnect;

  /// No description provided for @facebookDisconnectTitle.
  ///
  /// In en, this message translates to:
  /// **'Disconnect Facebook?'**
  String get facebookDisconnectTitle;

  /// No description provided for @facebookDisconnectBody.
  ///
  /// In en, this message translates to:
  /// **'You won’t be able to sign in with Facebook any more. Your account, listings and saved homes stay as they are.'**
  String get facebookDisconnectBody;

  /// No description provided for @facebookDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Facebook disconnected'**
  String get facebookDisconnected;

  /// No description provided for @facebookLinkDisabled.
  ///
  /// In en, this message translates to:
  /// **'Connecting accounts isn’t switched on yet. Try again later.'**
  String get facebookLinkDisabled;

  /// No description provided for @facebookTaken.
  ///
  /// In en, this message translates to:
  /// **'That Facebook account already belongs to another Akarat.ai account. Sign in with Facebook to use that one.'**
  String get facebookTaken;

  /// No description provided for @facebookOnlyWayIn.
  ///
  /// In en, this message translates to:
  /// **'Facebook is how this account signs in. Add a phone number first, then you can disconnect it.'**
  String get facebookOnlyWayIn;

  /// No description provided for @savedTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get savedTitle;

  /// No description provided for @savedProperties.
  ///
  /// In en, this message translates to:
  /// **'Properties'**
  String get savedProperties;

  /// No description provided for @savedSearches.
  ///
  /// In en, this message translates to:
  /// **'Searches'**
  String get savedSearches;

  /// No description provided for @savedEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing saved yet'**
  String get savedEmptyTitle;

  /// No description provided for @savedEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Tap the heart on any property to keep it here.'**
  String get savedEmptyBody;

  /// No description provided for @savedSearchesEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No saved searches'**
  String get savedSearchesEmptyTitle;

  /// No description provided for @savedSearchesEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Run an AI search, then save it to come back to it any time.'**
  String get savedSearchesEmptyBody;

  /// No description provided for @savedSearchesSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in to keep searches with your account.'**
  String get savedSearchesSignIn;

  /// No description provided for @savedDeviceOnly.
  ///
  /// In en, this message translates to:
  /// **'Saved on this device. Sign in to keep them with your account.'**
  String get savedDeviceOnly;

  /// No description provided for @savedSyncUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Your account can\'t store saved properties yet, so these are kept on this device.'**
  String get savedSyncUnavailable;

  /// No description provided for @savedRemoved.
  ///
  /// In en, this message translates to:
  /// **'Removed from saved'**
  String get savedRemoved;

  /// No description provided for @savedAdded.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get savedAdded;

  /// No description provided for @savedSearchRun.
  ///
  /// In en, this message translates to:
  /// **'Search again'**
  String get savedSearchRun;

  /// No description provided for @savedSearchDeleted.
  ///
  /// In en, this message translates to:
  /// **'Search removed'**
  String get savedSearchDeleted;

  /// No description provided for @savedListingGone.
  ///
  /// In en, this message translates to:
  /// **'No longer available'**
  String get savedListingGone;

  /// No description provided for @listingNewTitle.
  ///
  /// In en, this message translates to:
  /// **'List your property'**
  String get listingNewTitle;

  /// No description provided for @listingEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit listing'**
  String get listingEditTitle;

  /// No description provided for @stepOf.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String stepOf(int current, int total);

  /// No description provided for @stepPurpose.
  ///
  /// In en, this message translates to:
  /// **'What are you listing?'**
  String get stepPurpose;

  /// No description provided for @stepType.
  ///
  /// In en, this message translates to:
  /// **'What kind of property?'**
  String get stepType;

  /// No description provided for @stepLocation.
  ///
  /// In en, this message translates to:
  /// **'Where is it?'**
  String get stepLocation;

  /// No description provided for @stepDetails.
  ///
  /// In en, this message translates to:
  /// **'The details'**
  String get stepDetails;

  /// No description provided for @stepPrice.
  ///
  /// In en, this message translates to:
  /// **'Price and contact'**
  String get stepPrice;

  /// No description provided for @stepAmenities.
  ///
  /// In en, this message translates to:
  /// **'Features'**
  String get stepAmenities;

  /// No description provided for @stepDescription.
  ///
  /// In en, this message translates to:
  /// **'Title and description'**
  String get stepDescription;

  /// No description provided for @stepMedia.
  ///
  /// In en, this message translates to:
  /// **'Photos and video'**
  String get stepMedia;

  /// No description provided for @stepPreview.
  ///
  /// In en, this message translates to:
  /// **'Review and publish'**
  String get stepPreview;

  /// No description provided for @purposeSale.
  ///
  /// In en, this message translates to:
  /// **'For sale'**
  String get purposeSale;

  /// No description provided for @purposeSaleBody.
  ///
  /// In en, this message translates to:
  /// **'Sell the property outright.'**
  String get purposeSaleBody;

  /// No description provided for @purposeRent.
  ///
  /// In en, this message translates to:
  /// **'For rent'**
  String get purposeRent;

  /// No description provided for @purposeRentBody.
  ///
  /// In en, this message translates to:
  /// **'Let it out monthly.'**
  String get purposeRentBody;

  /// No description provided for @fieldCity.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get fieldCity;

  /// No description provided for @fieldNeighborhood.
  ///
  /// In en, this message translates to:
  /// **'Area'**
  String get fieldNeighborhood;

  /// No description provided for @fieldNeighborhoodNone.
  ///
  /// In en, this message translates to:
  /// **'Other / not listed'**
  String get fieldNeighborhoodNone;

  /// No description provided for @fieldAddress.
  ///
  /// In en, this message translates to:
  /// **'Street address (optional)'**
  String get fieldAddress;

  /// No description provided for @fieldAddressHelp.
  ///
  /// In en, this message translates to:
  /// **'Published only if you choose to show the exact pin.'**
  String get fieldAddressHelp;

  /// No description provided for @locationPinTitle.
  ///
  /// In en, this message translates to:
  /// **'Pin it on the map'**
  String get locationPinTitle;

  /// No description provided for @locationPinBody.
  ///
  /// In en, this message translates to:
  /// **'Optional. Tap the map to drop the pin on the building. The city and area follow it.'**
  String get locationPinBody;

  /// No description provided for @locationPinPlace.
  ///
  /// In en, this message translates to:
  /// **'Place a pin'**
  String get locationPinPlace;

  /// No description provided for @locationPinEdit.
  ///
  /// In en, this message translates to:
  /// **'Move the pin'**
  String get locationPinEdit;

  /// No description provided for @locationPinRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove pin'**
  String get locationPinRemove;

  /// No description provided for @locationPinNone.
  ///
  /// In en, this message translates to:
  /// **'No pin placed yet'**
  String get locationPinNone;

  /// No description provided for @locationPinSnapped.
  ///
  /// In en, this message translates to:
  /// **'Area set from the pin'**
  String get locationPinSnapped;

  /// No description provided for @precisionTitle.
  ///
  /// In en, this message translates to:
  /// **'What buyers see'**
  String get precisionTitle;

  /// No description provided for @precisionApprox.
  ///
  /// In en, this message translates to:
  /// **'Approximate circle'**
  String get precisionApprox;

  /// No description provided for @precisionApproxNote.
  ///
  /// In en, this message translates to:
  /// **'Publishes a point up to 300 m away. The exact address stays yours alone.'**
  String get precisionApproxNote;

  /// No description provided for @precisionExact.
  ///
  /// In en, this message translates to:
  /// **'Exact pin'**
  String get precisionExact;

  /// No description provided for @precisionExactNote.
  ///
  /// In en, this message translates to:
  /// **'Publishes the pin and the address exactly as you set them.'**
  String get precisionExactNote;

  /// No description provided for @locationMapsOff.
  ///
  /// In en, this message translates to:
  /// **'Map pins aren\'t enabled in this build. The city and area are enough to publish.'**
  String get locationMapsOff;

  /// No description provided for @fieldBedrooms.
  ///
  /// In en, this message translates to:
  /// **'Bedrooms'**
  String get fieldBedrooms;

  /// No description provided for @fieldBathrooms.
  ///
  /// In en, this message translates to:
  /// **'Bathrooms'**
  String get fieldBathrooms;

  /// No description provided for @fieldAreaSqm.
  ///
  /// In en, this message translates to:
  /// **'Built area (m²)'**
  String get fieldAreaSqm;

  /// No description provided for @fieldLandSqm.
  ///
  /// In en, this message translates to:
  /// **'Land area (m²)'**
  String get fieldLandSqm;

  /// No description provided for @fieldYearBuilt.
  ///
  /// In en, this message translates to:
  /// **'Year built'**
  String get fieldYearBuilt;

  /// No description provided for @fieldPrice.
  ///
  /// In en, this message translates to:
  /// **'Price (JOD)'**
  String get fieldPrice;

  /// No description provided for @fieldPriceRent.
  ///
  /// In en, this message translates to:
  /// **'Monthly rent (JOD)'**
  String get fieldPriceRent;

  /// No description provided for @fieldContactPhone.
  ///
  /// In en, this message translates to:
  /// **'Contact phone'**
  String get fieldContactPhone;

  /// No description provided for @fieldContactPhoneHelp.
  ///
  /// In en, this message translates to:
  /// **'Shown on the listing so people can call you or message you on WhatsApp.'**
  String get fieldContactPhoneHelp;

  /// No description provided for @fieldTitleEn.
  ///
  /// In en, this message translates to:
  /// **'Title in English'**
  String get fieldTitleEn;

  /// No description provided for @fieldTitleAr.
  ///
  /// In en, this message translates to:
  /// **'Title in Arabic'**
  String get fieldTitleAr;

  /// No description provided for @fieldTitleHelp.
  ///
  /// In en, this message translates to:
  /// **'Add at least one. The other language shows this one until you add it.'**
  String get fieldTitleHelp;

  /// No description provided for @fieldDescEn.
  ///
  /// In en, this message translates to:
  /// **'Description in English'**
  String get fieldDescEn;

  /// No description provided for @fieldDescAr.
  ///
  /// In en, this message translates to:
  /// **'Description in Arabic'**
  String get fieldDescAr;

  /// No description provided for @mediaAddPhotos.
  ///
  /// In en, this message translates to:
  /// **'Add photos'**
  String get mediaAddPhotos;

  /// No description provided for @mediaAddVideo.
  ///
  /// In en, this message translates to:
  /// **'Add video'**
  String get mediaAddVideo;

  /// No description provided for @mediaHelp.
  ///
  /// In en, this message translates to:
  /// **'Up to 8 files, including up to 2 video clips. Photos are resized before they upload. The first photo is the cover — drag to reorder.'**
  String get mediaHelp;

  /// No description provided for @mediaCover.
  ///
  /// In en, this message translates to:
  /// **'Cover'**
  String get mediaCover;

  /// No description provided for @mediaTooMany.
  ///
  /// In en, this message translates to:
  /// **'Eight files is the maximum.'**
  String get mediaTooMany;

  /// No description provided for @mediaTooManyVideos.
  ///
  /// In en, this message translates to:
  /// **'Two video clips is the maximum.'**
  String get mediaTooManyVideos;

  /// No description provided for @mediaTooLarge.
  ///
  /// In en, this message translates to:
  /// **'{name} is larger than {size} MB.'**
  String mediaTooLarge(String name, int size);

  /// No description provided for @mediaUnsupported.
  ///
  /// In en, this message translates to:
  /// **'{name} isn\'t a supported format.'**
  String mediaUnsupported(String name);

  /// No description provided for @mediaUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading file {done} of {total}'**
  String mediaUploading(int done, int total);

  /// No description provided for @mediaUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'A file didn\'t upload, so nothing was saved yet. Check your connection and try again — files that already uploaded won\'t be sent twice.'**
  String get mediaUploadFailed;

  /// No description provided for @mediaRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get mediaRemove;

  /// No description provided for @previewPublish.
  ///
  /// In en, this message translates to:
  /// **'Publish listing'**
  String get previewPublish;

  /// No description provided for @previewSaveDraft.
  ///
  /// In en, this message translates to:
  /// **'Save as draft'**
  String get previewSaveDraft;

  /// No description provided for @previewSaveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get previewSaveChanges;

  /// No description provided for @previewWorking.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get previewWorking;

  /// No description provided for @previewDraftNote.
  ///
  /// In en, this message translates to:
  /// **'A draft is saved to your account but hidden from everyone else until you publish it.'**
  String get previewDraftNote;

  /// No description provided for @publishSuccess.
  ///
  /// In en, this message translates to:
  /// **'Your listing is live.'**
  String get publishSuccess;

  /// No description provided for @draftSuccess.
  ///
  /// In en, this message translates to:
  /// **'Saved as a draft. Publish it from My listings.'**
  String get draftSuccess;

  /// No description provided for @editSuccess.
  ///
  /// In en, this message translates to:
  /// **'Changes saved.'**
  String get editSuccess;

  /// No description provided for @listingMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'Add a title in English or Arabic.'**
  String get listingMissingTitle;

  /// No description provided for @listingMissingPrice.
  ///
  /// In en, this message translates to:
  /// **'Add the price.'**
  String get listingMissingPrice;

  /// No description provided for @listingMissingCity.
  ///
  /// In en, this message translates to:
  /// **'Choose the city.'**
  String get listingMissingCity;

  /// No description provided for @listingDraftRestored.
  ///
  /// In en, this message translates to:
  /// **'We kept your unfinished listing.'**
  String get listingDraftRestored;

  /// No description provided for @listingDraftDiscard.
  ///
  /// In en, this message translates to:
  /// **'Start over'**
  String get listingDraftDiscard;

  /// No description provided for @listingLeaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave this listing?'**
  String get listingLeaveTitle;

  /// No description provided for @listingLeaveBody.
  ///
  /// In en, this message translates to:
  /// **'Your progress is kept on this device, so you can carry on later.'**
  String get listingLeaveBody;

  /// No description provided for @listingLeaveEditBody.
  ///
  /// In en, this message translates to:
  /// **'Changes you haven’t saved will be lost.'**
  String get listingLeaveEditBody;

  /// No description provided for @listingLeaveStay.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get listingLeaveStay;

  /// No description provided for @listingLeaveGo.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get listingLeaveGo;

  /// No description provided for @errorUnknownArea.
  ///
  /// In en, this message translates to:
  /// **'This area is not set up in the database yet. Choose another area, or “Other”, and try again.'**
  String get errorUnknownArea;

  /// No description provided for @errorGeoColumns.
  ///
  /// In en, this message translates to:
  /// **'Location pins aren\'t set up on the server yet. Remove the pin and try again.'**
  String get errorGeoColumns;

  /// No description provided for @errorStorageMissing.
  ///
  /// In en, this message translates to:
  /// **'Photo storage isn\'t set up on the server yet. Remove the files and publish without them, or try later.'**
  String get errorStorageMissing;

  /// No description provided for @dashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'My listings'**
  String get dashboardTitle;

  /// No description provided for @dashStatListings.
  ///
  /// In en, this message translates to:
  /// **'Listings'**
  String get dashStatListings;

  /// No description provided for @dashStatLive.
  ///
  /// In en, this message translates to:
  /// **'Live now'**
  String get dashStatLive;

  /// No description provided for @dashStatHidden.
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get dashStatHidden;

  /// No description provided for @dashStatInquiries.
  ///
  /// In en, this message translates to:
  /// **'Inquiries'**
  String get dashStatInquiries;

  /// No description provided for @statusDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get statusDraft;

  /// No description provided for @statusPending.
  ///
  /// In en, this message translates to:
  /// **'In review'**
  String get statusPending;

  /// No description provided for @statusActive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get statusActive;

  /// No description provided for @statusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get statusRejected;

  /// No description provided for @statusPaused.
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get statusPaused;

  /// No description provided for @statusSold.
  ///
  /// In en, this message translates to:
  /// **'Sold'**
  String get statusSold;

  /// No description provided for @statusRented.
  ///
  /// In en, this message translates to:
  /// **'Rented'**
  String get statusRented;

  /// No description provided for @statusArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get statusArchived;

  /// No description provided for @actionHide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get actionHide;

  /// No description provided for @actionPublish.
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get actionPublish;

  /// No description provided for @actionMarkSold.
  ///
  /// In en, this message translates to:
  /// **'Mark sold'**
  String get actionMarkSold;

  /// No description provided for @actionMarkRented.
  ///
  /// In en, this message translates to:
  /// **'Mark rented'**
  String get actionMarkRented;

  /// No description provided for @actionRelist.
  ///
  /// In en, this message translates to:
  /// **'Relist'**
  String get actionRelist;

  /// No description provided for @actionView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get actionView;

  /// No description provided for @deleteListingTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this listing?'**
  String get deleteListingTitle;

  /// No description provided for @deleteListingBody.
  ///
  /// In en, this message translates to:
  /// **'It will be removed from Akarat.ai on every device, along with its photos. This can\'t be undone.'**
  String get deleteListingBody;

  /// No description provided for @dashEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No listings yet'**
  String get dashEmptyTitle;

  /// No description provided for @dashEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Add your first property to see it here. It appears on the website too.'**
  String get dashEmptyBody;

  /// No description provided for @dashAnalyticsNote.
  ///
  /// In en, this message translates to:
  /// **'Views are not tracked yet. We show no numbers before they exist.'**
  String get dashAnalyticsNote;

  /// No description provided for @dashStatusUpdated.
  ///
  /// In en, this message translates to:
  /// **'Listing updated'**
  String get dashStatusUpdated;

  /// No description provided for @dashDeleted.
  ///
  /// In en, this message translates to:
  /// **'Listing deleted'**
  String get dashDeleted;

  /// No description provided for @inquiriesTitle.
  ///
  /// In en, this message translates to:
  /// **'Inquiries'**
  String get inquiriesTitle;

  /// No description provided for @inquiriesReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get inquiriesReceived;

  /// No description provided for @inquiriesSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get inquiriesSent;

  /// No description provided for @inquiriesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No inquiries yet. They arrive here the moment someone contacts you about a property.'**
  String get inquiriesEmpty;

  /// No description provided for @inquiriesSentEmpty.
  ///
  /// In en, this message translates to:
  /// **'Inquiries you send to owners appear here.'**
  String get inquiriesSentEmpty;

  /// No description provided for @inquiryAbout.
  ///
  /// In en, this message translates to:
  /// **'About {title}'**
  String inquiryAbout(String title);

  /// No description provided for @inquiryDeletedProperty.
  ///
  /// In en, this message translates to:
  /// **'a deleted property'**
  String get inquiryDeletedProperty;

  /// No description provided for @inquiryUnknownSender.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get inquiryUnknownSender;

  /// No description provided for @inquiryReplyEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get inquiryReplyEmail;

  /// No description provided for @inquiryReplyCall.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get inquiryReplyCall;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @profileGuestTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re browsing as a guest'**
  String get profileGuestTitle;

  /// No description provided for @profileGuestBody.
  ///
  /// In en, this message translates to:
  /// **'Sign in to list a property, keep saved searches with your account, and see inquiries.'**
  String get profileGuestBody;

  /// No description provided for @profileMyListings.
  ///
  /// In en, this message translates to:
  /// **'My listings'**
  String get profileMyListings;

  /// No description provided for @profileInquiries.
  ///
  /// In en, this message translates to:
  /// **'Inquiries'**
  String get profileInquiries;

  /// No description provided for @profileSavedSearches.
  ///
  /// In en, this message translates to:
  /// **'Saved searches'**
  String get profileSavedSearches;

  /// No description provided for @profileListProperty.
  ///
  /// In en, this message translates to:
  /// **'List a property'**
  String get profileListProperty;

  /// No description provided for @profileEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get profileEdit;

  /// No description provided for @profileSaved.
  ///
  /// In en, this message translates to:
  /// **'Profile saved'**
  String get profileSaved;

  /// No description provided for @profilePhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get profilePhone;

  /// No description provided for @profileVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get profileVerified;

  /// No description provided for @settingsSection.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsSection;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @settingsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get settingsPrivacy;

  /// No description provided for @settingsTerms.
  ///
  /// In en, this message translates to:
  /// **'Terms of use'**
  String get settingsTerms;

  /// No description provided for @settingsHelp.
  ///
  /// In en, this message translates to:
  /// **'Help and support'**
  String get settingsHelp;

  /// No description provided for @settingsHelpBody.
  ///
  /// In en, this message translates to:
  /// **'Questions, a listing problem, or something not working? Write to us and a person will answer.'**
  String get settingsHelpBody;

  /// No description provided for @settingsEmailUs.
  ///
  /// In en, this message translates to:
  /// **'Email support'**
  String get settingsEmailUs;

  /// No description provided for @settingsWebsite.
  ///
  /// In en, this message translates to:
  /// **'Open the website'**
  String get settingsWebsite;

  /// No description provided for @settingsVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String settingsVersion(String version);

  /// No description provided for @settingsDeleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get settingsDeleteAccount;

  /// No description provided for @signOutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get signOutConfirmTitle;

  /// No description provided for @signOutConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Your listings and saved searches stay in your account.'**
  String get signOutConfirmBody;

  /// No description provided for @deleteAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete your account?'**
  String get deleteAccountTitle;

  /// No description provided for @deleteAccountBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes your account, your listings and their photos, your saved searches and saved properties, on the app and the website. Messages you already sent to other owners stay in their inbox.'**
  String get deleteAccountBody;

  /// No description provided for @deleteAccountConfirmHint.
  ///
  /// In en, this message translates to:
  /// **'Type DELETE to confirm'**
  String get deleteAccountConfirmHint;

  /// No description provided for @deleteAccountConfirmWord.
  ///
  /// In en, this message translates to:
  /// **'DELETE'**
  String get deleteAccountConfirmWord;

  /// No description provided for @deleteAccountUnavailable.
  ///
  /// In en, this message translates to:
  /// **'In-app deletion isn\'t switched on yet. We\'ve opened an email to {email} so you can request it.'**
  String deleteAccountUnavailable(String email);

  /// No description provided for @deleteAccountDone.
  ///
  /// In en, this message translates to:
  /// **'Your account has been deleted.'**
  String get deleteAccountDone;

  /// No description provided for @legalUpdated.
  ///
  /// In en, this message translates to:
  /// **'Last updated: August 2026'**
  String get legalUpdated;

  /// No description provided for @privacyH1.
  ///
  /// In en, this message translates to:
  /// **'What we collect'**
  String get privacyH1;

  /// No description provided for @privacyP1.
  ///
  /// In en, this message translates to:
  /// **'An account needs an email address and a name. If you list a property, we store what you write about it: location, price, specifications and descriptions. Search text is kept to improve how requests are read, and is not tied to your account.'**
  String get privacyP1;

  /// No description provided for @privacyH2.
  ///
  /// In en, this message translates to:
  /// **'What we do not collect'**
  String get privacyH2;

  /// No description provided for @privacyP2.
  ///
  /// In en, this message translates to:
  /// **'We do not ask for national ID numbers, banking details or your physical location. We run no advertising, we do not sell your data, and we do not share it with ad brokers.'**
  String get privacyP2;

  /// No description provided for @privacyH3.
  ///
  /// In en, this message translates to:
  /// **'Links to other portals'**
  String get privacyH3;

  /// No description provided for @privacyP3.
  ///
  /// In en, this message translates to:
  /// **'When you open a result from another Jordanian portal, you leave for their site. From that moment their privacy policy applies, not ours, and we do not tell them who was searching.'**
  String get privacyP3;

  /// No description provided for @privacyH4.
  ///
  /// In en, this message translates to:
  /// **'Your rights'**
  String get privacyH4;

  /// No description provided for @privacyP4.
  ///
  /// In en, this message translates to:
  /// **'You can edit or delete any listing from your dashboard at any time, and deleting removes it from our database. To request full account deletion, write to privacy@akarat.ai.'**
  String get privacyP4;

  /// No description provided for @termsH1.
  ///
  /// In en, this message translates to:
  /// **'Using the platform'**
  String get termsH1;

  /// No description provided for @termsP1.
  ///
  /// In en, this message translates to:
  /// **'Searching is open to everyone. Listing a property requires an account, and you are responsible for what is published under it. Do not list a property you have no right to market.'**
  String get termsP1;

  /// No description provided for @termsH2.
  ///
  /// In en, this message translates to:
  /// **'Listing accuracy'**
  String get termsH2;

  /// No description provided for @termsP2.
  ///
  /// In en, this message translates to:
  /// **'What you write is what gets shown. Listing a property at a price, size or location that is not real is reason enough to remove it without notice.'**
  String get termsP2;

  /// No description provided for @termsH3.
  ///
  /// In en, this message translates to:
  /// **'External results'**
  String get termsH3;

  /// No description provided for @termsP3.
  ///
  /// In en, this message translates to:
  /// **'Results from other portals are what those portals published. We show them as they are, with a link to the source. We do not guarantee those properties are still available or correctly priced, and we take no commission on any deal.'**
  String get termsP3;

  /// No description provided for @termsH4.
  ///
  /// In en, this message translates to:
  /// **'Liability'**
  String get termsH4;

  /// No description provided for @termsP4.
  ///
  /// In en, this message translates to:
  /// **'Akarat is a search and listing tool, not a broker or an agent. View the property and verify ownership before any payment. Any agreement stays between you and the other party.'**
  String get termsP4;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
