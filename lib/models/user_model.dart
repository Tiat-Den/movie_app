class Users {
  final String uid;
  final String email;
  final String userName;
  final String displayName;
  final String photoUrl;

  Users({
    required this.uid,
    required this.email,
    required this.userName,
    required this.displayName,
    required this.photoUrl,
  });

  factory Users.fromMap(Map<String, dynamic> map, String documentId) {
    return Users(
      uid: documentId,
      email: map['email'] ?? '',
      userName: map['userName'] ?? '',
      displayName: map['displayName'] ?? 'Người dùng',
      photoUrl: map['photoUrl'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'last_login': DateTime.now().toIso8601String(),
      'searchKey': userName.toLowerCase(),
    };
  }
}
