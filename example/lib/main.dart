import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:precached_network_image/precached_network_image.dart';
class _MyHomePageState extends State<MyHomePage> {
  @override
  void initState() {
    super.initState();
    // PrecachedNetworkImageManager.instance.cleanCaches();
    PrecachedNetworkImageManager.instance.precacheNetworkImages();
  }
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      initialIndex: 0,
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('PrecachedNetworkImage'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.cloud_outlined)),
              Tab(icon: Icon(Icons.beach_access_sharp)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const Center(child: Text("It's cloudy here")),
            Center(
              child: PrecachedNetworkImage(
                url: 'https://picsum.photos/200',
                width: 200, 
                height: 200,
                precache: true,
                placeholder: (context, url) => const Icon(Icons.person),
                errorWidget: (context, url, error) {
                  log("get image failed code: $error");
                  return const Icon(Icons.error);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
class MyHomePage extends StatefulWidget {
  const MyHomePage({Key key, @required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

Future<void> main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}
