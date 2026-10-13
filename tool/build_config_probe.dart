// Prints the build configuration that the app's own BuildConfig resolves from
// the --define values it was run with. Compiling it with an invalid
// configuration fails with BuildConfig's assertion message, exactly as the app
// build would. Used by tool/verify_build_config.sh; not part of the app.
//
//     dart run -DAPP_ENV=staging ... tool/build_config_probe.dart
import 'dart:io';

import 'package:signer/config/build_config.dart';

void main() {
  stdout.writeln('APP_ENV=${BuildConfig.environment}');
  stdout.writeln('NETWORK_ENVIRONMENT=${BuildConfig.networkEnvironment}');
  stdout.writeln('USE_TESTNET=${BuildConfig.useTestnet}');
  stdout.writeln('API_BASE_URL=${BuildConfig.apiBaseUrl}');
}
