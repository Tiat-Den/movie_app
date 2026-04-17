import 'package:cloud_firestore/cloud_firestore.dart';

class Room {
  final String id;
  final String hostId;
  final String roomName;
  final String movieTitle;
  final String videoUrl;
  final bool isPlaying;
  final int currentMovieIndex;
  final int currentPosition;
  final DateTime? createAt;

  Room({
    required this.id,
    required this.hostId,
    required this.roomName,
    required this.movieTitle,
    required this.videoUrl,
    required this.isPlaying,
    required this.currentMovieIndex,
    required this.currentPosition,
    this.createAt,
  });

  factory Room.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    return Room(
      id: doc.id,
      hostId: data['hostId'] ?? '',
      roomName: data['roomName'] ?? '',
      movieTitle: data['movieTitle'] ?? '',
      videoUrl: data['videoUrl'] ?? '',
      isPlaying: data['isPlaying'] ?? false,
      currentPosition: data['currentPosition'] ?? 0,
      currentMovieIndex: data['currentMovieIndex'] ?? 0,
      createAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'hostId': hostId,
      'roomName': roomName,
      'movieTitle': movieTitle,
      'videoUrl': videoUrl,
      'isPlaying': isPlaying,
      'currentPosition': currentPosition,
      'currentMovieIndex': currentMovieIndex,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
