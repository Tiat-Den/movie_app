import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/movie_model.dart';
import '../services/api_service.dart';
import 'watch_movie_screen.dart';

class MovieDetailScreen extends StatefulWidget {
  final Movie movie;

  const MovieDetailScreen({super.key, required this.movie});

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  List<dynamic>? _episodes; // Lưu danh sách tập phim thực tế
  String _totalEpisodesFromApi =
      "?"; // Lưu tổng số tập dự kiến (VD: 12, 24, Full)
  bool _isLoadingEpisodes = false;

  List<Map<String, dynamic>>? _cast;

  @override
  void initState() {
    super.initState();
    // Nếu là phim bộ thì mới đi tìm thông tin tập
    if (widget.movie.isTv) {
      _fetchEpisodeInfo();
    }

    _fetchCast();
  }

  Future<void> _fetchCast() async {
    final castData = await ApiService().getMovieCast(
      widget.movie.id,
      widget.movie.isTv,
    );
    if (mounted) {
      setState(() {
        _cast = castData.take(10).toList();
      });
    }
  }

  // Hàm lấy thông tin tập phim từ phimapi.com
  Future<void> _fetchEpisodeInfo() async {
    setState(() => _isLoadingEpisodes = true);

    // Lấy phần tên chính của phim để search slug
    String cleanTitle = widget.movie.title.split(':').first.trim();

    try {
      final searchUrl = Uri.parse(
        'https://phimapi.com/v1/api/tim-kiem?keyword=${Uri.encodeComponent(cleanTitle)}&limit=1',
      );
      final res = await http.get(searchUrl);

      if (res.statusCode == 200) {
        final searchData = json.decode(res.body);
        final items = searchData['data']['items'];

        if (items != null && items.isNotEmpty) {
          final detailRes = await http.get(
            Uri.parse('https://phimapi.com/phim/${items[0]['slug']}'),
          );

          if (detailRes.statusCode == 200) {
            final detailData = json.decode(detailRes.body);

            if (mounted) {
              setState(() {
                // 1. Lấy danh sách các tập đã có link (để map sang màn hình xem phim)
                _episodes = detailData['episodes'][0]['server_data'];

                // 2. Lấy tổng số tập dự kiến từ thông tin phim
                _totalEpisodesFromApi =
                    detailData['movie']['episode_total'] ?? "?";

                _isLoadingEpisodes = false;
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Lỗi lấy thông tin tập: $e");
      if (mounted) setState(() => _isLoadingEpisodes = false);
    }
  }

  //////////////////////////////////
  Widget _buildCastList() {
    if (_cast == null) return const Center(child: CircularProgressIndicator());
    if (_cast!.isEmpty)
      return const Text(
        "Không có thông tin diễn viên",
        style: TextStyle(color: Colors.white54),
      );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Diễn viên chính",
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 140,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _cast!.length,
            itemBuilder: (context, index) {
              final actor = _cast![index];
              return Container(
                width: 80,
                margin: const EdgeInsets.only(right: 12),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 35,
                      backgroundColor: Colors.grey[900],
                      backgroundImage: CachedNetworkImageProvider(
                        actor['profile_path'],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      actor['name'],
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStarRating(double rating) {
    int starCount = (rating / 2).round();
    List<Widget> stars = [];
    for (int i = 1; i <= 5; i++) {
      stars.add(
        Icon(
          i <= starCount ? Icons.star : Icons.star_border,
          color: Colors.amber,
          size: 24,
        ),
      );
    }
    return Row(
      children: [
        ...stars,
        const SizedBox(width: 8),
        Text(
          '${rating.toStringAsFixed(1)}/10',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      extendBodyBehindAppBar: true,
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Banner/Poster Phim
              SizedBox(
                width: double.infinity,
                height: 500,
                child: CachedNetworkImage(
                  imageUrl: widget.movie.posterPath,
                  fit: BoxFit.cover,
                  placeholder: (context, url) =>
                      Container(color: Colors.grey[900]),
                  errorWidget: (context, url, error) => const Icon(Icons.error),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.movie.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 🟢 HIỂN THỊ TRẠNG THÁI SỐ TẬP (CHỈ PHIM BỘ)
                    if (widget.movie.isTv)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.blueAccent.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            _isLoadingEpisodes
                                ? "Đang tải số tập..."
                                : "Số tập: ${_episodes?.length ?? '0'} / $_totalEpisodesFromApi tập",
                            style: const TextStyle(
                              color: Colors.blueAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),

                    _buildStarRating(widget.movie.voteAverage),
                    const SizedBox(height: 20),

                    _buildCastList(),
                    const SizedBox(height: 25),

                    // NÚT XEM PHIM
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(Icons.play_circle_fill, size: 28),
                        label: const Text(
                          "XEM PHIM NGAY",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () async {
                          // Hiện loading dialog trong khi lấy link stream
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (context) => const Center(
                              child: CircularProgressIndicator(
                                color: Colors.red,
                              ),
                            ),
                          );

                          String? realVideoUrl = await ApiService()
                              .getMovieStreamLink(
                                widget.movie.id,
                                widget.movie.title,
                                widget.movie.originalTitle,
                                isTv: widget.movie.isTv,
                              );

                          if (mounted) {
                            Navigator.pop(context); // Tắt loading dialog
                          }

                          if (realVideoUrl != null && mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => WatchMovieScreen(
                                  movie: widget.movie,
                                  videoUrl: realVideoUrl,
                                  isOffline: false,
                                  episodes: _episodes, // Truyền list tập sang
                                ),
                              ),
                            );
                          } else {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    "Không tìm thấy link phim phù hợp!",
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                      ),
                    ),

                    const SizedBox(height: 25),
                    const Text(
                      "Nội dung phim",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.movie.overview.isEmpty
                          ? "Đang cập nhật nội dung..."
                          : widget.movie.overview,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
