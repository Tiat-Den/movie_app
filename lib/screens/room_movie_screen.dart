import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:movie_app/models/movie_model.dart';
import 'package:movie_app/services/api_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/room_model.dart';

class RoomMovieScreen extends StatefulWidget {
  final String roomId;
  const RoomMovieScreen({super.key, required this.roomId});

  @override
  State<RoomMovieScreen> createState() => _RoomMovieScreenState();
}

class _RoomMovieScreenState extends State<RoomMovieScreen> {
  // --- Controllers ---
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ApiService _api = ApiService();

  // --- Firebase & Auth ---
  final String _currentUid = FirebaseAuth.instance.currentUser!.uid;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _roomName = "";

  // --- Agora (Voice/Video) ---
  late RtcEngine _engine;
  bool _isMicOn = false;
  bool _isCamOn = false;
  final List<int> _remoteUsers = [];

  // --- Logic Sync ---
  StreamSubscription? _roomSubscription;
  bool _isHost = false;
  bool _isInitialized = false;
  String _currentVideoUrl = "";

  // --- Episode state (phim bộ) ---
  List<dynamic> _episodes = [];
  bool _loadingEpisodes = false;
  int _currentEpisodeIndex = 0;
  int _lastEpisodeMovieId = -1;
  String? _episodeTotalFromApi;

  // --- Guard flags ---
  bool _isRoomActive = true;
  int _lastSyncMs = 0;

  @override
  void initState() {
    super.initState();
    _initAgora();
    _listenToRoomChanges();
  }

