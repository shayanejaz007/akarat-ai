import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart'
    show
        AppleIDAuthorizationScopes,
        AuthorizationErrorCode,
        SignInWithApple,
        SignInWithAppleAuthorizationException,
        SignInWithAppleException,
        generateNonce;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/localization/l10n.dart';
import '../../core/config/env.dart';
import '../../shared/repositories/account_repositories.dart';
import '../../shared/services/supabase_providers.dart';

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(ref.watch(supabaseClientProvider).auth, profiles: ref.watch(profileRepositoryProvider)),
);

/// The sign-in methods switched on in the Supabase project (`phone`,
/// `facebook`, `google`…), read from its public auth settings. Options that
/// depend on one appear the moment the owner turns it on, with no app update,
/// and never before, when they could only fail. Kept for ten minutes; a
/// failure (no network) is asked again next time.
final authProvidersProvider = FutureProvider.autoDispose<Map<String, bool>>((ref) async {
  final keep = ref.keepAlive();
  final expiry = Timer(const Duration(minutes: 10), keep.close);
  ref.onDispose(expiry.cancel);
  try {
    final res =
        await Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 8)))
            .get<Map<String, dynamic>>(
              '${Env.supabaseUrl}/auth/v1/settings',
              options: Options(headers: {'apikey': Env.supabasePublishableKey}),
            );
    final external = res.data?['external'];
    return {
      if (external is Map)
        for (final e in external.entries) '${e.key}': e.value == true,
    };
  } on Object {
    keep.close();
    return const {};
  }
});

/// Whether to offer phone sign-in (Env.phoneSignIn): in the default `auto`,
/// once the project's Phone provider is on.
final phoneSignInAvailableProvider = FutureProvider.autoDispose<bool>((ref) async {
  switch (Env.phoneSignIn) {
    case 'off':
      return false;
    case 'on':
      return true;
  }
  return (await ref.watch(authProvidersProvider.future))['phone'] ?? false;
});

/// Whether to offer Facebook (Env.facebookSignIn): in the default `auto`,
/// once the project's Facebook provider is on. Screens also check
/// [offersSocialLogin], which on iOS asks for Sign in with Apple beside it.
final facebookSignInAvailableProvider = FutureProvider.autoDispose<bool>((ref) async {
  switch (Env.facebookSignIn) {
    case 'off':
      return false;
    case 'on':
      return true;
  }
  return (await ref.watch(authProvidersProvider.future))['facebook'] ?? false;
});

/// Whether to offer Sign in with Apple (Env.appleSignIn): in the default
/// `auto`, once the project's Apple provider is on.
final appleSignInAvailableProvider = FutureProvider.autoDispose<bool>((ref) async {
  switch (Env.appleSignIn) {
    case 'off':
      return false;
    case 'on':
      return true;
  }
  return (await ref.watch(authProvidersProvider.future))['apple'] ?? false;
});

/// Whether Google and Facebook may be offered. App Store guideline 4.8
/// requires Sign in with Apple wherever a third-party login is offered on
/// Apple's platforms, so there they come only with it ([apple]: Sign in with
/// Apple is offered). Email and phone work everywhere, and an account made
/// any way is the same account.
bool offersSocialLogin(TargetPlatform platform, {required bool apple}) =>
    apple || (platform != TargetPlatform.iOS && platform != TargetPlatform.macOS);

/// Where Apple's own sign-in sheet exists. Elsewhere Apple signs people in
/// on its web page, through Supabase, as Google does.
bool hasNativeAppleSignIn(TargetPlatform platform) =>
    !kIsWeb && (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS);

/// How a sign-in or connection that may leave the app went.
enum AuthOutcome {
  /// Finished here: signed in, or connected.
  done,

  /// Goes on in the browser; the session comes back through the
  /// ai.akarat.app://login-callback link.
  inBrowser,

  /// The person closed Apple's sheet: nothing to say.
  cancelled,
}

