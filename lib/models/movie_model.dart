class Movie {
  final int id;
  final String title;
  final String originalTitle;
  final String overview;
  final String posterPath;
  final double voteAverage;
  final String releaseDate;
  final bool isTv;
  final int? totalEpisodes;

  Movie({
    required this.id,
    required this.title,
    required this.originalTitle,
    required this.overview,
    required this.posterPath,
    required this.voteAverage,
    required this.releaseDate,
    required this.isTv,
    required this.totalEpisodes,
  });

  factory Movie.fromJson(Map<String, dynamic> json) {
    return Movie(
      id: json['id'] ?? 0,
      isTv: json['media_type'] == 'tv' ||
          json.containsKey('first_air_date') ||
          (json['is_tv'] == true),
      title: json['title'] ?? json['name'] ?? '',
      originalTitle: json['original_title'] ?? '',
      overview: json['overview'] ?? '',
      posterPath: json['poster_path'] != null
          ? (json['poster_path'].toString().startsWith('http')
              ? json['poster_path']
              : 'https://image.tmdb.org/t/p/w500${json['poster_path']}')
          : 'https://via.placeholder.com/500x750?text=No+Image',
      voteAverage: (json['vote_average'] ?? 0)?.toDouble(),
      releaseDate: json['release_date'] ?? '',
      totalEpisodes: json['number_of_episodes'] ?? json['total_episodes'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'original_title': originalTitle,
      'overview': overview,
      'poster_path': posterPath,
      'vote_average': voteAverage,
      'release_date': releaseDate,
      'is_tv': isTv,
      'total_episodes': totalEpisodes,
      'save_date': DateTime.now().toIso8601String(),
    };
  }

  String get fullPosterUrl => 'https://image.tmdb.org/t/p/w500$posterPath';
}
