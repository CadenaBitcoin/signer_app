/// Build-time environment configuration: the single source of truth for which
/// backend and Bitcoin network a build targets. Pure Dart, shared by Android and
/// iOS (no platform code).
///
/// The environment is chosen explicitly, for every build, with
///
///     --dart-define-from-file=config/build/staging.json
///     --dart-define-from-file=config/build/production.json
///
/// There is NO default environment. A build that supplies no configuration, an
/// incomplete one, an unknown one or a contradictory one does not compile: the
/// message of the first violated rule is printed and no app is produced. This
/// holds for debug, profile and release/AOT builds alike, for `flutter run` and
/// for CI. Neither environment can fall back to the other. The Git branch name
/// plays no part in selection.
///
/// The native flavor (`--flavor staging|production`) selects only the platform
/// identity (application ID / bundle ID and display name). Flutter passes it to
/// Dart as FLUTTER_APP_FLAVOR, and the build fails unless it equals APP_ENV, so
/// the identity and the environment cannot disagree and no second selector exists.
/// See docs/BUILD_CONFIGURATION.md.
library;

/// Production API endpoint.
const String _productionApiBaseUrl = 'https://cadenabitcoin.com/app';

/// Staging API endpoint, as documented in docs/SECURITY_BOUNDARY.md.
const String _stagingApiBaseUrl = 'https://staging.purabitcoin.com/app';

/// Validates the raw build inputs. Every failed [assert] is a compile-time
/// error ("Constant evaluation error") because the object is created in a
/// constant expression, so the rules also run in release/AOT builds.
class _BuildConfigCheck {
  const _BuildConfigCheck({
    required String env,
    required String network,
    required String testnet,
    required String url,
    required String flavor,
  })  : assert(
          env == 'staging' || env == 'production',
          env == '' && network == '' && testnet == '' && url == ''
              ? 'No build configuration was supplied and there is no default '
                  'environment. Pass --dart-define-from-file='
                  'config/build/staging.json or config/build/production.json '
                  '(see docs/BUILD_CONFIGURATION.md).'
              : env == ''
                  ? 'Partial build configuration: APP_ENV is not set but other '
                      'settings are. Pass --dart-define-from-file='
                      'config/build/<environment>.json.'
                  : 'APP_ENV must be "staging" or "production", got "$env".',
        ),
        assert(
          network != '' && testnet != '' && url != '',
          'Incomplete "$env" build configuration: NETWORK_ENVIRONMENT, '
          'USE_TESTNET and API_BASE_URL must all be set.',
        ),
        assert(
          network == 'bitcoin' || network == 'signet',
          'NETWORK_ENVIRONMENT must be "bitcoin" or "signet", got "$network".',
        ),
        assert(
          testnet == 'true' || testnet == 'false',
          'USE_TESTNET must be true or false, got "$testnet".',
        ),
        assert(
          (testnet == 'true') == (network == 'signet'),
          'Contradictory network settings: USE_TESTNET=$testnet with '
          'NETWORK_ENVIRONMENT="$network" (signet requires USE_TESTNET=true, '
          'bitcoin requires false).',
        ),
        assert(
          env != 'staging' || network == 'signet',
          'A staging build must use NETWORK_ENVIRONMENT="signet", got '
          '"$network".',
        ),
        assert(
          env != 'staging' || url == _stagingApiBaseUrl,
          'A staging build must use API_BASE_URL="$_stagingApiBaseUrl", got '
          '"$url".',
        ),
        assert(
          env != 'production' || network == 'bitcoin',
          'A production build must use NETWORK_ENVIRONMENT="bitcoin", got '
          '"$network".',
        ),
        assert(
          env != 'production' || url == _productionApiBaseUrl,
          'A production build must use API_BASE_URL="$_productionApiBaseUrl", '
          'got "$url".',
        ),
        assert(
          flavor != '',
          'No build flavor was supplied for the "$env" configuration. Pass '
          '--flavor $env together with --dart-define-from-file='
          'config/build/$env.json (there is no default flavor).',
        ),
        assert(
          flavor == env,
          'Build flavor "$flavor" does not match APP_ENV "$env". The flavor '
          'selects the application identity and must agree with the '
          'environment: use --flavor $env with config/build/$env.json.',
        );
}

class BuildConfig {
  BuildConfig._();

  // Raw inputs. An empty string means "not supplied", which is rejected.
  static const String _env = String.fromEnvironment('APP_ENV');
  static const String _network = String.fromEnvironment('NETWORK_ENVIRONMENT');
  static const String _testnet = String.fromEnvironment('USE_TESTNET');
  static const String _url = String.fromEnvironment('API_BASE_URL');

  // Set by `flutter build/run --flavor X` itself; Flutter refuses to let it be
  // passed by hand. Compared with APP_ENV, never used to select anything.
  static const String _flavor = String.fromEnvironment('FLUTTER_APP_FLAVOR');

  /// Creating this constant is what enforces every rule above; nothing reads it.
  ///
  /// This is the single analyzer suppression in the file. `flutter analyze` and
  /// the IDE run without any build configuration, so the analyzer evaluates the
  /// rules with empty inputs and reports their (intended) failure as
  /// `const_eval_throws_exception`. Suppressing that one diagnostic on the line
  /// below does NOT weaken the build: the compiler front end, which receives the
  /// real defines, still rejects every violation (verified for debug, release/AOT
  /// and `flutter build` by tool/verify_build_config.sh, which also fails if the
  /// suppression is duplicated or changed).
  // ignore: const_eval_throws_exception
  static const Object validated = _BuildConfigCheck(
    env: _env,
    network: _network,
    testnet: _testnet,
    url: _url,
    flavor: _flavor,
  );

  /// "staging" or "production".
  static const String environment = _env;

  /// Network string passed to the native library: "bitcoin" or "signet".
  static const String networkEnvironment = _network;

  /// True for Signet (testnet-style addresses and derivation path).
  static const bool useTestnet = _testnet == 'true';

  /// Backend base URL. HTTPS only (enforced again by DataService).
  static const String apiBaseUrl = _url;
}
