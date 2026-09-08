import 'package:dio/dio.dart';

class PushPlatformConflict implements Exception {}

/// Uses the same API base URL and bearer credential as the existing Auth API.
/// Kept separate from UI-oriented DataService calls, which log request bodies.
class PushRegistrationApi {
  PushRegistrationApi(String baseUrl, {Dio? dio})
      : _dio = dio ?? Dio(),
        _baseUrl = baseUrl.replaceFirst(RegExp(r'/$'), '');
  final Dio _dio;
  final String _baseUrl;

  Future<void> register(String token, String fid, String platform,
      CancelToken cancellation) async {
    final response = await _dio.post<dynamic>(
      '$_baseUrl/auth/push-registration',
      data: {'firebase_installation_id': fid, 'platform': platform},
      options: _options(token),
      cancelToken: cancellation,
    );
    if (response.statusCode == 409) throw PushPlatformConflict();
    if (response.statusCode != 200) throw StateError('Registration rejected');
  }

  Future<void> deactivate(
      String token, String fid, CancelToken cancellation) async {
    final response = await _dio.delete<dynamic>(
      '$_baseUrl/auth/push-registration/${Uri.encodeComponent(fid)}',
      options: _options(token),
      cancelToken: cancellation,
    );
    if (response.statusCode != 204) throw StateError('Deregistration rejected');
  }

  Options _options(String token) => Options(
        headers: {'Authorization': 'Bearer $token'},
        contentType: Headers.jsonContentType,
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        validateStatus: (_) => true,
      );
}
