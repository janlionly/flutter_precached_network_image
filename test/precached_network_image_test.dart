import 'package:flutter_test/flutter_test.dart';

import 'package:precached_network_image/precached_network_image.dart';

void main() {
  test('precache network image from url', () {
    final manager = PrecachedNetworkImageManager.instance;
    manager.precacheNetworkImages();
    const PrecachedNetworkImage(url: 'https://picsum.photos/200', width: 200, height: 200, precache: true);
  });
}
