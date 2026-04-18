import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();
  User? currentUser;

  @override
  void initState() {
    super.initState();
    currentUser = _authService.getCurrentUser();
  }

  // 1. Hàm chọn và tải ảnh đại diện lên Firestore
  Future<void> _pickAndUploadAvatar() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 300,
        maxHeight: 300,
        imageQuality: 50,
      );

      if (image == null) return;

      _showToast("Đang xử lý ảnh...", isError: false);

      final bytes = await image.readAsBytes();
      final base64String = base64Encode(bytes);

      if (currentUser != null) {
        // Lưu vào Firestore với field riêng 'customAvatarUrl'
        // KHÔNG dùng 'avatarUrl' vì có thể bị ghi đè bởi photoURL Google
        await _firestore.collection('users').doc(currentUser!.uid).set({
          'customAvatarUrl': base64String, // <-- field riêng cho ảnh tự chọn
          'uid': currentUser!.uid,
          'email': currentUser!.email,
          'name': currentUser!.displayName ?? "Người dùng",
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        _showToast("Cập nhật ảnh đại diện thành công!", isError: false);
      }
    } catch (e) {
      _showToast("Lỗi khi tải ảnh: $e");
      debugPrint("❌ Chi tiết lỗi upload avatar: $e");
    }
  }

  // 2. Hàm lấy nguồn ảnh — ưu tiên đúng thứ tự
  ImageProvider? _getAvatarProvider(
    Map<String, dynamic>? userData,
    bool isGoogle,
  ) {
    // ƯU TIÊN 1: Ảnh người dùng tự chọn (base64) — luôn thắng
    // Dùng field 'customAvatarUrl' để không bao giờ bị Google photoURL ghi đè
    final String? customAvatar = userData?['customAvatarUrl'];
    if (customAvatar != null && customAvatar.isNotEmpty) {
      try {
        return MemoryImage(base64Decode(customAvatar));
      } catch (e) {
        debugPrint("❌ Lỗi giải mã Base64: $e");
      }
    }

    // ƯU TIÊN 2 (legacy): Nếu 'avatarUrl' trong Firestore là link http
    // (tức là ảnh Google đã được lưu thủ công trước đó)
    final String? legacyAvatar = userData?['avatarUrl'];
    if (legacyAvatar != null && legacyAvatar.isNotEmpty) {
      if (legacyAvatar.startsWith('http')) {
        return NetworkImage(legacyAvatar);
      }
      // Nếu là base64 cũ trong 'avatarUrl'
      try {
        return MemoryImage(base64Decode(legacyAvatar));
      } catch (e) {
        debugPrint("❌ Lỗi giải mã Base64 legacy: $e");
      }
    }

    // ƯU TIÊN 3: Ảnh mặc định từ Google (chỉ khi chưa đổi ảnh bao giờ)
    if (isGoogle && currentUser?.photoURL != null) {
      return NetworkImage(currentUser!.photoURL!);
    }

    // ƯU TIÊN 4: Không có ảnh → hiện icon mặc định
    return null;
  }

  // --- HÀM ĐỔI MẬT KHẨU ---
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
                        if (context.mounted) {
                          setDialogState(() => isLoading = false);
                        }
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

  // --- HÀM CHỈNH SỬA THÔNG TIN ---
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
                        await _firestore
                            .collection('users')
                            .doc(currentUser!.uid)
                            .update({'name': nameController.text.trim()});
                        await currentUser!.updateDisplayName(
                          nameController.text.trim(),
                        );
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        _showToast("Lỗi: $e");
                      } finally {
                        if (context.mounted) {
                          setDialogState(() => isLoading = false);
                        }
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

          var userData = snapshot.data?.data() as Map<String, dynamic>?;

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
                  child: GestureDetector(
                    onTap: _pickAndUploadAvatar,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 55,
                          backgroundColor: Colors.redAccent,
                          backgroundImage: _getAvatarProvider(
                            userData,
                            isGoogle,
                          ),
                          child: _getAvatarProvider(userData, isGoogle) == null
                              ? const Icon(
                                  Icons.person,
                                  size: 60,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Colors.blueAccent,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 30),
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
                _buildAuthMethodTile(isGoogle),
                const SizedBox(height: 40),
                _buildButton(
                  "Chỉnh sửa thông tin",
                  () => _showEditProfileDialog(userData ?? {}),
                ),
                const SizedBox(height: 15),
                _buildButton("Đăng xuất", () async {
                  await _authService.signOut();
                  if (mounted) {
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/login',
                      (route) => false,
                    );
                  }
                }),
                const SizedBox(height: 30),
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
