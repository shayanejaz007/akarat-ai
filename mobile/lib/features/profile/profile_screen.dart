import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart' show ImageSource, XFile;
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SignOutScope;
import 'package:url_launcher/url_launcher.dart';

import '../../app/localization/l10n.dart';
import '../../app/router/routes.dart';
import '../../app/theme/tokens.dart';
import '../../core/config/env.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/segmented_pill.dart';
import '../../shared/models/account_models.dart';
import '../../shared/models/listing.dart';
import '../../shared/repositories/account_repositories.dart';
import '../../shared/repositories/listings_repository.dart';
import '../../shared/services/hidden_owners.dart';
import '../../shared/services/preferences.dart';
import '../../shared/services/profile_photos.dart';
import '../../shared/services/supabase_providers.dart';
import '../authentication/auth_service.dart';
import '../authentication/presentation/auth_scaffold.dart' show AppleMark, FacebookMark;
import '../daily/daily_providers.dart';
import '../property_details/property_details_screen.dart';
import '../settings/settings_controller.dart';
import '../tour/tour.dart';

final profileProvider = FutureProvider.autoDispose<Profile?>((ref) {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return ref.watch(profileRepositoryProvider).mine();
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final user = ref.watch(currentUserProvider);
    final phoneSignIn = ref.watch(phoneSignInAvailableProvider).value ?? false;
    final signInPhone = Phone.display(user?.phone);
    // Apple and Facebook as ways into this account; on iOS, Facebook only
    // beside Apple (offersSocialLogin).
    final apple = appleIdentity(user);
    final appleOn = ref.watch(appleSignInAvailableProvider).value ?? false;
    final showApple = appleOn || apple != null;
    final facebook = facebookIdentity(user);
    final facebookOn = ref.watch(facebookSignInAvailableProvider).value ?? false;
    final showFacebook =
        offersSocialLogin(Theme.of(context).platform, apple: appleOn) && (facebookOn || facebook != null);
    // Supabase will not remove an account's only way in.
    final ways = user?.identities?.length ?? 0;
    final facebookOnly = facebook != null && ways <= 1;
    final appleOnly = apple != null && ways <= 1;
    final hidden = ref.watch(hiddenOwnersProvider);
    final unread = user == null ? 0 : ref.watch(unreadNotificationsProvider);
    final pendingRequests = user == null ? 0 : ref.watch(pendingRequestsProvider);
    final inset = Layout.inset(context);
    const gap = SizedBox(height: Space.lg);
    final external = Icon(Icons.open_in_new_rounded, size: 18, color: c.inkFaint);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          LargeTitleBar(title: l.profileTitle),
          SliverPadding(
            padding: inset.copyWith(top: Space.xs, bottom: Space.xxl + MediaQuery.paddingOf(context).bottom),
            sliver: SliverList.list(
              children: [
                if (user == null) const _GuestCard() else const _AccountCard(),
                gap,
                // What this person has here.
                GroupedSection(
                  children: [
                    if (user != null) ...[
                      GroupedTile(
                        icon: Icons.home_work_outlined,
                        title: l.profileMyListings,
                        onTap: () => context.push(Routes.dashboard),
                      ),
                      GroupedTile(
                        icon: Icons.event_available_outlined,
                        title: l.profileBookings,
                        value: pendingRequests > 0 ? '$pendingRequests' : null,
                        onTap: () => context.push(Routes.bookingsFor(pendingRequests > 0 ? 'requests' : 'mine')),
                      ),
                      GroupedTile(
                        icon: Icons.notifications_none_rounded,
                        title: l.profileNotifications,
                        value: unread > 0 ? '$unread' : null,
                        onTap: () => context.push(Routes.notifications),
                      ),
                      GroupedTile(
                        icon: Icons.mark_email_unread_outlined,
                        title: l.profileInquiries,
                        onTap: () => context.push(Routes.inquiries),
                      ),
                      GroupedTile(
                        icon: Icons.bookmarks_outlined,
                        title: l.profileSavedSearches,
                        onTap: () =>
                            context.go('${Routes.saved}?tab=searches&t=${DateTime.now().millisecondsSinceEpoch}'),
                      ),
                    ],
                    GroupedTile(
                      icon: Icons.add_home_outlined,
                      title: l.profileListProperty,
                      onTap: () => context.push(Routes.newListing),
                    ),
                  ],
                ),
                gap,
                GroupedSection(
                  title: l.settingsSection,
                  children: [
                    _PreferenceRow(
                      icon: Icons.translate_rounded,
                      title: l.settingsLanguage,
                      control: SegmentedPill<String>(
                        expand: true,
                        value: context.lang,
                        onChanged: (v) => unawaited(ref.read(localeProvider.notifier).set(v)),
                        segments: const [
                          PillSegment(value: 'en', label: 'English'),
                          PillSegment(value: 'ar', label: 'العربية'),
                        ],
                      ),
                    ),
                    const _AppearanceRow(),
                    // Advertisers hidden from a listing's "More", on this
                    // device; a tap brings them back.
                    if (hidden.isNotEmpty)
                      GroupedTile(
                        icon: Icons.visibility_off_outlined,
                        title: l.profileHiddenAdvertisers(hidden.length),
                        subtitle: l.profileHiddenAdvertisersShow,
                        onTap: () => _showHidden(context, ref),
                      ),
                  ],
                ),
                gap,
                // Replays the tours that ran on first use.
                GroupedSection(
                  title: l.guidesSection,
                  children: [
                    GroupedTile(
                      icon: Icons.travel_explore_rounded,
                      title: l.guideFinding,
                      onTap: () => _guide(context, ref, TourId.explore),
                    ),
                    GroupedTile(
                      icon: Icons.map_outlined,
                      title: l.guideMap,
                      onTap: () => _guide(context, ref, TourId.map),
                    ),
                    GroupedTile(
                      icon: Icons.add_home_work_outlined,
                      title: l.guideListing,
                      onTap: () => _guide(context, ref, TourId.listing),
                    ),
                    GroupedTile(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: l.guideProperty,
                      onTap: () => _guide(context, ref, TourId.property),
                    ),
                  ],
                ),
                gap,
                GroupedSection(
                  children: [
                    GroupedTile(icon: Icons.support_agent_rounded, title: l.settingsHelp, onTap: () => _help(context)),
                    GroupedTile(
                      icon: Icons.privacy_tip_outlined,
                      title: l.settingsPrivacy,
                      onTap: () => context.push(Routes.legal('privacy')),
                    ),
                    GroupedTile(
                      icon: Icons.gavel_rounded,
                      title: l.settingsTerms,
                      onTap: () => context.push(Routes.legal('terms')),
                    ),
                    GroupedTile(
                      icon: Icons.public_rounded,
                      title: l.settingsWebsite,
                      trailing: external,
                      onTap: () => launchUrl(Uri.parse(Env.siteUrl), mode: LaunchMode.externalApplication),
                    ),
                    GroupedTile(
                      icon: Icons.description_outlined,
                      title: l.settingsLicences,
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: 'Akarat.ai',
                        applicationVersion: Env.appVersion,
                        applicationIcon: const Padding(padding: EdgeInsets.all(Space.sm), child: BrandMark(size: 48)),
                      ),
                    ),
                  ],
                ),
                if (user != null) ...[
                  gap,
                  GroupedSection(
                    children: [
                      // The number this account signs in with by phone.
                      // Adding it is what lets someone who signed up by
                      // email sign in by phone to this same account.
                      if (phoneSignIn || signInPhone.isNotEmpty)
                        GroupedTile(
                          icon: Icons.phone_iphone_rounded,
                          title: l.profileSignInPhone,
                          subtitle: signInPhone.isEmpty ? l.profileSignInPhoneNone : '\u2066$signInPhone\u2069',
                          onTap: phoneSignIn ? () => context.push(Routes.phoneLink) : null,
                        ),
                      // "Connected: the way this account signs in" and
                      // "Disconnect" read the same for any provider.
                      if (showApple)
                        GroupedTile(
                          leading: const AppleMark(),
                          title: l.profileApple,
                          subtitle: apple == null
                              ? l.profileAppleConnect
                              : (appleOnly ? l.profileFacebookOnly : l.profileAppleConnected),
                          trailing: apple == null || appleOnly
                              ? null
                              : Text(l.facebookDisconnect, style: context.text.labelLarge?.copyWith(color: c.danger)),
                          onTap: apple == null
                              ? () => _connectApple(context, ref)
                              : () => _disconnect(context, ref, provider: 'apple', onlyWayIn: appleOnly),
                        ),
                      if (showFacebook)
                        GroupedTile(
                          leading: const FacebookMark(),
                          title: l.profileFacebook,
                          subtitle: facebook == null
                              ? l.profileFacebookConnect
                              : (facebookOnly ? l.profileFacebookOnly : l.profileFacebookConnected),
                          trailing: facebook == null || facebookOnly
                              ? null
                              : Text(l.facebookDisconnect, style: context.text.labelLarge?.copyWith(color: c.danger)),
                          onTap: facebook == null
                              ? () => _connectFacebook(context, ref)
                              : () => _disconnect(context, ref, provider: 'facebook', onlyWayIn: facebookOnly),
                        ),
                      GroupedTile(
                        icon: Icons.logout_rounded,
                        title: l.actionSignOut,
                        chevron: false,
                        onTap: () => _signOut(context, ref),
                      ),
                      GroupedTile(
                        icon: Icons.delete_forever_outlined,
                        title: l.settingsDeleteAccount,
                        destructive: true,
                        chevron: false,
                        onTap: () => _deleteAccount(context, ref),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: Space.xl),
                Center(
                  child: Column(
                    children: [
                      const BrandMark(size: 28),
                      const SizedBox(height: Space.xs),
                      Text(l.settingsVersion(Env.appVersion), style: context.text.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Goes to the tour's screen, then asks for the tour once it is showing.
  void _guide(BuildContext context, WidgetRef ref, TourId id) {
    final pending = ref.read(pendingTourProvider.notifier);
    switch (id) {
      case TourId.explore:
        context.go(Routes.home);
      case TourId.map:
        context.go(Routes.explore);
      case TourId.listing:
        // The form looks for the request as it opens.
        pending.request(id);
        unawaited(context.push(Routes.newListing));
        return;
      case TourId.property:
        // Shown on the newest listing; the page looks for the request.
        unawaited(_propertyGuide(context, ref));
        return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => pending.request(id));
  }

  Future<void> _propertyGuide(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final rows = await ref.read(listingsRepositoryProvider).recent(limit: 1).catchError((Object _) => <Listing>[]);
    if (!context.mounted) return;
    if (rows.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l.guidePropertyNone)));
      return;
    }
    ref.read(pendingTourProvider.notifier).request(TourId.property);
    openProperty(context, rows.first);
  }

  Future<void> _help(BuildContext context) async {
    final l = context.l10n;
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.settingsHelp, style: context.text.titleLarge),
              const SizedBox(height: Space.xs),
              Text(l.settingsHelpBody, style: context.text.bodyMedium),
              const SizedBox(height: Space.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => launchUrl(
                    Uri(scheme: 'mailto', path: Env.supportEmail, queryParameters: {'subject': 'Akarat.ai app'}),
                  ),
                  icon: const Icon(Icons.mail_outline_rounded),
                  label: Text(l.settingsEmailUs),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Facebook confirms in the browser; the app says so when Supabase sends
  /// the reader back (AuthCallbackScreen), and the row shows it connected.
  Future<void> _connectFacebook(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final fallback = context.failureMessage;
    final prefs = ref.read(preferencesProvider);
    try {
      await prefs.setPendingLink('facebook');
      await ref.read(authServiceProvider).linkFacebook();
    } on Object catch (e) {
      await prefs.setPendingLink(null);
      messenger.showSnackBar(SnackBar(content: Text(linkErrorMessage(l, e, fallback))));
    }
  }

  /// On an iPhone, Apple's sheet connects it at once. Elsewhere Apple
  /// confirms in the browser and the app says so on the way back, as with
  /// Facebook.
  Future<void> _connectApple(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final fallback = context.failureMessage;
    final prefs = ref.read(preferencesProvider);
    try {
      await prefs.setPendingLink('apple');
      final outcome = await ref.read(authServiceProvider).linkApple();
      if (outcome == AuthOutcome.inBrowser) return;
      await prefs.setPendingLink(null);
      if (outcome == AuthOutcome.done) messenger.showSnackBar(SnackBar(content: Text(l.appleConnected)));
    } on Object catch (e) {
      await prefs.setPendingLink(null);
      messenger.showSnackBar(SnackBar(content: Text(linkErrorMessage(l, e, fallback, provider: 'apple'))));
    }
  }

  /// Disconnects [provider] (`apple` or `facebook`), after confirming.
  Future<void> _disconnect(
    BuildContext context,
    WidgetRef ref, {
    required String provider,
    required bool onlyWayIn,
  }) async {
    final l = context.l10n;
    final apple = provider == 'apple';
    final messenger = ScaffoldMessenger.of(context);
    if (onlyWayIn) {
      messenger.showSnackBar(SnackBar(content: Text(apple ? l.appleOnlyWayIn : l.facebookOnlyWayIn)));
      return;
    }
    final fallback = context.failureMessage;
    final ok = await confirmAction(
      context,
      title: apple ? l.appleDisconnectTitle : l.facebookDisconnectTitle,
      body: apple ? l.appleDisconnectBody : l.facebookDisconnectBody,
      confirmLabel: l.facebookDisconnect,
      cancelLabel: l.actionCancel,
      destructive: true,
    );
    if (!ok) return;
    final auth = ref.read(authServiceProvider);
    try {
      await (apple ? auth.unlinkApple() : auth.unlinkFacebook());
      messenger.showSnackBar(SnackBar(content: Text(apple ? l.appleDisconnected : l.facebookDisconnected)));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(linkErrorMessage(l, e, fallback, provider: provider))));
    }
  }

  Future<void> _showHidden(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await confirmAction(
      context,
      title: l.showHiddenTitle,
      body: l.showHiddenBody,
      confirmLabel: l.showHiddenAction,
      cancelLabel: l.actionCancel,
    );
    if (!ok) return;
    await ref.read(hiddenOwnersProvider.notifier).showAll();
    messenger.showSnackBar(SnackBar(content: Text(l.showHiddenDone)));
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final ok = await confirmAction(
      context,
      title: l.signOutConfirmTitle,
      body: l.signOutConfirmBody,
      confirmLabel: l.actionSignOut,
      cancelLabel: l.actionCancel,
    );
    if (ok) await ref.read(authServiceProvider).signOut();
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final failText = context.failureMessage;
    final user = ref.read(currentUserProvider);
    // An account that signs in with Apple: Apple confirms too, and the
    // website revokes Akarat.ai's access to the Apple ID as the account goes,
    // as Apple requires. That takes Apple's sheet, so iPhones only.
    final viaApple = appleIdentity(user) != null && hasNativeAppleSignIn(Theme.of(context).platform);
    // Typing the word is the confirmation; the button stays inert until then.
    final typed = TextEditingController();
    final matches = ValueNotifier(false);
    typed.addListener(
      () => matches.value = typed.text.trim().toUpperCase() == l.deleteAccountConfirmWord.toUpperCase(),
    );
    final confirmed = await confirmAction(
      context,
      title: l.deleteAccountTitle,
      body: l.deleteAccountBody,
      confirmLabel: l.actionDelete,
      cancelLabel: l.actionCancel,
      destructive: true,
      enabled: matches,
      extra: Padding(
        padding: const EdgeInsets.only(top: Space.md),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (viaApple) ...[
                Text(l.deleteAccountAppleNote, style: context.text.bodyMedium),
                const SizedBox(height: Space.sm),
              ],
              TextField(
                controller: typed,
                autocorrect: false,
                decoration: InputDecoration(hintText: l.deleteAccountConfirmHint),
              ),
            ],
          ),
        ),
      ),
    );
    // After the dialog's exit animation, which still reads the controller.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        typed.dispose();
        matches.dispose();
      });
    });
    if (!confirmed) return;
    try {
      final appleCode = viaApple ? await ref.read(authServiceProvider).appleCodeForDeletion() : null;
      await ref.read(accountRepositoryProvider).deleteMyAccount(appleAuthorizationCode: appleCode);
      // The picture kept on this phone goes with the account.
      if (user != null) await ref.read(profilePhotosProvider).remove(user.id).catchError((Object _) {});
      await ref.read(supabaseClientProvider).auth.signOut(scope: SignOutScope.local).catchError((Object _) {});
      final prefs = ref.read(preferencesProvider);
      await prefs.setLocalFavorites(const []);
      await prefs.setListingDraft(null);
      messenger.showSnackBar(SnackBar(content: Text(l.deleteAccountDone)));
      router.go(Routes.home);
    } on AppleCancelled {
      messenger.showSnackBar(SnackBar(content: Text(l.deleteAccountAppleCancelled)));
    } on AccountDeletionUnavailable {
      // The deployed website does not have the deletion route yet: fall back
      // to the documented request by email, prefilled so nothing is lost.
      messenger.showSnackBar(
        SnackBar(content: Text(l.deleteAccountUnavailable(Env.privacyEmail)), duration: const Duration(seconds: 6)),
      );
      await launchUrl(
        Uri(
          scheme: 'mailto',
          path: Env.privacyEmail,
          queryParameters: {
            'subject': 'Account deletion request',
            'body':
                'Please delete my Akarat.ai account.\n\nEmail: ${user?.email ?? ''}\n'
                'Phone: ${Phone.display(user?.phone)}\nAccount id: ${user?.id ?? ''}',
          },
        ),
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(failText(e))));
    }
  }
}

