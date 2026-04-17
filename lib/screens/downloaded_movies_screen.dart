import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'watch_movie_screen.dart';
import '../models/movie_model.dart';

class DownloadedMoviesScreen extends StatefulWidget {
  const DownloadedMoviesScreen({super.key});

  @override
  State<DownloadedMoviesScreen> createState() => _DownloadedMoviesScreenState();
}

class _DownloadedMoviesScreenState extends State<DownloadedMoviesScreen> {
  List<FileSystemEntity> _downloadedFiles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDownloadedMovies();
  }

  // HÀM QUÉT THƯ MỤC LẤY DANH SÁCH FILE VIDEO
  Future<void> _loadDownloadedMovies() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final directory = Directory(dir.path);

      debugPrint("📁 Đang quét thư mục lưu trữ: ${directory.path}");

      if (!directory.existsSync()) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Lấy danh sách toàn bộ file trong thư mục app_flutter
      final List<FileSystemEntity> entities = directory.listSync();

      if (mounted) {
        setState(() {
          _downloadedFiles = entities.where((file) {
            // Chỉ lấy những file là video thực thụ (đuôi .mp4 hoặc .m3u8)
            // Loại bỏ các thư mục tạm (temp_) hoặc file text (list.txt)
            String path = file.path.toLowerCase();
            return (path.endsWith('.mp4') || path.endsWith('.m3u8')) &&
                !path.contains('temp_') &&
                !path.contains('list.txt');
          }).toList();

          // Sắp xếp phim mới tải lên đầu
          _downloadedFiles.sort(
            (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
          );

          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Lỗi khi quét danh sách phim: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // HÀM XÓA PHIM
  void _deleteMovie(FileSystemEntity file) {
    try {
      if (file.existsSync()) {
        file.deleteSync();
        _loadDownloadedMovies(); // Cập nhật lại danh sách ngay lập tức
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Đã xóa bản tải xuống khỏi máy"),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Không thể xóa file: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF15141F),
      appBar: AppBar(
        title: const Text(
          "Phim đã tải",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.red))
          : _downloadedFiles.isEmpty
          ? _buildEmptyState()
          : _buildFileList(),
    );
  }

  // Giao diện khi danh sách trống
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.video_library_outlined,
            size: 100,
            color: Colors.grey[800],
          ),
          const SizedBox(height: 20),
          const Text(
            "Bạn chưa tải bộ phim nào",
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
          const SizedBox(height: 10),
          Text(
            "Phim đã tải xong sẽ xuất hiện tại đây",
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
        ],
      ),
    );
  }

  // Danh sách phim
  Widget _buildFileList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemCount: _downloadedFiles.length,
      itemBuilder: (context, index) {
        final file = _downloadedFiles[index];
        // Tách lấy tên file và xóa đuôi mở rộng để hiển thị tiêu đề đẹp
        final fileNameWithExt = file.path.split('/').last;
        final fileName = fileNameWithExt
            .replaceAll(RegExp(r'\.mp4|\.m3u8'), '')
            .replaceAll('_', ' ');

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF211F30),
            borderRadius: BorderRadius.circular(15),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 10,
            ),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.play_circle_fill,
                color: Colors.redAccent,
                size: 30,
              ),
            ),
            title: Text(
              fileName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                "Dung lượng: ${(file.statSync().size / (1024 * 1024)).toStringAsFixed(1)} MB",
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: Colors.grey),
              onPressed: () => _confirmDelete(context, fileName, file),
            ),
            onTap: () {
              // CHUYỂN TRANG XEM PHIM (OFFLINE MODE)
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => WatchMovieScreen(
                    movie: Movie(
                      isTv: false,
                      id: 0,
                      title: fileName,
                      totalEpisodes: 0,
                      overview:
                          "Bạn đang xem phim ở chế độ ngoại tuyến. Một số tính năng như bình luận sẽ bị tạm khóa.",
                      posterPath: "",
                      voteAverage: 0,
                      originalTitle: fileName,
                      releaseDate: "Ngoại tuyến",
                    ),
                    videoUrl: file.path,
                    isOffline: true,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // Hộp thoại xác nhận xóa
  void _confirmDelete(
    BuildContext context,
    String title,
    FileSystemEntity file,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF211F30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text(
          "Xóa bản tải xuống?",
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          "Bạn có chắc muốn xóa phim '$title'? Hành động này không thể hoàn tác.",
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Để sau", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(context);
              _deleteMovie(file);
            },
            child: const Text(
              "Xóa ngay",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
