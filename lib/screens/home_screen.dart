import 'package:flutter/material.dart';
import 'package:movie_app/screens/downloaded_movies_screen.dart';
import '../models/movie_model.dart';
import '../services/api_service.dart';
import 'movie_detail_screen.dart';
import 'category_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _apiService = ApiService();

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
          // --- NÚT AVATAR CÓ DROPDOWN ---
          PopupMenuButton<String>(
            // Icon hiển thị trên AppBar
            icon: const CircleAvatar(
              backgroundColor: Colors.white24,
              child: Icon(Icons.person, color: Colors.white),
            ),
            // Màu nền của cái menu xổ xuống
            color: const Color(0xFF211F30),
            // Chỉnh khoảng cách để menu tụt xuống một chút, không che mất cái Avatar
            offset: const Offset(0, 50),
            // Xử lý sự kiện khi chọn 1 dòng
            onSelected: (String value) {
              if (value == 'profile') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ProfileScreen(),
                  ),
                );
              } else if (value == 'downloads') {
                // Chuyển sang màn hình Phim đã tải mình vừa làm
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DownloadedMoviesScreen(),
                  ),
                );
              }
            },
            // Các mục con bên trong Menu
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.account_circle, color: Colors.white),
                    SizedBox(width: 10),
                    Text("Tài khoản", style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'downloads',
                child: Row(
                  children: [
                    Icon(Icons.download_for_offline, color: Colors.white),
                    SizedBox(width: 10),
                    Text("Phim đã tải", style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),

          // --- NÚT ĐĂNG XUẤT (Giữ nguyên của bạn) ---
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () {
              // Code đăng xuất của bạn
            },
          ),
          const SizedBox(width: 10), // Cách lề phải một xíu cho đẹp
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildMovieCategory(context, "🔥 Phim Hot", "popular"),
            _buildMovieCategory(context, "🍿 Phim Mới", "now_playing"),
            _buildMovieCategory(
              context,
              "⭐ Phim Được Đánh Giá Cao",
              "top_rated",
            ),
            _buildMovieCategory(context, "Phim Hoạt hình", "animation"),
            _buildMovieCategory(context, "Phim Hành Động", "action"),
            _buildMovieCategory(context, "Phim Hài Hước", "comedy"),
            _buildMovieCategory(context, "Phim Kinh Dị", "horror"),
            _buildMovieCategory(context, "Phim Khoa Học Viễn Tưởng", "scifi"),
            _buildMovieCategory(context, "Phim Lãng Mạn", "romance"),
            _buildMovieCategory(context, "Phim Tài Liệu", "documentary"),

            const SizedBox(height: 30),
          ],
        ),
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

              final allMovies = snapshot.data!;
              final displayMovies = allMovies.length > 6
                  ? allMovies.sublist(0, 6)
                  : allMovies;

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
