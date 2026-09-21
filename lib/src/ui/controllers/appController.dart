import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signer/models/appVersionEPModel.dart';
import 'package:signer/models/sigReqsByDlcIdsModel.dart';
import 'package:signer/models/userOfferDlcPollModel.dart';
import 'package:signer/models/user_profile_model.dart';
import 'package:signer/models/xpub_validation_model.dart';
import 'package:signer/models/dlc_signature_response_model.dart';
import 'package:signer/services/storage_service.dart';
import 'package:signer/services/auto_signing_service.dart';
import 'package:signer/src/ui/screens/splashScreen.dart';
import 'package:bip32/bip32.dart'as bip32;

/// AppController - Central configuration for network settings
/// 
/// EASY NETWORK SWITCHING:
/// To switch between mainnet and testnet, simply change these two variables:
/// 
/// 1. USE_TESTNET = false (for mainnet) or true (for testnet/signet)
/// 2. API_BASE_URL = "http://cadenabitcoin.com/app" (mainnet) or "http://staging.purabitcoin.com/app" (staging)
/// 
/// NETWORK TYPES:
/// - MAINNET_NATIVE_SEGWIT: Generates vpub/vprv (recommended for mainnet)
/// - MAINNET_LEGACY: Generates xpub/xprv (legacy mainnet)
/// - SIGNET_NATIVE_SEGWIT: Generates vpub/vprv for signet
/// - TESTNET_NATIVE_SEGWIT: Generates tpub/tprv for testnet
/// 
/// DERIVATION PATHS:
/// - MAINNET_DERIVATION_PATH: "m/84'/0'/0'" (native segwit mainnet)
/// - TESTNET_DERIVATION_PATH: "m/84'/1'/0'" (native segwit testnet/signet)
/// 
/// ADDRESS FORMATS:
/// - Mainnet: bc1q... (bech32)
/// - Testnet: tb1q... (bech32)
/// - Signet: tb1q... (bech32)
class AppController extends GetxController {
  var isDark = false.obs;
  var selectedBottomTabIndex = 0.obs;
  var loginLoader = false.obs;
  var getUserProfileLoader = false.obs;
  var userProfileObject = UserProfileModel().obs;
  var xpubValidationObject = XpubValidationModel().obs;
  var xpubValidationLoader = false.obs;
  var userOfferDlcIdsPollLoader = false.obs;
  var userDlcByIdLoader = false.obs;

  var userUpgradeLoader = false.obs;
  var offerDlcSignaturesLoader = false.obs;
  var dlcSignatureResponseObject = DlcSignatureResponseModel().obs;
  var userOfferDlcIdsPollObject = UserOfferDlcIdsPoll().obs;
  var sigReqsByDlcIdsModelLoader = false.obs;
  var sigReqsByDlcIdsModelObject = SigReqsByDlcIdsModel().obs;
  
  // App version management
  var appVersionObject = AppVersionEPModel().obs;
  
  // Home screen state management
  var showVerifyButton = true.obs;
  var showScanButton = false.obs;
  var showResetButton = false.obs;
  
  // XPUB mismatch state management
  var xpubMismatchDetected = false.obs;
  
  // Server connection state
  var serverReachable = true.obs;

  // Auth failure tracking (401 responses)
  var consecutive401Count = 0.obs;
  static const int max401BeforeWipe = 10;

  /// When false, the app is in offline / not-connected mode after session teardown.
  /// Auth retries and 401 wipe dialogs must not run until a new login succeeds.
  var backendSessionActive = true.obs;

  // ========================================
  // NETWORK CONFIGURATION - EASY SWITCHING
  // ========================================
  
  /// Set to true for testnet/signet, false for mainnet
  /// 
  /// EXAMPLE SWITCHING:
  /// For MAINNET: USE_TESTNET = false, API_BASE_URL = "http://cadenabitcoin.com/app"
  /// For STAGING: USE_TESTNET = true, API_BASE_URL = "http://staging.purabitcoin.com/app"
  static const bool USE_TESTNET = false;
  
