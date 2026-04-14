import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/movie_model.dart';

class ApiService {
  static const String _apiKey = '0cfefa564c9ae02b4e482b80fdaa59d2';
  static const String _baseUrl = 'https://api.themoviedb.org/3';

  Future<List<Movie>> getPopularMovies() async{
    final url = Uri.parse('$_baseUrl/movie/popular?api_key=$_apiKey&language=vi-VN');

    try{
      final response = await http.get(url);

      if(response.statusCode == 200){
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
}