/// The person closed Apple's sheet while confirming an account's deletion.
class AppleCancelled implements Exception {
  const AppleCancelled();
}

/// Sign-in, sign-up and recovery against the website's own Supabase Auth
/// project. An account made here signs in on the website and the other way
/// round: there is one user table, auth.users, and nothing parallel to it.
///
/// Phone codes: Supabase makes and checks them, and Twilio delivers them,
/// configured in the Supabase dashboard. No message provider's credentials
/// are in the app; it only asks for a code and hands back what was typed.
class AuthService {
  AuthService(this._auth, {this._dio, OtpChannel? channel, this._profiles, TargetPlatform? platform})
    : channel = channel ?? configuredChannel,
      _platform = platform ?? defaultTargetPlatform;
  final GoTrueClient _auth;

  /// Where a name Apple shares is kept (see [_keepAppleName]).
  final ProfileRepository? _profiles;

  /// Decides between Apple's sheet and its web page.
  final TargetPlatform _platform;

  /// Only for a change of number over WhatsApp; made when first needed.
  Dio? _dio;

  /// The channel codes travel by.
  final OtpChannel channel;

  /// The channel this build was configured with (Env.otpChannel).
  static OtpChannel get configuredChannel => Env.otpChannel == 'whatsapp' ? OtpChannel.whatsapp : OtpChannel.sms;

  Future<void> signIn(String email, String password) =>
      _auth.signInWithPassword(email: email.trim(), password: password);

  /// Returns true when a session came back straight away; false when the
  /// project requires email confirmation first (it does in production).
  ///
  /// full_name and locale ride in the user metadata, which the
  /// handle_new_user() trigger copies into public.profiles.
  Future<bool> signUp({
    required String email,
    required String password,
    required String name,
    required String locale,
    Map<String, Object> extra = const {},
  }) async {
    final res = await _auth.signUp(
      email: email.trim(),
      password: password,
      // [extra]: the guided tour's state for the new account (TourStore).
      data: {'full_name': name.trim(), 'locale': locale, ...extra},
      emailRedirectTo: Env.authCallbackUrl,
    );
    return res.session != null;
  }

  /// Opens Google in the browser; the session arrives through the
  /// ai.akarat.app://login-callback deep link and the PKCE exchange.
  Future<void> signInWithGoogle() => _auth.signInWithOAuth(
    OAuthProvider.google,
    redirectTo: Env.authCallbackUrl,
    authScreenLaunchMode: LaunchMode.externalApplication,
    queryParams: const {'prompt': 'select_account'},
  );

  /// Opens Facebook in the browser, as Google does; the session arrives
  /// through the ai.akarat.app://login-callback link and the PKCE exchange.
  /// Someone new to Akarat.ai gets an account the first time.
  Future<void> signInWithFacebook() => _auth.signInWithOAuth(
    OAuthProvider.facebook,
    redirectTo: Env.authCallbackUrl,
    authScreenLaunchMode: LaunchMode.externalApplication,
    scopes: 'email',
  );

  /// Connects Facebook to the signed-in account: Facebook confirms it in the
  /// browser, and from then on "Continue with Facebook" reaches this same
  /// account and its listings. Needs manual linking switched on in Supabase.
  Future<void> linkFacebook() => _auth.linkIdentity(
    OAuthProvider.facebook,
    redirectTo: Env.authCallbackUrl,
    authScreenLaunchMode: LaunchMode.externalApplication,
  );

  /// Disconnects Facebook. Supabase refuses to remove an account's only way
  /// in; the session is refreshed so the change shows at once.
  Future<void> unlinkFacebook() => _unlink('facebook');