  // 1. Khởi tạo Agora
  Future<void> _initAgora() async {
    await [Permission.microphone, Permission.camera].request();
    _engine = createAgoraRtcEngine();
    await _engine.initialize(
      const RtcEngineContext(appId: "e8c6c5381eeb45b58cf8119a94115e68"),
    );

    _engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          final uid = connection.localUid ?? 0;
          final user = FirebaseAuth.instance.currentUser;
          _firestore
              .collection('rooms')
              .doc(widget.roomId)
              .collection('members')
              .doc(uid.toString())
              .set({
                'agoraUid': uid,
                'firebaseUid': _currentUid,
                'name': user?.displayName ?? user?.email ?? 'User',
                'joinedAt': FieldValue.serverTimestamp(),
              });
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          debugPrint("-----> Thấy người mới vào: $remoteUid");
          if (!_remoteUsers.contains(remoteUid)) {
            setState(() {
              _remoteUsers.add(remoteUid);
            });
          }
        },
        onUserOffline:
            (
              RtcConnection connection,
              int remoteUid,
              UserOfflineReasonType reason,
            ) {
              debugPrint("-----> Người kia đã thoát: $remoteUid");
              setState(() {
                _remoteUsers.remove(remoteUid);
              });
              // Đừng xóa members trên firestore
            },
      ),
    );

    await _engine.enableVideo();
    await _engine.muteLocalAudioStream(true);
    await _engine.enableLocalVideo(false);

    await _engine.joinChannel(
      token: "",
      channelId: widget.roomId,
      uid: 0,
      options: const ChannelMediaOptions(
        clientRoleType:
            ClientRoleType.clientRoleBroadcaster, // Bắt buộc dòng này
        publishCameraTrack: true,
        publishMicrophoneTrack: true,
      ),
    );
  }

  void _toggleMic() async {
    setState(() => _isMicOn = !_isMicOn);
    await _engine.muteLocalAudioStream(!_isMicOn);
  }

  void _toggleCam() async {
    setState(() => _isCamOn = !_isCamOn);
    await _engine.enableLocalVideo(_isCamOn);
    if (_isCamOn) {
      await _engine.startPreview();
    } else {
      await _engine.stopPreview();
    }
  }

  // 2. Lắng nghe thay đổi từ Firestore
  void _listenToRoomChanges() {
    _roomSubscription = _firestore
        .collection('rooms')
        .doc(widget.roomId)
        .snapshots()
        .listen((snapshot) {
          if (!snapshot.exists) {
            if (!_isHost && mounted) Navigator.of(context).pop();
            return;
          }
          final room = Room.fromFirestore(snapshot);

          if (!_isInitialized) {
            setState(() {
              _roomName = room.roomName;
              _isHost = room.hostId == _currentUid;
              _isInitialized = true;
              _currentVideoUrl = room.videoUrl;
            });
            _initVideo(room.videoUrl);
          }

          if (room.videoUrl != _currentVideoUrl && room.videoUrl.isNotEmpty) {
            _currentVideoUrl = room.videoUrl;
            _initVideo(room.videoUrl);
          }

          final data = snapshot.data() as Map<String, dynamic>;
          final isTv = data['movieIsTv'] as bool? ?? false;
          final movieId = data['currentMovieId'] as int? ?? 0;
          final episodeIdx = data['currentEpisodeIndex'] as int? ?? 0;

          if (!_isHost && episodeIdx != _currentEpisodeIndex) {
            setState(() => _currentEpisodeIndex = episodeIdx);
          }

          if (isTv && movieId != _lastEpisodeMovieId && movieId > 0) {
            _lastEpisodeMovieId = movieId;
            _loadEpisodes(
              movieId,
              data['movieTitle'] as String? ?? '',
              episodeIdx,
            );
          } else if (!isTv && _episodes.isNotEmpty) {
            setState(() {
              _episodes = [];
              _currentEpisodeIndex = 0;
            });
          }

          if (!_isHost &&
              _videoController != null &&
              _videoController!.value.isInitialized) {
            _syncVideoWithFirebase(room);
          }
        });
  }

  // 3. Khởi tạo Video
  void _initVideo(String url) async {
    if (url.isEmpty) return;
    await _videoController?.dispose();
    _videoController = VideoPlayerController.networkUrl(Uri.parse(url));
    await _videoController!.initialize();
    setState(() {
      _chewieController = ChewieController(
        videoPlayerController: _videoController!,
        autoPlay: true,
        aspectRatio: 16 / 9,
        showControls: _isHost,
        allowMuting: true,
      );
    });
    if (_isHost) _videoController!.addListener(_hostVideoListener);
  }

  void _hostVideoListener() {
    if (!_isHost || !_isRoomActive) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSyncMs < 1000) return;
    _lastSyncMs = now;

    _firestore
        .collection('rooms')
        .doc(widget.roomId)
        .update({
          'isPlaying': _videoController!.value.isPlaying,
          'currentPosition': _videoController!.value.position.inMilliseconds,
        })
        .catchError((e) {
          _isRoomActive = false;
          _videoController?.removeListener(_hostVideoListener);
        });
  }

  void _syncVideoWithFirebase(Room room) {
    if (room.isPlaying && !_videoController!.value.isPlaying) {
      _videoController!.play();
    } else if (!room.isPlaying && _videoController!.value.isPlaying) {
      _videoController!.pause();
    }
    int diff =
        (room.currentPosition - _videoController!.value.position.inMilliseconds)
            .abs();
    if (diff > 3000) {
      _videoController!.seekTo(Duration(milliseconds: room.currentPosition));
    }
  }

  // ─── EPISODE METHODS ──────────────────────────────────────────────────────

  Future<void> _loadEpisodes(
    int movieId,
    String title,
    int initialIndex,
  ) async {
    if (!mounted) return;
    setState(() {
      _loadingEpisodes = true;
      _episodes = [];
    });
    try {
      final cleanTitle = title.split(':').first.trim();
      final res = await http.get(
        Uri.parse(
          'https://phimapi.com/v1/api/tim-kiem?keyword=${Uri.encodeComponent(cleanTitle)}&limit=1',
        ),
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final items = data['data']?['items'];
        if (items != null && items.isNotEmpty) {
          final detailRes = await http.get(
            Uri.parse('https://phimapi.com/phim/${items[0]['slug']}'),
          );
          if (detailRes.statusCode == 200) {
            final detailData = json.decode(detailRes.body);
            final eps = detailData['episodes'][0]['server_data'] ?? [];
            final epTotal = detailData['movie']?['episode_total']?.toString();
            if (mounted) {
              setState(() {
                _episodeTotalFromApi = epTotal;
                _episodes = eps;
                _currentEpisodeIndex = initialIndex;
                _loadingEpisodes = false;
              });
              return;
            }
          }
        }
      }
      if (mounted) setState(() => _loadingEpisodes = false);
    } catch (e) {
      debugPrint('_loadEpisodes error: $e');
      if (mounted) setState(() => _loadingEpisodes = false);
    }
  }

  Future<void> _changeEpisode(int index) async {
    if (!_isHost || index == _currentEpisodeIndex) return;
    if (index >= _episodes.length) return;

    final ep = _episodes[index];
    String? newUrl;

    if (ep['link_m3u8'] != null && ep['link_m3u8'].toString().isNotEmpty) {
      newUrl = ep['link_m3u8'].toString();
    } else if (ep['server_data'] != null &&
        (ep['server_data'] as List).isNotEmpty) {
      newUrl = ep['server_data'][0]['link_m3u8'].toString();
    }

    if (newUrl == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Tập này chưa có link!')));
      }
      return;
    }

    setState(() => _currentEpisodeIndex = index);

    await _firestore.collection('rooms').doc(widget.roomId).update({
      'videoUrl': newUrl,
      'currentEpisodeIndex': index,
      'currentPosition': 0,
      'isPlaying': true,
    });
  }

  // 4. Gửi tin nhắn
  void _sendMessage() {
    if (_chatController.text.trim().isEmpty) return;
    _firestore
        .collection('rooms')
        .doc(widget.roomId)
        .collection('messages')
        .add({
          'senderId': _currentUid,
          'senderName':
              FirebaseAuth.instance.currentUser?.displayName ?? "User",
          'text': _chatController.text.trim(),
          'sentAt': FieldValue.serverTimestamp(),
        });
    _chatController.clear();
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _leaveRoom();
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF15141F),
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
            onPressed: () => _leaveRoom(),
          ),
          title: Text(
            _roomName.isEmpty ? "Đang tải..." : _roomName,
            style: const TextStyle(color: Colors.white),
          ),
          centerTitle: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.share, color: Colors.blueAccent),
              onPressed: () =>
                  Share.share("Cùng xem phim nhé! Mã phòng: ${widget.roomId}"),
            ),
            if (_isHost)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Chip(
                  label: Text("HOST"),
                  backgroundColor: Colors.redAccent,
                ),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverToBoxAdapter(
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: _chewieController != null
                            ? Chewie(controller: _chewieController!)
                            : const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.red,
                                ),
                              ),
                      ),
                    ),
                    SliverToBoxAdapter(child: _buildMovieTitleHeader()),
                    if (_episodes.isNotEmpty || _loadingEpisodes)
                      SliverToBoxAdapter(child: _buildEpisodeSection()),
                    SliverToBoxAdapter(child: _buildPlaylistBar()),
                    const SliverToBoxAdapter(
                      child: Divider(color: Colors.white12, height: 1),
                    ),
                    SliverToBoxAdapter(child: _buildParticipantAndControls()),
                    const SliverToBoxAdapter(
                      child: Divider(color: Colors.white12, height: 1),
                    ),
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          "Tin nhắn",
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    _buildChatMessages(),
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  ],
                ),
              ),
              _buildInputArea(),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  WIDGETS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildMovieTitleHeader() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('rooms').doc(widget.roomId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists)
          return const SizedBox();
        final data = snapshot.data!.data() as Map<String, dynamic>;
        final title = data['movieTitle'] as String? ?? 'Đang tải...';
        final isTv = data['movieIsTv'] as bool? ?? false;
        final totalEpisodes = data['movieTotalEpisodes'] as int?;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (isTv) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.blueAccent.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.tv, color: Colors.blueAccent, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        _loadingEpisodes
                            ? 'Đang tải số tập...'
                            : 'Số tập: ${_episodes.length} / ${_episodeTotalFromApi ?? totalEpisodes ?? '?'} tập',
                        style: const TextStyle(
                          color: Colors.blueAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildEpisodeSection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Row(
            children: [
              const Text(
                'Danh sách tập',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              if (_loadingEpisodes) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: Colors.white38,
                  ),
                ),
              ],
              if (!_isHost && _episodes.isNotEmpty) ...[
                const SizedBox(width: 6),
                const Text(
                  '(chỉ host đổi tập)',
                  style: TextStyle(color: Colors.white24, fontSize: 10),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (_loadingEpisodes)
            const SizedBox(
              height: 40,
              child: Center(
                child: Text(
                  'Đang tải danh sách tập...',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            )
          else
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _episodes.length,
                itemBuilder: (context, index) {
                  final isSelected = index == _currentEpisodeIndex;
                  final epName = _episodes[index]['filename']?.toString() ?? '';
                  final label = epName.isNotEmpty
                      ? epName.replaceAll(RegExp(r'[^0-9]'), '')
                      : '${index + 1}';
                  final displayLabel = label.isEmpty || label.length > 3
                      ? '${index + 1}'
                      : label;

                  return GestureDetector(
                    onTap: _isHost ? () => _changeEpisode(index) : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 46,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.redAccent
                            : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? Colors.red : Colors.white12,
                          width: isSelected ? 1.5 : 1,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: Colors.red.withValues(alpha: 0.35),
                                  blurRadius: 6,
                                ),
                              ]
                            : [],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        displayLabel,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white60,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildParticipantAndControls() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('rooms')
          .doc(widget.roomId)
          .collection('members')
          .snapshots(),

      builder: (context, snap) {
        final Map<int, String> nameMap = {};
        if (snap.hasData) {
          for (final doc in snap.data!.docs) {
            final u = doc.data() as Map<String, dynamic>;
            final aId = u['agoraUid'] as int? ?? 0;
            final name = u['name'] as String? ?? 'User';
            nameMap[aId] = name;
          }
        }

        final myName =
            FirebaseAuth.instance.currentUser?.displayName ??
            FirebaseAuth.instance.currentUser?.email ??
            'Tôi';

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 120,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _buildUserBox(0, myName, isMe: true),
                    ..._remoteUsers.map((remoteUid) {
                      String remoteName =
                          nameMap[remoteUid] ?? "Người dùng $remoteUid";
                      return _buildUserBox(remoteUid, remoteName, isMe: false);
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _controlButton(
                    _isMicOn ? Icons.mic : Icons.mic_off,
                    _isMicOn,
                    _toggleMic,
                    label: _isMicOn ? 'Tắt Mic' : 'Bật Mic',
                  ),
                  const SizedBox(width: 12),
                  _controlButton(
                    _isCamOn ? Icons.videocam : Icons.videocam_off,
                    _isCamOn,
                    _toggleCam,
                    label: _isCamOn ? 'Tắt Cam' : 'Bật Cam',
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _controlButton(
    IconData icon,
    bool isOn,
    VoidCallback onTap, {
    required String label,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: isOn
              ? LinearGradient(
                  colors: [
                    Colors.redAccent.withValues(alpha: 0.7),
                    Colors.red.shade900.withValues(alpha: 0.5),
                  ],
                )
              : null,
          color: isOn ? null : Colors.white10,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isOn ? Colors.redAccent : Colors.white24,
            width: 1.5,
          ),
          boxShadow: isOn
              ? [
                  BoxShadow(
                    color: Colors.redAccent.withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isOn ? Colors.white : Colors.white54, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isOn ? Colors.white : Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserBox(int agoraUid, String name, {bool isMe = false}) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: const Color(0xFF211F30),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isMe ? Colors.redAccent : Colors.white24,
                width: isMe ? 2.5 : 1,
              ),
              boxShadow: isMe
                  ? [
                      BoxShadow(
                        color: Colors.redAccent.withValues(alpha: 0.25),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ]
                  : [],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: isMe
                  ? (_isCamOn
                        ? AgoraVideoView(
                            controller: VideoViewController(
                              rtcEngine: _engine,
                              canvas: const VideoCanvas(uid: 0),
                            ),
                          )
                        : _buildPlaceholder(isMe))
                  : AgoraVideoView(
                      // ĐỐI VỚI NGƯỜI KIA
                      controller: VideoViewController.remote(
                        rtcEngine: _engine,
                        canvas: VideoCanvas(
                          uid: agoraUid,
                        ), // Dùng trực tiếp agoraUid kiểu int
                        connection: RtcConnection(channelId: widget.roomId),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            style: TextStyle(
              color: isMe ? Colors.redAccent : Colors.white70,
              fontSize: 11,
              fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(bool isMe) {
    return Center(
      child: Icon(
        Icons.person,
        color: isMe ? Colors.redAccent.withOpacity(0.6) : Colors.white24,
        size: 42,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  PLAYLIST BAR + ADD MOVIE SHEET
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildPlaylistBar() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('rooms')
          .doc(widget.roomId)
          .collection('playlist')
          .orderBy('order')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        final docs = snapshot.data!.docs;
        return Container(
          color: const Color(0xFF1A1828),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  "Danh sách phim",
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: docs.length + 1,
                  itemBuilder: (context, index) {
                    if (index == docs.length) {
                      return GestureDetector(
                        onTap: _showAddMovieSheet,
                        child: Container(
                          width: 62,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.white24,
                              width: 1.5,
                            ),
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.add,
                              color: Colors.white54,
                              size: 28,
                            ),
                          ),
                        ),
                      );
                    }

                    final movieDoc = docs[index];
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        GestureDetector(
                          onTap: () async {
                            if (_isHost) {
                              final isTv = movieDoc['is_tv'] as bool? ?? false;
                              int? totalEps =
                                  movieDoc['total_episodes'] as int?;
                              if (isTv && totalEps == null) {
                                totalEps = await _api.getTvEpisodeCount(
                                  movieDoc['id'] as int,
                                );
                                if (totalEps != null) {
                                  _firestore
                                      .collection('rooms')
                                      .doc(widget.roomId)
                                      .collection('playlist')
                                      .doc(movieDoc.id)
                                      .update({'total_episodes': totalEps});
                                }
                              }
                              String? newUrl = await _api.getMovieStreamLink(
                                movieDoc['id'],
                                movieDoc['title'],
                                movieDoc['original_title'] ?? "",
                                isTv: isTv,
                              );
                              if (newUrl != null) {
                                _firestore
                                    .collection('rooms')
                                    .doc(widget.roomId)
                                    .update({
                                      'videoUrl': newUrl,
                                      'movieTitle': movieDoc['title'],
                                      'movieIsTv': isTv,
                                      'movieTotalEpisodes': totalEps,
                                      'currentMovieId': movieDoc['id'],
                                      'currentEpisodeIndex': 0,
                                      'currentPosition': 0,
                                      'isPlaying': true,
                                    });
                              }
                            }
                          },
                          child: Container(
                            width: 62,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white10),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(
                                movieDoc['poster_path'],
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                        if (_isHost)
                          Positioned(
                            top: -6,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => _firestore
                                  .collection('rooms')
                                  .doc(widget.roomId)
                                  .collection('playlist')
                                  .doc(movieDoc.id)
                                  .delete(),
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 13,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── BOTTOM SHEET THÊM PHIM — CÓ TÌM KIẾM ONLINE THẬT ───────────────────
  void _showAddMovieSheet() {
    final List<Map<String, String>> movieCategories = [
      {'label': 'Hot', 'type': 'popular'},
      {'label': 'Mới', 'type': 'now_playing'},
      {'label': 'Hay', 'type': 'top_rated'},
      {'label': 'Hành Động', 'type': 'action'},
      {'label': 'Hài', 'type': 'comedy'},
      {'label': 'Kinh Dị', 'type': 'horror'},
      {'label': 'Viễn Tưởng', 'type': 'scifi'},
    ];

    final List<Map<String, String>> tvCategories = [
      {'label': 'Phổ Biến', 'type': 'tv_popular'},
      {'label': 'Đánh Giá Cao', 'type': 'tv_top_rated'},
      {'label': 'Chiếu Hôm Nay', 'type': 'tv_airing_today'},
      {'label': 'Hoạt Hình', 'type': 'tv_animation'},
    ];

    final searchCtrl = TextEditingController();
    List<Movie> allMovies = [];
    List<int> addedIds = [];
    bool loading = true;
    bool isSearching = false;
    bool isTvMode = false;
    int selectedCat = 0;
    int currentPage = 1;
    bool sheetInitialized = false;
    Timer? debounce;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF15141F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          List<Map<String, String>> categories = isTvMode
              ? tvCategories
              : movieCategories;

          Future<void> loadMovies({bool resetPage = false}) async {
            if (resetPage) currentPage = 1;
            setSheet(() => loading = true);
            try {
              final res = await _api.getMovies(
                categories[selectedCat]['type']!,
                page: currentPage,
              );
              setSheet(() {
                allMovies = res;
                loading = false;
              });
            } catch (_) {
              setSheet(() => loading = false);
            }
          }

          void onSearchChanged(String query) {
            if (debounce?.isActive ?? false) debounce!.cancel();
            debounce = Timer(const Duration(milliseconds: 600), () async {
              final q = query.trim();
              if (q.isEmpty) {
                setSheet(() => isSearching = false);
                loadMovies(resetPage: true);
                return;
              }
              setSheet(() {
                loading = true;
                isSearching = true;
              });
              try {
                final results = await _api.searchMovies(q);
                setSheet(() {
                  allMovies = results;
                  loading = false;
                });
              } catch (_) {
                setSheet(() => loading = false);
              }
            });
          }

          Future<void> addMovie(Movie movie) async {
            if (addedIds.contains(movie.id)) return;
            setSheet(() => addedIds.add(movie.id));

            int? episodeCount = movie.totalEpisodes;
            if (movie.isTv && episodeCount == null) {
              episodeCount = await _api.getTvEpisodeCount(movie.id);
            }

            final snap = await _firestore
                .collection('rooms')
                .doc(widget.roomId)
                .collection('playlist')
                .get();
            await _firestore
                .collection('rooms')
                .doc(widget.roomId)
                .collection('playlist')
                .doc(movie.id.toString())
                .set({
                  ...movie.toJson(),
                  'total_episodes': episodeCount,
                  'order': snap.docs.length,
                  'addedAt': FieldValue.serverTimestamp(),
                });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Đã thêm "${movie.title}"!'),
                  backgroundColor: Colors.green.shade700,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          }

          if (!sheetInitialized) {
            sheetInitialized = true;
            WidgetsBinding.instance.addPostFrameCallback((_) => loadMovies());
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.92,
            maxChildSize: 0.97,
            minChildSize: 0.5,
            builder: (_, scrollCtrl) => Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Chọn Phim Thêm Vào Phòng',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF211F30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (isTvMode) {
                                setSheet(() {
                                  isTvMode = false;
                                  selectedCat = 0;
                                  currentPage = 1;
                                  isSearching = false;
                                  searchCtrl.clear();
                                });
                                WidgetsBinding.instance.addPostFrameCallback(
                                  (_) => loadMovies(),
                                );
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: !isTvMode
                                    ? Colors.redAccent
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.movie,
                                    color: !isTvMode
                                        ? Colors.white
                                        : Colors.white38,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Phim Lẻ',
                                    style: TextStyle(
                                      color: !isTvMode
                                          ? Colors.white
                                          : Colors.white38,
                                      fontWeight: !isTvMode
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (!isTvMode) {
                                setSheet(() {
                                  isTvMode = true;
                                  selectedCat = 0;
                                  currentPage = 1;
                                  isSearching = false;
                                  searchCtrl.clear();
                                });
                                WidgetsBinding.instance.addPostFrameCallback(
                                  (_) => loadMovies(),
                                );
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: isTvMode
                                    ? Colors.redAccent
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.tv,
                                    color: isTvMode
                                        ? Colors.white
                                        : Colors.white38,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Phim Bộ',
                                    style: TextStyle(
                                      color: isTvMode
                                          ? Colors.white
                                          : Colors.white38,
                                      fontWeight: isTvMode
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF211F30),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: TextField(
                      controller: searchCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Tìm kiếm phim toàn cầu...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.redAccent,
                        ),
                        suffixIcon: isSearching
                            ? IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.white38,
                                  size: 18,
                                ),
                                onPressed: () {
                                  searchCtrl.clear();
                                  onSearchChanged('');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                      ),
                      onChanged: onSearchChanged,
                    ),
                  ),
                ),
                if (!isSearching) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 38,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: categories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final sel = i == selectedCat;
                        return GestureDetector(
                          onTap: () {
                            if (selectedCat != i) {
                              setSheet(() {
                                selectedCat = i;
                                currentPage = 1;
                              });
                              loadMovies();
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: sel
                                  ? Colors.redAccent
                                  : const Color(0xFF211F30),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: sel ? Colors.redAccent : Colors.white12,
                              ),
                            ),
                            child: Text(
                              categories[i]['label']!,
                              style: TextStyle(
                                color: sel ? Colors.white : Colors.white60,
                                fontWeight: sel
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ] else
                  const SizedBox(height: 10),
                Expanded(
                  child: loading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Colors.redAccent,
                          ),
                        )
                      : allMovies.isEmpty
                      ? Center(
                          child: Text(
                            isSearching
                                ? 'Không tìm thấy phim nào'
                                : 'Không có phim',
                            style: const TextStyle(color: Colors.white54),
                          ),
                        )
                      : GridView.builder(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                childAspectRatio: 0.62,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                              ),
                          itemCount: allMovies.length,
                          itemBuilder: (_, i) {
                            final movie = allMovies[i];
                            final added = addedIds.contains(movie.id);
                            return GestureDetector(
                              onTap: () => addMovie(movie),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: added
                                        ? Colors.greenAccent
                                        : Colors.transparent,
                                    width: 2.5,
                                  ),
                                  boxShadow: added
                                      ? [
                                          BoxShadow(
                                            color: Colors.greenAccent
                                                .withValues(alpha: 0.35),
                                            blurRadius: 10,
                                          ),
                                        ]
                                      : [],
                                ),
                                child: Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        movie.posterPath,
                                        width: double.infinity,
                                        height: double.infinity,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    if (movie.isTv)
                                      Positioned(
                                        top: 6,
                                        left: 6,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.blueAccent.withValues(
                                              alpha: 0.85,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: const Text(
                                            'Bộ',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    Positioned(
                                      bottom: 0,
                                      left: 0,
                                      right: 0,
                                      child: Container(
                                        padding: const EdgeInsets.fromLTRB(
                                          6,
                                          20,
                                          6,
                                          6,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                bottom: Radius.circular(8),
                                              ),
                                          gradient: LinearGradient(
                                            begin: Alignment.bottomCenter,
                                            end: Alignment.topCenter,
                                            colors: [
                                              Colors.black.withValues(
                                                alpha: 0.85,
                                              ),
                                              Colors.transparent,
                                            ],
                                          ),
                                        ),
                                        child: Text(
                                          movie.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (added)
                                      Positioned(
                                        top: 6,
                                        right: 6,
                                        child: Container(
                                          padding: const EdgeInsets.all(3),
                                          decoration: const BoxDecoration(
                                            color: Colors.greenAccent,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.check,
                                            size: 14,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                if (!isSearching)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    color: const Color(0xFF211F30),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: currentPage > 1
                              ? () {
                                  setSheet(() => currentPage--);
                                  loadMovies();
                                }
                              : null,
                          icon: const Icon(Icons.arrow_back_ios),
                          color: currentPage > 1
                              ? Colors.white
                              : Colors.white24,
                          iconSize: 18,
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Trang $currentPage',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          onPressed: () {
                            setSheet(() => currentPage++);
                            loadMovies();
                          },
                          icon: const Icon(
                            Icons.arrow_forward_ios,
                            color: Colors.white,
                          ),
                          iconSize: 18,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() => debounce?.cancel());
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  CHAT
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildChatMessages() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('rooms')
          .doc(widget.roomId)
          .collection('messages')
          .orderBy('sentAt', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  "Chưa có tin nhắn nào",
                  style: TextStyle(color: Colors.white24, fontSize: 13),
                ),
              ),
            ),
          );
        }

        final docs = snapshot.data!.docs;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });

        return SliverList(
          delegate: SliverChildBuilderDelegate((context, i) {
            final doc = docs[i];
            final bool isMe = doc['senderId'] == _currentUid;
            return Align(
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isMe ? Colors.redAccent : Colors.white10,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  crossAxisAlignment: isMe
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    if (!isMe)
                      Text(
                        doc['senderName'] ?? "",
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                        ),
                      ),
                    Text(
                      doc['text'] ?? "",
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            );
          }, childCount: docs.length),
        );
      },
    );
  }

  Widget _buildInputArea() {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(10, 10, 10, 10 + bottomPadding),
      color: const Color(0xFF211F30),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _chatController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: "Nhắn tin...",
                hintStyle: TextStyle(color: Colors.white38),
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          IconButton(
            onPressed: _sendMessage,
            icon: const Icon(Icons.send, color: Colors.redAccent),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  LEAVE / DELETE ROOM
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _leaveRoom() async {
    if (_isHost) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1828),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Rời phòng?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'Bạn là chủ phòng. Khi rời đi, phòng sẽ bị xóa và tất cả mọi người sẽ bị đẩy ra ngoài.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Xóa phòng & Rời',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      _roomSubscription?.cancel();
      _roomSubscription = null;

      await _deleteRoom();
    } else {
      _roomSubscription?.cancel();
      _roomSubscription = null;
    }

    try {
      await _engine.stopPreview();
      await _engine.leaveChannel();
      await _engine.release();
      debugPrint("Agora đã được dọn dẹp sạch sẽ!");
    } catch (e) {
      debugPrint("Lỗi dọn dẹp Agora: $e");
    }

    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _deleteRoom() async {
    _isRoomActive = false;
    _videoController?.removeListener(_hostVideoListener);
    _videoController?.pause();
    _videoController?.dispose();

    final roomRef = _firestore.collection('rooms').doc(widget.roomId);
    final batch = _firestore.batch();

    try {
      final subs = ['playlist', 'messages', 'members'];
      for (final sub in subs) {
        final snap = await roomRef.collection(sub).get();
        for (final doc in snap.docs) {
          batch.delete(doc.reference);
        }
      }
      batch.delete(roomRef);
      await batch.commit();
      debugPrint("✅ Đã xóa toàn bộ dữ liệu phòng: ${widget.roomId}");
    } catch (e) {
      debugPrint("❌ Lỗi khi xóa phòng: $e");
    }
  }

  @override
  void dispose() {
    _isRoomActive = false;
    _videoController?.removeListener(_hostVideoListener);
    _roomSubscription?.cancel();
    _videoController?.dispose();
    _chewieController?.dispose();
    _chatController.dispose();
    _scrollController.dispose();
    _engine.stopPreview();
    _engine.leaveChannel();
    _engine.release();
    super.dispose();
  }
}