class _GuestCard extends StatelessWidget {
  const _GuestCard();

  // The brand's forest in both themes; the dark theme's forest token is a
  // light mint meant for text.
  static const _deep = Color(0xFF123C34);
  static const _deeper = Color(0xFF0B231F);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [_deep, _deeper],
        ),
        borderRadius: Radii.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.profileGuestTitle, style: context.text.titleLarge?.copyWith(color: Colors.white)),
          const SizedBox(height: Space.xs),
          Text(
            l.profileGuestBody,
            style: context.text.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: Space.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: _deep),
              onPressed: () => context.push(Routes.signIn),
              child: Text(l.actionSignIn),
            ),
          ),
          const SizedBox(height: Space.xs),
          Center(
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () => context.push(Routes.signUp),
              child: Text(l.authCreateAccount),
            ),
          ),
        ],
      ),
    );
  }
}

/// The account's picture, kept on this phone (ProfilePhotos), or its
/// initials. A tap changes it; the rest of the card edits the profile.
class _Avatar extends ConsumerWidget {
  const _Avatar({required this.userId, required this.initials});
  final String userId;
  final String? initials;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final photo = ref.watch(profilePhotoProvider).value;
    return Semantics(
      button: true,
      label: l.profilePhotoChange,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _choose(context, ref, hasPhoto: photo != null),
        child: SizedBox(
          width: 60,
          height: 60,
          child: Stack(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFF123C34),
                foregroundImage: photo == null ? null : MemoryImage(photo),
                child: initials == null
                    ? const Icon(Icons.person_rounded, color: Colors.white)
                    : Text(initials!, style: context.text.titleMedium?.copyWith(color: Colors.white)),
              ),
              PositionedDirectional(
                end: 0,
                bottom: 0,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: c.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.surfaceMuted, width: 2),
                  ),
                  child: Icon(Icons.photo_camera_rounded, size: 13, color: c.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _choose(BuildContext context, WidgetRef ref, {required bool hasPhoto}) async {
    final l = context.l10n;
    final c = context.colors;
    final messenger = ScaffoldMessenger.of(context);
    // Each message replaces the last, so "removed" never waits behind "updated".
    void say(String text) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.profilePhoto, style: context.text.titleLarge),
                  const SizedBox(height: Space.xxs),
                  Text(l.profilePhotoNote, style: context.text.bodySmall),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l.profilePhotoChoose),
              onTap: () => Navigator.pop(context, 'library'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l.profilePhotoTake),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            if (hasPhoto)
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: c.danger),
                title: Text(l.profilePhotoRemove, style: TextStyle(color: c.danger)),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    final photos = ref.read(profilePhotosProvider);
    if (choice == 'remove') {
      await photos.remove(userId);
      if (!context.mounted) return;
      ref.invalidate(profilePhotoProvider);
      say(l.profilePhotoRemoved);
      return;
    }
    final camera = choice == 'camera';
    final XFile? picked;
    try {
      picked = await ref.read(profilePhotoPickerProvider)(camera ? ImageSource.camera : ImageSource.gallery);
    } on Object {
      // A phone or simulator without a camera says so here.
      say(camera ? l.profilePhotoNoCamera : l.profilePhotoFailed);
      return;
    }
    if (picked == null) return;
    try {
      await photos.save(userId, picked);
      if (!context.mounted) return;
      ref.invalidate(profilePhotoProvider);
      say(l.profilePhotoUpdated);
    } on Object {
      say(l.profilePhotoFailed);
    }
  }
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final user = ref.watch(currentUserProvider)!;
    final profile = ref.watch(profileProvider).value;
    final name = (profile?.fullName.trim().isNotEmpty ?? false)
        ? profile!.fullName
        : ((user.userMetadata?['full_name'] as String?) ?? '');
    // An account made by phone may have no email at all.
    final signInPhone = Phone.display(user.phone);
    final email = user.email?.trim() ?? '';
    final initials = name.trim().isNotEmpty
        ? name.trim().split(RegExp(r'\s+')).take(2).map((p) => p.characters.first).join().toUpperCase()
        : email.isNotEmpty
        ? email.characters.first.toUpperCase()
        : null;
    void edit() => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EditProfileSheet(profile: profile, fallbackName: name),
    );
    return Material(
      color: c.surfaceMuted,
      shape: const RoundedRectangleBorder(borderRadius: Radii.card),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: edit,
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Row(
            children: [
              _Avatar(userId: user.id, initials: initials),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name.isNotEmpty ? name : (email.isNotEmpty ? email : signInPhone),
                            textDirection: name.isEmpty && email.isEmpty ? TextDirection.ltr : null,
                            style: context.text.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (profile?.verified ?? false) ...[
                          const SizedBox(width: Space.xxs),
                          Tooltip(
                            message: l.profileVerified,
                            child: Icon(Icons.verified_rounded, size: 18, color: c.emerald),
                          ),
                        ],
                      ],
                    ),
                    if (name.isNotEmpty && email.isNotEmpty)
                      Text(email, style: context.text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (signInPhone.isNotEmpty && (name.isNotEmpty || email.isNotEmpty))
                      Text(signInPhone, textDirection: TextDirection.ltr, style: context.text.bodySmall),
                    // The contact number on listings, when it is not the same.
                    if ((profile?.phone?.trim().isNotEmpty ?? false) &&
                        Phone.digitsOf(profile!.phone) != Phone.digitsOf(user.phone))
                      Text(profile.phone!, textDirection: TextDirection.ltr, style: context.text.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: Space.xs),
              Text(l.actionEdit, style: context.text.labelLarge?.copyWith(color: c.emerald)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({required this.profile, required this.fallbackName});
  final Profile? profile;
  final String fallbackName;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final _name = TextEditingController(text: widget.profile?.fullName ?? widget.fallbackName);
  late final _phone = TextEditingController(text: widget.profile?.phone ?? '');
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = context.l10n;
    try {
      await ref.read(profileRepositoryProvider).update(fullName: _name.text, phone: _phone.text);
      ref.invalidate(profileProvider);
      if (!mounted) return;
      showSuccess(context, l.profileSaved);
      Navigator.pop(context);
    } on Object catch (e) {
      if (mounted) setState(() => _error = context.failureMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, MediaQuery.viewInsetsOf(context).bottom + Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.profileEdit, style: context.text.titleLarge),
          const SizedBox(height: Space.md),
          TextField(
            controller: _name,
            maxLength: 120,
            decoration: InputDecoration(labelText: l.fieldName, counterText: ''),
          ),
          const SizedBox(height: Space.sm),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            maxLength: 24,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: l.profilePhone, counterText: ''),
          ),
          if (_error != null) Text(_error!, style: context.text.bodySmall?.copyWith(color: context.colors.danger)),
          const SizedBox(height: Space.md),
          BusyButton(label: l.actionSave, onPressed: _save),
        ],
      ),
    );
  }
}

/// A preference: its name, and the choice full width beneath it, so the
/// control never squeezes the label at large text sizes or in Arabic.
class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({required this.icon, required this.title, required this.control});
  final IconData icon;
  final String title;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.md, Space.sm + 2, Space.md, Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(width: 24, child: Icon(icon, size: 22, color: context.colors.forest)),
              const SizedBox(width: Space.md),
              Expanded(child: Text(title, style: context.text.bodyLarge)),
            ],
          ),
          const SizedBox(height: Space.sm),
          control,
        ],
      ),
    );
  }
}

class _AppearanceRow extends ConsumerWidget {
  const _AppearanceRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final mode = ref.watch(themeModeProvider);
    return _PreferenceRow(
      icon: Icons.contrast_rounded,
      title: l.settingsAppearance,
      control: SegmentedPill<ThemeMode>(
        expand: true,
        value: mode,
        onChanged: (m) => unawaited(ref.read(themeModeProvider.notifier).set(m)),
        segments: [
          PillSegment(value: ThemeMode.system, label: l.themeSystem),
          PillSegment(value: ThemeMode.light, label: l.themeLight),
          PillSegment(value: ThemeMode.dark, label: l.themeDark),
        ],
      ),
    );
  }
}
