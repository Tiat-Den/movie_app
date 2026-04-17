import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../models/movie_model.dart';

class ApiService {
  static final String _apiKey = dotenv.env['TMDB_API_KEY'] ?? '';
  final String _baseUrl = 'https://api.themoviedb.org/3';
  static const _kTimeout = Duration(seconds: 10);

  // ─────────────────────────────────────────────────────────────────────────
  // LẤY DANH SÁCH PHIM (TRENDING, CATEGORY, FILTER NÂNG CAO)
  // ─────────────────────────────────────────────────────────────────────────
  Future<List<Movie>> getMovies(String type, {int page = 1}) async {
    String endpoint = '';

    // 1. XỬ LÝ CHUỖI LỌC (CÓ DẤU GẠCH DƯỚI _)
    if (type.contains('_')) {
      final parts = type.split('_');
      final prefix = parts[0]; // movie, tv, trending, now...
      final value = parts[1]; // ID thể loại hoặc day/week/playing...

      // A. LOGIC LỌC ĐA DANH MỤC THỰC SỰ (Ví dụ: movie_28,16 hoặc tv_16)
      // Kiểm tra nếu value là danh sách số (ID) hoặc mã thể loại
      bool isGenreFilter = RegExp(r'^[0-9,]+$').hasMatch(value);

      if (isGenreFilter && (prefix == 'movie' || prefix == 'tv')) {
        endpoint =
            '/discover/$prefix?with_genres=$value&sort_by=popularity.desc';
      }
      // B. XỬ LÝ CÁC CASE ĐẶC BIỆT CỦA TRANG CHỦ MÀ CÓ DẤU "_"
      else if (prefix == 'trending') {
        endpoint = '/trending/all/$value'; // trending_day, trending_week
      } else if (prefix == 'now' && value == 'playing') {
        endpoint = '/movie/now_playing';
      } else if (prefix == 'tv' && value == 'popular') {
        endpoint = '/tv/popular';
      } else if (prefix == 'tv' && value == 'top') {
        endpoint = '/tv/top_rated';
      } else if (prefix == 'tv' && value == 'animation') {
        endpoint = '/discover/tv?with_genres=16';
      } else if (prefix == 'tv' && value == 'airing') {
        endpoint = '/tv/airing_today';
      } else {
        // Dự phòng nếu filter rỗng (ví dụ: movie_all)
        endpoint = prefix == 'tv' ? '/tv/popular' : '/movie/popular';
      }
    }
    // 2. XỬ LÝ CÁC CASE MẶC ĐỊNH (KHÔNG DẤU _)
    else {
      switch (type) {
        case 'popular':
          endpoint = '/movie/popular';
          break;
        case 'now_playing':
          endpoint = '/movie/now_playing';
          break;
        case 'top_rated':
          endpoint = '/movie/top_rated';
          break;
        case 'upcoming':
          endpoint = '/movie/upcoming';
          break;

        // Thể loại phim lẻ lẻ (Shortcuts)
        case 'action':
          endpoint = '/discover/movie?with_genres=28';
          break;
        case 'horror':
          endpoint = '/discover/movie?with_genres=27';
          break;
        case 'scifi':
          endpoint = '/discover/movie?with_genres=878';
          break;
        case 'comedy':
          endpoint = '/discover/movie?with_genres=35';
          break;
        case 'animation':
          endpoint = '/discover/movie?with_genres=16';
          break;
        case 'romance':
          endpoint = '/discover/movie?with_genres=10749';
          break;
        case 'documentary':
          endpoint = '/discover/movie?with_genres=99';
          break;

        default:
          endpoint = '/movie/popular';
      }
    }

    // Tự động xử lý dấu nối tham số (? hoặc &) để URL luôn đúng
    final sep = endpoint.contains('?') ? '&' : '?';
    final url = Uri.parse(
      '$_baseUrl$endpoint${sep}api_key=$_apiKey&language=vi-VN&page=$page',
    );

    try {
      debugPrint("🚀 ApiService Calling: $url");
      final res = await http.get(url).timeout(_kTimeout);

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final List results = data['results'] ?? [];

        // Lọc bỏ rác: chỉ lấy phim có poster và không phải media_type 'person'
        return results
            .where(
              (m) => m['poster_path'] != null && m['media_type'] != 'person',
            )
            .map((m) => Movie.fromJson(m))
            .toList();
      } else {
        debugPrint("❌ Lỗi API TMDB (${res.statusCode}): ${res.body}");
        return [];
      }
    } catch (e) {
      debugPrint("💥 Lỗi kết nối ApiService ($type): $e");
      return [];
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LẤY SỐ TẬP TV
  // ─────────────────────────────────────────────────────────────────────────
  Future<int?> getTvEpisodeCount(int tvId) async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/tv/$tvId?api_key=$_apiKey&language=vi-VN'))
          .timeout(_kTimeout);
      if (res.statusCode == 200) {
        return json.decode(res.body)['number_of_episodes'] as int?;
      }
    } catch (e) {
      debugPrint("getTvEpisodeCount($tvId) error: $e");
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LẤY DANH SÁCH TẬP PHIM (phimapi.com)
  // ─────────────────────────────────────────────────────────────────────────
  Future<List<dynamic>> getEpisodeList(
    int tmdbId,
    String title,
    String original, {
    bool isTv = true,
  }) async {
    try {
      final type = isTv ? 'tv' : 'movie';
      final res = await http
          .get(Uri.parse('https://phimapi.com/tmdb/$type/$tmdbId'))
          .timeout(_kTimeout);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['episodes'] != null && (data['episodes'] as List).isNotEmpty) {
          return data['episodes'][0]['server_data'] ?? [];
        }
      }
    } catch (e) {
      debugPrint("getEpisodeList TMDB ID error: $e");
    }

