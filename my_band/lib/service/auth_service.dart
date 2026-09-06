import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class AuthService {
  // Временное хранилище (имитация базы данных)
  // В реальном проекте используйте Firebase, SQLite или серверный API
  final Map<String, Map<String, String>> _users = {}; // email -> {hash, salt}

  // Хеширует пароль с солью
  String _hashPassword(String password, String salt) {
    final bytes = utf8.encode(password + salt);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // Генерирует случайную соль (16 байт в hex)
  String _generateSalt() {
    final random = Random.secure();
    final saltBytes = List<int>.generate(16, (_) => random.nextInt(256));
    return saltBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  // Регистрация
  Future<bool> signUp(String email, String password) async {
    await Future.delayed(const Duration(seconds: 1)); // имитация сети

    if (_users.containsKey(email)) {
      return false; // пользователь уже существует
    }

    final salt = _generateSalt();
    final hash = _hashPassword(password, salt);
    _users[email] = {'hash': hash, 'salt': salt};
    return true;
  }

  // Вход
  Future<bool> signIn(String email, String password) async {
    await Future.delayed(const Duration(seconds: 1));

    final user = _users[email];
    if (user == null) return false;

    final hash = _hashPassword(password, user['salt']!);
    return hash == user['hash'];
  }
}