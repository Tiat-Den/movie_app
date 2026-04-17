import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:movie_app/models/movie_model.dart';
import 'package:movie_app/models/room_model.dart';
import 'package:movie_app/services/api_service.dart';

class RoomService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ApiService _api = ApiService();

  Future<String?> createRoom({
    required String roomName,
    required String videoUrl,
    required List<Movie> movieList,
  }) async {
    try {
      final String uid = _auth.currentUser?.uid ?? '';
      final DocumentReference ref = _db.collection('rooms').doc();

      final firstMovie = movieList.isNotEmpty ? movieList.first : null;

      // Nếu phim bộ và chưa có totalEpisodes → fetch từ TMDB detail
      int? episodeCount = firstMovie?.totalEpisodes;
      if (firstMovie != null && firstMovie.isTv && episodeCount == null) {
        episodeCount = await _api.getTvEpisodeCount(firstMovie.id);
      }

      final Room newRoom = Room(
        id: ref.id,
        hostId: uid,
        roomName: roomName,
        movieTitle: firstMovie?.title ?? 'Phim chưa đặt tên',
        videoUrl: videoUrl,
        isPlaying: false,
        currentMovieIndex: 0,
        currentPosition: 0,
      );

      // Lưu thông tin phòng chính kèm thêm thông tin phim bộ
      await ref.set({
        ...newRoom.toMap(),
        'movieIsTv': firstMovie?.isTv ?? false,
        'movieTotalEpisodes': episodeCount,
      });

      if (movieList.isNotEmpty) {
        final WriteBatch batch = _db.batch();
        for (int i = 0; i < movieList.length; i++) {
          final movie = movieList[i];
          // Cập nhật episodeCount cho phim đầu tiên
          final eps = (i == 0 && movie.isTv) ? episodeCount : movie.totalEpisodes;
          final movieRef = ref.collection('playlist').doc(movie.id.toString());
          batch.set(movieRef, {
            ...movie.toJson(),
            'total_episodes': eps,
            'order': i,
            'addedAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }

      return ref.id;
    } catch (e) {
      debugPrint('❌ Error creating room: $e');
      return null;
    }
  }
}
