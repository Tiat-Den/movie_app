import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:movie_app/screens/downloaded_movies_screen.dart';
import '../models/movie_model.dart';
import '../services/api_service.dart';
import 'movie_detail_screen.dart';
import 'category_screen.dart';
import 'profile_screen.dart';
import 'create_room_screen.dart';
import 'room_movie_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _apiService = ApiService();

  // --- Dialog chọn: vào phòng hoặc tạo phòng ---
  void _showRoomDialog() {
    final TextEditingController _codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF211F30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.movie_filter, color: Colors.redAccent, size: 22),
            SizedBox(width: 8),
            Text(
              'Phòng Phim',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _codeController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Nhập mã phòng...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.vpn_key, color: Colors.white38),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final code = _codeController.text.trim();
                  if (code.isEmpty) return;
                  Navigator.of(ctx).pop();
                  final doc = await FirebaseFirestore.instance
                      .collection('rooms')
                      .doc(code)
                      .get();
                  if (!mounted) return;
                  if (doc.exists) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RoomMovieScreen(roomId: code),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Không tìm thấy phòng!'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.login, size: 18),
                label: const Text('Vào Phòng'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Row(
              children: [
                Expanded(child: Divider(color: Colors.white12)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'hoặc',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
                Expanded(child: Divider(color: Colors.white12)),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CreateRoomScreen()),
                  );
                },
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('Tạo Phòng Mới'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
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
          'Rạp Phim',
          style: TextStyle(
            color: Colors.redAccent,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const CircleAvatar(
              backgroundColor: Colors.white24,
              child: Icon(Icons.person, color: Colors.white),
            ),
            color: const Color(0xFF211F30),
            offset: const Offset(0, 50),
            onSelected: (String value) {
              if (value == 'profile') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ProfileScreen(),
                  ),
                );
              } else if (value == 'downloads') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DownloadedMoviesScreen(),
                  ),
                );
              } else if (value == 'room') {
                _showRoomDialog();
              }
            },
            itemBuilder: (BuildContext context) => [
              _buildPopupItem('profile', Icons.account_circle, "Tài khoản"),
              _buildPopupItem(
                'downloads',
                Icons.download_for_offline,
                "Phim đã tải",
              ),
              _buildPopupItem(
                'room',
                Icons.movie_filter,
                "Phòng Phim",
                iconColor: Colors.redAccent,
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () {
              // Thêm logic đăng xuất của bạn ở đây
            },
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // --- XEN KẼ PHIM LẺ VÀ PHIM BỘ ---
            _buildMovieCategory(context, "Phim Hot", "popular"),
            _buildMovieCategory(context, "Phim Bộ Phổ Biến", "tv_popular"),
            _buildMovieCategory(context, "Phim Mới Cập Nhật", "now_playing"),
            _buildMovieCategory(context, "Hoạt Hình Dài Tập", "tv_animation"),
            _buildMovieCategory(context, "Đánh Giá Cao", "top_rated"),
            _buildMovieCategory(
              context,
              "Phim Bộ Chiếu Hôm Nay",
              "tv_airing_today",
            ),

            // --- THỂ LOẠI KHÁC ---
            _buildMovieCategory(context, "Hành Động", "action"),
            _buildMovieCategory(context, "Kinh Dị", "horror"),
            _buildMovieCategory(context, "Viễn Tưởng", "scifi"),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildPopupItem(
    String value,
    IconData icon,
    String text, {
    Color iconColor = Colors.white,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 10),
          Text(text, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildMovieCategory(BuildContext context, String title, String type) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          CategoryScreen(title: title, type: type),
                    ),
                  );
                },
                child: const Text(
                  "Xem tất cả",
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 220,
          child: FutureBuilder<List<Movie>>(
            future: _apiService.getMovies(type, page: 1),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.red),
                );
              } else if (snapshot.hasError) {
                return const Center(
                  child: Text(
                    "Lỗi tải dữ liệu",
                    style: TextStyle(color: Colors.white),
                  ),
                );
              } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(
                  child: Text(
                    "Chưa có phim",
                    style: TextStyle(color: Colors.white),
                  ),
                );
              }

              final displayMovies = snapshot.data!.take(6).toList();

              return ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: displayMovies.length,
                itemBuilder: (context, index) {
                  final movie = displayMovies[index];
                  return GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => MovieDetailScreen(movie: movie),
                      ),
                    ),
                    child: Container(
                      width: 130,
                      margin: const EdgeInsets.only(right: 16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          movie.posterPath,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                                color: Colors.white10,
                                child: const Icon(
                                  Icons.broken_image,
                                  color: Colors.white24,
                                ),
                              ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
