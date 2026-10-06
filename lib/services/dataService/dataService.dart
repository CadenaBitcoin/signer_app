import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fluttertoast/fluttertoast.dart';

import 'package:http/http.dart' as http;
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../storage_service.dart';
import '../../src/ui/controllers/appController.dart';
import 'package:get/get.dart'as getX;
import 'apiService.dart';

class DataService {
  // Use API URL from AppController for easy switching
  var _baseURL = AppController.API_BASE_URL;

  var _response;

  /// Authenticated backend traffic is HTTPS-only. Never fall back to cleartext.
  bool get _isSecureBaseUrl => Uri.tryParse(_baseURL)?.scheme == 'https';

  /// Status code of the synthetic response returned when a call is refused
  /// because the base URL is not HTTPS. Distinct from any real HTTP status
  /// and from a plain network failure (which yields a null response).
  static const int insecureTransportStatus = -1;

  Response _insecureTransportRefusal(String api) {
    print("Refusing backend call: base URL is not HTTPS");
    return Response(
      requestOptions: RequestOptions(path: api),
      statusCode: insecureTransportStatus,
      statusMessage: 'INSECURE_TRANSPORT_REFUSED',
    );
  }

  Future<Response?> genericDioGetCall(String api) async {
    if (!_isSecureBaseUrl) return _insecureTransportRefusal(api);
    print(_baseURL + '$api');

    final appController = getX.Get.find<AppController>();

    // Inner function to make the GET request with the current token
    Future<Response?> _makeRequest() async {
      final token = await getToken();

      var _dio = Dio(
        BaseOptions(
          baseUrl: _baseURL,
          headers: {
            "Authorization": "Bearer $token",
            "Content-Type": "application/json",
          },
        ),
      );

      try {
        _response = await _dio.get(_baseURL + '$api');
        print("GET $api -> ${_response?.statusCode}");
      } on DioError catch (e) {
        if (e.response != null) {
          // Check if this is a token expiration error
          final isTokenExpired = e.response?.statusCode == 401 && 
              (e.response?.data?["detail"] == "Invalid authentication credentials: Signature has expired." ||
               e.message?.contains("401") == true);
          
          // Only show error messages if it's not a token expiration
          if (!isTokenExpired) {
            getX.Get.snackbar(
              'Error',
              '${e.message ?? ""}',
              backgroundColor: Colors.red,
              colorText: Colors.white,
              duration: Duration(seconds: 3),
            );
          }
        }
        _response = e.response;
      }

      return _response;
    }

    // First attempt
    _response = await _makeRequest();

    // Check for expired token
    if (_response?.statusCode == 401 && _response?.data["detail"] == "Invalid authentication credentials: Signature has expired.") {
      print("Token expired — refreshing...");
      String refreshResult = await refreshToken();

      if (refreshResult == 'OK') {
        print("Token refreshed — retrying request...");
        _response = await _makeRequest();
      } else {
        print("Token refresh failed.");
      }
    }

    // Update auth failure tracking
    if (_response?.statusCode == 401) {
      await appController.handleAuth401();
    } else {
      appController.resetAuth401Counter();
    }

    print(_baseURL + '$api' + ' Status_Code: ${_response?.statusCode}');
    return _response;
  }

