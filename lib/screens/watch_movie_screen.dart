import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';

import '../models/movie_model.dart';

class WatchMovieScreen extends StatefulWidget {
  final Movie movie;
  final String videoUrl;
  final bool isOffline;
  final List<dynamic>? episodes; // Danh sách tập phim từ API
  final int initialEpisodeIndex;

  const WatchMovieScreen({
    super.key,
    required this.movie,
    required this.videoUrl,
    required this.isOffline,
    this.episodes,
    this.initialEpisodeIndex = 0,
  });

  @override
  State<WatchMovieScreen> createState() => _WatchMovieScreenState();
}

class _WatchMovieScreenState extends State<WatchMovieScreen> {
  // --- Video Controllers ---
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;

  // --- Services ---
  final TextEditingController _commentController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _user = FirebaseAuth.instance.currentUser;

  // --- States ---
  double _downloadProgress = 0;
  bool _isDownloading = false;
  String _downloadStatus = "";
  late String _currentUrl;
  late int _currentEpisodeIndex;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.videoUrl;
    _currentEpisodeIndex = widget.initialEpisodeIndex;
    // Cho phép xoay ngang màn hình khi xem phim
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _initPlayer();
  }

  // Khởi tạo hoặc khởi tạo lại trình phát (khi đổi tập)
  Future<void> _initPlayer() async {
    _chewieController?.dispose();
    _videoPlayerController?.pause();
    _videoPlayerController?.dispose();

    setState(() {
      _chewieController = null;
    });

    if (widget.isOffline) {
      _videoPlayerController = VideoPlayerController.file(File(_currentUrl));
    } else {
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(_currentUrl),
      );
    }

    try {
      await _videoPlayerController!.initialize();
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        aspectRatio: 16 / 9,
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.red,
          handleColor: Colors.redAccent,
          backgroundColor: Colors.white24,
          bufferedColor: Colors.white54,
        ),
      );
    } catch (e) {
      debugPrint("Lỗi khởi tạo trình phát: $e");
    }

    if (mounted) setState(() {});
  }

  void _changeEpisode(int index) {
    if (_currentEpisodeIndex == index) return;
    if (widget.episodes == null || widget.episodes!.length <= index) return;

    try {
      var episodeData = widget.episodes![index];
      String? newUrl;

      // KIỂM TRA CẤU TRÚC 1: Link nằm trực tiếp ở ngoài
      if (episodeData['link_m3u8'] != null &&
          episodeData['link_m3u8'].toString().isNotEmpty) {
        newUrl = episodeData['link_m3u8'].toString();
      }
      // KIỂM TRA CẤU TRÚC 2: Link nằm trong server_data -> [0] -> link_m3u8
      else if (episodeData['server_data'] != null &&
          (episodeData['server_data'] as List).isNotEmpty) {
        newUrl = episodeData['server_data'][0]['link_m3u8'].toString();
      }

      if (newUrl != null) {
        setState(() {
          _currentEpisodeIndex = index;
          _currentUrl = newUrl!;
        });
        debugPrint(" Đã lấy được link tập mới: $_currentUrl");
        _initPlayer();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Tập này chưa có link!")));
      }
    } catch (e) {
      debugPrint("❌ Lỗi đổi tập: $e");
    }
  }

  // ============================================================
  //  DOWNLOAD LOGIC
  // ============================================================
  Future<void> _handleSuperDownload() async {
    setState(() {
      _isDownloading = true;
      _downloadStatus = "Đang bắt đầu tải...";
      _downloadProgress = 0;
    });

    try {
      final dir = await getApplicationDocumentsDirectory();
      final String safeTitle = widget.movie.title
          .replaceAll(RegExp(r'[/\\:*?"<>|]'), '')
          .trim();
      final String epName = "Tap_${_currentEpisodeIndex + 1}";
      final String outputPath = "${dir.path}/${safeTitle}_$epName.mp4";

      final outputFile = File(outputPath);
      if (outputFile.existsSync()) outputFile.deleteSync();

      // FFmpeg convert HLS (.m3u8) sang MP4
      final String ffmpegCommand =
          "-y -i \"$_currentUrl\" -c copy \"$outputPath\"";

      final session = await FFmpegKit.execute(ffmpegCommand);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        setState(() {
          _downloadProgress = 1.0;
          _downloadStatus = "Tải thành công!";
        });
      } else {
        throw Exception("FFmpeg failed to convert video.");
      }
    } catch (e) {
      debugPrint("Lỗi Download: $e");
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _sendComment() {
    if (_commentController.text.trim().isNotEmpty && _user != null) {
      _firestore.collection('comments').add({
        'movieId': widget.movie.id,
        'userName': _user.displayName ?? "Khán giả",
        'text': _commentController.text.trim(),
        'timestamp': FieldValue.serverTimestamp(),
      });
      _commentController.clear();
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ─── PHẦN 1: VIDEO PLAYER ───
            _buildVideoPlayerSection(),

            // ─── PHẦN 2: CHI TIẾT & TƯƠNG TÁC ───
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeaderSection(),

                    if (_isDownloading) _buildDownloadProgress(),

                    // HIỂN THỊ CHỌN TẬP PHIM
                    if (widget.episodes != null && widget.episodes!.isNotEmpty)
                      _buildEpisodeList(),

                    const SizedBox(height: 15),
                    Text(
                      widget.movie.overview.isEmpty
                          ? "Không có mô tả."
                          : widget.movie.overview,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),

                    const Divider(color: Colors.white10, height: 40),

                    if (!widget.isOffline) ...[
                      const Text(
                        "Bình luận",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      _buildCommentInput(),
                      _buildCommentList(),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlayerSection() {
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            color: Colors.black,
            child: _chewieController != null
                ? Chewie(controller: _chewieController!)
                : const Center(
                    child: CircularProgressIndicator(color: Colors.red),
                  ),
          ),
        ),
        Positioned(
          top: 10,
          left: 10,
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderSection() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            widget.movie.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (!widget.isOffline)
          IconButton(
            onPressed: _isDownloading ? null : _handleSuperDownload,
            icon: _isDownloading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.red,
                    ),
                  )
                : const Icon(
                    Icons.download_for_offline,
                    color: Colors.white,
                    size: 28,
                  ),
          ),
      ],
    );
  }

  Widget _buildDownloadProgress() {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        children: [
          LinearProgressIndicator(
            value: _downloadProgress,
            color: Colors.red,
            backgroundColor: Colors.white12,
          ),
          Text(
            _downloadStatus,
            style: const TextStyle(color: Colors.redAccent, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildEpisodeList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        const Text(
          "Danh sách tập",
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: widget.episodes!.length,
            itemBuilder: (context, index) {
              bool isSelected = _currentEpisodeIndex == index;
              return GestureDetector(
                onTap: () => _changeEpisode(index),
                child: Container(
                  width: 45,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.red : Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? Colors.red : Colors.white24,
                    ),
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
      ],
    );
  }

  Widget _buildCommentInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Cảm nhận của bạn...",
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: _sendComment,
            icon: const Icon(Icons.send, color: Colors.red),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('comments')
          .where('movieId', isEqualTo: widget.movie.id)
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, i) {
            var doc = snapshot.data!.docs[i];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: Colors.redAccent,
                child: Text(
                  doc['userName'][0],
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              title: Text(
                doc['userName'],
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              subtitle: Text(
                doc['text'],
                style: const TextStyle(color: Colors.white70),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    // Trả lại định dạng màn hình đứng khi thoát
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    _commentController.dispose();
    super.dispose();
  }
}
