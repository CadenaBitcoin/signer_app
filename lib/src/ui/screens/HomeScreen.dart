import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_idensic_mobile_sdk_plugin/flutter_idensic_mobile_sdk_plugin.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signer/services/app_minimize_service.dart';
import 'package:signer/services/auto_signing_service.dart';
import 'package:signer/services/dataService/apiService.dart';
import 'package:signer/services/storage_service.dart';
import 'package:signer/services/utilService.dart';
import 'package:signer/src/ui/controllers/appController.dart';
import 'package:signer/src/ui/screens/qrScanner/qrScanner.dart';
import 'package:signer/src/ui/screens/splashScreen.dart';
import 'package:signer/src/ui/screens/verify_password_screen.dart';
import 'package:signer/src/ui/theme/app_Text_Styles.dart';
import 'package:signer/src/ui/theme/colors.dart';
import 'package:signer/src/ui/widgets/connect_to_cadena_button.dart';

import '../../../models/user_profile_model.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppController appController = Get.find<AppController>();
  final AutoSigningService autoSigningService = Get.find<AutoSigningService>();

  final _storage = const FlutterSecureStorage();
  bool _isKycLaunching = false;
  Future<String?> getMnemonic(String email) async {
    final _storage = const FlutterSecureStorage();

    final userKey = 'user_$email';

    final storedData = await _storage.read(key: userKey);
    if (storedData == null) return null;

    final Map<String, dynamic> decoded = jsonDecode(storedData);
    return decoded['mnemonic'] as String?;
  }

  String generateEntropyHexFromMnemonic(String mnemonic) {
    return bip39.mnemonicToEntropy(mnemonic); // Already returns hex string
  }

  Future<void> initWallet() async {
    final _storage = const FlutterSecureStorage();

    final emailKey = 'logged_in_user_email';

    final storedData = await _storage.read(key: emailKey);
    print("storedData ${storedData}");

    final mnemonic = await getMnemonic("${storedData}");
    if (mnemonic == null) {
      print("Mnemonic not found");
      return;
    }
  }

  var qrText = ''.obs;
  Timer? _profileTimer;
  bool _isConnectingToCadena = false;

  /// True while local credentials exist but Cadena connect step still needed.
  bool get _needsCadenaConnectAttention =>
      appController.showVerifyButton.value;

  Future<String> _getLocalEmail() async {
    return await StorageService.getLoggedInEmail() ?? '';
  }

  String _kycDisplayText(String? status) {
    final s = (status ?? '').trim().toLowerCase();
    if (s.isEmpty || s == 'null') return 'Not started';
    if (s == 'pending' ||
        s == 'in_progress' ||
        s == 'in progress' ||
        s == 'provider_pending') {
      return 'In progress';
    }
    if (s == 'rejected' || s == 'finally_rejected' || s == 'finallyrejected') return 'Rejected';
    if (s == 'approved' || s == 'completed' || s == 'verified') return 'Verified';
    return status ?? 'Unknown';
  }

  Color _kycColor(String? status) {
    final s = (status ?? '').trim().toLowerCase();
    if (s.isEmpty || s == 'null') return Colors.orange;
    if (s == 'pending' ||
        s == 'in_progress' ||
        s == 'in progress' ||
        s == 'provider_pending') {
      return Colors.blue;
    }
    if (s == 'rejected' || s == 'finally_rejected' || s == 'finallyrejected') return Colors.red;
    if (s == 'approved' || s == 'completed' || s == 'verified') return Colors.green;
    return Colors.grey;
  }

  IconData _kycIcon(String? status) {
    final s = (status ?? '').trim().toLowerCase();
    if (s.isEmpty || s == 'null') return Icons.assignment_outlined;
    if (s == 'pending' ||
        s == 'in_progress' ||
        s == 'in progress' ||
        s == 'provider_pending') {
      return Icons.hourglass_top_outlined;
    }
    if (s == 'rejected' || s == 'finally_rejected' || s == 'finallyrejected') return Icons.error_outline;
    if (s == 'approved' || s == 'completed' || s == 'verified') return Icons.verified_outlined;
    return Icons.help_outline;
  }

  bool _kycIsActionable(String? status) {
    final s = (status ?? '').trim().toLowerCase();
    return s.isEmpty ||
        s == 'null' ||
        s == 'rejected' ||
        s == 'finally_rejected' ||
        s == 'finallyrejected';
  }

  bool _kycIsInProgress(String? status) {
    final s = (status ?? '').trim().toLowerCase();
    return s == 'pending' ||
        s == 'in_progress' ||
        s == 'in progress' ||
        s == 'provider_pending';
  }

  bool _kycIsVerified(String? status) {
    final s = (status ?? '').trim().toLowerCase();
    return s == 'approved' || s == 'completed' || s == 'verified';
  }

  double _kycNowTs() =>
      DateTime.now().toUtc().millisecondsSinceEpoch / 1000.0;

  Future<void> _reportKycEvent(String event, {String? details}) async {
    await ApiService().kycAppStatus(
      event: event,
      eventTs: _kycNowTs(),
      details: details,
    );
  }

  /// Maps Sumsub SDK result to backend lifecycle event names.
  Future<void> _reportKycSdkFinished(SNSMobileSDKResult result) {
    if (result.success) {
      return _reportKycEvent('sdk_completed', details: result.toString());
    }

    switch (result.status) {
      case SNSMobileSDKStatus.Initial:
        return _reportKycEvent('sdk_cancelled', details: result.toString());
      case SNSMobileSDKStatus.Incomplete:
      case SNSMobileSDKStatus.Pending:
        return _reportKycEvent('sdk_cancelled', details: result.toString());
      case SNSMobileSDKStatus.Failed:
      case SNSMobileSDKStatus.FinallyRejected:
        return _reportKycEvent('sdk_error', details: result.toString());
      default:
        return _reportKycEvent('sdk_completed', details: result.toString());
    }
  }

  Future<String> _fetchNewKycAccessToken() async {
    final payload = await ApiService().kycStartApp();
    final token = payload?['access_token']?.toString();
    if (token == null || token.isEmpty) {
      throw Exception('Failed to refresh KYC access token');
    }
    return token;
  }

  Future<void> _startKycFlow() async {
    if (_isKycLaunching) return;
    setState(() => _isKycLaunching = true);
    try {
      await _reportKycEvent('screen_opened');

      final payload = await ApiService().kycStartApp();
      final token = payload?['access_token']?.toString();

      if (token == null || token.isEmpty) {
        await _reportKycEvent('sdk_error', details: 'failed_to_fetch_token');
        Get.snackbar(
          'KYC',
          'Failed to start KYC. Please try again.',
          backgroundColor: Colors.red.withOpacity(0.9),
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }

      await _reportKycEvent('sdk_started');

      final sdk = SNSMobileSDK.init(
        token,
        () async => await _fetchNewKycAccessToken(),
      ).withDebug(false).build();

      try {
        final result = await sdk.launch();
        print('KYC SDK result: $result');
        await _reportKycSdkFinished(result);
      } catch (e) {
        await _reportKycEvent('sdk_error', details: e.toString());
        Get.snackbar(
          'KYC',
          'An error occurred while launching KYC: $e',
          backgroundColor: Colors.red.withOpacity(0.9),
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (e) {
      print('Error launching KYC: $e');
      Get.snackbar(
        'KYC',
        'An error occurred while launching KYC: $e',
        backgroundColor: Colors.red.withOpacity(0.9),
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      await ApiService().getUserProfile();
      if (mounted) setState(() => _isKycLaunching = false);
    }
  }

  @override
  void initState() {
    super.initState();
    initWallet();
    _checkTokenAndStartTimer();
    _checkTokenAndGetProfile();

    // Check JWT token and update button states
    appController.checkJwtTokenAndUpdateButtons();
  }

  Future<void> _checkTokenAndStartTimer() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final jwtToken = prefs.getString('jwtToken');

    if (jwtToken != null &&
        jwtToken.isNotEmpty &&
        appController.backendSessionActive.value) {
      debugPrint("JWT token found, starting periodic timer");
      // Start timer only if JWT token exists
      _profileTimer?.cancel();
      _profileTimer = Timer.periodic(Duration(seconds: 10), (timer) {
        if (!appController.backendSessionActive.value) {
          timer.cancel();
          _profileTimer = null;
          return;
        }
        ApiService().getUserProfile();
      });
    } else {
      debugPrint("No JWT token found, timer not started");
      _profileTimer?.cancel();
      _profileTimer = null;
    }
  }

  // Removed local state - now using AppController reactive state

  Future<void> _checkTokenAndGetProfile() async {
    try {
      // Check if JWT token exists
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwtToken');

      if (jwtToken != null && jwtToken.isNotEmpty) {
        debugPrint("JWT token found in initState, calling getUserProfile");
        final profileResult = await ApiService().getUserProfile();

        if (profileResult == 'OK') {
          debugPrint("User profile loaded successfully in initState");
          // Button states are now handled by _updateButtonStatesBasedOnAuthCode() in ApiService

          // Get app version after successful login
          await ApiService().getAppVersion();
        } else {
          debugPrint("Failed to load user profile in initState");
          appController.showScanButton.value = false;
        }
      } else {
        debugPrint("No JWT token found in initState, skipping getUserProfile");
        appController.showScanButton.value = false;
      }
    } catch (e) {
      debugPrint("Error checking token in initState: $e");
      appController.showScanButton.value = false;
    }
  }

  Future<void> _verifyUser() async {
    if (_isConnectingToCadena) return;
    setState(() => _isConnectingToCadena = true);
    try {
      // Call the existing _initializeUserData which does login + getUserProfile
      await _initializeUserData();

      // After API calls, check if JWT token exists
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwtToken');
      print('jwtToken $jwtToken');

      if (jwtToken != null && jwtToken.isNotEmpty) {
        print("User verified successfully");
        // Don't override verify button state here - let _updateButtonStatesBasedOnAuthCode handle it
        _checkTokenAndGetProfile();
      } else {
        print("User verification failed");
      }
    } catch (e) {
      print("Error during verification: $e");
    } finally {
      if (mounted) setState(() => _isConnectingToCadena = false);
    }
  }

  Widget _subordinateIfNeedsConnect({required Widget child}) {
    return Obx(() {
      final needsConnect = _needsCadenaConnectAttention;
      return Opacity(
        opacity: needsConnect ? 0.45 : 1.0,
        child: IgnorePointer(
          ignoring: needsConnect,
          child: child,
        ),
      );
    });
  }

  Future<void> _initializeUserData() async {
    try {
      // Get user credentials from local storage
      final loggedInEmail = await StorageService.getLoggedInEmail();
      final userData = await StorageService.getUserByEmail(loggedInEmail ?? '');

      if (userData != null && userData['email'] != null && userData['password'] != null) {
        print(userData);
        await _performVerificationProcess(userData['email'] ?? '', userData['password'] ?? '');
      } else {
        print("No user credentials found in local storage");
      }
    } catch (e) {
      print("Error initializing user data: $e");
    }
  }

  /// Complete verification process following new decision tree
  /// Condition conn -> A -> B -> C -> D
  Future<void> _performVerificationProcess(String email, String password) async {
    try {
      // ========================================
      // CONDITION conn: Check server status
      // ========================================
      print("Condition conn: Checking server status...");
      final serverStatus = await ApiService().checkServerStatus();

      if (serverStatus != 'OK') {
        // Server not reachable - HALT
        print("Server is not accessible - HALT");
        appController.setServerReachable(false);
        appController.updateButtonVisibility(
          isServerReachable: false,
          hasRemoteXpub: false,
          xpubMatches: false,
          isHaltState: true,
        );
        _showServerUnreachableMessage();
        appController.userProfileObject.value = UserProfileModel();
        // Update status to show "CadenaBitcoin out of reach"
        return;
      }

      appController.setServerReachable(true);
      print("Server is reachable - proceeding to Condition A");

      // ========================================
      // CONDITION A: Check if email in DB and password matches
      // ========================================
      print("Condition A: Attempting login...");
      final loginResult = await ApiService().login(
        email: email,
        pass: password,
      );

      if (loginResult != 'OK') {
        // Login failed - try registration
        print("Login failed - attempting registration...");
        final registerResult = await ApiService().registerNewUser(
          email: email,
          pass: password,
        );

        // Registration attempt made (we don't know the exact outcome)
        print("Registration attempt completed - showing message");
        _showRegistrationAttemptMessage(email);
        appController.updateButtonVisibility(
          isServerReachable: true,
          hasRemoteXpub: false,
          xpubMatches: false,
          isHaltState: true,
        );
        appController.userProfileObject.value = UserProfileModel();
        return; // HALT
      }

      print("Condition A passed - login successful, proceeding to Condition B");

      // ========================================
      // CONDITION B: Password match (already validated in A)
      // ========================================
      print("Condition B: Password match confirmed (validated in Condition A)");

      // ========================================
      // CONDITION C: Check if remote XPUB exists
      // ========================================
      print("Condition C: Checking user profile for remote XPUB...");
      final profileResult = await ApiService().getUserProfile();

      if (profileResult != 'OK') {
        print("Failed to get user profile");
        _showLoginFailureDialog();
        return;
      }

      final authCode = appController.userProfileObject.value.payload?.authCode ?? 999;
      final remoteXpub = appController.userProfileObject.value.payload?.xpub;
      final hasRemoteXpub = remoteXpub != null && remoteXpub.isNotEmpty;

      print("Auth code: $authCode, Has remote XPUB: $hasRemoteXpub");

      // Check auth_code pattern: ..xx0x means bit-1 not set (not registered)
      // Check if bit-1 is set: auth_code & 2 != 0
      final isRegistered = (authCode & 2) != 0;

      if (!isRegistered) {
        // User not registered (auth_code = ..xx0x) - HALT
        print("User not registered (auth_code bit-1 not set) - HALT");
        _showRegistrationRequiredMessage();
        appController.updateButtonVisibility(
          isServerReachable: true,
          hasRemoteXpub: false,
          xpubMatches: false,
          isHaltState: true,
        );
        return;
      }

      if (!hasRemoteXpub) {
        // Condition C: No remote XPUB (auth_code = ..x01x)
        print("Condition C: No remote XPUB - user needs to pair device");
        _showPairingRequiredMessage();
        appController.updateButtonVisibility(
          isServerReachable: true,
          hasRemoteXpub: false,
          xpubMatches: false,
          isHaltState: false,
        );
        return; // HALT but buttons are ON
      }

      print("Condition C passed - remote XPUB exists, proceeding to Condition D");

      // ========================================
      // CONDITION D: Compare local vs remote XPUB
      // ========================================
      print("Condition D: Comparing local vs remote XPUB...");
      final xpubMatches = await ApiService().compareXpubWithServer();

      if (!xpubMatches) {
        // Condition !D: XPUB mismatch
        print("Condition !D: XPUB mismatch detected");
        appController.setXpubMismatchDetected();
        _showXpubMismatchMessage();
        appController.updateButtonVisibility(
          isServerReachable: true,
          hasRemoteXpub: true,
          xpubMatches: false,
          isHaltState: false,
        );
        return; // HALT
      }

      // Condition D: XPUB matches - fully paired
      print("Condition D: XPUB matches - user is fully paired");
      appController.clearXpubMismatchDetected();
      _showFullyPairedMessage();
      appController.updateButtonVisibility(
        isServerReachable: true,
        hasRemoteXpub: true,
        xpubMatches: true,
        isHaltState: false,
      );
    } catch (e) {
      print("Error in verification process: $e");
      _showLoginFailureDialog();
    }
  }

  /// Perform login process for existing users
  Future<void> _performLoginProcess(String email, String password) async {
    try {
      // STEP 2: Attempt login
      print("Step 2: Attempting login...");
      final loginResult = await ApiService().login(
        email: email,
        pass: password,
      );
      print("Step 2: Attempting login...${loginResult}");
      if (loginResult == 'OK') {
        print("Login successful");

        // STEP 3: Get user profile to check auth_code
        print("Step 3: Fetching user profile...");
        final profileResult = await ApiService().getUserProfile();

        if (profileResult == 'OK') {
          final authCode = appController.userProfileObject.value.payload?.authCode ?? 999;
          print("User profile loaded - auth_code: $authCode");

          // STEP 4: Handle different auth_code scenarios
          await _handleAuthCodeScenario(authCode);
        } else if (profileResult == 'BLOCKED_XPUB_MISMATCH') {
          print("API calls blocked due to xpub mismatch - data reset required");
          _showXpubMismatchDialog();
        } else {
          print("Failed to load user profile");
          _showLoginFailureDialog();
        }
      } else if (loginResult == 'BLOCKED_XPUB_MISMATCH') {
        print("API calls blocked due to xpub mismatch - data reset required");
        _showXpubMismatchDialog();
      } else {
        print("Login failed - wrong password");
        _showLoginFailureDialog();
      }
    } catch (e) {
      print("Error in login process: $e");
      _showLoginFailureDialog();
    }
  }

  /// Handle different auth_code scenarios
  Future<void> _handleAuthCodeScenario(int authCode) async {
    switch (authCode) {
      case 2:
        // Registered user - can scan
        print("Auth code 2: User is registered and can scan");
        _showSuccessMessage("User verified successfully");
        break;
      case 6:
        // Advanced user - need to compare XPUB
        print("Auth code 6: Advanced user - comparing XPUB...");
        final xpubMatches = await ApiService().compareXpubWithServer();

        if (xpubMatches) {
          print("XPUB matches - user verified");
          _showSuccessMessage("User verified successfully");
        } else {
          print("XPUB mismatch - reset required");
          _showXpubMismatchDialog();
        }
        break;
      default:
        print("Unknown auth_code: $authCode");
        _showLoginFailureDialog();
        break;
    }
  }

  void _showEmailVerificationDialog() {
    Get.dialog(
      AlertDialog(
        backgroundColor: cardBgColor.value,
        title: Text(
          "Check Your Email",
          style: TextStyle(
            color: primaryTextColor.value,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          "A verification email has been sent to your email address. Please check your inbox and follow the instructions to complete registration.",
          style: TextStyle(color: secondaryTextColor.value),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Get.back();
            },
            child: Text("OK", style: TextStyle(color: primaryColor.value)),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  void _showSuccessMessage(String message) {
    Get.snackbar(
      'Success',
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.green.withOpacity(0.9),
      colorText: Colors.white,
    );
  }

  /// Show server unreachable message (Condition !conn)
  void _showServerUnreachableMessage() {
    Get.snackbar(
      'Server Unreachable',
      'Server is not accessible',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.red.withOpacity(0.9),
      colorText: Colors.white,
      duration: Duration(seconds: 5),
    );
  }

  /// Show registration attempt message (Condition !A)
  void _showRegistrationAttemptMessage(String email) {
    Get.snackbar(
      'Registration Requested',
      'A registration attempt was requested. CadenaBitcoin cannot be accessed with the credentials saved in your APP. You will receive an email with instructions shortly.',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.red.withOpacity(0.9),
      colorText: Colors.white,
      duration: Duration(seconds: 8),
    );
  }

  /// Show registration required message (auth_code = ..xx0x)
  void _showRegistrationRequiredMessage() {
    Get.snackbar(
      'Registration Required',
      'User is not registered. Please check your email to complete registration.',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.red.withOpacity(0.9),
      colorText: Colors.white,
      duration: Duration(seconds: 5),
    );
  }

  /// Show pairing required message (Condition C - no remote XPUB)
  void _showPairingRequiredMessage() {
    Get.snackbar(
      'Pairing Required',
      'Please Pair your device with Cadena. Push the Pair button and follow instructions!',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.orange.withOpacity(0.9),
      colorText: Colors.white,
      duration: Duration(seconds: 6),
    );
  }

  /// Show XPUB mismatch message (Condition !D)
  void _showXpubMismatchMessage() {
    Get.snackbar(
      'XPUB Mismatch',
      'The XPUB derived from the SeedPhrase does not match the one stored with Cadena online',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.red.withOpacity(0.9),
      colorText: Colors.white,
      duration: Duration(seconds: 6),
    );
  }

  /// Show fully paired message (Condition D)
  void _showFullyPairedMessage() {
    Get.snackbar(
      'Fully Paired',
      'You are paired with CadenaBitcoin',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.green.withOpacity(0.9),
      colorText: Colors.white,
      duration: Duration(seconds: 3),
    );
  }

  void _showXpubMismatchDialog() {
    Get.dialog(
      AlertDialog(
        backgroundColor: cardBgColor.value,
        title: Text(
          "XPUB Mismatch",
          style: TextStyle(
            color: primaryTextColor.value,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          "Your local XPUB doesn't match the server XPUB. This may indicate a security issue. Please reset your data.",
          style: TextStyle(color: secondaryTextColor.value),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Get.back();
            },
            child: Text("Cancel", style: TextStyle(color: primaryColor.value)),
          ),
          TextButton(
            onPressed: () async {
              Get.back();
              await _wipeAllData();
              Get.offAll(() => SplashScreen());
            },
            child: Text("Reset Data", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  void _showLoginFailureDialog() {
    Get.dialog(
      AlertDialog(
        backgroundColor: cardBgColor.value,
        title: Text(
          "Verification Failed",
          style: TextStyle(
            color: primaryTextColor.value,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          "Incorrect email or password",
          style: TextStyle(color: secondaryTextColor.value),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Get.back();
            },
            child: Text("Cancel", style: TextStyle(color: primaryColor.value)),
          ),
          TextButton(
            onPressed: () async {
              Get.back();
              await _wipeAllData();
              Get.offAll(() => SplashScreen());
            },
            child: Text("WipeData", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  Future<void> _wipeAllData() async {
    try {
      await appController.wipeAllLocalDataAndEnterOffline();

      Get.snackbar(
        'Data Cleared',
        'All local data has been removed',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      print("Error wiping data: $e");
    }
  }

  // Future<void> _checkLocalUserData() async {
  //   try {
  //     // Get the logged in user's email
  //     final loggedInEmail = await StorageService.getLoggedInEmail();
  //
  //     if (loggedInEmail != null && loggedInEmail.isNotEmpty) {
  //       // Check if user data exists for this email
  //       final userData = await StorageService.getUserByEmail(loggedInEmail);
  //       if (userData != null &&
  //           userData['email'] != null &&
  //           userData['password'] != null &&
  //           userData['mnemonic'] != null &&
  //           userData['xpub'] != null) {
  //         Get.snackbar(
  //           'Success',
  //           'User verified successfully',
  //           snackPosition: SnackPosition.BOTTOM,
  //           backgroundColor: Colors.green.withOpacity(0.9),
  //           colorText: Colors.white,
  //           duration: Duration(seconds: 2),
  //         );
  //       } else {
  //         // Some user data missing
  //         Get.snackbar(
  //           'User Unverified',
  //           'Incomplete user data in local storage',
  //           snackPosition: SnackPosition.BOTTOM,
  //           backgroundColor: Colors.red.withOpacity(0.9),
  //           colorText: Colors.white,
  //           duration: Duration(seconds: 2),
  //         );
  //       }
  //     } else {
  //       // No logged in email found
  //       Get.snackbar(
  //         'User Unverified',
  //         'No logged in user found',
  //         snackPosition: SnackPosition.BOTTOM,
  //         backgroundColor: Colors.red.withOpacity(0.9),
  //         colorText: Colors.white,
  //         duration: Duration(seconds: 2),
  //       );
  //     }
  //   } catch (e) {
  //     print("Error checking local user data: $e");
  //     // show error case
  //     Get.snackbar(
  //       'User Unverified',
  //       'Error checking user data',
  //       snackPosition: SnackPosition.BOTTOM,
  //       backgroundColor: Colors.red.withOpacity(0.9),
  //       colorText: Colors.white,
  //       duration: Duration(seconds: 2),
  //     );
  //   }
  // }

  @override
  void dispose() {
    _profileTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Scaffold(
        backgroundColor: primaryBackgroundColor.value,
        body: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: ListView(
              // crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Dashboard", style: AppTextStyles.heading1),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: primaryColor.value.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: GestureDetector(
                        // onTap: () async {
                        //   final _storage = const FlutterSecureStorage();
                        //   final SharedPreferences prefs =
                        //       await SharedPreferences.getInstance();
                        //   await prefs.clear();
                        //
                        //   final emailKey = 'logged_in_user_email';
                        //
                        //   final storedData = await _storage.read(key: emailKey);
                        //   await _storage.delete(key: "logged_in_user_email");
                        //   await _storage.delete(key: "user_${storedData}");
                        //
                        //   await _storage.deleteAll().then(
                        //     await Get.offAll(SignInScreen()),
                        //   );
                        // },
                        onTap: () async {
                          // Only set isLoggedIn to false, don't delete user data
                          await StorageService.logoutUser();
                          appController.userProfileObject.value = UserProfileModel();
                          // final emailKey = 'logged_in_user_email';
                          // final storedData = await _storage.read(key: emailKey);
                          // await _storage.delete(key: "logged_in_user_email");
                          // await _storage.delete(key: "logged_in_user_password");
                          // await _storage.delete(key: "user_${storedData}");

                          // await _storage
                          //     .deleteAll()
                          //     .then(await Get.offAll(SignInScreen()));
                          // Navigate to sign-in screen
                          Get.offAll(() => VerifyPasswordScreen());
                        },
                        child: Text(
                          "Logout",
                          style: AppTextStyles.caption.copyWith(
                            color: subTextColor.value,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Obx(() => _buildAppVersionDisplay()),
                if (AppController.USE_TESTNET) const SizedBox(height: 8),
                if (AppController.USE_TESTNET) _buildSignetBanner(),
                const SizedBox(height: 16),
                // Status Card with email (profile email, fallback to local)
                FutureBuilder<String>(
                  future: _getLocalEmail(),
                  builder: (context, snapshot) {
                    final localEmail = snapshot.data ?? '';
                    final profileEmail = appController.userProfileObject.value.payload?.email ?? '';
                    final displayEmail = profileEmail.isNotEmpty ? profileEmail : localEmail;

                    return Obx(() => _buildInfoCard(
                          title: "User Status ${displayEmail}",
                          value: appController.getUserStatus(),
                          icon: appController.getStatusIcon(),
                          valueColor: appController.getStatusColor(),
                        ));
                  },
                ),
                const SizedBox(height: 16),
                // Prominent Cadena connect CTA (after credentials created/restored)
                Obx(() => appController.showVerifyButton.value
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: ConnectToCadenaButton(
                          isLoading: _isConnectingToCadena,
                          onTap: () {
                            _verifyUser().then((_) {
                              initWallet();
                              ApiService().getUserProfile();
                              _checkTokenAndStartTimer();
                            });
                          },
                        ),
                      )
                    : const SizedBox.shrink()),
                // KYC Status Card (chip opens Sumsub when actionable)
                // Soft-subordinated until Cadena connect — requires online session
                _subordinateIfNeedsConnect(
                  child: Obx(() {
                    final kycStatus =
                        appController.userProfileObject.value.payload?.kycStatus;
                    final display = _kycDisplayText(kycStatus);
                    final actionable = _kycIsActionable(kycStatus) &&
                        !_kycIsVerified(kycStatus) &&
                        !_kycIsInProgress(kycStatus);

                    return _buildInfoCard(
                      title: "KYC Status",
                      value: _isKycLaunching ? "Opening..." : display,
                      icon: _kycIcon(kycStatus),
                      valueColor: _kycColor(kycStatus),
                      trailing: (actionable && !_isKycLaunching)
                          ? GestureDetector(
                              onTap: _startKycFlow,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: primaryColor.value.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'Verify',
                                  style: AppTextStyles.caption.copyWith(
                                    color: subTextColor.value,
                                  ),
                                ),
                              ),
                            )
                          : null,
                    );
                  }),
                ),

                const SizedBox(height: 16),

                // Mode Card
                Obx(() => Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: inputFieldBackgroundColor.value,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderColor.value),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              // Left Icon
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: primaryColor.value.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  autoSigningService.isAutoSigningEnabled.value ? Icons.auto_awesome : Icons.touch_app_outlined,
                                  color: primaryColor.value,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 16),

                              // Text
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Signing Mode', style: AppTextStyles.body),
                                    const SizedBox(height: 4),
                                    Text(
                                      autoSigningService.isAutoSigningEnabled.value ? 'Automatic' : 'Manual',
                                      style: AppTextStyles.heading3.copyWith(
                                        color: autoSigningService.isAutoSigningEnabled.value ? Colors.green : warningColor.value,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Transform.scale(
                                scale: 0.8,
                                child: Switch(
                                  value: autoSigningService.isAutoSigningEnabled.value,
                                  activeColor: primaryColor.value,
                                  inactiveThumbColor: borderColor.value,
                                  inactiveTrackColor: borderColor.value.withOpacity(0.3),
                                  onChanged: (value) {
                                    autoSigningService.toggleAutoSigning(value);
                                  },
                                ),
                              ),
                            ],
                          ),
                          // Status indicator for both manual and automatic modes
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: autoSigningService.isAutoSigningEnabled.value ? Colors.blue.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color:
                                      autoSigningService.isAutoSigningEnabled.value ? Colors.blue.withOpacity(0.3) : Colors.orange.withOpacity(0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  autoSigningService.isProcessing.value
                                      ? Icons.sync
                                      : (autoSigningService.isAutoSigningEnabled.value ? Icons.check_circle : Icons.notifications),
                                  color: autoSigningService.isProcessing.value
                                      ? Colors.blue
                                      : (autoSigningService.isAutoSigningEnabled.value ? Colors.green : Colors.orange),
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  autoSigningService.isProcessing.value
                                      ? 'Processing transaction...'
                                      : (autoSigningService.isAutoSigningEnabled.value
                                          ? 'Monitoring for transactions'
                                          : 'Monitoring for notifications'),
                                  style: AppTextStyles.caption.copyWith(
                                    color: autoSigningService.isProcessing.value
                                        ? Colors.blue
                                        : (autoSigningService.isAutoSigningEnabled.value ? Colors.green : Colors.orange),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildBalanceCard(
                        title: "Wallet Balance",
                        amount:
                            "${UtilService().toFixed2DecimalPlaces("${satoshiToBitcoin(num.parse(appController.userProfileObject.value.payload?.balanceOnchain.toString() ?? '0'))}", decimalPlaces: 8)}\nBTC",
                        icon: Icons.account_balance_wallet_outlined,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildBalanceCard(
                        title: "Liquid Balance",
                        amount:
                            "${UtilService().toFixed2DecimalPlaces("${satoshiToBitcoin(num.parse(appController.userProfileObject.value.payload?.balanceDerived.toString() ?? '0'))}", decimalPlaces: 8)}\nBTC",
                        icon: Icons.water_drop_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Quick Actions Title
                Text("Quick Actions", style: AppTextStyles.heading2),
                const SizedBox(height: 16),

                // Quick Actions Buttons
                // Soft-subordinate Cadena-online actions (Refresh / Pair) until CONNECT
                _subordinateIfNeedsConnect(
                  child: Row(
                    spacing: 16,
                    children: [
                      if (!appController.showVerifyButton.value)
                        Expanded(
                            child: _buildActionButton(
                                icon: Icons.refresh,
                                label: "Refresh",
                                onTap: () {
                                  autoSigningService.checkForNewTransactions();
                                })),
                      Obx(() => appController.showScanButton.value
                          ? Expanded(
                              child: _buildActionButton(
                                icon: Icons.qr_code_scanner,
                                label: "Pair",
                                onTap: () async {
                                  Get.to(() => QrScanner())?.then((onValue) async {
                                    debugPrint('onValue : $onValue');
                                    qrText.value = onValue ?? '';
                                    debugPrint(' qrText.value  : ${qrText.value}');

                                    if (onValue != null && onValue.isNotEmpty) {
                                      try {
                                        // Parse the QR JSON result
                                        final Map<String, dynamic> qrData = jsonDecode(onValue);
                                        final String? upgradeURL = qrData['upgradeURL'];

                                        if (upgradeURL != null) {
                                          // Get xpub from local storage
                                          final loggedInEmail = await StorageService.getLoggedInEmail();
                                          final userData = await StorageService.getUserByEmail(
                                            loggedInEmail ?? '',
                                          );
                                          final String? xpub = userData?['xpub'];

                                          if (xpub != null && xpub.isNotEmpty) {
                                            // Call the API with dynamic URL and local xpub
                                            ApiService()
                                                .userUpgradePubx(
                                              xpub: xpub,
                                              upgradeURL: upgradeURL,
                                            )
                                                .then((result) {
                                              if (result == "OK") {
                                                Get.snackbar(
                                                  'Success',
                                                  'User XPub upgraded successfully.',
                                                  snackPosition: SnackPosition.BOTTOM,
                                                  backgroundColor: Colors.green.withOpacity(0.9),
                                                  colorText: Colors.white,
                                                );
                                              } else if (result == "BLOCKED_XPUB_MISMATCH") {
                                                print("API call blocked due to xpub mismatch - data reset required");
                                                _showXpubMismatchDialog();
                                              } else {
                                                Get.snackbar(
                                                  'Error',
                                                  'Failed to upgrade user',
                                                  snackPosition: SnackPosition.BOTTOM,
                                                  backgroundColor: Colors.red.withOpacity(0.9),
                                                  colorText: Colors.white,
                                                );
                                              }
                                            });
                                          } else {
                                            print("No xpub found in local storage");
                                          }
                                        } else {
                                          print("No upgradeURL found in QR data");
                                        }
                                      } catch (e) {
                                        print("Error parsing QR data: $e");
                                      }
                                    }
                                  });
                                },
                              ),
                            )
                          : SizedBox.shrink()),
                    ],
                  ),
                ),
                SizedBox(
                  height: 16,
                ),
                Obx(() => appController.showResetButton.value
                    ? _buildActionButton(
                        icon: Icons.restart_alt,
                        label: "Reset",
                        onTap: () async {
                          await _wipeAllData();
                          Get.offAll(() => SplashScreen());
                        },
                      )
                    : SizedBox.shrink()),
                Obx(() => SizedBox(
                      height: (appController.showVerifyButton.value || appController.showResetButton.value) ? 60 : 0,
                    )),
                if (Platform.isAndroid)
                  _buildActionButton(
                      icon: AppMinimizeService.to.minimizeButtonIcon,
                      label: AppMinimizeService.to.minimizeButtonText,
                      onTap: () {
                        AppMinimizeService.to.minimizeApp();
                      }),
                SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSignetBanner() {
    // Only show banner if using testnet/signet environment
    if (!AppController.USE_TESTNET) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_outlined,
            color: Colors.orange,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Test Environment',
                  style: AppTextStyles.body.copyWith(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'You are using Signet environment.',
                  style: AppTextStyles.caption.copyWith(
                    color: Colors.orange.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required String value,
    required IconData icon,
    Color? valueColor,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: inputFieldBackgroundColor.value,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor.value),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primaryColor.value.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: primaryColor.value, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.body),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: AppTextStyles.heading3.copyWith(
                    color: valueColor ?? primaryTextColor.value,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing,
          ],
        ],
      ),
    );
  }

  Widget _buildBalanceCard({
    required String title,
    required String amount,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: inputFieldBackgroundColor.value,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor.value),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: primaryColor.value.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: primaryColor.value, size: 16),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title,
                  style: AppTextStyles.body.copyWith(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            amount,
            style: AppTextStyles.heading2.copyWith(color: primaryTextColor.value, fontWeight: FontWeight.w600, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: inputFieldBackgroundColor.value,
        foregroundColor: primaryTextColor.value,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: borderColor.value),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Row(
        spacing: 8,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20),
          Text(label, style: AppTextStyles.body),
        ],
      ),
    );
  }

  Widget _buildAppVersionDisplay() {
    final appVersion = appController.appVersionObject.value.payload?.appVersionNrNewest;
    final apiVersion = appController.appVersionObject.value.payload?.apiVersionNr;

    if (appVersion == null && apiVersion == null) {
      return SizedBox.shrink();
    }

    return Container(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text(
            'App: ${appVersion ?? 'N/A'} | API: ${apiVersion ?? 'N/A'}',
            style: AppTextStyles.caption.copyWith(
              color: primaryTextColor.value.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  String satoshiToBitcoin(num satoshi) {
    num bitcoin = satoshi / 100000000;
    return bitcoin.toStringAsFixed(
      8,
    );
  }
}