  Future<Response?> genericDioPostCall(
    String api, {
    Map<String, dynamic>? data,
    String? token,
    bool isFormUrlEncoded = false,
  }) async {
    if (!_isSecureBaseUrl) return _insecureTransportRefusal(api);
    Response? _response;
    String? _authToken;
    final appController = getX.Get.find<AppController>();

    // Internal function to make the POST request with the current token
    Future<Response?> _makeRequest({String? useToken}) async {
      if (!api.contains('/auth/app-token')) {
        _authToken = useToken ?? token ?? await getToken();
      }

      final headers = {
        'accept': 'application/json',
        'Content-Type': isFormUrlEncoded ? 'application/x-www-form-urlencoded' : 'application/json',
        if (_authToken != null && _authToken!.isNotEmpty) 'Authorization': 'Bearer $_authToken',
      };

      final dio = Dio(BaseOptions(baseUrl: _baseURL, headers: headers));

      print("URL: $_baseURL$api");

      try {
        Response response;
        if (isFormUrlEncoded) {
          // Convert map to URL-encoded string
          final encodedData =
              data!.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value.toString())}').join('&');

          response = await dio.post(
            api,
            data: encodedData,
            options: Options(contentType: Headers.formUrlEncodedContentType),
          );
        } else {
          response = await dio.post(api, data: data);
        }
        print("POST $api -> ${response.statusCode}");
        return response;
      } on DioError catch (e) {
        print("POST $api failed: ${e.type} status=${e.response?.statusCode}");

        // Check if this is the "already exists and is confirmed" error
        final errorDetail = e.response?.data?['detail'] ?? '';
        final isAlreadyConfirmedError = errorDetail.contains('already exists and is confirmed');
        
        // Check if this is a token expiration error
        final isTokenExpired = e.response?.statusCode == 401 && 
            (errorDetail == "Invalid authentication credentials: Signature has expired." ||
             e.message?.contains("401") == true);
        
        // Only show error messages if it's not the "already confirmed" case and not token expiration
        if (!isAlreadyConfirmedError && !isTokenExpired) {
          Fluttertoast.showToast(msg: e.message ?? "Unknown error",);
          getX.Get.snackbar(
            'Error',
            '${e.message ?? "Unknown error"}',
            backgroundColor: Colors.red,
            colorText: Colors.white,
            duration: Duration(seconds: 3),
          );
        }
        return e.response;
      }
    }

    // First attempt
    _response = await _makeRequest();

    // Retry if token expired
    if (_response?.statusCode == 401 && _response?.data["detail"] == "Invalid authentication credentials: Signature has expired.") {
      print("Token expired — refreshing...");
      String refreshResult = await refreshToken();

      if (refreshResult == 'OK') {
        print("Token refreshed — retrying POST request...");
        _response = await _makeRequest();
      } else {
        print("Token refresh failed.");
      }
    }

    // Update auth failure tracking
    if (_response?.statusCode == 401) {
      await appController.handleAuth401();
    } else {
      appController.resetAuth401Counter();
    }

    return _response;
  }
}

Future<String?> getToken() async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  return prefs.getString('jwtToken') != null ? prefs.getString('jwtToken') : '';
}

saveToken(token) async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.setString('jwtToken', token);
  
  // Immediately update button states after saving JWT token
  final appController = getX.Get.find<AppController>();
  appController.checkJwtTokenAndUpdateButtons();
  
  // Also get user profile to set scan button based on authCode
  final apiService = ApiService();
  await apiService.getUserProfile();
}

Future<String> refreshToken() async {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // 1. Get logged-in email
  final email = await _storage.read(key: 'logged_in_user_email');
  if (email == null || email.isEmpty) {
    print("No logged-in email found");
    return 'FAILED';
  }

  // 2. Fetch user data from your storage
  final user = await StorageService.getUserByEmail(email);
  if (user == null) {
    print("User not found in local storage");
    return 'FAILED';
  }


  // 3. Prepare data for API call
  final data = {
    'username': user['email'] ?? '',
    'password': user['password'] ?? '',
    'scope': '',
    'client_id': '',
    'client_secret': '',
  };

  // 4. Make API call
  final response = await DataService().genericDioPostCall(
    '/auth/app-token',
    data: data,
    isFormUrlEncoded: true,
  );

  print("Token refresh response status: ${response?.statusCode}");

  // 5. Handle response
  if (response != null && response.statusCode == 200 && response.data != null) {
    await saveToken(response.data['access_token']);
    return 'OK';
  } else {
    return 'FAILED';
  }
}
