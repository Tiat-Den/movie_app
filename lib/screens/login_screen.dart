import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:movie_app/screens/register_screen.dart';
import 'package:movie_app/services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;

  // --- ĐĂNG NHẬP EMAIL ---
  void _handleEmailLogin() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showSnackBar("Vui lòng nhập đầy đủ thông tin!");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Thực hiện đăng nhập
      UserCredential credential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );

      User? user = credential.user;

      if (user != null) {
        // 2. Cập nhật trạng thái mới nhất từ Firebase (để check emailVerified)
        await user.reload();
        user = FirebaseAuth.instance.currentUser;

        // 3. Kiểm tra đã xác thực email chưa
        if (!user!.emailVerified) {
          await _authService.signOut();
          _showSnackBar("Tài khoản chưa xác thực! Vui lòng kiểm tra email.");
        } else {
          // Thành công -> Vào Home
          if (mounted) Navigator.pushReplacementNamed(context, '/home');
        }
      }
    } on FirebaseAuthException catch (e) {
      String errorMsg = "Lỗi đăng nhập!";
      if (e.code == 'user-not-found') {
        errorMsg = "Email không tồn tại!";
      } else if (e.code == 'wrong-password') {
        errorMsg = "Sai mật khẩu!";
      }

      _showSnackBar(errorMsg);
    } catch (e) {
      _showSnackBar("Lỗi hệ thống: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---ĐĂNG NHẬP GOOGLE ---
  void _handleGoogleLogin() async {
    setState(() => _isLoading = true);
    try {
      final user = await _authService.signInWithGoogle();
      if (user != null && mounted) {
        // Google thường tự động verify email nên cho vào luôn
        Navigator.pushReplacementNamed(context, '/home');
      }
    } catch (e) {
      if (mounted) {
        print("Chi tiết lỗi Google Login: $e");
        _showSnackBar("Đăng nhập thất bại!");
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF15141F), // Màu nền tối đồng bộ
      appBar: AppBar(
        title: const Text(
          "Đăng Nhập",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.movie_filter, size: 80, color: Colors.redAccent),
              const SizedBox(height: 30),

              // Ô Email
              TextField(
                controller: _emailController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Email",
                  labelStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.email, color: Colors.redAccent),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),

              // Ô Mật khẩu
              TextField(
                controller: _passwordController,
                style: const TextStyle(color: Colors.white),
                obscureText: true,
                decoration: InputDecoration(
                  labelText: "Mật khẩu",
                  labelStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.lock, color: Colors.redAccent),
                ),
              ),
              const SizedBox(height: 30),

              if (_isLoading)
                const CircularProgressIndicator(color: Colors.redAccent)
              else
                Column(
                  children: [
                    // Nút Đăng nhập Email
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _handleEmailLogin,
                        child: const Text(
                          "Đăng Nhập",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Nút Đăng nhập Google
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: Image.network(
                          // Link từ gstatic của Google cực kỳ ổn định
                          'https://www.gstatic.com/images/branding/product/2x/googleg_48dp.png',
                          height: 20,
                          // Fix lỗi crash nếu link ảnh chết hoặc bị chặn
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.account_circle,
                              color: Colors.white,
                            );
                          },
                          // Hiển thị loading nhẹ trong khi tải ảnh
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            );
                          },
                        ),
                        label: const Text(
                          "Tiếp tục với Google",
                          style: TextStyle(color: Colors.white),
                        ),
                        onPressed: _handleGoogleLogin,
                      ),
                    ),

                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RegisterScreen(),
                        ),
                      ),
                      child: const Text(
                        "Chưa có tài khoản? Đăng ký ngay",
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