  /// Sign in with Apple. On an iPhone, Apple's own sheet: Supabase checks the
  /// identity token it returns, and the session is ready at once. Elsewhere,
  /// Apple's page in the browser, as with Google. Someone new to Akarat.ai
  /// gets an account the first time.
  Future<AuthOutcome> signInWithApple() async {
    if (!hasNativeAppleSignIn(_platform)) {
      await _auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: Env.authCallbackUrl,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      return AuthOutcome.inBrowser;
    }
    final apple = await _appleCredential();
    if (apple == null) return AuthOutcome.cancelled;
    final res = await _auth.signInWithIdToken(provider: OAuthProvider.apple, idToken: apple.token, nonce: apple.nonce);
    await _keepAppleName(res.user, apple.name);
    return AuthOutcome.done;
  }

  /// Connects Apple to the signed-in account, so "Continue with Apple"
  /// reaches it. Immediate on an iPhone; elsewhere Apple confirms in the
  /// browser, as Facebook does. Needs manual linking switched on in Supabase.
  Future<AuthOutcome> linkApple() async {
    if (!hasNativeAppleSignIn(_platform)) {
      await _auth.linkIdentity(
        OAuthProvider.apple,
        redirectTo: Env.authCallbackUrl,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      return AuthOutcome.inBrowser;
    }
    final apple = await _appleCredential();
    if (apple == null) return AuthOutcome.cancelled;
    final res = await _auth.linkIdentityWithIdToken(
      provider: OAuthProvider.apple,
      idToken: apple.token,
      nonce: apple.nonce,
    );
    await _keepAppleName(res.user, apple.name);
    await _auth.refreshSession();
    return AuthOutcome.done;
  }

  /// Disconnects Apple, as [unlinkFacebook] does Facebook.
  Future<void> unlinkApple() => _unlink('apple');

  /// For deleting an account that signs in with Apple: Apple's confirmation,
  /// a one-time code the website exchanges to revoke Akarat.ai's access to
  /// the Apple ID, as Apple requires. Null where there is no Apple sheet or
  /// Apple could not be asked (the account is deleted all the same); throws
  /// [AppleCancelled] if the person closes the sheet, which stops it.
  Future<String?> appleCodeForDeletion() async {
    if (!hasNativeAppleSignIn(_platform)) return null;
    try {
      return (await SignInWithApple.getAppleIDCredential(scopes: const [])).authorizationCode;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) throw const AppleCancelled();
      return null;
    } on Object {
      return null;
    }
  }

  Future<void> _unlink(String provider) async {
    final identity = (await _auth.getUserIdentities()).where((i) => i.provider == provider).firstOrNull;
    if (identity == null) return;
    await _auth.unlinkIdentity(identity);
    await _auth.refreshSession();
  }

