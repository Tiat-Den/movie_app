import 'package:firebase_auth/firebase_auth.dart'; // Thêm để dùng User
import 'package:flutter/material.dart';
import 'package:movie_app/services/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;

  void _handleRegister() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (name.isEmpty) {
      _showSnackBar('Vui lòng nhập họ tên!');
      return;
    }

    // 1. Kiểm tra mật khẩu khớp nhau
    if (password != confirmPassword) {
      _showSnackBar('Mật khẩu nhập lại không khớp!');
      return;
    }

    // 2. Kiểm tra độ dài mật khẩu
    if (password.length < 6) {
      _showSnackBar('Mật khẩu phải trên 6 ký tự!');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 3. Đăng ký tài khoản
      User? user = await _authService.registerWithEmail(email, password, name);

      if (user != null) {
        // 4. Gửi email xác thực
        await user.sendEmailVerification();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Đăng ký thành công! Vui lòng kiểm tra Email để xác thực tài khoản.',
              ),
              backgroundColor: Colors.green,
            ),
          );
          // Quay lại màn hình đăng nhập
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String msg, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Đăng Ký")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 50),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: "Email",
                  prefixIcon: Icon(Icons.email, color: Colors.redAccent),
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 15),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: "Tên",
                  prefixIcon: Icon(Icons.person, color: Colors.redAccent),
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 15),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: "Mật khẩu",
                  prefixIcon: Icon(Icons.lock, color: Colors.redAccent),
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),

              const SizedBox(height: 15),
              // --- Ô NHẬP LẠI MẬT KHẨU ---
              TextField(
                controller: _confirmPasswordController,
                decoration: const InputDecoration(
                  labelText: "Nhập lại mật khẩu",
                  prefixIcon: Icon(
                    Icons.lock_reset_rounded,
                    color: Colors.redAccent,
                  ),
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),

              const SizedBox(height: 30),
              _isLoading
                  ? const CircularProgressIndicator()
                  : SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                        ),
                        onPressed: _handleRegister,
                        child: const Text(
                          "Đăng Ký",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}
