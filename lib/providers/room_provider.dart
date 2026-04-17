import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:movie_app/models/room_model.dart';

class RoomProvider with ChangeNotifier {
  Room? _currentRoom;
  Room? get currentRoom => _currentRoom;

  void joinRoom(String roomId) {
    FirebaseFirestore.instance
        .collection('rooms')
        .doc(roomId)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists) {
            _currentRoom = Room.fromFirestore(snapshot);
            notifyListeners();
          }
        });
  }
}