  /// Environment string for API calls: "bitcoin" for mainnet, "signet" for testnet
  static const String NETWORK_ENVIRONMENT = "bitcoin";
  
  /// API Base URL - change this for different environments
  static const String API_BASE_URL = "http://cadenabitcoin.com/app";
  // For mainnet: "http://cadenabitcoin.com/app"
  
  // ========================================
  // BIP32 NETWORK TYPES
  // ========================================
  
  /// Mainnet Native Segwit (P2WPKH) - generates vpub/vprv
  var MAINNET_NATIVE_SEGWIT = bip32.NetworkType(
    bip32: bip32.Bip32Type(
      public: 0x04b24746,  // vpub prefix
      private: 0x04b2430c, // vprv prefix
    ),
    wif: 0x80, // Mainnet WIF prefix
  );
  
  /// Mainnet Legacy (P2PKH) - generates xpub/xprv
  var MAINNET_LEGACY = bip32.NetworkType(
    bip32: bip32.Bip32Type(
      public: 0x0488B21E,  // xpub prefix
      private: 0x0488ADE4, // xprv prefix
    ),
    wif: 0x80, // Mainnet WIF prefix
  );
  
  /// Signet Native Segwit (P2WPKH) - generates vpub/vprv
  var SIGNET_NATIVE_SEGWIT = bip32.NetworkType(
    bip32: bip32.Bip32Type(
      public: 0x045f1cf6,  // vpub prefix for signet
      private: 0x045f18bc, // vprv prefix for signet
    ),
    wif: 0xEF, // Signet WIF prefix
  );
  
  /// Testnet Native Segwit (P2WPKH) - generates tpub/tprv
  var TESTNET_NATIVE_SEGWIT = bip32.NetworkType(
    bip32: bip32.Bip32Type(
      public: 0x043587cf,  // tpub prefix
      private: 0x04358394, // tprv prefix
    ),
    wif: 0xEF, // Testnet WIF prefix
  );
  
  // ========================================
  // DERIVATION PATHS
  // ========================================
  
  /// Mainnet Native Segwit derivation path
  static const String MAINNET_DERIVATION_PATH = "m/84'/0'/0'";
  
  /// Testnet/Signet Native Segwit derivation path
  static const String TESTNET_DERIVATION_PATH = "m/84'/1'/0'";
  
  // ========================================
  // ACTIVE CONFIGURATION
  // ========================================
  
  /// Current network type - automatically selected based on USE_TESTNET
  bip32.NetworkType get currentNetworkType => USE_TESTNET ? SIGNET_NATIVE_SEGWIT : MAINNET_NATIVE_SEGWIT;
  
  /// Current derivation path - automatically selected based on USE_TESTNET
  String get currentDerivationPath => USE_TESTNET ? TESTNET_DERIVATION_PATH : MAINNET_DERIVATION_PATH;
  
  /// Current environment string for API calls
  String get currentEnvironment => NETWORK_ENVIRONMENT;
  
  /// Whether we're using testnet (for address generation)
  bool get isTestnet => USE_TESTNET;
  
  /// Legacy variable for backward compatibility
  bip32.NetworkType get mainnet => currentNetworkType;
  
  // ========================================
  // HOME SCREEN STATE MANAGEMENT
  // ========================================
  
  /// Check JWT token and update button states accordingly
  Future<void> checkJwtTokenAndUpdateButtons() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwtToken');
      
