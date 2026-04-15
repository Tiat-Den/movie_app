import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// dio removed – FFmpeg handles HLS download natively
import 'package:path_provider/path_provider.dart';

import '../models/movie_model.dart';

class WatchMovieScreen extends StatefulWidget {
  final Movie movie;
  final String videoUrl;
  final bool isOffline;

  const WatchMovieScreen({
    super.key,
    required this.movie,
    required this.videoUrl,
    required this.isOffline,
  });

  @override
  State<WatchMovieScreen> createState() => _WatchMovieScreenState();
}

class _WatchMovieScreenState extends State<WatchMovieScreen> {
  // --- Video Controllers ---
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;

  // --- Services ---
  final TextEditingController _commentController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _user = FirebaseAuth.instance.currentUser;

  // --- Download & Crawler States ---
  double _downloadProgress = 0;
  bool _isDownloading = false;
  String _downloadStatus = "";

  @override
  void initState() {
    super.initState();
    // Cho phép xoay ngang màn hình
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _initPlayer();
  }

  void _initPlayer() async {
    if (widget.isOffline) {
      _videoPlayerController = VideoPlayerController.file(
        File(widget.videoUrl),
      );
    } else {
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
      );
    }

    try {
      await _videoPlayerController.initialize();
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
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

  // ============================================================
  //  DOWNLOAD HLS → MP4 (dùng FFmpeg native, không tải segment thủ công)
  // ============================================================
  Future<void> _handleSuperDownload() async {
    setState(() {
      _isDownloading = true;
      _downloadStatus = "Đang tải phim...";
      _downloadProgress = 0;
    });

    try {
      final dir = await getApplicationDocumentsDirectory();
      final String safeTitle = widget.movie.title
          .replaceAll(RegExp(r'[/\\:*?"<>|]'), '') // chỉ xóa ký tự không hợp lệ trong tên file
          .trim()
          .replaceAll(RegExp(r'\s+'), '_');
      final String outputPath = "${dir.path}/$safeTitle.mp4";

      // Xóa file cũ nếu tồn tại
      final outputFile = File(outputPath);
      if (outputFile.existsSync()) outputFile.deleteSync();

      // FFmpeg tự xử lý toàn bộ: master playlist → variant → segments → mp4
      // Không cần tải từng segment thủ công
      final String ffmpegCommand =
          "-y -i \"${widget.videoUrl}\" -c copy \"$outputPath\"";

      debugPrint("▶ FFmpeg command: $ffmpegCommand");

      final session = await FFmpegKit.execute(ffmpegCommand);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        setState(() {
          _downloadProgress = 1.0;
          _downloadStatus = "Hoàn tất!";
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Tải phim thành công!"),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        final logs = await session.getLogs();
        final errMsg = logs
            .map((l) => l.getMessage())
            .where((m) => m.toLowerCase().contains('error') || m.toLowerCase().contains('invalid'))
            .join('\n');
        throw Exception("FFmpeg thất bại.\n$errMsg");
      }
    } catch (e) {
      debugPrint("Lỗi Download: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Lỗi: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 0;
        });
      }
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
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    _commentController.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // TRÌNH PHÁT VIDEO
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    color: Colors.black,
                    child:
                        _chewieController != null &&
                            _videoPlayerController.value.isInitialized
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
            ),

            // NỘI DUNG CHI TIẾT
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                            onPressed: _isDownloading
                                ? null
                                : _handleSuperDownload,
                            icon: _isDownloading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.red,
                                    ),
                                  )
                                : const Icon(
                                    Icons.download_for_offline,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                          ),
                      ],
                    ),
                    if (_isDownloading)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          children: [
                            LinearProgressIndicator(
                              value: _downloadProgress,
                              color: Colors.red,
                              backgroundColor: Colors.white10,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _downloadStatus,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    Text(
                      widget.movie.overview.isEmpty
                          ? "Không có mô tả cho phim này."
                          : widget.movie.overview,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 20),
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
              leading: CircleAvatar(child: Text(doc['userName'][0])),
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
}
