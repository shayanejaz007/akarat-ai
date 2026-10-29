/// Every path in the app, in one place.
///
/// Deep links: `ai.akarat.app://open/property/<id>` and the website's own
/// `https://<site>/{en|ar}/property/<id>` both land on [property]. Supabase
/// auth redirects arrive as `ai.akarat.app://login-callback?code=…` and are
/// routed to [authCallback] while the Supabase client exchanges the code.
class Routes {
  const Routes._();

  static const home = '/home';
  static const explore = '/explore';
  static const daily = '/daily';
  static const aiSearch = '/ai';
  static const saved = '/saved';
  static const profile = '/profile';

  static const onboarding = '/onboarding';
  static const signIn = '/auth/sign-in';
  static const signUp = '/auth/sign-up';
  static const forgotPassword = '/auth/forgot';
  static const resetPassword = '/auth/reset-password';
  static const authCallback = '/login-callback';

  /// Phone sign-in; `?mode=signup` makes a new account with the number.
  static const phoneSignIn = '/auth/phone';
  static String phoneSignUp([String? next]) =>
      next == null ? '$phoneSignIn?mode=signup' : '$phoneSignIn?mode=signup&next=${Uri.encodeComponent(next)}';

  /// Adding a phone number to the signed-in account, from Profile.
  static const phoneLink = '/account/phone';

  static const newListing = '/listing/new';
  static String editListing(String id) => '/listing/$id/edit';
  static const dashboard = '/dashboard';
  static const inquiries = '/inquiries';
  static String legal(String doc) => '/legal/$doc';
  static String property(String id) => '/property/$id';

  /// Daily-rental requests: `requests` for the owner's places, `mine` for
  /// the reader's own.
  static const bookings = '/bookings';
  static String bookingsFor(String tab) => '$bookings?tab=$tab';
  static const notifications = '/notifications';
  static String availability(String id) => '/listing/$id/availability';

  /// Screens that need a session. Browsing, searching and saving never do.
  static const protectedPrefixes = ['/listing', '/dashboard', '/inquiries', '/account', '/bookings', '/notifications'];

  static bool isProtected(String path) => protectedPrefixes.any(path.startsWith);

  static bool isAuthPage(String path) => path.startsWith('/auth/') && path != resetPassword;

  /// [link], if it is a page of ours: never another app or site.
  static String? safeLink(String? link) {
    if (link == null || link.isEmpty) return null;
    final uri = Uri.tryParse(link);
    if (uri == null || uri.hasScheme || uri.hasAuthority || !uri.path.startsWith('/')) return null;
    return link;
  }

  /// Where to return after signing in, if it is one of ours and not another
  /// sign-in page.
  static String? safeNext(String? next) {
    final link = safeLink(next);
    if (link == null || Uri.parse(link).path.startsWith('/auth/')) return null;
    return link;
  }

  static String withNext(String path, String next) => '$path?next=${Uri.encodeComponent(next)}';
}
