import 'package:get/get.dart' as getX;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signer/models/appVersionEPModel.dart';
import 'package:signer/models/dlc_signature_response_model.dart';
import 'package:signer/models/sigReqsByDlcIdsModel.dart';
import 'package:signer/models/userOfferDlcPollModel.dart';
import 'package:signer/models/user_profile_model.dart';
import 'package:signer/models/xpub_validation_model.dart';
import 'package:signer/services/dataService/dataService.dart';
import 'package:signer/services/sharedPrefs.dart';
import 'package:signer/services/storage_service.dart';
import 'package:signer/src/ui/controllers/appController.dart';

class ApiService {
  final appController = getX.Get.find<AppController>();

  Future<String> login({String? email, String? pass}) async {
    // Allow login even if XPUB mismatch flag is set; only warn so the flow can recover.
    if (appController.shouldBlockApiCalls()) {
      print("XPUB mismatch flag set – allowing login so user can re-authenticate.");
    }

    appController.loginLoader.value = true;
    SharedPref sharedPref = SharedPref();
    SharedPreferences prefs = await SharedPreferences.getInstance();

    final data = {
      'username': email ?? '',
      'password': pass ?? '',
      'scope': '',
      'client_id': '',
      'client_secret': '',
    };

    final response = await DataService().genericDioPostCall(
      '/auth/app-token',
      data: data,
      isFormUrlEncoded: true,
    );

    print("Status Code: ${response?.statusCode}");

    appController.loginLoader.value = false;

    if (response != null &&
        response.statusCode == 200 &&
        response.data != null) {
      // Clear XPUB mismatch flag BEFORE saving token so the rest of the app can call APIs again.
      appController.clearXpubMismatchDetected();
      appController.activateBackendSession();
      saveToken(response.data['access_token']);
      return 'OK';
    } else {
      return 'FAILED';
    }
  }

  saveToken(token) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwtToken', token);
    
    // Immediately update button states after saving JWT token
    appController.checkJwtTokenAndUpdateButtons();
    
