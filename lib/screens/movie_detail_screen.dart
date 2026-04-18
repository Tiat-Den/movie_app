import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
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
  List<dynamic>? _episodes; // Danh sách tập phim thực tế
  String _totalEpisodesFromApi = "?"; // Tổng số tập dự kiến
  bool _isLoadingEpisodes = false;

  List<Map<String, dynamic>>? _cast; // Danh sách diễn viên
  YoutubePlayerController? _youtubeController; // Controller trailer
  String? _trailerKey;

  @override
  void initState() {
    super.initState();
    // 1. Nếu là phim bộ thì mới tìm tập phim
    if (widget.movie.isTv) {
      _fetchEpisodeInfo();
    }
    // 2. Lấy danh sách diễn viên
    _fetchCast();
    // 3. Lấy trailer phim
    _fetchTrailer();
  }

  @override
  void dispose() {
    _youtubeController?.dispose();
    super.dispose();
  }

  // Lấy danh sách diễn viên chính (10 người)
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

  // Lấy mã video trailer YouTube
  Future<void> _fetchTrailer() async {
    final key = await ApiService().getMovieTrailer(
      widget.movie.id,
      widget.movie.isTv,
    );
    if (key != null && mounted) {
      setState(() {
        _trailerKey = key;
        _youtubeController = YoutubePlayerController(
          initialVideoId: key,
          flags: const YoutubePlayerFlags(
            autoPlay: false,
            mute: false,
            isLive: false,
          ),
        );
      });
    }
  }

  // Lấy thông tin tập phim từ phimapi.com
  Future<void> _fetchEpisodeInfo() async {
    setState(() => _isLoadingEpisodes = true);
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
                _episodes = detailData['episodes'][0]['server_data'];
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

  // WIDGETS HIỂN THỊ

  Widget _buildStarRating(double rating) {
    int starCount = (rating / 2).round();
    return Row(
      children: [
        for (int i = 1; i <= 5; i++)
          Icon(
            i <= starCount ? Icons.star : Icons.star_border,
            color: Colors.amber,
            size: 22,
          ),
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

  Widget _buildCastList() {
    if (_cast == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.red));
    }

    if (_cast!.isEmpty) return const SizedBox.shrink();

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

  Widget _buildTrailerSection() {
    if (_trailerKey == null || _youtubeController == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Trailer",
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: YoutubePlayer(
            controller: _youtubeController!,
            showVideoProgressIndicator: true,
            progressIndicatorColor: Colors.red,
          ),
        ),
        const SizedBox(height: 25),
      ],
    );
  }

  Widget _buildEpisodeList() {
    if (_episodes == null || _episodes!.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Danh sách tập",
          style: TextStyle(color: Colors.white54, fontSize: 14),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 45,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _episodes!.length,
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () => _watchEpisode(index),
                child: Container(
                  width: 50,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    "${index + 1}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // Hàm chuyển sang màn hình xem phim
  Future<void> _watchEpisode([int index = 0]) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          const Center(child: CircularProgressIndicator(color: Colors.red)),
    );

    String? realVideoUrl = await ApiService().getMovieStreamLink(
      widget.movie.id,
      widget.movie.title,
      widget.movie.originalTitle,
      isTv: widget.movie.isTv,
      episodeIndex: index,
    );

    if (mounted) Navigator.pop(context);

    if (realVideoUrl != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => WatchMovieScreen(
            movie: widget.movie,
            videoUrl: realVideoUrl,
            isOffline: false,
            episodes: _episodes,
            initialEpisodeIndex: index,
          ),
        ),
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Không tìm thấy link phim phù hợp!"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingEpisodes) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.red)),
      );
    }

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
              // Banner Poster
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

                    // Trạng thái số tập
                    if (widget.movie.isTv)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _isLoadingEpisodes
                              ? "Đang tải số tập..."
                              : "Số tập: ${_episodes?.length ?? '0'} / $_totalEpisodesFromApi tập",
                          style: const TextStyle(
                            color: Colors.blueAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                    _buildStarRating(widget.movie.voteAverage),
                    const SizedBox(height: 20),

                    // DANH SÁCH TẬP (Nếu là phim bộ)
                    if (widget.movie.isTv) _buildEpisodeList(),

                    // DIỄN VIÊN
                    _buildCastList(),
                    const SizedBox(height: 25),

                    // TRAILER
                    _buildTrailerSection(),

                    // NÚT XEM PHIM
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(
                          Icons.play_circle_fill,
                          size: 28,
                          color: Colors.white,
                        ),
                        label: const Text(
                          "XEM PHIM NGAY",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        onPressed: () => _watchEpisode(0),
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
