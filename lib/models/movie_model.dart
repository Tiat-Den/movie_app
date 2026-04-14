class Movie {
  final int id;
  final String title;
  final String overview;
  final String posterPath;
  final double voteAverage;
  final String releaseDate;

  Movie({
    required this.id,
    required this.title,
    required this.overview,
    required this.posterPath,
    required this.voteAverage,
    required this.releaseDate,
  });

  factory Movie.fromJson(Map<String, dynamic> json) {
    return Movie(
      id: json['id'] ?? 0,
      title: json['title'] ?? '',
      overview: json['overview'] ?? '',
      posterPath: json['poster_path'] != null 
          ? 'https://image.tmdb.org/t/p/w500${json['poster_path']}' 
          : 'https://via.placeholder.com/500x750?text=No+Image',      
      voteAverage: (json['vote_average'] ?? 0)?.toDouble(),
      releaseDate: json['release_date'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'overview': overview,
      'poster_path': posterPath,
      'vote_average': voteAverage,
      'release_date': releaseDate,
      'save_date': DateTime.now().toIso8601String(),
    };
  }

  String get fullPosterUrl => 'https://image.tmdb.org/t/p/w500$posterPath';
}
