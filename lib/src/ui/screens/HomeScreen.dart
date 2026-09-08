import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

    if (jwtToken != null && jwtToken.isNotEmpty) {
      debugPrint("JWT token found, starting periodic timer");
      // Start timer only if JWT token exists
      _profileTimer = Timer.periodic(Duration(seconds: 10), (timer) {
        ApiService().getUserProfile();
      });
    } else {
      debugPrint("No JWT token found, timer not started");
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
    }
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

  /// Complete verification process as per requirements
  Future<void> _performVerificationProcess(String email, String password) async {
    try {
      // STEP 1: Try to register new user first
      print("Step 1: Attempting to register new user...");
      final registerResult = await ApiService().registerNewUser(
        email: email,
        pass: password,
      );

      if (registerResult == 'OK') {
        // Registration successful - user is new (auth_code = 0)
        print("Registration successful - user is new");
        _showEmailVerificationDialog();
        return;
      } else if (registerResult == 'USER_EXISTS' || registerResult == 'USER_CONFIRMED') {
        // User already exists (confirmed or not) - proceed to login
        print("User already exists - proceeding to login...");
        await _performLoginProcess(email, password);
      } else {
        // Registration failed for other reasons
        print("Registration failed: $registerResult");
        _showLoginFailureDialog();
      }
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
      // Set xpub mismatch flag to block API calls
      appController.setXpubMismatchDetected();

      // Deactivate the installation before credentials are destroyed.
      await StorageService.resetUserData();

      print("All data wiped successfully - API calls will be blocked until next login");

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
                // Status Card
                Obx(() => _buildInfoCard(
                      title: "Signer Status",
                      value: appController.getUserStatus(),
                      icon: appController.getStatusIcon(),
                      valueColor: appController.getStatusColor(),
                    )),
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
                Row(
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
                                                'User Upgrade Pubx successfully',
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
                // if (showVerifyButton) const Spacer(),
                // appController.userProfileObject.value.payload?.uuid != null &&
                //         appController.userProfileObject.value.payload?.uuid !=
                //             ""
                //     ? SizedBox.shrink()
                //     :
                SizedBox(
                  height: 16,
                ),
                Obx(() => appController.showVerifyButton.value
                    ? _buildActionButton(
                        icon: Icons.refresh,
                        label: "Verify",
                        onTap: () {
                          _verifyUser().then((_) {
                            initWallet();
                            ApiService().getUserProfile();
                            _checkTokenAndStartTimer();
                          });
                        },
                      )
                    : SizedBox.shrink()),
                Obx(() => SizedBox(
                      height: appController.showVerifyButton.value ? 60 : 0,
                    )),
                if (Platform.isAndroid)
                  _buildActionButton(
                      icon: AppMinimizeService.to.minimizeButtonIcon,
                      label: AppMinimizeService.to.minimizeButtonText,
                      onTap: () {
                        AppMinimizeService.to.minimizeApp();
                      }),
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
