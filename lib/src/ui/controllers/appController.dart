import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signer/models/appVersionEPModel.dart';
import 'package:signer/models/sigReqsByDlcIdsModel.dart';
import 'package:signer/models/userOfferDlcPollModel.dart';
import 'package:signer/models/user_profile_model.dart';
import 'package:signer/models/xpub_validation_model.dart';
import 'package:signer/models/dlc_signature_response_model.dart';
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
  
  // XPUB mismatch state management
  var xpubMismatchDetected = false.obs;

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
  static const String API_BASE_URL = String.fromEnvironment(
    'API_BASE_URL', defaultValue: 'http://cadenabitcoin.com/app');
  // For staging: "http://staging.purabitcoin.com/app"
  
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
  
  /// Get user status based on auth code level
  String getUserStatus() {
    final authCode = userProfileObject.value.payload?.authCode;
    if(authCode == null){
      return "Please verify";
    }
    if (authCode < 2) {
      return "Check Email";
    } else if (authCode < 6) {
      return "Active";
    } else if (authCode == 6) {
      return "Signer";
    } else {
      return "";
    }
  }
  
  /// Get appropriate icon for user status
  IconData getStatusIcon() {
    final authCode = userProfileObject.value.payload?.authCode;
    if(authCode == null){
      return Icons.help_outline;
    }
    if (authCode < 2) {
      return Icons.email_outlined;
    } else if (authCode < 6) {
      return Icons.verified_user_outlined;
    } else if (authCode == 6) {
      return Icons.security_outlined;
    } else {
      return Icons.help_outline;
    }
  }
  
  /// Get appropriate color for user status
  Color getStatusColor() {
    final authCode = userProfileObject.value.payload?.authCode;
    if(authCode == null){
      return Colors.grey;
    }
    if (authCode < 2) {
      return Colors.orange;
    } else if (authCode < 6) {
      return Colors.blue;
    } else if (authCode == 6) {
      return Colors.green;
    } else {
      return Colors.grey;
    }
  }
}
