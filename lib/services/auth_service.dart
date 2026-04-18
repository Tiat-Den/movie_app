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
        await user.updateDisplayName(name);

        await _firestore.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'name': name,
          'email': email.trim(),
          'createdAt': DateTime.now(),
          'avatarUrl': '',
        });

        await user.sendEmailVerification();
        // 2. Đăng xuất ngay lập tức
        await signOut();
      }

      return user;
    } catch (e) {
      print(e);
      rethrow;
    }
  }

  Future<User?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );
      return userCredential.user;
    } catch (e) {
      print("Lỗi : $e");
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
