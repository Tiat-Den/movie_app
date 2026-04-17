import 'package:flutter/material.dart';
import 'package:movie_app/screens/room_movie_screen.dart';
import '../models/movie_model.dart';
import '../services/api_service.dart';
import '../services/room_service.dart';

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  // ─── Bước ────────────────────────────────────────────────────────────────
  int _step = 0; // 0 = nhập tên phòng, 1 = chọn phim

  // ─── Bước 1 ───────────────────────────────────────────────────────────────
  final _roomNameController = TextEditingController();

  // ─── Bước 2 ───────────────────────────────────────────────────────────────
  final ApiService _api = ApiService();
  final RoomService _roomService = RoomService();

  final _searchController = TextEditingController();
  String _searchQuery = '';

  // Danh sách tất cả phim tải về
  List<Movie> _allMovies = [];
  bool _loadingMovies = true;

  // Phim đã chọn vào playlist
  final List<Movie> _playlist = [];

  // Nút tạo phòng
  bool _isCreating = false;

  // ─── Loại nội dung: phim lẻ hay phim bộ ──────────────────────────────────
  bool _isTvMode = false; // false = phim lẻ, true = phim bộ

  // ─── Phân trang ───────────────────────────────────────────────────────────
  int _currentPage = 1;

  // ─── Tab category phim lẻ ─────────────────────────────────────────────────
  final List<Map<String, String>> _movieCategories = [
    {'label': 'Hot', 'type': 'popular'},
    {'label': 'Mới', 'type': 'now_playing'},
    {'label': 'Hay', 'type': 'top_rated'},
    {'label': 'Hành Động', 'type': 'action'},
    {'label': 'Hài', 'type': 'comedy'},
    {'label': 'Kinh Dị', 'type': 'horror'},
    {'label': 'Viễn Tưởng', 'type': 'scifi'},
  ];

  // ─── Tab category phim bộ ─────────────────────────────────────────────────
  final List<Map<String, String>> _tvCategories = [
    {'label': 'Phổ Biến', 'type': 'tv_popular'},
    {'label': 'Đánh Giá Cao', 'type': 'tv_top_rated'},
    {'label': 'Chiếu Hôm Nay', 'type': 'tv_airing_today'},
    {'label': 'Hoạt Hình', 'type': 'tv_animation'},
  ];

  int _selectedCategory = 0;

  List<Map<String, String>> get _categories =>
      _isTvMode ? _tvCategories : _movieCategories;

  @override
  void initState() {
    super.initState();
    _loadMovies();
  }

  Future<void> _loadMovies({bool resetPage = false}) async {
    setState(() {
      if (resetPage) _currentPage = 1;
      _loadingMovies = true;
    });
    try {
      final movies = await _api.getMovies(
        _categories[_selectedCategory]['type']!,
        page: _currentPage,
      );
      setState(() {
        _allMovies = movies;
        _loadingMovies = false;
      });
    } catch (_) {
      setState(() => _loadingMovies = false);
    }
  }

  List<Movie> get _filteredMovies {
    if (_searchQuery.isEmpty) return _allMovies;
    return _allMovies
        .where(
          (m) =>
              m.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              m.originalTitle.toLowerCase().contains(
                _searchQuery.toLowerCase(),
              ),
        )
        .toList();
  }

  bool _isInPlaylist(Movie movie) => _playlist.any((m) => m.id == movie.id);

  void _toggleMovie(Movie movie) {
    setState(() {
      if (_isInPlaylist(movie)) {
        _playlist.removeWhere((m) => m.id == movie.id);
      } else {
        _playlist.add(movie);
      }
    });
  }

  Future<void> _createRoom() async {
    if (_isCreating || _playlist.isEmpty) return;
    setState(() => _isCreating = true);

    try {
      final firstMovie = _playlist.first;

      String? realVideoUrl = await _api.getMovieStreamLink(
        firstMovie.id,
        firstMovie.title,
        firstMovie.originalTitle,
        isTv: firstMovie.isTv,
      );

      if (realVideoUrl == null || realVideoUrl.isEmpty) {
        if (!mounted) return;
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Không lấy được link phim, hãy thử phim khác!"),
          ),
        );
        return;
      }

      debugPrint("Link phím: $realVideoUrl");

      final roomId = await _roomService.createRoom(
        roomName: _roomNameController.text.trim(),
        videoUrl: realVideoUrl,
        movieList: _playlist,
      );

      if (!mounted) return;
      setState(() => _isCreating = false);

      if (roomId != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => RoomMovieScreen(roomId: roomId),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCreating = false);
      debugPrint("❌ Lỗi hệ thống khi tạo phòng: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().contains('TimeoutException')
                ? 'Kết nối quá chậm, vui lòng thử lại!'
                : 'Lỗi tạo phòng: ${e.toString()}',
          ),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // Chuyển đổi chế độ phim lẻ / phim bộ
  void _switchMode(bool toTv) {
    if (_isTvMode == toTv) return;
    setState(() {
      _isTvMode = toTv;
      _selectedCategory = 0;
      _searchQuery = '';
      _searchController.clear();
      _currentPage = 1;
    });
    _loadMovies();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  UI
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF15141F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          _step == 0 ? 'Tạo Phòng Xem Phim' : 'Chọn Phim Cho Phòng',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: _step == 1
            ? [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: TextButton.icon(
                    onPressed: _playlist.isEmpty || _isCreating
                        ? null
                        : _createRoom,
                    icon: _isCreating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.check_circle,
                            color: Colors.greenAccent,
                          ),
                    label: Text(
                      'Tạo phòng',
                      style: TextStyle(
                        color: _playlist.isEmpty
                            ? Colors.white38
                            : Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ]
            : null,
      ),
      body: _step == 0 ? _buildStep1() : _buildStep2(),
    );
  }

  // ─── Bước 1: Nhập tên phòng ───────────────────────────────────────────────
  Widget _buildStep1() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Illustration
          Center(
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                gradient: const RadialGradient(
                  colors: [Color(0xFF3D1A1A), Color(0xFF15141F)],
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.4),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.meeting_room_rounded,
                color: Colors.redAccent,
                size: 52,
              ),
            ),
          ),
          const SizedBox(height: 32),

          const Text(
            'Đặt tên cho phòng của bạn',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Bạn bè sẽ thấy tên phòng khi tham gia cùng xem phim.',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 24),

          // TextField tên phòng
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF211F30),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: TextField(
              controller: _roomNameController,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'VD: Phòng chiếu phim tối thứ 6',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.edit, color: Colors.redAccent),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
                // Giới hạn số ký tự
                suffixText: '${_roomNameController.text.length}/40',
                suffixStyle: const TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                ),
              ),
              maxLength: 40,
              buildCounter:
                  (
                    context, {
                    required currentLength,
                    required isFocused,
                    maxLength,
                  }) => null,
              onChanged: (_) => setState(() {}),
            ),
          ),

          const Spacer(),

          // Nút Tiếp theo
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _roomNameController.text.trim().isEmpty
                  ? null
                  : () => setState(() => _step = 1),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                disabledBackgroundColor: Colors.white12,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Tiếp theo — Chọn phim',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ─── Bước 2: Chọn phim ────────────────────────────────────────────────────
  Widget _buildStep2() {
    return Column(
      children: [
        // ── Toggle Phim Lẻ / Phim Bộ ──────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF211F30),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _switchMode(false),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: !_isTvMode
                            ? Colors.redAccent
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.movie,
                            color: !_isTvMode ? Colors.white : Colors.white38,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Phim Lẻ',
                            style: TextStyle(
                              color: !_isTvMode ? Colors.white : Colors.white38,
                              fontWeight: !_isTvMode
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _switchMode(true),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _isTvMode ? Colors.redAccent : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.tv,
                            color: _isTvMode ? Colors.white : Colors.white38,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Phim Bộ',
                            style: TextStyle(
                              color: _isTvMode ? Colors.white : Colors.white38,
                              fontWeight: _isTvMode
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Thanh search ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF211F30),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Tìm kiếm phim...',
                hintStyle: TextStyle(color: Colors.white38),
                prefixIcon: Icon(Icons.search, color: Colors.redAccent),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
        ),

        // ── Category tabs ─────────────────────────────────────────────────
        const SizedBox(height: 10),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _categories.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final selected = i == _selectedCategory;
              return GestureDetector(
                onTap: () {
                  if (_selectedCategory != i) {
                    setState(() {
                      _selectedCategory = i;
                      _searchQuery = '';
                      _searchController.clear();
                      _currentPage = 1;
                    });
                    _loadMovies();
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.redAccent
                        : const Color(0xFF211F30),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? Colors.redAccent : Colors.white12,
                    ),
                  ),
                  child: Text(
                    _categories[i]['label']!,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white60,
                      fontWeight: selected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),

        // ── Playlist đã chọn (ẩn nếu rỗng) ──────────────────────────────
        if (_playlist.isNotEmpty) _buildPlaylistBar(),

        // ── Grid phim ────────────────────────────────────────────────────
        Expanded(
          child: _loadingMovies
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.redAccent),
                )
              : _filteredMovies.isEmpty
              ? const Center(
                  child: Text(
                    'Không tìm thấy phim',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.62,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  itemCount: _filteredMovies.length,
                  itemBuilder: (context, i) {
                    final movie = _filteredMovies[i];
                    final inList = _isInPlaylist(movie);
                    return _buildMovieTile(movie, inList);
                  },
                ),
        ),

        // ── Phân trang ────────────────────────────────────────────────────
        if (_searchQuery.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            color: const Color(0xFF211F30),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _currentPage > 1
                      ? () {
                          setState(() => _currentPage--);
                          _loadMovies();
                        }
                      : null,
                  icon: const Icon(Icons.arrow_back_ios),
                  color: _currentPage > 1 ? Colors.white : Colors.white24,
                  iconSize: 18,
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Trang $_currentPage',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: () {
                    setState(() => _currentPage++);
                    _loadMovies();
                  },
                  icon: const Icon(Icons.arrow_forward_ios, color: Colors.white),
                  iconSize: 18,
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ─── Playlist bar ─────────────────────────────────────────────────────────
  Widget _buildPlaylistBar() {
    return Container(
      height: 100,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF211F30),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Đã chọn ${_playlist.length} phim:',
            style: const TextStyle(
              color: Colors.redAccent,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _playlist.length,
              separatorBuilder: (context, index) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final m = _playlist[i];
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        m.posterPath,
                        width: 38,
                        height: 56,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () => _toggleMovie(m),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── Movie tile ───────────────────────────────────────────────────────────
  Widget _buildMovieTile(Movie movie, bool inList) {
    return GestureDetector(
      onTap: () => _toggleMovie(movie),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: inList ? Colors.greenAccent : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: inList
              ? [
                  BoxShadow(
                    color: Colors.greenAccent.withValues(alpha: 0.35),
                    blurRadius: 10,
                  ),
                ]
              : [],
        ),
        child: Stack(
          children: [
            // Poster
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                movie.posterPath,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
              ),
            ),

            // Badge phim bộ
            if (movie.isTv)
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Bộ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

            // Gradient + tiêu đề
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 20, 6, 6),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(8),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.85),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Text(
                  movie.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            // Dấu check khi đã chọn
            if (inList)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.greenAccent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 14, color: Colors.black),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _roomNameController.dispose();
    _searchController.dispose();
    super.dispose();
  }
}