  /// Apple's sheet, with a fresh nonce: Apple signs its SHA-256 into the
  /// identity token and Supabase checks it against the original, so a token
  /// captured elsewhere cannot be replayed here. Null if it was closed.
  Future<({String token, String nonce, String? name})?> _appleCredential() async {
    final nonce = generateNonce();
    try {
      final c = await SignInWithApple.getAppleIDCredential(
        scopes: const [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
        nonce: sha256.convert(utf8.encode(nonce)).toString(),
      );
      final token = c.identityToken;
      if (token == null) throw const AuthException('Apple returned no identity token.');
      final name = [c.givenName, c.familyName].map((s) => s?.trim() ?? '').where((s) => s.isNotEmpty).join(' ');
      return (token: token, nonce: nonce, name: name.isEmpty ? null : name);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      rethrow;
    }
  }

  /// Apple tells an app someone's name only the first time they use it with
  /// that app, and never in the token, so a new account starts nameless.
  /// Kept where both clients read it: the user metadata (which the sign-up
  /// trigger copies from) and the profile.
  Future<void> _keepAppleName(User? user, String? name) async {
    if (user == null || name == null) return;
    if ('${user.userMetadata?['full_name'] ?? ''}'.trim().isNotEmpty) return;
    try {
      await _auth.updateUser(UserAttributes(data: {'full_name': name}));
      await _profiles?.update(fullName: name);
    } on Object {
      // Best effort: the account works without a name.
    }
  }

  Future<void> sendPasswordReset(String email) =>
      _auth.resetPasswordForEmail(email.trim(), redirectTo: Env.authCallbackUrl);

  Future<void> updatePassword(String password) => _auth.updateUser(UserAttributes(password: password));

  /// Sends a one-time code to [phone] (E.164). Signing in ([create] false)
  /// only reaches an account that already has this number, so someone who
  /// signed up by email is told to add their number instead of being handed
  /// a second, empty account. Creating one carries [data] (name, language,
  /// the tour's state) into the new account, as email sign-up does.
  Future<void> sendPhoneCode(String phone, {bool create = false, Map<String, Object> data = const {}}) =>
      _auth.signInWithOtp(phone: phone, shouldCreateUser: create, data: create ? data : null, channel: channel);

  /// The code typed back; signs in. Returns the user it signed in.
  Future<User?> verifyPhoneCode(String phone, String code) async =>
      (await _auth.verifyOTP(phone: phone, token: code, type: OtpType.sms)).user;

  /// Adds [phone] to the signed-in account, or replaces its number. Supabase
  /// sends a code to the new number, which [confirmPhoneLink] checks; from
  /// then on, signing in by phone reaches this same account.
  Future<void> startPhoneLink(String phone) async {
    if (channel == OtpChannel.sms) {
      await _auth.updateUser(UserAttributes(phone: phone));
      return;
    }
    final token = _auth.currentSession?.accessToken;
    if (token == null) throw AuthSessionMissingException();
    await requestPhoneChange(_dio ??= Dio(), token: token, phone: phone, channel: channel);
  }

  /// The code sent to the new number.
  Future<void> confirmPhoneLink(String phone, String code) =>
      _auth.verifyOTP(phone: phone, token: code, type: OtpType.phoneChange);

  Future<void> signOut() => _auth.signOut();
}

/// Asks Supabase to send a change-of-number code over [channel]. The client
/// library's updateUser cannot choose the channel; Supabase's endpoint can,
/// so this is the request updateUser makes, with the channel added. Errors
/// come back as the library's own AuthApiException, worded the same way.
Future<void> requestPhoneChange(
  Dio dio, {
  required String token,
  required String phone,
  required OtpChannel channel,
}) async {
  try {
    await dio.put<Object?>(
      '${Env.supabaseUrl}/auth/v1/user',
      data: {'phone': phone, 'channel': channel.name},
      options: Options(
        headers: {'apikey': Env.supabasePublishableKey, 'Authorization': 'Bearer $token'},
        sendTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
  } on DioException catch (e) {
    final body = e.response?.data;
    final map = body is Map ? body : const <String, Object?>{};
    throw AuthApiException(
      '${map['msg'] ?? map['message'] ?? map['error_description'] ?? e.message ?? 'Request failed'}',
      statusCode: e.response?.statusCode?.toString(),
      code: map['error_code']?.toString(),
    );
  }
}

/// The [provider] identity on [user] (`facebook`, `apple`…), if connected.
UserIdentity? identityOf(User? user, String provider) =>
    user?.identities?.where((i) => i.provider == provider).firstOrNull;

/// The Facebook identity on [user], if Facebook is connected.
UserIdentity? facebookIdentity(User? user) => identityOf(user, 'facebook');

/// The Apple identity on [user], if Apple is connected.
UserIdentity? appleIdentity(User? user) => identityOf(user, 'apple');

/// A sign-in method switched off in the Supabase project.
bool isProviderDisabled(Object error) {
  if (error is! AuthException) return false;
  final msg = error.message.toLowerCase();
  return error.code == 'provider_disabled' ||
      msg.contains('provider is not enabled') ||
      msg.contains('unsupported provider');
}

/// A reader-facing sentence for a failure connecting or disconnecting an
/// account ([provider]: `facebook` or `apple`), in their language.
String linkErrorMessage(
  AppLocalizations l,
  Object error,
  String Function(Object) fallback, {
  String provider = 'facebook',
}) {
  final apple = provider == 'apple';
  if (error is AuthException) {
    final code = error.code ?? '';
    final msg = error.message.toLowerCase();
    if (code == 'manual_linking_disabled' || msg.contains('manual linking')) return l.facebookLinkDisabled;
    if (code == 'identity_already_exists' || msg.contains('already linked')) {
      return apple ? l.appleTaken : l.facebookTaken;
    }
    if (code == 'single_identity_not_deletable' || msg.contains('at least 1 identity')) {
      return apple ? l.appleOnlyWayIn : l.facebookOnlyWayIn;
    }
    if (isProviderDisabled(error)) return apple ? l.authAppleDisabled : l.authFacebookDisabled;
  }
  if (error is SignInWithAppleException) return l.authAppleFailed;
  return authErrorMessage(l, error, fallback);
}

/// A reader-facing sentence for a failed Sign in with Apple.
String appleSignInErrorMessage(AppLocalizations l, Object error, String Function(Object) fallback) {
  if (isProviderDisabled(error)) return l.authAppleDisabled;
  if (error is SignInWithAppleException) return l.authAppleFailed;
  return authErrorMessage(l, error, fallback);
}

/// Signing in by phone found no account with that number.
bool isNoPhoneAccount(Object error) =>
    error is AuthException &&
    (error.code == 'otp_disabled' || error.message.toLowerCase().contains('signups not allowed'));

/// A reader-facing sentence for an error from the phone flows: the codes
/// have their own failures, worded as codes rather than links.
String phoneAuthErrorMessage(AppLocalizations l, Object error, String Function(Object) fallback) {
  if (error is AuthException) {
    final code = error.code ?? '';
    final msg = error.message.toLowerCase();
    if (code == 'phone_provider_disabled' || msg.contains('unsupported phone provider')) {
      return l.authPhoneUnavailable;
    }
    if (isNoPhoneAccount(error)) return l.authPhoneNoAccount;
    if (code == 'phone_exists' || msg.contains('already been registered') || msg.contains('phone number already')) {
      return l.authPhoneTaken;
    }
    if (code == 'validation_failed' && msg.contains('phone')) return l.authPhoneInvalid;
    if (code == 'sms_send_failed' || msg.contains('error sending')) return l.authCodeSendFailed;
    if (code == 'otp_expired' || msg.contains('token has expired') || msg.contains('invalid')) return l.authCodeWrong;
    if (code.startsWith('over_') || error.statusCode == '429') return l.authCodeTooMany;
  }
  return authErrorMessage(l, error, fallback);
}

/// A reader-facing sentence for an auth error, in their language.
String authErrorMessage(AppLocalizations l, Object error, String Function(Object) fallback) {
  if (error is AuthException) {
    final code = error.code ?? '';
    final msg = error.message.toLowerCase();
    if (code == 'invalid_credentials' || msg.contains('invalid login credentials')) return l.authInvalidCredentials;
    if (code == 'email_not_confirmed' || msg.contains('email not confirmed')) return l.authEmailNotConfirmed;
    if (code == 'user_already_exists' || code == 'email_exists' || msg.contains('already registered')) {
      return l.authUserExists;
    }
    if (code == 'weak_password' || msg.contains('password should')) return l.authWeakPassword;
    if (code == 'provider_disabled' ||
        msg.contains('provider is not enabled') ||
        msg.contains('unsupported provider')) {
      return l.authGoogleDisabled;
    }
    if (code == 'otp_expired' || code == 'flow_state_expired' || msg.contains('expired')) return l.authLinkExpired;
    if (code.startsWith('over_') || error.statusCode == '429') return l.errorRateLimited;
  }
  return fallback(error);
}
