import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:movie_app/screens/home_screen.dart';
import 'package:movie_app/screens/login_screen.dart';
import 'package:movie_app/services/auth_service.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // Chỉ định rõ Stream này trả về User của Firebase
    return StreamBuilder<User?>(
      stream: AuthService().userStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData) {
          // Dùng fb.User để khớp với dữ liệu từ snapshot
          User? firebaseUser = snapshot.data;

          // Kiểm tra xác thực email
          if (firebaseUser != null && firebaseUser.emailVerified) {
            return const HomeScreen();
          } else {
            return const LoginScreen();
          }
        }

        return const LoginScreen();
      },
    );
  }
}
