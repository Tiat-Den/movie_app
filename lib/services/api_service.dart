import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../models/movie_model.dart';

class ApiService {
  static final String _apiKey = dotenv.env['TMDB_API_KEY'] ?? '';
  final String _baseUrl = 'https://api.themoviedb.org/3';
  static const _kTimeout = Duration(seconds: 8);

  Future<List<Movie>> getMovies(String type, {int page = 1}) async {
    String endpoint = '';
    switch (type) {
      case 'animation': endpoint = '/discover/movie?with_genres=16'; break;
      case 'action':    endpoint = '/discover/movie?with_genres=28'; break;
      case 'comedy':    endpoint = '/discover/movie?with_genres=35'; break;
      case 'horror':    endpoint = '/discover/movie?with_genres=27'; break;
      case 'scifi':     endpoint = '/discover/movie?with_genres=878'; break;
      case 'romance':   endpoint = '/discover/movie?with_genres=10749'; break;
      case 'documentary': endpoint = '/discover/movie?with_genres=99'; break;
      case 'tv_popular':     endpoint = '/tv/popular'; break;
      case 'tv_top_rated':   endpoint = '/tv/top_rated'; break;
      case 'tv_airing_today':endpoint = '/tv/airing_today'; break;
      case 'tv_animation':   endpoint = '/discover/tv?with_genres=16'; break;
      default: endpoint = '/movie/$type';
    }

    final sep = endpoint.contains('?') ? '&' : '?';
    final url = Uri.parse('$_baseUrl$endpoint${sep}api_key=$_apiKey&language=vi-VN&page=$page');
    try {
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return (data['results'] as List).map((m) => Movie.fromJson(m)).toList();
      }
      throw Exception('Lỗi API TMDB: ${res.statusCode}');
    } catch (e) {
      debugPrint("getMovies error: $e");
      return [];
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LẤY SỐ TẬP — cần gọi /tv/{id} riêng vì list API không trả về field này
  // ─────────────────────────────────────────────────────────────────────────
  Future<int?> getTvEpisodeCount(int tvId) async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/tv/$tvId?api_key=$_apiKey&language=vi-VN'))
          .timeout(_kTimeout);
      if (res.statusCode == 200) return json.decode(res.body)['number_of_episodes'] as int?;
    } catch (e) {
      debugPrint("getTvEpisodeCount($tvId) error: $e");
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LẤY DANH SÁCH TẬP từ phimapi.com  →  List<{link_m3u8, filename, ...}>
  // ─────────────────────────────────────────────────────────────────────────
  Future<List<dynamic>> getEpisodeList(
    int tmdbId,
    String title,
    String original, {
    bool isTv = true,
  }) async {
    // 1. Thử trực tiếp qua TMDB ID
    try {
      final type = isTv ? 'tv' : 'movie';
      final res = await http
          .get(Uri.parse('https://phimapi.com/tmdb/$type/$tmdbId'))
          .timeout(_kTimeout);
      if (res.statusCode == 200) {
        final episodes = json.decode(res.body)['episodes'];
        if (episodes != null && (episodes as List).isNotEmpty) {
          final serverData = episodes[0]['server_data'];
          if (serverData != null && (serverData as List).isNotEmpty) return serverData;
        }
      }
    } catch (e) {
      debugPrint("getEpisodeList TMDB ID error: $e");
    }

    // 2. Fallback: tìm theo tên → lấy slug → lấy chi tiết
    final cleanTitle = title.split(':').first.trim();
    final keywords = <String>{title, original, cleanTitle}.where((k) => k.isNotEmpty).toList();

    for (final k in keywords) {
      try {
        final searchRes = await http
            .get(Uri.parse('https://phimapi.com/v1/api/tim-kiem?keyword=${Uri.encodeComponent(k)}&limit=1'))
            .timeout(_kTimeout);
        if (searchRes.statusCode != 200) continue;
        final items = json.decode(searchRes.body)['data']?['items'];
        if (items == null || (items as List).isEmpty) continue;

        final detailRes = await http
            .get(Uri.parse('https://phimapi.com/phim/${items[0]['slug']}'))
            .timeout(_kTimeout);
        if (detailRes.statusCode != 200) continue;
        final eps = json.decode(detailRes.body)['episodes'];
        if (eps != null && (eps as List).isNotEmpty) {
          final serverData = eps[0]['server_data'];
          if (serverData != null && (serverData as List).isNotEmpty) return serverData;
        }
      } catch (e) {
        debugPrint("getEpisodeList fallback '$k' error: $e");
      }
    }
    return [];
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LẤY LINK STREAM M3U8
  // ─────────────────────────────────────────────────────────────────────────
  Future<String?> getMovieStreamLink(
    int tmdbId, String title, String original, {
    bool isTv = false, int episodeIndex = 0,
  }) async {
    try {
      final type = isTv ? 'tv' : 'movie';
      final tmdbRes = await http
          .get(Uri.parse('https://phimapi.com/tmdb/$type/$tmdbId'))
          .timeout(_kTimeout);
      if (tmdbRes.statusCode == 200) {
        final eps = json.decode(tmdbRes.body)['episodes'];
        if (eps != null && (eps as List).isNotEmpty) {
          final sd = eps[0]['server_data'];
          if (sd != null && episodeIndex < (sd as List).length) {
            final link = sd[episodeIndex]['link_m3u8'];
            if (link != null && link.toString().isNotEmpty) return link;
          }
        }
      }
    } catch (e) {
      debugPrint("getMovieStreamLink TMDB ID error: $e");
    }

    final cleanTitle = title.split(':').first.trim();
    final keywords = <String>{title, original, cleanTitle}.where((k) => k.isNotEmpty).toList();
    for (final k in keywords) {
      try {
        final sr = await http
            .get(Uri.parse('https://phimapi.com/v1/api/tim-kiem?keyword=${Uri.encodeComponent(k)}&limit=1'))
            .timeout(_kTimeout);
        if (sr.statusCode != 200) continue;
        final items = json.decode(sr.body)['data']?['items'];
        if (items == null || (items as List).isEmpty) continue;
        final dr = await http
            .get(Uri.parse('https://phimapi.com/phim/${items[0]['slug']}'))
            .timeout(_kTimeout);
        if (dr.statusCode != 200) continue;
        final eps = json.decode(dr.body)['episodes'];
        if (eps != null && (eps as List).isNotEmpty) {
          final sd = eps[0]['server_data'];
          if (sd != null && episodeIndex < (sd as List).length) {
            final link = sd[episodeIndex]['link_m3u8'];
            if (link != null && link.toString().isNotEmpty) return link;
          }
        }
      } catch (e) {
        debugPrint("getMovieStreamLink fallback '$k' error: $e");
      }
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TÌM KIẾM PHIM
  // ─────────────────────────────────────────────────────────────────────────
  Future<List<Movie>> searchMovies(String query) async {
    final url = Uri.parse(
      '$_baseUrl/search/multi?api_key=$_apiKey&language=vi-VN&query=${Uri.encodeComponent(query)}&page=1',
    );
    try {
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final results = json.decode(res.body)['results'] as List;
        return results
            .where((m) => m['media_type'] == 'movie' || m['media_type'] == 'tv')
            .map((m) => Movie.fromJson(m))
            .toList();
      }
      throw Exception('Lỗi tìm kiếm: ${res.statusCode}');
    } catch (e) {
      debugPrint("searchMovies error: $e");
      return [];
    }
  }
}
