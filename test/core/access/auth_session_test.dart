import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hemolink/core/access/auth_session.dart';
import 'package:hemolink/core/access/token_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemoryTokenStore implements TokenStore {
  String? token;
  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String value) async => token = value;
  @override
  Future<void> delete() async => token = null;
}

const nursingUser = {
  'id': 'nurse',
  'role': 'nursing',
  'isVerified': true,
  'siteId': 'sede-central',
  'hospitalId': null,
};

http.Response jsonResponse(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('UT01.1-A: autentica credenciales y conserva solo el token', () async {
    final storage = MemoryTokenStore();
    final session = AuthSession(
      tokenStore: storage,
      client: MockClient((request) async {
        expect(jsonDecode(request.body), {
          'email': 'nurse@test',
          'password': 'secret',
        });
        return jsonResponse({'user': nursingUser, 'token': 'opaque'});
      }),
    );
    await session.login('nurse@test', 'secret');
    expect(session.currentUser?.siteId, 'sede-central');
    expect(storage.token, 'opaque');
  });

  test('restaura sesión consultando identidad al servidor', () async {
    final storage = MemoryTokenStore()..token = 'saved';
    final session = AuthSession(
      tokenStore: storage,
      client: MockClient((request) async {
        expect(request.url.path, '/api/me');
        expect(request.headers['Authorization'], 'Bearer saved');
        return jsonResponse({'user': nursingUser});
      }),
    );
    await session.restore();
    expect(session.currentUser?.id, 'nurse');
  });

  test('UT01.1-B: rechaza credenciales sin persistir una sesión', () async {
    final storage = MemoryTokenStore();
    final session = AuthSession(
      tokenStore: storage,
      client: MockClient(
        (_) async => jsonResponse({'message': 'Credenciales inválidas.'}, 401),
      ),
    );
    await expectLater(
      session.login('bad', 'bad'),
      throwsA(isA<AuthException>()),
    );
    expect(session.currentUser, isNull);
    expect(storage.token, isNull);
  });

  test('UT01.1-C: sesión revocada se borra al restaurar', () async {
    final storage = MemoryTokenStore()..token = 'revoked';
    final session = AuthSession(
      tokenStore: storage,
      client: MockClient(
        (_) async => jsonResponse({'message': 'Sesión inválida.'}, 401),
      ),
    );
    await session.restore();
    expect(storage.token, isNull);
    expect(session.currentUser, isNull);
  });

  test('UT01.1-C: cerrar revoca en servidor antes de eliminar token', () async {
    final storage = MemoryTokenStore()..token = 'saved';
    final session = AuthSession(
      tokenStore: storage,
      client: MockClient((request) async {
        if (request.url.path == '/api/me') {
          return jsonResponse({'user': nursingUser});
        }
        expect(request.url.path, '/api/logout');
        expect(request.method, 'POST');
        expect(storage.token, 'saved');
        return jsonResponse({'message': 'Sesión cerrada.'});
      }),
    );
    await session.restore();
    await session.logout();
    expect(storage.token, isNull);
    expect(session.currentUser, isNull);
  });

  test(
    'fallo de red al salir conserva sesión para reintentar revocación',
    () async {
      final storage = MemoryTokenStore()..token = 'saved';
      final session = AuthSession(
        tokenStore: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/me') {
            return jsonResponse({'user': nursingUser});
          }
          throw http.ClientException('offline');
        }),
      );
      await session.restore();
      await expectLater(session.logout(), throwsA(isA<AuthException>()));
      expect(storage.token, 'saved');
      expect(session.currentUser, isNotNull);
    },
  );

  test(
    'sesión expirada durante una consulta elimina identidad y token',
    () async {
      final storage = MemoryTokenStore()..token = 'saved';
      final session = AuthSession(
        tokenStore: storage,
        client: MockClient(
          (request) async => request.url.path == '/api/me'
              ? jsonResponse({'user': nursingUser})
              : jsonResponse({'message': 'Sesión expirada.'}, 401),
        ),
      );
      await session.restore();
      await expectLater(
        session.loadModule('donors'),
        throwsA(isA<AuthException>()),
      );
      expect(session.currentUser, isNull);
      expect(storage.token, isNull);
    },
  );

  test('fallo de red restaurando no elimina el token recuperable', () async {
    final storage = MemoryTokenStore()..token = 'saved';
    final session = AuthSession(
      tokenStore: storage,
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    await expectLater(session.restore(), throwsA(isA<AuthException>()));
    expect(storage.token, 'saved');
  });
}
