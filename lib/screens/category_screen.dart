import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'movie_detail_screen.dart';

class CategoryScreen extends StatefulWidget {
  final String title;
  final String type;

  const CategoryScreen({super.key, required this.title, required this.type});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  int _page = 1;
  final ApiService _api = ApiService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF15141F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: FutureBuilder(
                future: _api.getMovies(widget.type, page: _page),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.red),
                    );
                  } else if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        "Lỗi: ${snapshot.error}",
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    );
                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(
                      child: Text(
                        "Không có phim",
                        style: TextStyle(color: Colors.white),
                      ),
                    );
                  }

                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.65,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                        ),
                    itemCount: snapshot.data!.length,
                    itemBuilder: (context, i) {
                      final movie = snapshot.data![i];
                      return GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                MovieDetailScreen(movie: movie),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            movie.posterPath,
                            fit: BoxFit.cover,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              color: const Color(0xFF211F30),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: _page > 1 ? () => setState(() => _page--) : null,
                    icon: const Icon(Icons.arrow_back_ios),
                    color: _page > 1 ? Colors.white : Colors.white38,
                  ),
                  const SizedBox(width: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "Trang $_page",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  IconButton(
                    onPressed: () => setState(() => _page++),
                    icon: const Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
