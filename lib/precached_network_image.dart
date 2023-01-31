library precached_network_image;

import 'dart:core';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http; 
import 'package:path_provider/path_provider.dart'; 
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

class PrecachedNetworkImageManager {
  PrecachedNetworkImageManager._();

  static final instance = PrecachedNetworkImageManager._();
  Map<String, File> cachedFiles = {};
  final _savedTokey = "PrecachedNetworkImageManagerKey";

  final Map<String, bool> _isRequesteds = {};
  final Map<String, bool> _isLoadSuccessfuls = {};
  final Map<String, dynamic> _statusCodes = {};

  /// precache all urls(or the target param urls) to files in memory
  /// usage:
  ///   you can call this method in advance(eg. on launch) to avoid the flash screen caused by the delay time
  ///   after set the parameter [precache] of PrecachedNetworkImage(..., precache: true) to true.
  precacheNetworkImages({List<String> urls}) async {
    if (urls != null) {
      await _precacheReadLocal(urls: urls);
    } else {
      final prefs = await SharedPreferences.getInstance();
      List<String> allUrls = prefs.getStringList(_savedTokey) ?? [];
      await _precacheReadLocal(urls: allUrls);
    }
  }

  /// add the url which you want to precache next time
  addPrecache({@required String url}) {
    SharedPreferences.getInstance().then((prefs) {
      List<String> urls = prefs.getStringList(_savedTokey) ?? [];
      if (!urls.contains(url)) {
        urls.add(url);
      }
      prefs.setStringList(_savedTokey, urls);
    });
  }

  /// delete the url which you cancel to precache 
  deletePrecache({@required String url}) {
    SharedPreferences.getInstance().then((prefs) {
      List<String> urls = prefs.getStringList(_savedTokey) ?? [];
      if (urls.contains(url)) {
        urls.remove(url);
      }
      prefs.setStringList(_savedTokey, urls);
    });
  }

  /// delete the file of given url cache in memory and disk
  deleteImageCache({@required String url}) async {
    Directory documentDirectory = await getApplicationDocumentsDirectory();
    String filePath = path.join(documentDirectory.path, path.basename(url));
    File file = File(filePath);
    try {
      if (await file.exists()) {
        await file.writeAsString('');
        await file.delete();
        cachedFiles[url] = null;
        log("$url delete file success!");
      }
    } catch (e) {
      // Error in getting access to the file.
      log("$url delete file failure with error:($e)");
    }
  }

  /// clean all precache's files of given urls cache in memory and disk
  cleanImageCache() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> urls = prefs.getStringList(_savedTokey) ?? [];
    for (String url in urls) {
      await deleteImageCache(url: url);
    }
  }

  /// clean all urls precache
  cleanPrecache() {
    SharedPreferences.getInstance().then((prefs) {
      List<String> urls = [];
      prefs.setStringList(_savedTokey, urls);
      log("clean all precache success");
    });
  }

  /// clean all urls precache and file cache in memory and disk
  cleanCaches() async {
    await cleanImageCache();
    cleanPrecache();
    cachedFiles = {};
  }

  // precache target urls to files in memory
  _precacheReadLocal({@required List<String> urls}) async {
    final documentDirectory = await getApplicationDocumentsDirectory();
    for (String url in urls) {
      File file = File(path.join(documentDirectory.path, path.basename(url)));
      final isExists = await file.exists();
      final length = await file.length();
      cachedFiles[url] = (isExists && length > 0) ? file : null;
    }
    log("memory cache:$cachedFiles");
  }
}

class PrecachedNetworkImage extends StatelessWidget {
  final String url;
  final double width;
  final double height;
  final BoxFit fit;
  // call PrecachedNetworkImageManager's precacheNetworkImages which read the disk file to memory after set to true
  final bool precache; 
  final Widget Function(BuildContext contect, String url) placeholder;
  final Widget Function(BuildContext context, String url, dynamic error) errorWidget; 

  const PrecachedNetworkImage({
    @required this.url, 
    @required this.width, 
    @required this.height, 
    this.precache = false,
    this.fit = BoxFit.fill, 
    this.placeholder,
    this.errorWidget,
    Key key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (precache) {
      File targetFile = PrecachedNetworkImageManager.instance.cachedFiles[url];
      if (targetFile != null) {
        log("$url read memory precache file success");
        return Image.file(
          targetFile,
          width: width,
          height: height,
          fit: fit,
        );
      }
    }
    return FutureBuilder<File>(
      future: _getUrlFile(),
      builder: (BuildContext context, AsyncSnapshot<File> snapshot) {
        if (snapshot.hasData) {
          return Image.file(
            snapshot.data,
            width: width,
            height: height,
            fit: fit,
          );
        }
        var isError = false;
        final isRequested = PrecachedNetworkImageManager.instance._isRequesteds[url] ?? false;
        final isLoadSuccessful = PrecachedNetworkImageManager.instance._isLoadSuccessfuls[url] ?? false;

        if (isRequested && !isLoadSuccessful && errorWidget != null) {
          isError = true;
        }
        return SizedBox(
          width: width,
          height: height,
          child: isError ? 
          errorWidget(context, url, PrecachedNetworkImageManager.instance._statusCodes[url]) : 
          placeholder != null ? placeholder(context, url) : null,
        );
      });
  }


  Future<File> _getUrlFile() async {
    if (url.isEmpty) {
      return null;
    }

    Directory documentDirectory = await getApplicationDocumentsDirectory();
    String filePath = path.join(documentDirectory.path, path.basename(url));

    File file = File(filePath);
    bool isExists = await file.exists();

    if (isExists) {
      int length = await file.length();
      if (length > 0) {
        log("$url read file success");
        return file;
      } 
    }

    file = await File(filePath).create(recursive: true);
    http.Response response;
    dynamic error;
    try {
      response = await http.get(Uri.parse(url));
    } catch (e) {
      error = e;
    }
    PrecachedNetworkImageManager.instance._isRequesteds[url] = true;
    PrecachedNetworkImageManager.instance._statusCodes[url] = response.statusCode;

    if (error != null) {
      PrecachedNetworkImageManager.instance._statusCodes[url] = error;
      log("$url get url image data failed with error code: $error");
      return null;
    }

    if (response.statusCode == 200) {
      await file.writeAsBytes(response.bodyBytes);
      log("$url write file success");
      PrecachedNetworkImageManager.instance._isLoadSuccessfuls[url] = true;
      if (precache) {
        PrecachedNetworkImageManager.instance.addPrecache(url: url);
      }
      return file;
    }

    log("$url get url image data failed with error code: ${response.statusCode}");
    return null;
  }
}
