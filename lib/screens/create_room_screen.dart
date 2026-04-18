import 'dart:async'; // Cần để dùng Timer
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
  int _step = 0; // 0: Nhập tên phòng, 1: Chọn phim
  final _roomNameController = TextEditingController();
  final _searchController = TextEditingController();
  final ApiService _api = ApiService();
  final RoomService _roomService = RoomService();

  String _searchQuery = '';
  Timer? _debounceTimer; // Dùng để đợi người dùng gõ xong mới search
  List<Movie> _allMovies = [];
  bool _loadingMovies = true;
  final List<Movie> _playlist = [];
  bool _isCreating = false;
  bool _isTvMode = false;
  int _currentPage = 1;
  int _selectedCategory = 0;

  final List<Map<String, String>> _movieCategories = [
    {'label': 'Hot', 'type': 'popular'},
    {'label': 'Mới', 'type': 'now_playing'},
    {'label': 'Hay', 'type': 'top_rated'},
    {'label': 'Hành Động', 'type': 'action'},
    {'label': 'Hài', 'type': 'comedy'},
    {'label': 'Kinh Dị', 'type': 'horror'},
  ];

  final List<Map<String, String>> _tvCategories = [
    {'label': 'Phổ Biến', 'type': 'tv_popular'},
    {'label': 'Đánh Giá Cao', 'type': 'tv_top_rated'},
    {'label': 'Hoạt Hình', 'type': 'tv_animation'},
  ];

  List<Map<String, String>> get _categories =>
      _isTvMode ? _tvCategories : _movieCategories;

  @override
  void initState() {
    super.initState();
    _loadMovies();
  }

  // --- LOGIC LẤY PHIM ---
  // Tách biệt logic load theo trang và search online
  Future<void> _loadMovies({bool resetPage = false}) async {
    if (_searchQuery.isNotEmpty)
      return; // Nếu đang search thì không load theo trang

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

  // --- LOGIC TÌM KIẾM ONLINE (QUAN TRỌNG NHẤT) ---
  void _onSearchChanged(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();

    _debounceTimer = Timer(const Duration(milliseconds: 600), () async {
      setState(() {
        _searchQuery = query.trim();
        _loadingMovies = true;
      });

      if (_searchQuery.isEmpty) {
        _loadMovies(
          resetPage: true,
        ); // Nếu xóa ô search thì hiện lại phim mặc định
        return;
      }

      try {
        // GỌI API SEARCH ĐỂ LỤC TOÀN BỘ KHO PHIM
        final results = await _api.searchMovies(_searchQuery);
        setState(() {
          _allMovies = results;
          _loadingMovies = false;
        });
      } catch (e) {
        setState(() => _loadingMovies = false);
      }
    });
  }

  void _toggleMovie(Movie movie) {
    setState(() {
      if (_playlist.any((m) => m.id == movie.id)) {
        _playlist.removeWhere((m) => m.id == movie.id);
      } else {
        _playlist.add(movie);
      }
    });
  }

  void _switchMode(bool toTv) {
    if (_isTvMode == toTv) return;
    setState(() {
      _isTvMode = toTv;
      _selectedCategory = 0;
      _currentPage = 1;
      _searchQuery = '';
      _searchController.clear();
    });
    _loadMovies();
  }

  Future<void> _createRoom() async {
    if (_isCreating || _playlist.isEmpty) return;
    setState(() => _isCreating = true);
    try {
      final firstMovie = _playlist.first;
      String? realUrl = await _api.getMovieStreamLink(
        firstMovie.id,
        firstMovie.title,
        firstMovie.originalTitle,
        isTv: firstMovie.isTv,
      );

      if (realUrl == null) {
        if (!mounted) return;
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Lỗi link phim!")));
        return;
      }

      final roomId = await _roomService.createRoom(
        roomName: _roomNameController.text.trim(),
        videoUrl: realUrl,
        movieList: _playlist,
      );

      if (roomId != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => RoomMovieScreen(roomId: roomId)),
        );
      }
    } catch (e) {
      setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF15141F),
      body: SafeArea(
        child: Column(
          children: [
            _buildCustomAppBar(),
            Expanded(child: _step == 0 ? _buildStep1() : _buildStep2()),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () =>
                _step == 1 ? setState(() => _step = 0) : Navigator.pop(context),
          ),
          Text(
            _step == 0 ? 'Tạo Phòng' : 'Chọn Phim',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          if (_step == 1)
            TextButton(
              onPressed: _playlist.isEmpty || _isCreating ? null : _createRoom,
              child: _isCreating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.greenAccent,
                      ),
                    )
                  : Text(
                      'Tạo',
                      style: TextStyle(
                        color: _playlist.isEmpty
                            ? Colors.white24
                            : Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
        ],
      ),
    );
  }

  // BƯỚC 1: NHẬP TÊN
  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 40,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(25),
            decoration: BoxDecoration(
              color: Colors.redAccent.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.meeting_room_rounded,
              color: Colors.redAccent,
              size: 60,
            ),
          ),
          const SizedBox(height: 30),
          const Text(
            'Tên phòng của bạn',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 30),
          TextField(
            controller: _roomNameController,
            style: const TextStyle(color: Colors.white),
            autofocus: true,
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF211F30),
              hintText: 'Nhập tên phòng...',
              hintStyle: const TextStyle(color: Colors.white24),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
              prefixIcon: const Icon(Icons.edit, color: Colors.redAccent),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 50),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              onPressed: _roomNameController.text.trim().isEmpty
                  ? null
                  : () => setState(() => _step = 1),
              child: const Text(
                'Tiếp theo',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // BƯỚC 2: CHỌN PHIM
  Widget _buildStep2() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _modeTab(
                'Phim Lẻ',
                Icons.movie_outlined,
                !_isTvMode,
                () => _switchMode(false),
              ),
              const SizedBox(width: 10),
              _modeTab(
                'Phim Bộ',
                Icons.tv_rounded,
                _isTvMode,
                () => _switchMode(true),
              ),
            ],
          ),
        ),
        // THANH SEARCH ONLINE
        Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF211F30),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Tìm phim trên toàn cầu...',
                hintStyle: TextStyle(color: Colors.white24),
                prefixIcon: Icon(Icons.search, color: Colors.redAccent),
                border: InputBorder.none,
              ),
              onChanged: _onSearchChanged, // GỌI HÀM SEARCH ONLINE
            ),
          ),
        ),
        if (_playlist.isNotEmpty) _buildSmallPlaylist(),

        Expanded(
          child: _loadingMovies
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.redAccent),
                )
              : _allMovies.isEmpty
              ? const Center(
                  child: Text(
                    "Không tìm thấy phim nào",
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.65,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: _allMovies.length,
                  itemBuilder: (ctx, i) => _buildMovieCard(_allMovies[i]),
                ),
        ),
        // CHỈ HIỆN PHÂN TRANG KHI KHÔNG SEARCH (Vì kết quả search thường trả về toàn bộ)
        if (_searchQuery.isEmpty) _buildPagination(),
      ],
    );
  }

  Widget _modeTab(
    String title,
    IconData icon,
    bool active,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? Colors.redAccent : Colors.white10,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: active ? Colors.white : Colors.white38,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: active ? Colors.white : Colors.white38,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmallPlaylist() {
    return Container(
      height: 70,
      padding: const EdgeInsets.only(left: 16, bottom: 10),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _playlist.length,
        itemBuilder: (ctx, i) => Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  _playlist[i].posterPath,
                  width: 45,
                  height: 60,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () => _toggleMovie(_playlist[i]),
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
          ),
        ),
      ),
    );
  }

  Widget _buildMovieCard(Movie movie) {
    bool isSelected = _playlist.any((m) => m.id == movie.id);
    return GestureDetector(
      onTap: () => _toggleMovie(movie),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              movie.posterPath,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
          if (isSelected)
            Container(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Icon(
                  Icons.check_circle,
                  color: Colors.greenAccent,
                  size: 30,
                ),
              ),
            ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black, Colors.transparent],
                ),
              ),
              child: Text(
                movie.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPagination() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
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
            icon: const Icon(
              Icons.arrow_back_ios,
              color: Colors.white,
              size: 18,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.redAccent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Trang $_currentPage',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() => _currentPage++);
              _loadMovies();
            },
            icon: const Icon(
              Icons.arrow_forward_ios,
              color: Colors.white,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _roomNameController.dispose();
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }
}
