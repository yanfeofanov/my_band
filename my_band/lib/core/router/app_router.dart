import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/splash_screen.dart';
import '../../features/auth/auth_screen.dart';
import '../../features/auth/home_screen.dart';
import '../../features/auth/auth_service.dart';

class AppRouter {
  static final AuthService _auth = AuthService();

  static final GoRouter router = GoRouter(
    initialLocation: '/splash',
    redirect: (BuildContext context, GoRouterState state) async {
      final loggedIn = await _auth.isLoggedIn();
      final String path = state.matchedLocation;

      final bool isOnSplash = path == '/splash';
      final bool isOnAuth = path == '/login' || path == '/register';

      if (isOnSplash) return null;
      if (!loggedIn && !isOnAuth) return '/login';
      if (loggedIn && isOnAuth) return '/home';

      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/splash',
        builder: (BuildContext context, GoRouterState state) =>
            const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (BuildContext context, GoRouterState state) =>
            const AuthScreen(initialLoginMode: true),
      ),
      GoRoute(
        path: '/register',
        builder: (BuildContext context, GoRouterState state) =>
            const AuthScreen(initialLoginMode: false),
      ),
      GoRoute(
        path: '/home',
        builder: (BuildContext context, GoRouterState state) =>
            const HomeScreen(),
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) => Scaffold(
      appBar: AppBar(title: const Text('Страница не найдена')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('404', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text('Путь: ${state.matchedLocation}'),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/home'),
              child: const Text('На главную'),
            ),
          ],
        ),
      ),
    ),
  );
}