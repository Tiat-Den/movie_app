import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../models/movie_model.dart';

class ApiService {
  static final String _apiKey = dotenv.env['TMDB_API_KEY'] ?? '';
    final String _baseUrl = 'https://api.themoviedb.org/3';

  Future<List<Movie>> getMovies(String type, {int page = 1}) async {
    String endpoint = '';

    switch (type) {
      case 'animation': endpoint = '/discover/movie?with_genres=16'; break;
      case 'action': endpoint = '/discover/movie?with_genres=28'; break;
      case 'comedy': endpoint = '/discover/movie?with_genres=35'; break;
      case 'horror': endpoint = '/discover/movie?with_genres=27'; break;
      case 'scifi': endpoint = '/discover/movie?with_genres=878'; break;
      case 'romance': endpoint = '/discover/movie?with_genres=10749'; break;
      case 'documentary': endpoint = '/discover/movie?with_genres=99'; break;
      default: endpoint = '/movie/$type'; 
    }

    final String separator = endpoint.contains('?') ? '&' : '?';
    final url = Uri.parse('$_baseUrl$endpoint${separator}api_key=$_apiKey&language=vi-VN&page=$page');

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return (data['results'] as List).map((m) => Movie.fromJson(m)).toList();
    } else {
      throw Exception('Lỗi API TMDB: ${response.statusCode}');
    }
  }

  Future<String?> getMovieStreamLink(String title, String original) async {
    String cleanTitle = title.split(':').first.trim();
    List<String> keywords = [title, original, cleanTitle];

    for (var k in keywords) {
      if (k.isEmpty) continue;
      try {
        final searchUrl = Uri.parse('https://phimapi.com/v1/api/tim-kiem?keyword=${Uri.encodeComponent(k)}&limit=1');
        final res = await http.get(searchUrl);
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          final items = data['data']['items'];
          if (items != null && items.isNotEmpty) {
            final detailRes = await http.get(Uri.parse('https://phimapi.com/phim/${items[0]['slug']}'));
            final detailData = json.decode(detailRes.body);
            return detailData['episodes'][0]['server_data'][0]['link_m3u8'];
          }
        }
      } catch (e) { print(e); }
    }
    return null;
  }
}