      if (jwtToken != null && jwtToken.isNotEmpty) {
        // Check if user is auth_code = 6 (advanced user)
        final authCode = userProfileObject.value.payload?.authCode ?? 999;
        
        if (authCode == 6) {
          // For advanced users, keep verify button visible
          showVerifyButton.value = true;
        } else {
          // For other users, hide verify button when logged in
          showVerifyButton.value = false;
        }
        
        // Don't set showScanButton here - it depends on authCode from user profile
        // showScanButton will be set by _checkTokenAndGetProfile() based on authCode
      } else {
        showVerifyButton.value = true;
        showScanButton.value = false;
      }
    } catch (e) {
      print("Error checking JWT token: $e");
      showVerifyButton.value = true;
      showScanButton.value = false;
    }
  }
  
  /// Set xpub mismatch flag when data is reset due to xpub mismatch
  void setXpubMismatchDetected() {
    xpubMismatchDetected.value = true;
    print("XPUB mismatch detected - API calls will be blocked");
  }
  
  /// Clear xpub mismatch flag when user successfully logs in
  void clearXpubMismatchDetected() {
    xpubMismatchDetected.value = false;
    print("XPUB mismatch flag cleared - API calls are now allowed");
  }
  
  /// Check if API calls should be blocked due to xpub mismatch
  bool shouldBlockApiCalls() {
    return xpubMismatchDetected.value;
  }
  
  // ========================================
  // STATUS MANAGEMENT
  // ========================================
  
  /// Get user status based on decision tree conditions
  String getUserStatus() {
    // Check server reachability first
    if (!serverReachable.value) {
      return "CadenaBitcoin out of reach";
    }
    
    // Check XPUB mismatch
    if (xpubMismatchDetected.value) {
      return "XPUB mismatch";
    }
    
    final authCode = userProfileObject.value.payload?.authCode;
    final remoteXpub = userProfileObject.value.payload?.xpub;
    final hasRemoteXpub = remoteXpub != null && remoteXpub.isNotEmpty;
    
    if (authCode == null) {
      return "Please verify";
    }
    
    // Check if user is registered (bit-1 set)
    final isRegistered = (authCode & 2) != 0;
    
    if (!isRegistered) {
      return "Check Email";
    }
    
    if (!hasRemoteXpub) {
      // Condition C: No remote XPUB
      return "Active";
    }
    
    // Condition D: Has remote XPUB and matches (fully paired)
    return "Signer";
  }
  
  /// Get appropriate icon for user status
  IconData getStatusIcon() {
    if (!serverReachable.value) {
      return Icons.cloud_off_outlined;
    }
    
    if (xpubMismatchDetected.value) {
      return Icons.error_outline;
    }
    
    final authCode = userProfileObject.value.payload?.authCode;
    final remoteXpub = userProfileObject.value.payload?.xpub;
    final hasRemoteXpub = remoteXpub != null && remoteXpub.isNotEmpty;
    
    if (authCode == null) {
      return Icons.help_outline;
    }
    
    final isRegistered = (authCode & 2) != 0;
    
    if (!isRegistered) {
      return Icons.email_outlined;
    }
    
    if (!hasRemoteXpub) {
      return Icons.verified_user_outlined;
    }
    
    return Icons.security_outlined;
  }
  
  /// Get appropriate color for user status
  Color getStatusColor() {
    if (!serverReachable.value) {
      return Colors.red;
    }
    
    if (xpubMismatchDetected.value) {
      return Colors.red;
    }
    
    final authCode = userProfileObject.value.payload?.authCode;
    final remoteXpub = userProfileObject.value.payload?.xpub;
    final hasRemoteXpub = remoteXpub != null && remoteXpub.isNotEmpty;
    
    if (authCode == null) {
      return Colors.grey;
    }
    
    final isRegistered = (authCode & 2) != 0;
    
    if (!isRegistered) {
      return Colors.orange;
    }
    
    if (!hasRemoteXpub) {
      // Condition C: ORANGE for pairing needed
      return Colors.orange;
    }
    
    // Condition D: GREEN for fully paired
    return Colors.green;
  }
  
  // ========================================
  // BUTTON VISIBILITY CONTROL
  // ========================================
  
  /// Update button visibility based on decision tree conditions
  /// Condition C (no remote XPUB, auth_code = ..x01x): Scan ON, Verify ON, Reset HIDE
  /// Condition D mismatch (!D): Scan OFF, Verify OFF, Reset ON
  /// Condition D match (D): Scan OFF, Verify OFF, Reset HIDE
  /// HALT states: Scan OFF, Verify ON, Reset HIDE
  void updateButtonVisibility({
    required bool isServerReachable,
    required bool hasRemoteXpub,
    required bool xpubMatches,
    required bool isHaltState,
  }) {
    if (!isServerReachable || isHaltState) {
      // HALT states: server unreachable or other halt conditions
      showScanButton.value = false;
      showVerifyButton.value = true;
      showResetButton.value = false;
    } else if (!hasRemoteXpub) {
      // Condition C: No remote XPUB (auth_code = ..x01x)
      showScanButton.value = true;
      showVerifyButton.value = true;
      showResetButton.value = false;
    } else if (!xpubMatches) {
      // Condition !D: XPUB mismatch
      showScanButton.value = false;
      showVerifyButton.value = false;
      showResetButton.value = true;
    } else {
      // Condition D: XPUB matches - fully paired
      showScanButton.value = false;
      showVerifyButton.value = false;
      showResetButton.value = false;
    }
  }
  
  /// Set server reachability status
  void setServerReachable(bool reachable) {
    serverReachable.value = reachable;
  }

  /// Handle consecutive 401 authentication failures.
  Future<void> handleAuth401() async {
    if (!backendSessionActive.value) {
      // Session already torn down (e.g. after Reset Data) — do not retry or re-prompt.
      return;
    }
    consecutive401Count.value++;
    if (consecutive401Count.value >= max401BeforeWipe) {
      consecutive401Count.value = 0;
      await _showAuthFailureResetDialog();
    }
  }

  /// Reset the 401 counter on successful authenticated calls.
  void resetAuth401Counter() {
    consecutive401Count.value = 0;
  }

  /// Mark backend session as active after a successful login / CONNECT.
  void activateBackendSession() {
    backendSessionActive.value = true;
    resetAuth401Counter();
    clearXpubMismatchDetected();
    setServerReachable(true);
  }

  Future<void> _showAuthFailureResetDialog() async {
    Get.dialog(
      AlertDialog(
        title: const Text("Session Invalid"),
        content: const Text(
            "We received repeated authentication errors. Your account may have been removed. Please reset your data."),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              Get.back();
              await wipeAllLocalDataAndEnterOffline();
              Get.offAll(() => SplashScreen());
            },
            child: const Text(
              "Reset Data",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  /// Wipe local data, stop auth retries/polling, and enter offline / not-connected state.
  /// Does not require backend availability. Safe to call from Session Invalid or other reset flows.
  Future<void> wipeAllLocalDataAndEnterOffline() async {
    // Stop retries first so wiped credentials cannot keep being used,
    // even if a later storage wipe step fails on a given platform.
    backendSessionActive.value = false;
    resetAuth401Counter();

    try {
      final autoSigning = Get.find<AutoSigningService>();
      await autoSigning.stopAllSessionActivity();
    } catch (e) {
      print("AutoSigningService not available during session wipe: $e");
    }

    try {
      await StorageService.clearAllUsers();
    } catch (e) {
      print("Error clearing users during session wipe: $e");
    }

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (e) {
      print("Error clearing SharedPreferences during session wipe: $e");
    }

    try {
      const FlutterSecureStorage storage = FlutterSecureStorage();
      await storage.deleteAll();
    } catch (e) {
      print("Error clearing secure storage during session wipe: $e");
    }

    // Discard invalid in-memory session / API state
    userProfileObject.value = UserProfileModel();
    xpubValidationObject.value = XpubValidationModel();
    userOfferDlcIdsPollObject.value = UserOfferDlcIdsPoll();
    sigReqsByDlcIdsModelObject.value = SigReqsByDlcIdsModel();
    dlcSignatureResponseObject.value = DlcSignatureResponseModel();
    appVersionObject.value = AppVersionEPModel();

    // Offline / not-connected posture — local credential create/restore remains allowed
    setServerReachable(false);
    xpubMismatchDetected.value = false;
    showVerifyButton.value = true;
    showScanButton.value = false;
    showResetButton.value = false;
    selectedBottomTabIndex.value = 0;

    // Re-assert after storage steps in case of concurrent updates
    backendSessionActive.value = false;
    resetAuth401Counter();

    print("Session wiped — offline / not-connected; auth retries stopped");
  }

  /// Legacy name used by older call sites; delegates to [wipeAllLocalDataAndEnterOffline].
  Future<void> _wipeAllData() => wipeAllLocalDataAndEnterOffline();
}
