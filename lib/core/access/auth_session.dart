import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_user.dart';
import 'token_store.dart';

class AuthException implements Exception {
  const AuthException(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => message;
}

class AuthSession {
  AuthSession({
    this.baseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8080',
    ),
    http.Client? client,
    TokenStore? tokenStore,
  }) : _client = client ?? http.Client(),
       _store = tokenStore ?? SecureTokenStore(server: baseUrl);

  final String baseUrl;
  final http.Client _client;
  final TokenStore _store;
  String? _token;
  AppUser? _currentUser;
  AppUser? get currentUser => _currentUser;

  Future<void> _clear() async {
    _token = null;
    _currentUser = null;
    await _store.delete();
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, dynamic>? body,
    bool post = false,
  }) async {
    try {
      final headers = {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };
      final url = Uri.parse('$baseUrl/api/$path');
      final response =
          await (post
                  ? _client.post(
                      url,
                      headers: headers,
                      body: body == null ? null : jsonEncode(body),
                    )
                  : _client.get(url, headers: headers))
              .timeout(const Duration(seconds: 10));
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (response.statusCode >= 400) {
        if (response.statusCode == 401) await _clear();
        throw AuthException(
          data['message'] as String? ?? 'No se pudo completar la operación.',
          status: response.statusCode,
        );
      }
      return data;
    } on TimeoutException {
      throw const AuthException(
        'El servidor tardó demasiado. Vuelve a intentar.',
      );
    } on http.ClientException {
      throw const AuthException(
        'No se pudo conectar con el servidor. Vuelve a intentar.',
      );
    } on FormatException {
      throw const AuthException('El servidor devolvió una respuesta inválida.');
    }
  }

  Future<void> restore() async {
    _token = await _store.read();
    if (_token == null) return;
    try {
      final data = await _request('me');
      _currentUser = AppUser.fromJson(data['user'] as Map<String, dynamic>);
    } on AuthException catch (error) {
      if (error.status != 401) rethrow;
    }
  }

  Future<void> login(String email, String password) async {
    final data = await _request(
      'login',
      post: true,
      body: {'email': email.trim(), 'password': password},
    );
    final user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
    _token = data['token'] as String;
    try {
      await _store.write(_token!);
    } catch (_) {
      // No informar acceso exitoso si el almacenamiento local falló.
      try {
        await _request('logout', post: true);
      } catch (_) {
        /* Expira en el servidor. */
      }
      _token = null;
      throw const AuthException(
        'No se pudo guardar la sesión en este dispositivo.',
      );
    }
    _currentUser = user;
  }

  Future<void> logout() async {
    try {
      await _request('logout', post: true);
    } on AuthException catch (error) {
      if (error.status != 401) rethrow;
    }
    await _clear();
  }

  Future<List<Map<String, dynamic>>> loadModule(String module) async {
    final data = await _request(module);
    return (data['items'] as List).cast<Map<String, dynamic>>();
  }

  void dispose() => _client.close();
}
