import 'package:signer/services/push/push_registration_runtime.dart';
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

  Future<Response?> genericDioGetCall(String api) async {
    print(_baseURL + '$api');

    // Inner function to make the GET request with the current token
    Future<Response?> _makeRequest() async {
      final token = await getToken();
      print("$api --- *$token");

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
        print("response --- $_response");
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

    print(_baseURL + '$api' + ' Status_Code: ${_response?.statusCode}');
    return _response;
  }

  Future<Response?> genericDioPostCall(
    String api, {
    Map<String, dynamic>? data,
    String? token,
    bool isFormUrlEncoded = false,
  }) async {
    Response? _response;
    String? _authToken;

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
      print("DATA: $data");

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
        print("Response: ${response.data}");
        return response;
      } on DioError catch (e) {
        print("DioError: ${e.response?.data}");

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

    return _response;
  }
}

Future<String?> getToken() async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  return prefs.getString('jwtToken') != null ? prefs.getString('jwtToken') : '';
}

Future<bool> saveToken(String token, {int? generation}) async {
  if (!await PushRegistrationRuntime.persistToken(
      token, generation ?? PushRegistrationRuntime.sessionGeneration)) {
    return false;
  }
  
  // Immediately update button states after saving JWT token
  final appController = getX.Get.find<AppController>();
  appController.checkJwtTokenAndUpdateButtons();
  
  // Also get user profile to set scan button based on authCode
  final apiService = ApiService();
  await apiService.getUserProfile();
  return true;
}

Future<String> refreshToken() async {
  final generation = PushRegistrationRuntime.sessionGeneration;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // 1. Get logged-in email
  final email = await _storage.read(key: 'logged_in_user_email');
  if (email == null || email.isEmpty) {
    print("No logged-in email found");
    return 'FAILED';
  }
  print("Logged-in email: $email");

  // 2. Fetch user data from your storage
  final user = await StorageService.getUserByEmail(email);
  if (user == null) {
    print("User not found in local storage");
    return 'FAILED';
  }

  print("User data found:");
  print("Email: ${user['email']}");
  print("Password: ${user['password']}");

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

  print("Login response: ${response?.data}");
  print("Status Code: ${response?.statusCode}");

  // 5. Handle response
  if (response != null && response.statusCode == 200 && response.data != null) {
    return await saveToken(response.data['access_token'], generation: generation)
        ? 'OK' : 'FAILED';
  } else {
    return 'FAILED';
  }
}
