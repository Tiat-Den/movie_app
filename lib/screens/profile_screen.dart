import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  User? currentUser;

  @override
  void initState() {
    super.initState();
    currentUser = _authService.getCurrentUser();
  }

  // --- HÀM ĐỔI MẬT KHẨU (Chỉ dành cho người dùng Email) ---
  void _showChangePasswordDialog() {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool obscureOld = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF211F30),
          title: const Text(
            "Đổi mật khẩu",
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogTextField(
                  oldPasswordController,
                  "Mật khẩu cũ",
                  obscureOld,
                  () => setDialogState(() => obscureOld = !obscureOld),
                ),
                const SizedBox(height: 10),
                _buildDialogTextField(
                  newPasswordController,
                  "Mật khẩu mới",
                  obscureNew,
                  () => setDialogState(() => obscureNew = !obscureNew),
                ),
                const SizedBox(height: 10),
                _buildDialogTextField(
                  confirmPasswordController,
                  "Nhập lại mật khẩu mới",
                  obscureConfirm,
                  () => setDialogState(() => obscureConfirm = !obscureConfirm),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context),
              child: const Text("Hủy", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              onPressed: isLoading
                  ? null
                  : () async {
                      if (newPasswordController.text !=
                          confirmPasswordController.text) {
                        _showToast("Mật khẩu xác nhận không khớp!");
                        return;
                      }
                      setDialogState(() => isLoading = true);
                      try {
                        await _authService.updatePassword(
                          oldPasswordController.text,
                          newPasswordController.text,
                        );
                        if (context.mounted) {
                          Navigator.pop(context);
                          _showToast(
                            "Đổi mật khẩu thành công!",
                            isError: false,
                          );
                        }
                      } catch (e) {
                        _showToast(e.toString().replaceAll("Exception: ", ""));
                      } finally {
                        if (context.mounted)
                          setDialogState(() => isLoading = false);
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text("Cập nhật"),
            ),
          ],
        ),
      ),
    );
  }

  // --- HÀM CHỈNH SỬA THÔNG TIN (Cập nhật Firestore & DisplayName) ---
  void _showEditProfileDialog(Map<String, dynamic> currentData) {
    final nameController = TextEditingController(
      text: currentData['name'] ?? currentUser?.displayName,
    );
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF211F30),
          title: const Text(
            "Chỉnh sửa thông tin",
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: nameController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: "Họ và tên",
              labelStyle: TextStyle(color: Colors.grey),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.grey),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Hủy", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              onPressed: isLoading
                  ? null
                  : () async {
                      if (nameController.text.trim().isEmpty) return;
                      setDialogState(() => isLoading = true);
                      try {
                        // 1. Cập nhật Firestore
                        await _firestore
                            .collection('users')
                            .doc(currentUser!.uid)
                            .update({'name': nameController.text.trim()});
                        // 2. Cập nhật DisplayName trong Firebase Auth
                        await currentUser!.updateDisplayName(
                          nameController.text.trim(),
                        );

                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        _showToast("Lỗi: $e");
                      } finally {
                        if (context.mounted)
                          setDialogState(() => isLoading = false);
                      }
                    },
              child: const Text("Lưu lại"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF15141F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "Hồ sơ cá nhân",
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      // --- LẤY DỮ LIỆU TỪ FIRESTORE THỜI GIAN THỰC ---
      body: StreamBuilder<DocumentSnapshot>(
        stream: _firestore
            .collection('users')
            .doc(currentUser?.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.redAccent),
            );
          }

          // Dữ liệu từ Firestore (để lấy tên thật ông đã lưu)
          var userData = snapshot.data?.data() as Map<String, dynamic>?;

          // Kiểm tra xem có đăng nhập bằng Google không
          bool isGoogle = false;
          if (currentUser != null) {
            isGoogle = currentUser!.providerData.any(
              (p) => p.providerId == 'google.com',
            );
          }

          return SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 20),
                Center(
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.redAccent,
                    backgroundImage: isGoogle && currentUser?.photoURL != null
                        ? NetworkImage(currentUser!.photoURL!)
                        : null,
                    child: (!isGoogle || currentUser?.photoURL == null)
                        ? const Icon(
                            Icons.person,
                            size: 60,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 30),

                // Họ tên lấy từ Firestore (userData['name']) ưu tiên hơn
                _buildInfoTile(
                  Icons.person,
                  "Họ và tên",
                  userData?['name'] ??
                      currentUser?.displayName ??
                      "Chưa đặt tên",
                ),
                _buildInfoTile(
                  Icons.email,
                  "Email",
                  userData?['email'] ?? currentUser?.email ?? "Chưa có email",
                ),

                // Phần hiển thị mật khẩu/phương thức đăng nhập
                _buildAuthMethodTile(isGoogle),

                const SizedBox(height: 40),
                _buildButton(
                  "Chỉnh sửa thông tin",
                  () => _showEditProfileDialog(userData ?? {}),
                ),
                const SizedBox(height: 15),
                _buildButton("Đăng xuất", () async {
                  await _authService.signOut();
                  if (mounted)
                    Navigator.of(context).popUntil((route) => route.isFirst);
                }),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- CÁC WIDGET PHỤ TRỢ ---

  Widget _buildAuthMethodTile(bool isGoogle) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: const Color(0xFF211F30),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              isGoogle ? Icons.link : Icons.lock,
              color: isGoogle ? Colors.blue : Colors.redAccent,
              size: 30,
            ),
            const SizedBox(width: 15),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isGoogle ? "Phương thức đăng nhập" : "Mật khẩu",
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                Text(
                  isGoogle ? "Tài khoản Google" : "********",
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
            const Spacer(),
            if (!isGoogle)
              TextButton(
                onPressed: _showChangePasswordDialog,
                child: const Text(
                  "Đổi",
                  style: TextStyle(color: Colors.blueAccent),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogTextField(
    TextEditingController controller,
    String label,
    bool obscure,
    VoidCallback toggle,
  ) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off : Icons.visibility,
            color: Colors.grey,
          ),
          onPressed: toggle,
        ),
      ),
    );
  }

  Widget _buildButton(String text, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.redAccent),
          minimumSize: const Size(double.infinity, 50),
        ),
        child: Text(
          text,
          style: const TextStyle(color: Colors.redAccent, fontSize: 16),
        ),
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: const Color(0xFF211F30),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.redAccent),
            const SizedBox(width: 15),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                Text(
                  value,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showToast(String msg, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }
}
