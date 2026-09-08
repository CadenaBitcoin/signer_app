import 'package:signer/services/push/push_registration_runtime.dart';
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
    final generation = PushRegistrationRuntime.sessionGeneration;
    // Check if API calls should be blocked due to xpub mismatch
    if (appController.shouldBlockApiCalls()) {
      print("API call blocked due to xpub mismatch - data reset required");
      appController.loginLoader.value = false;
      return 'BLOCKED_XPUB_MISMATCH';
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

    print("Login response: ${response?.data}");
    print("Status Code: ${response?.statusCode}");

    appController.loginLoader.value = false;

    if (response != null &&
        response.statusCode == 200 &&
        response.data != null) {
      // Clear xpub mismatch flag BEFORE saving token to ensure getUserProfile works
      appController.clearXpubMismatchDetected();
      if (!await saveToken(response.data['access_token'], generation: generation)) {
        return 'FAILED';
      }
      // appController.user.value = user;
      return 'OK';
    } else {
      return 'FAILED';
    }
  }

  Future<bool> saveToken(String token, {int? generation}) async {
    if (!await PushRegistrationRuntime.persistToken(
        token, generation ?? PushRegistrationRuntime.sessionGeneration)) {
      return false;
    }
    
    // Immediately update button states after saving JWT token
    appController.checkJwtTokenAndUpdateButtons();
    
    // Also get user profile to set scan button based on authCode
    await getUserProfile();
    return true;
  }

  /// Register new user - returns 'OK' if successful, 'FAILED' if user already exists
  Future<String> registerNewUser({String? email, String? pass}) async {
    appController.loginLoader.value = true;
    
    final data = {
      'email_address': email ?? '',
      'password': pass ?? '',
    };

    final response = await DataService().genericDioPostCall(
      '/auth/new-user',
      data: data,
      isFormUrlEncoded: false,
    );

    print("Register response: ${response?.data}");
    print("Status Code: ${response?.statusCode}");

    appController.loginLoader.value = false;

    if (response != null && response.statusCode == 200) {
      // Check if the response contains the success message
      final message = response.data?['message'] ?? '';
      if (message.contains('confirmation link will be sent')) {
        // Registration successful - user is new (auth_code = 0)
        return 'OK';
      } else {
        return 'FAILED';
      }
    } else if (response != null && response.statusCode == 400) {
      // Check the error message to determine the specific case
      final detail = response.data?['detail'] ?? '';
      if (detail.contains('already exists and is confirmed')) {
        // User already exists and is confirmed - proceed to login
        return 'USER_CONFIRMED';
      } else {
        // User exists but not confirmed - proceed to login
        return 'USER_EXISTS';
      }
    } else {
      return 'FAILED';
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

    print("user profile response after hit Verify button: ${response?.data}");
    print("Status Code: ${response?.statusCode}");

    if (response != null &&
        response.statusCode == 200 &&
        response.data != null) {
      appController.userProfileObject.value = UserProfileModel.fromJson(
        response.data,
      );
      
      // Update button states based on authCode
      final authCode = appController.userProfileObject.value.payload?.authCode ?? 999;
      _updateButtonStatesBasedOnAuthCode(authCode);
      
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
      
      print("Local XPUB: $localXpub");
      print("Server XPUB: $serverXpub");
      
      return localXpub == serverXpub;
    } catch (e) {
      print("Error comparing XPUB: $e");
      return false;
    }
  }

  /*
  Future<String> userUpgradePubx({required String xpub}) async {
    appController.userUpgradeLoader.value = true;

    final data = {"xpub": "$xpub"};
    print("===========${data}");

    final response = await DataService().genericDioPostCall(
      '/dlca/v0/user-auth-s-upgrade',
      data: data,
      isFormUrlEncoded: false,
    );

    print("Login response: ${response?.data}");
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
    print("data inside userUpgradePubx$data");
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

    print("response of userUpgradePubx: ${response?.data}");
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

    print("user profile response: ${response?.data}");
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

    print("user profile response: ${response?.data}");
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

    print("user profile response: ${response?.data}");
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

    print("user profile response: ${response?.data}");
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
      print("Submitting DLC signatures: ${data}");

      final response = await DataService().genericDioPostCall(
        '/dlca/v0/offer-dlc-signatures',
        data: data,
        isFormUrlEncoded: false,
      );

      print("DLC signatures response: ${response?.data}");
      print("Status Code: ${response?.statusCode}");

      appController.offerDlcSignaturesLoader.value = false;

      if (response != null &&
          response.statusCode == 200 &&
          response.data != null) {
        appController.dlcSignatureResponseObject.value =
            DlcSignatureResponseModel.fromJson(response.data);
        print(
            "DLC signatures submitted successfully: ${response.data['message']}");
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
          if (response?.data['detail'] != null) {
            print("Error detail: ${response?.data['detail']}");
          }
        }
        return 'SERVER_ERROR';
      } else {
        print("Unexpected response: ${response?.statusCode}");
        if (response?.data != null) {
          appController.dlcSignatureResponseObject.value =
              DlcSignatureResponseModel.fromJson(response!.data);
          print("Response data: ${response?.data}");
        }
        return 'FAILED';
      }
    } catch (e) {
      appController.offerDlcSignaturesLoader.value = false;
      print("Exception in offerDlcSignatures: $e");
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
        print("ApiService: App version response received $response");
        appController.appVersionObject.value = AppVersionEPModel.fromJson(response.data);
        return 'OK';
      } else {
        print("ApiService: Failed to get app version - response: $response");
        return 'FAILED';
      }
    } catch (e) {
      print("Exception in getAppVersion: $e");
      return 'FAILED';
    }
  }
}