    // Fallback tìm kiếm theo tên
    final cleanTitle = title.split(':').first.trim();
    final keywords = [
      title,
      original,
      cleanTitle,
    ].where((k) => k.isNotEmpty).toList();

    for (final k in keywords) {
      try {
        final searchRes = await http
            .get(
              Uri.parse(
                'https://phimapi.com/v1/api/tim-kiem?keyword=${Uri.encodeComponent(k)}&limit=1',
              ),
            )
            .timeout(_kTimeout);
        if (searchRes.statusCode != 200) continue;
        final items = json.decode(searchRes.body)['data']?['items'];
        if (items == null || (items as List).isEmpty) continue;
        final detailRes = await http
            .get(Uri.parse('https://phimapi.com/phim/${items[0]['slug']}'))
            .timeout(_kTimeout);
        if (detailRes.statusCode != 200) continue;
        final detailData = json.decode(detailRes.body);
        if (detailData['episodes'] != null &&
            (detailData['episodes'] as List).isNotEmpty) {
          return detailData['episodes'][0]['server_data'] ?? [];
        }
      } catch (e) {
        debugPrint("getEpisodeList fallback error: $e");
      }
    }
    return [];
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LẤY LINK STREAM M3U8
  // ─────────────────────────────────────────────────────────────────────────
  Future<String?> getMovieStreamLink(
    int tmdbId,
    String title,
    String original, {
    bool isTv = false,
    int episodeIndex = 0,
  }) async {
    final episodes = await getEpisodeList(tmdbId, title, original, isTv: isTv);
    if (episodes.isNotEmpty && episodeIndex < episodes.length) {
      final epData = episodes[episodeIndex];
      return epData['link_m3u8']?.toString() ??
          epData['link_embed']?.toString();
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TÌM KIẾM PHIM (MOVIE + TV)
  // ─────────────────────────────────────────────────────────────────────────
  Future<List<Movie>> searchMovies(String query) async {
    final url = Uri.parse(
      '$_baseUrl/search/multi?api_key=$_apiKey&language=vi-VN&query=${Uri.encodeComponent(query)}&page=1',
    );
    try {
      final res = await http.get(url).timeout(_kTimeout);
      if (res.statusCode == 200) {
        final results = json.decode(res.body)['results'] as List;
        return results
            .where(
              (m) =>
                  (m['media_type'] == 'movie' || m['media_type'] == 'tv') &&
                  m['poster_path'] != null,
            )
            .map((m) => Movie.fromJson(m))
            .toList();
      }
    } catch (e) {
      debugPrint("searchMovies error: $e");
    }
    return [];
  }
}
