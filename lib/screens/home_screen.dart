import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:movie_app/screens/downloaded_movies_screen.dart';
import 'package:movie_app/services/auth_service.dart';
import '../models/movie_model.dart';
import '../services/api_service.dart';
import 'movie_detail_screen.dart';
import 'category_screen.dart';
import 'profile_screen.dart';
import 'room_movie_screen.dart';
import 'create_room_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();
  final AuthService _authService = AuthService();

  String _searchQuery = "";
  Timer? _debounceTimer;

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  // --- Trạng thái ---
  String _trendingTime = "day";
  String _selectedMediaType = "all"; // all, movie, tv
  final List<String> _selectedGenreIds = [];

  // ID chuẩn TMDB
  final List<Map<String, String>> _genreOptions = [
    {"label": "Hành động", "value": "28"},
    {"label": "Kinh dị", "value": "27"},
    {"label": "Hài hước", "value": "35"},
    {"label": "Hoạt hình", "value": "16"},
    {"label": "Viễn tưởng", "value": "878"},
    {"label": "Lãng mạn", "value": "10749"},
    {"label": "Bí ẩn", "value": "9648"},
    {"label": "Tài liệu", "value": "99"},
  ];

  // ============================================================
  // DIALOG & BOTTOM SHEET
  // ============================================================
  void _showRoomDialog() {
    final TextEditingController codeC = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF211F30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Phòng Phim',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ô nhập mã phòng
            TextField(
              controller: codeC,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Nhập mã phòng...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Nút Vào Phòng
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () async {
                final code = codeC.text.trim();
                if (code.isEmpty) return;
                Navigator.pop(ctx);
                final doc = await FirebaseFirestore.instance
                    .collection('rooms')
                    .doc(code)
                    .get();
                if (doc.exists && mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RoomMovieScreen(roomId: code),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Phòng không tồn tại!")),
                  );
                }
              },
              child: const Text(
                "VÀO PHÒNG",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),

            const SizedBox(height: 10),

            // Nút Tạo Phòng Mới (Của ông đây)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx); // Đóng Dialog
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CreateRoomScreen()),
                );
              },
              child: const Text(
                "Hoặc tạo phòng mới",
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF211F30),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Dùng SafeArea ở ĐÂY để đẩy cái nút lên trên 3 nút Android
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                child: Padding(
                  // Thêm chút padding bottom để nút không dính sát mép SafeArea
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // --- Tiêu đề ---
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Lọc phim",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextButton(
                            onPressed: () => setModalState(() {
                              _selectedMediaType = "all";
                              _selectedGenreIds.clear();
                            }),
                            child: const Text(
                              "Đặt lại",
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white10),

                      // --- Danh sách thể loại (Có thể cuộn) ---
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 10),
                              const Text(
                                "Loại phim",
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                children: [
                                  _buildTypeChip(
                                    "Tất cả",
                                    "all",
                                    setModalState,
                                  ),
                                  _buildTypeChip(
                                    "Phim lẻ",
                                    "movie",
                                    setModalState,
                                  ),
                                  _buildTypeChip(
                                    "Phim bộ",
                                    "tv",
                                    setModalState,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                "Thể loại",
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _genreOptions
                                    .map(
                                      (g) => _buildGenreFilterChip(
                                        g['label']!,
                                        g['value']!,
                                        setModalState,
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // --- NÚT ÁP DỤNG (Đã được SafeArea bảo vệ) ---
                      const SizedBox(height: 15),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 5,
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            setState(() {});
                          },
                          child: const Text(
                            "ÁP DỤNG LỌC",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      // Thêm một khoảng đệm nhỏ cuối cùng
                      const SizedBox(height: 5),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _showConfirmDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF211F30),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.logout, color: Colors.redAccent),
                SizedBox(width: 10),
                Text("Đăng xuất", style: TextStyle(color: Colors.white)),
              ],
            ),
            content: const Text(
              "Bạn có chắc chắn muốn thoát tài khoản không?",
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              // Nút Hủy
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  "Hủy",
                  style: TextStyle(color: Colors.white38),
                ),
              ),
              // Nút Thoát
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  "Thoát",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false; // Nếu click ra ngoài dialog thì mặc định là false
  }

  // ============================================================
  // WIDGET CHIPS
  // ============================================================
  Widget _buildTypeChip(String label, String value, Function setModalState) {
    bool isSelected = _selectedMediaType == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) => setModalState(() => _selectedMediaType = value),
      selectedColor: Colors.redAccent,
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black,
        fontSize: 12,
      ),
      showCheckmark: false,
    );
  }

  Widget _buildGenreFilterChip(
    String label,
    String value,
    Function setModalState,
  ) {
    bool isSelected = _selectedGenreIds.contains(value);
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) => setModalState(() {
        val ? _selectedGenreIds.add(value) : _selectedGenreIds.remove(value);
      }),
      selectedColor: Colors.redAccent,
      backgroundColor: Colors.white,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black,
        fontSize: 12,
      ),
    );
  }

  // ============================================================
  // UI SECTIONS
  // ============================================================
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: "Tìm kiếm phim...",
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
          prefixIcon: const Icon(Icons.search, color: Colors.redAccent),
          suffixIcon: IconButton(
            icon: const Icon(Icons.tune, color: Colors.white70),
            onPressed: _showFilterBottomSheet,
          ),
          filled: true,
          fillColor: Colors.white10,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (query) {
          if (query.trim().isEmpty) {
            setState(() {
              _searchQuery = "";
            });
            return;
          }
          if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
          _debounceTimer = Timer(const Duration(milliseconds: 500), () {
            setState(() {
              _searchQuery = query.trim();
            });
          });
        },
      ),
    );
  }

  Widget _buildTrendingSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.trending_up, color: Colors.amber, size: 26),
          const SizedBox(width: 8),
          const Text(
            "Bảng Xếp Hạng",
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _buildTimeOption("Ngày", "day"),
                _buildTimeOption("Tuần", "week"),
                _buildTimeOption("Tháng", "popular"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeOption(String label, String value) {
    bool isSelected = _trendingTime == value;
    return GestureDetector(
      onTap: () => setState(() => _trendingTime = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.redAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white38,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildTrendingList() {
    String apiType = _trendingTime == "day"
        ? "trending_day"
        : (_trendingTime == "week" ? "trending_week" : "popular");
    return SizedBox(
      height: 250,
      child: FutureBuilder<List<Movie>>(
        future: _apiService.getMovies(apiType),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.red),
            );
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const SizedBox();
          }
          final top10 = snapshot.data!.take(10).toList();
          return ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: top10.length,
            itemBuilder: (context, index) => GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MovieDetailScreen(movie: top10[index]),
                ),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 140,
                    margin: const EdgeInsets.only(
                      right: 30,
                      top: 10,
                      bottom: 20,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: Image.network(
                        top10[index].posterPath,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Positioned(
                    left: -15,
                    bottom: -10,
                    child: Text(
                      "${index + 1}",
                      style: TextStyle(
                        fontSize: 90,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                        color: Colors.white.withValues(alpha: 0.9),
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.8),
                            blurRadius: 15,
                            offset: const Offset(4, 4),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMovieCategory(String title, String type) {
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
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CategoryScreen(title: title, type: type),
                  ),
                ),
                child: const Text(
                  "Xem tất cả",
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 200,
          child: FutureBuilder<List<Movie>>(
            future: _apiService.getMovies(type),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const SizedBox();
              }

              final movies = snapshot.data!.take(6).toList();

              return ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: movies.length,
                itemBuilder: (context, i) => GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MovieDetailScreen(movie: movies[i]),
                    ),
                  ),
                  child: Container(
                    width: 130,
                    margin: const EdgeInsets.only(right: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        movies[i].posterPath,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ============================================================
  // CHÍNH: HIỂN THỊ NỘI DUNG
  // ============================================================
  Widget _buildMainBody() {
    if (_searchQuery.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Kết quả tìm kiếm",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() {
                    _searchQuery = "";
                    _searchController.clear();
                  }),
                  icon: const Icon(Icons.close, color: Colors.redAccent),
                ),
              ],
            ),
          ),
          FutureBuilder<List<Movie>>(
            future: _apiService.searchMovies(_searchQuery),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.red),
                );
              }

              final movies = snapshot.data ?? [];

              if (movies.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text(
                      "Không tìm thấy phim",
                      style: TextStyle(color: Colors.white38),
                    ),
                  ),
                );
              }

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.65,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: movies.length,
                itemBuilder: (context, i) => GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MovieDetailScreen(movie: movies[i]),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      movies[i].posterPath,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      );
    }

    if (_selectedMediaType != "all" || _selectedGenreIds.isNotEmpty) {
      String genreQuery = _selectedGenreIds.join(",");
      String filterType =
          "${_selectedMediaType == 'all' ? 'movie' : _selectedMediaType}_$genreQuery";
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Kết quả lọc",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() {
                    _selectedMediaType = "all";
                    _selectedGenreIds.clear();
                  }),
                  icon: const Icon(Icons.close, color: Colors.redAccent),
                ),
              ],
            ),
          ),
          FutureBuilder<List<Movie>>(
            future: _apiService.getMovies(filterType),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.red),
                );
              }

              final movies = snapshot.data ?? [];

              if (movies.isEmpty) {
                return const Center(
                  child: Text(
                    "Không có phim",
                    style: TextStyle(color: Colors.white38),
                  ),
                );
              }

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.65,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: movies.length,
                itemBuilder: (context, i) => GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MovieDetailScreen(movie: movies[i]),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      movies[i].posterPath,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      );
    }
    return Column(
      children: [
        _buildTrendingSelector(),
        _buildTrendingList(),
        const SizedBox(height: 20),
        _buildMovieCategory("🔥 Phim Hot", "popular"),
        _buildMovieCategory("📺 Phim Bộ Phổ Biến", "tv_popular"),
        _buildMovieCategory("🆕 Phim Mới Cập Nhật", "now_playing"),
        _buildMovieCategory("🐲 Hoạt Hình Dài Tập", "tv_animation"),
        _buildMovieCategory("🎬 Phim Bộ Chiếu Hôm Nay", "tv_airing_today"),
        _buildMovieCategory("⚔️ Hành Động", "action"),
        _buildMovieCategory("👻 Kinh Dị", "horror"),
        _buildMovieCategory("🚀 Viễn Tưởng", "scifi"),
        _buildMovieCategory("🤣 Hài Hước", "comedy"),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF15141F),
      body: SafeArea(
        // TRÁNH BỊ 3 NÚT ANDROID CHE
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Custom Top App Bar
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Rạp Phim',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        PopupMenuButton<String>(
                          icon: StreamBuilder<DocumentSnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('users')
                                .doc(FirebaseAuth.instance.currentUser?.uid)
                                .snapshots(),
                            builder: (context, snapshot) {
                              ImageProvider? provider;

                              if (snapshot.hasData && snapshot.data!.exists) {
                                final data =
                                    snapshot.data!.data()
                                        as Map<String, dynamic>?;

                                // Ưu tiên 1: ảnh tự chọn (base64) — khớp với ProfileScreen
                                final customAvatar =
                                    data?['customAvatarUrl'] as String?;
                                if (customAvatar != null &&
                                    customAvatar.isNotEmpty) {
                                  try {
                                    provider = MemoryImage(
                                      base64Decode(customAvatar),
                                    );
                                  } catch (_) {}
                                }

                                // Ưu tiên 2: avatarUrl cũ (legacy)
                                if (provider == null) {
                                  final legacy = data?['avatarUrl'] as String?;
                                  if (legacy != null && legacy.isNotEmpty) {
                                    if (legacy.startsWith('http')) {
                                      provider = NetworkImage(legacy);
                                    } else {
                                      try {
                                        provider = MemoryImage(
                                          base64Decode(legacy),
                                        );
                                      } catch (_) {}
                                    }
                                  }
                                }
                              }

                              // Ưu tiên 3: photoURL từ Google (chỉ khi chưa đổi ảnh)
                              if (provider == null) {
                                final photoUrl =
                                    FirebaseAuth.instance.currentUser?.photoURL;
                                if (photoUrl != null && photoUrl.isNotEmpty) {
                                  provider = NetworkImage(photoUrl);
                                }
                              }

                              return CircleAvatar(
                                backgroundColor: Colors.white24,
                                backgroundImage: provider,
                                child: provider == null
                                    ? const Icon(
                                        Icons.person,
                                        color: Colors.white,
                                        size: 20,
                                      )
                                    : null,
                              );
                            },
                          ),
                          color: const Color(0xFF211F30),
                          onSelected: (v) {
                            if (v == 'profile') {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ProfileScreen(),
                                ),
                              );
                            }

                            if (v == 'downloads') {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const DownloadedMoviesScreen(),
                                ),
                              );
                            }

                            if (v == 'room') _showRoomDialog();
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'profile',
                              child: Text(
                                "Tài khoản",
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'downloads',
                              child: Text(
                                "Phim đã tải",
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'room',
                              child: Text(
                                "Phòng Phim",
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.logout, color: Colors.white),
                          onPressed: () async {
                            bool confirm =
                                await _showConfirmDialog(); // Hàm hiện thông báo xác nhận
                            if (confirm) {
                              await _authService
                                  .signOut(); // Gọi hàm signOut ở trên
                              if (mounted) {
                                // Đẩy về Login và xóa hết các màn hình cũ trong Stack
                                Navigator.pushNamedAndRemoveUntil(
                                  context,
                                  '/login',
                                  (route) => false,
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _buildSearchBar(),
              const SizedBox(height: 10),
              _buildMainBody(),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
