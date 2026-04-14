import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/movie_model.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiService {
  static final String _apiKey = dotenv.env['TMDB_API_KEY'] ?? '';
  static const String _baseUrl = 'https://api.themoviedb.org/3';

  Future<List<Movie>> getPopularMovies() async {
    final url = Uri.parse('$_baseUrl/movie/popular?api_key=$_apiKey&language=vi-VN');

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List moviesData = data['results'];
        return moviesData.map((movieJson) => Movie.fromJson(movieJson)).toList();
      } else {
        throw Exception('lỗi : ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('lỗi : $e');
    }
  }

 Future<String?> getMovieStreamLink(String movieTitle, String originalTitle) async {
    // 1. Dọn dẹp từ khóa (Cắt bỏ phần sau dấu hai chấm để dễ tìm hơn)
    String cleanTitle = movieTitle.split(':').first.trim();
    String cleanOriginal = originalTitle.split(':').first.trim();

    // 2. Lên danh sách các tên cần thử (Loại bỏ những tên trùng nhau để đỡ mất công tìm)
    final List<String> titlesToTry = [
      movieTitle,
      if (originalTitle.isNotEmpty && originalTitle != movieTitle) originalTitle,
      if (cleanTitle != movieTitle) cleanTitle,
      if (cleanOriginal.isNotEmpty && cleanOriginal != originalTitle && cleanOriginal != cleanTitle) cleanOriginal,
    ];

    print("--- BẮT ĐẦU ĐI TÌM LINK PHIM ---");
    print("Danh sách từ khóa sẽ thử: $titlesToTry");

    for (final title in titlesToTry) {
      if (title.isEmpty) continue;

      final result = await _searchStreamLink(title);
      if (result != null) {
        return result; 
      }
    }
    
    print("KKPhim không có phim này!");
    return null; 
  }

  Future<String?> _searchStreamLink(String keyword) async {
    print("🚀 Đang tìm kiếm: '$keyword'");
    
    try {
      final encodedKeyword = Uri.encodeComponent(keyword);
      final searchUrl = Uri.parse('https://phimapi.com/v1/api/tim-kiem?keyword=$encodedKeyword&limit=1');
      final searchResponse = await http.get(searchUrl);

      if (searchResponse.statusCode == 200) {
        final searchData = json.decode(searchResponse.body);
        final items = searchData['data']['items'];

        if (items != null && items.isNotEmpty) {
          final String slug = items[0]['slug'];
          print("✅ Đã thấy phim (Slug: $slug). Đang lấy link m3u8...");

          final detailUrl = Uri.parse('https://phimapi.com/phim/$slug');
          final detailResponse = await http.get(detailUrl);

          if (detailResponse.statusCode == 200) {
            final detailData = json.decode(detailResponse.body);
            final episodes = detailData['episodes'];
            
            if (episodes != null && episodes.isNotEmpty) {
              final serverData = episodes[0]['server_data'];
              if (serverData != null && serverData.isNotEmpty) {
                String finalLink = serverData[0]['link_m3u8'];
                print("🎯 THÀNH CÔNG LẤY ĐƯỢC LINK: $finalLink");
                return finalLink; 
              }
            }
          }
        } else {
          print("❌ KKPhim không có phim nào tên là '$keyword'");
        }
      }
    } catch (e) {
      print("⚠️ Lỗi mạng khi tìm từ khóa '$keyword': $e");
    }
    
    return null; // Trả về null nếu hàm phụ này thất bại
  }
}