    // Also get user profile to set scan button based on authCode
    await getUserProfile();
  }

  /// Possible return values:
  /// 'OK'               -> Registration created (email confirmation required) OR generic success from API.
  /// 'USER_EXISTS'      -> Email already exists (backend indicated existing record via initiated=false)
  /// 'USER_CONFIRMED'   -> Registration already confirmed and enum-safe mode is off (backend returned 400 for already confirmed)
  /// 'PASSWORD_INVALID' -> Password policy violation (400)
  /// 'FAILED'           -> Any other error
  Future<String> registerNewUser({String? email, String? pass}) async {
    appController.loginLoader.value = true;

    final data = {
      'email_address': email ?? '',
      'password': pass ?? '',
    };

    try {
      final response = await DataService().genericDioPostCall(
        '/auth/new-user',
        data: data,
        isFormUrlEncoded: false,
      );

      print("Status Code: ${response?.statusCode}");

      if (response == null) return 'FAILED';
      if (response.statusCode == 200) {
        final respData = response.data ?? {};
        final payload = respData['payload'];

        // 1) Prefer the temporary/early 'initiated' boolean if present
        if (payload is Map && payload.containsKey('initiated')) {
          final initiated = payload['initiated'];
          if (initiated == true) {
            // New user created / email confirmation will be sent
            return 'OK';
          } else {
            // initiated == false => user exists (either confirmed or unconfirmed)
            return 'USER_EXISTS';
          }
        }

        // 2) Fallback to canonical API shape: payload.ok == true (generic success)
        if (payload is Map && payload['ok'] == true) {
          // The long-term API only gives a generic success response:
          // { "payload": {"ok": true}, "message": "...", "timestamp": ... }
          // We can't reliably tell whether it's a create/continue/no-op from this alone.
          // Return 'OK' to denote the call succeeded — the UI can decide whether to proceed to sign-in
          // or to show a "check your email" screen. If you want stricter behavior, query auth status next.
          return 'OK';
        }

        // If payload missing or in unexpected shape, consider it a generic success per spec
        return 'OK';
      }

      // -------------------------
      // 400 Bad Request handling
      // -------------------------
      if (response.statusCode == 400) {
        final respData = response.data ?? {};
        final message = (respData['message'] ?? '').toString();
        final detail = (respData['detail'] ?? '').toString();

        // Password policy violation (explicit per spec)
        if (message.contains('Password does not meet') || detail.contains('Password does not meet')) {
          return 'PASSWORD_INVALID';
        }

        // The spec: "Registration already confirmed and enumeration-safe mode is off." -> 400
        // Try to detect that case from 'message' or 'detail' if backend provides it.
        if (detail.toLowerCase().contains('already confirmed') ||
            message.toLowerCase().contains('already confirmed')) {
          return 'USER_CONFIRMED';
        }

        // Generic 400 fallback for user-exists / other validation
        return 'FAILED';
      }

      // Any other status codes -> failure
      return 'FAILED';
    } catch (e, st) {
      // Log and surface failure
      print('registerNewUser exception: ${e.runtimeType}');
      return 'FAILED';
    } finally {
      // Ensure loader is reset
      appController.loginLoader.value = false;
    }
  }


  // Future forgotPassword({
  //   String? email,
  // }) async {
  //   appController.forgotPasswordLoader.value = true;
  //
  //   String res = '';
  //   var data = {"email": "$email"};
  //
  //   Response? response = await DataService().genericDioPostCall('/users/forgot-password', data: data);
  //   print("response?.data['user'] ${response?.data}");
  //   print("response?.data['user'] ${response?.statusCode}");
  //
  //   if (response!.statusCode! <= 201) {
  //     appController.authToken.value = "${response?.data['token']}";
  //
  //     print(",,,,,${appController.authToken}");
  //
  //     appController.forgotPasswordLoader.value = false;
  //
  //     res = 'OK';
  //   } else {
  //     appController.forgotPasswordLoader.value = false;
  //   }
  //   appController.forgotPasswordLoader.value = false;
  //
  //   return res;
  // }

  // Future signUp({
  //   String? email,
  //   String? password,
  //   String? role,
  //   String? latitude,
  //   String? longitude,
  //   String? city,
  //   String? address,
  // }) async {
  //   appController.signUpLoader.value = true;
  //
  //   String res = '';
  //   var data = {"password": "$password", "longitude": "$longitude", "latitude": "$latitude", "email": "$email", "role": "$role", "city": "$city", "address": "$address"};
  //
  //   Response? response = await DataService().genericDioPostCall('/users/signup', data: data);
  //   print("response?.data['user'] ${response?.data}");
  //   print("response?.data['user'] ${response?.statusCode}");
  //
  //   if (response!.statusCode! <= 201) {
  //     res = '${response?.data['user']['id']}';
  //     appController.authToken.value = "${response?.data['token']}";
  //     appController.user.value = UserModel.fromJson(response?.data['user']);
  //     appController.signUpLoader.value = false;
  //   } else {
  //     appController.signUpLoader.value = false;
  //   }
  //   return res;
  // }

  Future<String> getUserProfile() async {
    // Check if API calls should be blocked due to xpub mismatch
    if (appController.shouldBlockApiCalls()) {
      print("API call blocked due to xpub mismatch - data reset required");
      appController.getUserProfileLoader.value = false;
      return 'BLOCKED_XPUB_MISMATCH';
    }
    
    appController.getUserProfileLoader.value = true;

    // Check if JWT token exists
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final jwtToken = prefs.getString('jwtToken');

    if (jwtToken == null || jwtToken.isEmpty) {
      print("No JWT token found, cannot call getUserProfile");
      appController.getUserProfileLoader.value = false;
      return 'NO_TOKEN';
    }

    final response = await DataService().genericDioGetCall(
      '/auth/users-app-profile',
    );

    print("Status Code: ${response?.statusCode}");

    if (response != null &&
        response.statusCode == 200 &&
        response.data != null) {
      appController.userProfileObject.value = UserProfileModel.fromJson(
        response.data,
      );
      
      // Update button visibility using new decision tree logic
      final authCode = appController.userProfileObject.value.payload?.authCode ?? 999;
      final remoteXpub = appController.userProfileObject.value.payload?.xpub;
      final hasRemoteXpub = remoteXpub != null && remoteXpub.isNotEmpty;
      
      // Check if user is registered (bit-1 set)
      final isRegistered = (authCode & 2) != 0;
      
      bool xpubMatches = false;
      if (hasRemoteXpub) {
        // Compare XPUB if remote XPUB exists
        xpubMatches = await compareXpubWithServer();
      }
      
      // Update button visibility based on decision tree
      appController.updateButtonVisibility(
        isServerReachable: appController.serverReachable.value,
        hasRemoteXpub: hasRemoteXpub && isRegistered,
        xpubMatches: xpubMatches,
        isHaltState: !isRegistered,
      );
      
      appController.getUserProfileLoader.value = false;
      return 'OK';
    } else {
      appController.getUserProfileLoader.value = false;
      return 'FAILED';
    }
  }

  /// Update button states based on auth_code
  void _updateButtonStatesBasedOnAuthCode(int authCode) {
    switch (authCode) {
      case 0:
        // New user - email sent, waiting for verification
        appController.showVerifyButton.value = true;
        appController.showScanButton.value = false;
        break;
      case 2:
        // Registered user - can scan
        appController.showVerifyButton.value = false;
        appController.showScanButton.value = true;
        break;
      case 6:
        // Advanced user - verify button can stay on, scan button off
        appController.showVerifyButton.value = true; // Can run verify anytime
        appController.showScanButton.value = false;
        break;
      default:
        // Unknown state - default to verify
        appController.showVerifyButton.value = true;
        appController.showScanButton.value = false;
        break;
    }
  }

  /// Compare local XPUB with server XPUB for auth_code = 6
  Future<bool> compareXpubWithServer() async {
    try {
      // Get local XPUB from storage
      final loggedInEmail = await StorageService.getLoggedInEmail();
      final userData = await StorageService.getUserByEmail(loggedInEmail ?? '');
      final localXpub = userData?['xpub'];
      
      // Get server XPUB from user profile
      final serverXpub = appController.userProfileObject.value.payload?.xpub;
      
      if (localXpub == null || serverXpub == null) {
        print("XPUB comparison failed: Missing local or server XPUB");
        return false;
      }
      
      
      return localXpub == serverXpub;
    } catch (e) {
      print("Error comparing XPUB: ${e.runtimeType}");
      return false;
    }
  }

  /*
  Future<String> userUpgradePubx({required String xpub}) async {
    appController.userUpgradeLoader.value = true;

    final data = {"xpub": "$xpub"};

    final response = await DataService().genericDioPostCall(
      '/dlca/v0/user-auth-s-upgrade',
      data: data,
      isFormUrlEncoded: false,
    );

    print("Status Code: ${response?.statusCode}");

    appController.userUpgradeLoader.value = false;

    if (response != null &&
        response.statusCode == 200 &&
        response.data != null) {
      return 'OK';
    } else {
      return 'FAILED';
    }
  }
*/
  Future<String> userUpgradePubx({
    required String xpub,
    required String upgradeURL,
  }) async {
    // Check if API calls should be blocked due to xpub mismatch
    if (appController.shouldBlockApiCalls()) {
      print("API call blocked due to xpub mismatch - data reset required");
      appController.userUpgradeLoader.value = false;
      return 'BLOCKED_XPUB_MISMATCH';
    }
    
    appController.userUpgradeLoader.value = true;

    final data = {"xpub": xpub};
    print("Using dynamic upgradeURL: $upgradeURL");

    // Extract the path from the full URL
    final uri = Uri.parse(upgradeURL);
    final path = uri.path;

    // Remove the base path "/app" if it exists to avoid duplication
    final cleanPath = path.startsWith('/app') ? path.substring(4) : path;
    print("Original path: $path");
    print("Clean path: $cleanPath");

    final response = await DataService().genericDioPostCall(
      cleanPath, // Use cleaned path to avoid double /app
      data: data,
      isFormUrlEncoded: false,
    );

    print("Status Code of userUpgradePubx: ${response?.statusCode}");

    appController.userUpgradeLoader.value = false;

    if (response != null &&
        response.statusCode == 200 &&
        response.data != null) {
      return 'OK';
    } else {
      return 'FAILED';
    }
  }

  Future<String> xpubValidation({required String xpub}) async {
    // Check if API calls should be blocked due to xpub mismatch
    if (appController.shouldBlockApiCalls()) {
      print("API call blocked due to xpub mismatch - data reset required");
      appController.xpubValidationLoader.value = false;
      return 'BLOCKED_XPUB_MISMATCH';
    }
    
    appController.xpubValidationLoader.value = true;

    final response = await DataService().genericDioGetCall(
      '/dlca/v0/xpub-validation?xpub=$xpub',
    );

    print("Status Code: ${response?.statusCode}");

    if (response != null &&
        response.statusCode == 200 &&
        response.data != null) {
      appController.xpubValidationObject.value = XpubValidationModel.fromJson(
        response.data,
      );
      print(
        "xpubValidationObject...${appController.xpubValidationObject.value.timestamp}",
      );
      appController.xpubValidationLoader.value = false;

      return 'OK';
    } else {
      appController.xpubValidationLoader.value = false;

      return 'FAILED';
    }
  }

  Future<String> userOfferDlcIdsPoll(String status) async {
    // Check if API calls should be blocked due to xpub mismatch
    if (appController.shouldBlockApiCalls()) {
      print("API call blocked due to xpub mismatch - data reset required");
      appController.userOfferDlcIdsPollLoader.value = false;
      return 'BLOCKED_XPUB_MISMATCH';
    }
    
    appController.userOfferDlcIdsPollLoader.value = true;
    String url;
    url = "/dlca/v0/user-offer-dlc-ids-poll?status_list=offer_dlc&status_list=sign_ini&status_list=sign_acc";

    final response = await DataService().genericDioGetCall('$url');

    print("Status Code: ${response?.statusCode}");

    if (response != null &&
        response.statusCode == 200 &&
        response.data != null) {
      appController.userOfferDlcIdsPollObject.value =
          UserOfferDlcIdsPoll.fromJson(response.data);
      print(
        "userProfile...${appController.userOfferDlcIdsPollObject.value.timestamp}",
      );
      appController.userOfferDlcIdsPollLoader.value = false;

      return 'OK';
    } else {
      appController.userOfferDlcIdsPollLoader.value = false;

      return 'FAILED';
    }
  }

  Future<String> userDlcById(String dlc_id) async {
    // Check if API calls should be blocked due to xpub mismatch
    if (appController.shouldBlockApiCalls()) {
      print("API call blocked due to xpub mismatch - data reset required");
      appController.userDlcByIdLoader.value = false;
      return 'BLOCKED_XPUB_MISMATCH';
    }
    
    appController.userDlcByIdLoader.value = true;
    String url;

    url = "/dlca/v0/user-dlc-by-id?dlc_id=$dlc_id";

    final response = await DataService().genericDioGetCall('$url');

    print("Status Code: ${response?.statusCode}");

    if (response != null &&
        response.statusCode == 200 &&
        response.data != null) {
      appController.userProfileObject.value = UserProfileModel.fromJson(
        response.data,
      );
      print("userProfile...${appController.userProfileObject.value.timestamp}");
      appController.userDlcByIdLoader.value = false;

      return 'OK';
    } else {
      appController.userDlcByIdLoader.value = false;

      return 'FAILED';
    }
  }

  Future<String> sigReqsByDlcIds(List<String> dlc_ids) async {
    // Check if API calls should be blocked due to xpub mismatch
    if (appController.shouldBlockApiCalls()) {
      print("API call blocked due to xpub mismatch - data reset required");
      appController.sigReqsByDlcIdsModelLoader.value = false;
      return 'BLOCKED_XPUB_MISMATCH';
    }
    
    appController.sigReqsByDlcIdsModelLoader.value = true;
    String url;
    String queryString = dlc_ids.map((id) => 'dlc_ids=$id').join('&');

    url = "/dlca/v0/sig-reqs-by-dlc-ids?$queryString";

    final response = await DataService().genericDioGetCall('$url');

    print("Status Code: ${response?.statusCode}");

    if (response != null &&
        response.statusCode == 200 &&
        response.data != null) {
      appController.sigReqsByDlcIdsModelObject.value =
          SigReqsByDlcIdsModel.fromJson(response.data);
      // print("userProfile...${appController.sigReqsByDlcIdsModelObject.value}");
      appController.sigReqsByDlcIdsModelLoader.value = false;

      return 'OK';
    } else {
      appController.sigReqsByDlcIdsModelLoader.value = false;

      return 'FAILED';
    }
  }

  Future<String> offerDlcSignatures({
    required String dlc_id,
    required String funding_sigs,
    required String refund_sig,
    required String adaptor_sig_points,
  }) async {
    // Check if API calls should be blocked due to xpub mismatch
    if (appController.shouldBlockApiCalls()) {
      print("API call blocked due to xpub mismatch - data reset required");
      appController.offerDlcSignaturesLoader.value = false;
      return 'BLOCKED_XPUB_MISMATCH';
    }
    
    appController.offerDlcSignaturesLoader.value = true;

    try {
      final data = {
        "dlc_id": "$dlc_id",
        "funding_sigs": "$funding_sigs",
        "refund_sig": "$refund_sig",
        "adaptor_sig_points": "$adaptor_sig_points"
      };

      final response = await DataService().genericDioPostCall(
        '/dlca/v0/offer-dlc-signatures',
        data: data,
        isFormUrlEncoded: false,
      );

      print("Status Code: ${response?.statusCode}");

      appController.offerDlcSignaturesLoader.value = false;

      if (response != null &&
          response.statusCode == 200 &&
          response.data != null) {
        appController.dlcSignatureResponseObject.value =
            DlcSignatureResponseModel.fromJson(response.data);
        print("DLC signatures submitted successfully");
        return 'OK';
      } else if (response?.statusCode == 400) {
        print("Bad Request: Missing or invalid dlc_id provided");
        if (response?.data != null) {
          appController.dlcSignatureResponseObject.value =
              DlcSignatureResponseModel.fromJson(response!.data);
        }
        return 'BAD_REQUEST';
      } else if (response?.statusCode == 403) {
        print("Forbidden: User is not part of the specified DLC");
        if (response?.data != null) {
          appController.dlcSignatureResponseObject.value =
              DlcSignatureResponseModel.fromJson(response!.data);
        }
        return 'FORBIDDEN';
      } else if (response?.statusCode == 500) {
        print(
            "Internal Server Error: Signature validation failed or DB write failed");
        if (response?.data != null) {
          appController.dlcSignatureResponseObject.value =
              DlcSignatureResponseModel.fromJson(response!.data);
        }
        return 'SERVER_ERROR';
      } else {
        print("Unexpected response: ${response?.statusCode}");
        if (response?.data != null) {
          appController.dlcSignatureResponseObject.value =
              DlcSignatureResponseModel.fromJson(response!.data);
        }
        return 'FAILED';
      }
    } catch (e) {
      appController.offerDlcSignaturesLoader.value = false;
      print("Exception in offerDlcSignatures: ${e.runtimeType}");
      return 'FAILED';
    }
  }

  Future<String> getAppVersion() async {
    try {
      print("ApiService: Getting app version...");
      
      final response = await DataService().genericDioGetCall(
         '/dlca/v0/service-version-info',
      );

      if (response != null && response.statusCode == 200 && response.data != null) {
        print("ApiService: App version response received");
        appController.appVersionObject.value = AppVersionEPModel.fromJson(response.data);
        return 'OK';
      } else {
        print("ApiService: Failed to get app version - status: ${response?.statusCode}");
        return 'FAILED';
      }
    } catch (e) {
      print("Exception in getAppVersion: ${e.runtimeType}");
      return 'FAILED';
    }
  }

  /// Check if server is reachable
  /// Returns 'OK' if server is accessible, 'FAILED' if not
  Future<String> checkServerStatus() async {
    try {
      print("ApiService: Checking server status...");
      
      // This endpoint doesn't require authentication
      final response = await DataService().genericDioGetCall(
        '/dlca/v0/server-status',
      );

      if (response != null && response.statusCode == 200) {
        print("ApiService: Server is reachable");
        return 'OK';
      } else {
        print("ApiService: Server is not reachable - status: ${response?.statusCode}");
        return 'FAILED';
      }
    } catch (e) {
      print("Exception in checkServerStatus: ${e.runtimeType}");
      return 'FAILED';
    }
  }

  /// Start/continue KYC and fetch Sumsub SDK access token.
  /// Calls POST /auth/kyc-start-app (empty body).
  /// Returns a map with keys: access_token, kyc_status, ttl_in_secs, provider, level_name.
  Future<Map<String, dynamic>?> kycStartApp() async {
    try {
      // Check if API calls should be blocked due to xpub mismatch
      if (appController.shouldBlockApiCalls()) {
        print("API call blocked due to xpub mismatch - data reset required");
        return null;
      }

      final response = await DataService().genericDioPostCall(
        '/auth/kyc-start-app',
        data: {},
        isFormUrlEncoded: false,
      );

      if (response != null && response.statusCode == 200 && response.data != null) {
        final respData = response.data as Map<String, dynamic>;
        final payload = respData['payload'];
        if (payload is Map<String, dynamic>) {
          return payload;
        }
      }

      print("ApiService: Failed to start KYC - response: ${response?.statusCode}");
      return null;
    } catch (e) {
      print("Exception in kycStartApp: ${e.runtimeType}");
      return null;
    }
  }

  /// Report app-side KYC lifecycle to backend (POST /auth/kyc-app-status).
  /// Body: { event, event_ts, details? }. Returns true on HTTP 200.
  Future<bool> kycAppStatus({
    required String event,
    double? eventTs,
    String? details,
  }) async {
    if (appController.shouldBlockApiCalls()) {
      print("API call blocked due to xpub mismatch - kycAppStatus skipped");
      return false;
    }

    final ts = eventTs ??
        (DateTime.now().toUtc().millisecondsSinceEpoch / 1000.0);

    final data = <String, dynamic>{
      'event': event,
      'event_ts': ts,
      if (details != null) 'details': details,
    };

    try {
      final response = await DataService().genericDioPostCall(
        '/auth/kyc-app-status',
        data: data,
        isFormUrlEncoded: false,
      );

      if (response != null && response.statusCode == 200) {
        return true;
      }

      print(
        "ApiService: kycAppStatus non-success - status: ${response?.statusCode}",
      );
      return false;
    } catch (e) {
      print("Exception in kycAppStatus: ${e.runtimeType}");
      return false;
    }
  }
}
