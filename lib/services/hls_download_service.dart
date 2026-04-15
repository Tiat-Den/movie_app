import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class HlsDownloadService {
  // Tải HLS stream và chuyển thành MP4 dùng FFmpeg native
  // FFmpeg tự xử lý: master playlist → variant playlist → segments → mp4
  Future<void> downloadAndMerge(
    String m3u8Url,
    String movieName,
    Function(double) onProgress,
  ) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final String safeName = movieName
          .replaceAll(RegExp(r'[/\\:*?"<>|]'), '') // chỉ xóa ký tự không hợp lệ trong tên file
          .trim()
          .replaceAll(RegExp(r'\s+'), '_');
      final String outputPath = "${dir.path}/$safeName.mp4";

      // Xóa file cũ nếu tồn tại
      final outputFile = File(outputPath);
      if (outputFile.existsSync()) outputFile.deleteSync();

      onProgress(0.05);

      // FFmpeg tự tải và gộp toàn bộ HLS (bao gồm cả encrypted segments)
      final String command = "-y -i \"$m3u8Url\" -c copy \"$outputPath\"";
      debugPrint("▶ HlsDownloadService FFmpeg: $command");

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        onProgress(1.0);
      } else {
        final logs = await session.getLogs();
        final errMsg = logs.map((l) => l.getMessage()).join('\n');
        throw Exception("Lỗi FFmpeg:\n$errMsg");
      }
    } catch (e) {
      rethrow;
    }
  }
}

