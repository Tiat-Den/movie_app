import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/services.dart';

class WatchMovieScreen extends StatefulWidget {
  final String movieTitle;
  final String videoUrl;

  const WatchMovieScreen({
    super.key,
    required this.movieTitle,
    required this.videoUrl,
  });

  @override
  State<WatchMovieScreen> createState() => _WatchMovieScreenState();
}

class _WatchMovieScreenState extends State<WatchMovieScreen> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  void _initPlayer() async {
    _videoPlayerController = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
    );
    await _videoPlayerController.initialize();

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController,
      autoPlay: true,
      looping: false,
      aspectRatio: 16 / 9,
      allowFullScreen: true,
      showControls: true,
      allowMuting: true,
      allowPlaybackSpeedChanging: true,
      showOptions: true,

      materialProgressColors: ChewieProgressColors(
        playedColor: Colors.red,
        handleColor: Colors.redAccent,
        backgroundColor: Colors.grey.withOpacity(0.5),
        bufferedColor: Colors.white38,
      ),
      errorBuilder: (context, errorMessage) {
        return Center(
          child: Text(
            errorMessage,
            style: const TextStyle(color: Colors.white),
          ),
        );
      },
    );

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.movieTitle,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),

      body: Center(
        child:
            _chewieController != null &&
                _videoPlayerController.value.isInitialized
            ? Chewie(controller: _chewieController!)
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.red),
                  SizedBox(height: 20),
                  Text(
                    "Đang kết nối tới máy chủ phim...",
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
      ),
    );
  }
}
