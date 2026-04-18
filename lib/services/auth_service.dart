import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<User?> get userStream => _auth.authStateChanges();

  User? getCurrentUser() {
    return _auth.currentUser;
  }

  Future<User?> registerWithEmail(
    String email,
    String password,
    String name,
  ) async {
    try {
      final UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

      User? user = result.user;

      if (user != null) {
        // 1. Cập nhật DisplayName
        await user.updateDisplayName(name);

        // 2. Lưu vào Firestore - Đợi lệnh này hoàn tất 100%
        await _firestore.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'name': name,
          'email': email.trim(),
          'createdAt':
              FieldValue.serverTimestamp(), // Dùng cái này chuyên nghiệp hơn DateTime.now()
          'avatarUrl': '',
        });

        // 3. Gửi email xác thực
        await user.sendEmailVerification();
        print("📩 Đã gửi lệnh yêu cầu gửi email xác thực");

        // 4. Đợi một nhịp nhỏ rồi mới đăng xuất để đảm bảo kết nối Firestore đã xong
        await Future.delayed(const Duration(milliseconds: 500));
        await _auth.signOut();
      }

      return user;
    } catch (e) {
      print("Lỗi tại registerWithEmail: $e");
      rethrow;
    }
  }

  Future<User?> signInWithGoogle() async {
    try {
      // 1. Kích hoạt hộp thoại chọn tài khoản Google
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      // 2. Lấy thông tin xác thực từ tài khoản đã chọn
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 3. Đăng nhập vào Firebase Authentication
      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );
      final User? user = userCredential.user;

      if (user != null) {
        // 4. ĐỒNG BỘ VÀO FIRESTORE
        // Dùng .set với merge: true để nếu user đã tồn tại thì không ghi đè mất dữ liệu cũ (như avatar đã đổi)
        await _firestore.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'email': user.email,
          'name': user.displayName ?? "Người dùng Google",
          // Chỉ lưu ảnh mặc định của Google nếu trong Firestore chưa có ảnh (avatarUrl trống)
          'avatarUrl': user.photoURL ?? '',
          'lastLogin':
              FieldValue.serverTimestamp(), // Lưu vết lần đăng nhập cuối
        }, SetOptions(merge: true));

        print("✅ Đã đồng bộ User Google ${user.email} vào Firestore");
      }

      return user;
    } catch (e) {
      print("❌ Lỗi đăng nhập Google: $e");
      rethrow;
    }
  }

  Future<void> updatePassword(String oldPassword, String newPassword) async {
    User? user = _auth.currentUser;

    if (user != null && user.email != null) {
      try {
        AuthCredential credential = EmailAuthProvider.credential(
          email: user.email!,
          password: oldPassword,
        );
        await user.reauthenticateWithCredential(credential);

        await user.updatePassword(newPassword);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
          throw Exception('Mật khẩu cũ không chính xác!');
        }
        throw Exception(e.message);
      }
    }
  }

  Future<void> updateProfile(String newName, String newEmail) async {
    User? user = _auth.currentUser;
    if (user != null) {
      try {
        if (newName.isNotEmpty && newName != user.displayName) {
          await user.updateDisplayName(newName);
        }

        if (newEmail.isNotEmpty && newEmail != user.email) {
          await user.verifyBeforeUpdateEmail(newEmail);
        }

        await user.reload();
      } on FirebaseAuthException catch (e) {
        if (e.code == 'requires-recent-login') {
          throw Exception(
            'Bạn cần đăng xuất và đăng nhập lại trước khi đổi Email!',
          );
        }
        throw Exception(e.message);
      }
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
