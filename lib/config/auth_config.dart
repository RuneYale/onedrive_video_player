/// Microsoft identity + Microsoft Graph configuration.
///
/// Before the app can sign in, you MUST register an application in the
/// Azure Portal and paste its Application (client) ID below.
///
/// Setup (one time):
///  1. Go to https://portal.azure.com -> Microsoft Entra ID -> App registrations
///     -> New registration.
///  2. Supported account types: choose "Accounts in any organizational
///     directory and personal Microsoft accounts" (= `common` tenant) so both
///     personal and work/school OneDrive work.
///  3. Redirect URI: leave it as "Public client/native (mobile & desktop)"
///     with NO redirect URI (device code flow does not need one).
///  4. Under "Authentication" -> "Advanced settings", enable
///     "Allow public client flows" = Yes.
///  5. Copy the "Application (client) ID" and set it as [clientId].
class AuthConfig {
  const AuthConfig._();

  /// TODO(user): Replace with your Azure app's Application (client) ID.
  static const String clientId = '8054f641-bd95-4328-b97a-be428b2708d2';

  /// Tenant used for the identity endpoints.
  /// - `common`     : personal + work/school accounts (recommended)
  /// - `consumers`  : personal Microsoft accounts only
  /// - `organizations` : work/school accounts only
  static const String tenant = 'common';

  /// OAuth scopes requested.
  /// - `Files.Read`   : read OneDrive files
  /// - `offline_access`: get a refresh token
  /// - `User.Read`    : display the signed-in user's name/email
  static const List<String> scopes = [
    'Files.Read',
    'offline_access',
    'User.Read',
  ];

  static String get authority => 'https://login.microsoftonline.com/$tenant';

  static String get deviceCodeEndpoint => '$authority/oauth2/v2.0/devicecode';

  static String get tokenEndpoint => '$authority/oauth2/v2.0/token';

  static String get graphBase => 'https://graph.microsoft.com/v1.0';

  static String get scopesString => scopes.join(' ');
}
