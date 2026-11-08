import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  // ✅ ВАШИ КЛЮЧИ SUPABASE
  static const String _supabaseUrl =
      'https://avmnlrmnhxvmcmxyuaep.supabase.co';
  static const String _supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF2bW5scm1uaHh2bWNteHl1YWVwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE3MTk2MDQsImV4cCI6MjEwNzI5NTYwNH0.5AR64EBnTzMRyNKLqNrEH3eVDliwoXXpic971ThPI6c';

  // Ключи для SharedPreferences
  static const String _tokenKey = 'auth_token';
  static const String _emailKey = 'auth_email';

  // ============================
  // ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ
  // ============================

  // --- Хеширование пароля (пароль + соль → base64) ---
  String _hashPassword(String password, String salt) {
    final combined = password + salt;
    return base64.encode(utf8.encode(combined));
  }

  // --- Генерация случайной соли (16 символов) ---
  String _generateSalt() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return String.fromCharCodes(
      Iterable.generate(
        16,
        (_) => chars.codeUnitAt(random.nextInt(chars.length)),
      ),
    );
  }

  // --- Фейковый токен (временно, пока не подключён Supabase Auth) ---
  String _generateFakeToken(String email) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random.secure().nextInt(999999);
    final raw = '$email:$timestamp:$random';
    return 'fake_${base64Url.encode(utf8.encode(raw))}';
  }

  // ============================
  // РАБОТА С СЕССИЕЙ
  // ============================

  // --- Сохранить токен и email ---
  Future<void> _saveSession(String token, String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_emailKey, email);
  }

  // --- Получить сохранённый токен ---
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  // --- Получить сохранённый email ---
  Future<String?> getEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_emailKey);
  }

  // --- Проверка: авторизован ли пользователь ---
  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  // --- Выход (очистка сессии) ---
  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_emailKey);
  }

  // ============================
  // РЕГИСТРАЦИЯ
  // ============================
  Future<Map<String, dynamic>> signUp(String email, String password) async {
    if (email.isEmpty || password.isEmpty) {
      return {'success': false, 'error': 'Заполните все поля'};
    }

    final salt = _generateSalt();
    final hash = _hashPassword(password, salt);

    final url = Uri.parse('$_supabaseUrl/rest/v1/users');
    final headers = {
      'apikey': _supabaseAnonKey,
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    };
    final body = json.encode({
      'email': email,
      'password_hash': hash,
      'salt': salt,
    });

    try {
      final response = await http.post(url, headers: headers, body: body);

      print('=== SIGN UP ===');
      print('URL: $url');
      print('Status: ${response.statusCode}');
      print('Body: ${response.body}');
      print('===============');

      if (response.statusCode == 201) {
        return {'success': true};
      }

      // Дубликат email
      if (response.statusCode == 409 ||
          response.body.contains('duplicate key') ||
          response.body.contains('users_email_key')) {
        return {
          'success': false,
          'error': 'Пользователь с таким email уже зарегистрирован',
          'code': 'email_exists',
        };
      }

      // Прочие ошибки
      try {
        final errorData = json.decode(response.body);
        final message = errorData['message'] ??
            errorData['details'] ??
            'Ошибка регистрации';
        return {'success': false, 'error': message};
      } catch (_) {
        return {
          'success': false,
          'error': 'Ошибка регистрации (${response.statusCode})'
        };
      }
    } catch (e) {
      print('Exception in signUp: $e');
      return {'success': false, 'error': 'Ошибка сети: $e'};
    }
  }

  // ============================
  // ВХОД
  // ============================
  Future<Map<String, dynamic>> signIn(String email, String password) async {
    if (email.isEmpty || password.isEmpty) {
      return {'success': false, 'error': 'Заполните все поля'};
    }

    final url = Uri.parse('$_supabaseUrl/rest/v1/users?email=eq.$email');
    final headers = {'apikey': _supabaseAnonKey};

    try {
      final response = await http.get(url, headers: headers);

      print('=== SIGN IN ===');
      print('URL: $url');
      print('Status: ${response.statusCode}');
      print('Body: ${response.body}');
      print('===============');

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (data.isEmpty) {
          return {'success': false, 'error': 'Пользователь не найден'};
        }

        final user = data.first as Map<String, dynamic>;
        final storedHash = user['password_hash'] as String;
        final salt = user['salt'] as String;

        final inputHash = _hashPassword(password, salt);
        if (inputHash == storedHash) {
          // ✅ Успешный вход → генерируем и сохраняем токен
          final fakeToken = _generateFakeToken(email);
          await _saveSession(fakeToken, email);

          return {
            'success': true,
            'token': fakeToken,
            'user': user,
          };
        } else {
          return {'success': false, 'error': 'Неверный пароль'};
        }
      } else {
        return {
          'success': false,
          'error': 'Ошибка сервера: ${response.statusCode}'
        };
      }
    } catch (e) {
      print('Exception in signIn: $e');
      return {'success': false, 'error': 'Ошибка сети: $e'};
    }
  }
}