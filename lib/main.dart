import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:movie_app/screens/auth_wrapper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: "key.env");

  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey:"AIzaSyAqqVZ1fKkgr-7wKJxKOHe476_3aBjoE8k",
      appId:"1:355226614467:android:248454c16f3eb7eb840076",
      messagingSenderId:"355226614467",
      projectId:"movie-app-68d6d",
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Movie App',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const AuthWrapper(),
    );
  }
}
