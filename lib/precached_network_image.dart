library precached_network_image;

import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dev_colorized_log/dev_colorized_log.dart';

// Platform-specific imports
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'src/file_mobile.dart' if (dart.library.html) 'src/file_web.dart'
    as platform_file;

class PrecachedNetworkImageManager {
  PrecachedNetworkImageManager._();

  static final instance = PrecachedNetworkImageManager._();
  Map<String, dynamic> cachedFiles = {};
  final _savedTokey = "PrecachedNetworkImageManagerKey";

  final Map<String, bool> _isRequesteds = {};
  final Map<String, bool> _isLoadSuccessfuls = {};
  final Map<String, dynamic> _statusCodes = {};

  /// precache all urls(or the target param urls) to files in memory
  /// usage:
  ///   you can call this method in advance(eg. on launch) to avoid the flash screen caused by the delay time
  ///   after set the parameter [precache] of PrecachedNetworkImage(..., precache: true) to true.
  precacheNetworkImages({List<String>? urls, bool isLog = false}) async {
    Dev.enable = isLog;

    if (urls != null) {
      await _precacheReadLocal(urls: urls);
    } else {
      final prefs = await SharedPreferences.getInstance();
      List<String> allUrls = prefs.getStringList(_savedTokey) ?? [];
      await _precacheReadLocal(urls: allUrls);
    }
  }

  setLog(bool isLog) {
    Dev.enable = isLog;
  }

  /// add the url which you want to precache next time
  addPrecache({required String url}) {
    SharedPreferences.getInstance().then((prefs) {
      List<String> urls = prefs.getStringList(_savedTokey) ?? [];
      if (!urls.contains(url)) {
        urls.add(url);
      }
      prefs.setStringList(_savedTokey, urls);
    });
  }

  /// delete the url which you cancel to precache
  deletePrecache({required String url}) {
    SharedPreferences.getInstance().then((prefs) {
      List<String> urls = prefs.getStringList(_savedTokey) ?? [];
      if (urls.contains(url)) {
        urls.remove(url);
      }
      prefs.setStringList(_savedTokey, urls);
    });
  }

  /// delete the file of given url cache in memory and disk
  deleteImageCache({required String url}) async {
    if (kIsWeb) {
      await _deleteWebCache(url);
      cachedFiles[url] = null;
      Dev.log("$url delete web cache success!");
      return;
    }

    try {
      dynamic file = await _getFileWithUrl(url);
      bool exists = await _fileExists(file);
      if (exists) {
        await _writeFileAsString(file, '');
        await _deleteFile(file);
        cachedFiles[url] = null;
        Dev.log("$url delete file success!");
      }
    } catch (e) {
      // Error in getting access to the file.
      Dev.log("$url delete file failure with error:($e)");
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
      Dev.log("clean all precache success");
    });
  }

  /// clean all urls precache and file cache in memory and disk
  cleanCaches() async {
    await cleanImageCache();
    cleanPrecache();
    cachedFiles = {};
  }

  // precache target urls to files in memory
  _precacheReadLocal({required List<String> urls}) async {
    for (String url in urls) {
      if (kIsWeb) {
        await _cacheWebFile(url);
      } else {
        dynamic file = await _getFileWithUrl(url);
        await _cacheToFile(url, file);
      }
    }
    Dev.log("memory cache:$cachedFiles");
  }

  Future<bool> _cacheToFile(String url, dynamic file) async {
    final isExists = await _fileExists(file);
    if (isExists) {
      final length = await _getFileLength(file);
      if (length > 0) {
        cachedFiles[url] = file;
        return true;
      }
    }
    return false;
  }

  Future<bool> _cacheWebFile(String url) async {
    if (!kIsWeb) return false;

    final key = _getWebCacheKey(url);
    try {
      final data = await _getWebStorage(key);
      if (data != null && data.isNotEmpty) {
        cachedFiles[url] = data;
        return true;
      }
    } catch (e) {
      Dev.log("Error accessing web storage for $url: $e");
    }
    return false;
  }

  String _getWebCacheKey(String url) {
    String hash = sha1.convert(utf8.encode(url)).toString();
    return 'precached_network_image_$hash';
  }

  Future<void> _deleteWebCache(String url) async {
    if (kIsWeb) {
      try {
        final key = _getWebCacheKey(url);
        await _removeWebStorage(key);
      } catch (e) {
        Dev.log("Error deleting web cache for $url: $e");
      }
    }
  }

  // Web storage helper methods
  Future<String?> _getWebStorage(String key) async {
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString(key);
      } catch (e) {
        Dev.log("Error getting web storage for $key: $e");
        return null;
      }
    }
    return null;
  }

  Future<void> _setWebStorage(String key, String value) async {
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(key, value);
      } catch (e) {
        Dev.log("Error setting web storage for $key: $e");
      }
    }
  }

  Future<void> _removeWebStorage(String key) async {
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(key);
      } catch (e) {
        Dev.log("Error removing web storage for $key: $e");
      }
    }
  }

  Future<dynamic> _getFileWithUrl(String url) async {
    if (kIsWeb) {
      return _getWebCacheKey(url);
    } else {
      try {
        var documentDirectory = await getApplicationDocumentsDirectory();
        String hash = sha1.convert(utf8.encode(url)).toString();
        String filePath = path.join(documentDirectory.path, hash);

        // Create File object safely for mobile platforms
        var file = _createMobileFile(filePath);
        Dev.log("Created file for $url at path: $filePath");
        return file;
      } catch (e) {
        Dev.log("Error creating file for $url: $e");
        rethrow;
      }
    }
  }

  dynamic _createMobileFile(String filePath) {
    if (kIsWeb) {
      throw UnsupportedError('File creation not supported on web');
    }

    // Use dynamic import to safely access File constructor
    try {
      // This uses a function to dynamically access the File class
      return _createFileInstance(filePath);
    } catch (e) {
      Dev.log("Error creating File object: $e");
      rethrow;
    }
  }

  dynamic _createFileInstance(String filePath) {
    // Use platform-specific implementation
    return platform_file.createPlatformFile(filePath);
  }

  // Platform-specific file operations
  Future<bool> _fileExists(dynamic file) async {
    if (kIsWeb) {
      final key = file as String;
      try {
        final data = await _getWebStorage(key);
        return data != null;
      } catch (e) {
        return false;
      }
    } else {
      return await file.exists();
    }
  }

  Future<int> _getFileLength(dynamic file) async {
    if (kIsWeb) {
      final key = file as String;
      try {
        final data = await _getWebStorage(key);
        return data?.length ?? 0;
      } catch (e) {
        return 0;
      }
    } else {
      return await file.length();
    }
  }

  Future<void> _writeFileAsString(dynamic file, String contents) async {
    if (kIsWeb) {
      final key = file as String;
      try {
        await _setWebStorage(key, contents);
      } catch (e) {
        Dev.log("Error writing web cache: $e");
      }
    } else {
      await file.writeAsString(contents);
    }
  }

  Future<void> _deleteFile(dynamic file) async {
    if (kIsWeb) {
      final key = file as String;
      try {
        await _removeWebStorage(key);
      } catch (e) {
        Dev.log("Error deleting web cache: $e");
      }
    } else {
      await file.delete();
    }
  }

  Future<dynamic> _createFile(dynamic file) async {
    if (kIsWeb) {
      return file; // No need to create in web storage
    } else {
      return await file.create(recursive: true);
    }
  }

  Future<void> _writeFileAsBytes(dynamic file, List<int> bytes) async {
    if (kIsWeb) {
      final key = file as String;
      final base64String = base64Encode(bytes);
      try {
        await _setWebStorage(key, base64String);
      } catch (e) {
        Dev.log("Error writing web cache: $e");
      }
    } else {
      await file.writeAsBytes(bytes);
    }
  }
}

class PrecachedNetworkImage extends StatelessWidget {
  final String url;
  final double width;
  final double height;
  final BoxFit fit;
  // call PrecachedNetworkImageManager's precacheNetworkImages which read the disk file to memory after set to true
  final bool precache;
  final bool gaplessPlayback;
  final Widget Function(BuildContext contect, String url)? placeholder;
  final Widget Function(BuildContext context, String url, dynamic error)?
      errorWidget;

  const PrecachedNetworkImage(
      {required this.url,
      required this.width,
      required this.height,
      this.precache = false,
      this.gaplessPlayback = true,
      this.fit = BoxFit.fill,
      this.placeholder,
      this.errorWidget,
      super.key});

  @override
  Widget build(BuildContext context) {
    dynamic targetFile = PrecachedNetworkImageManager.instance.cachedFiles[url];
    if (targetFile != null) {
      Dev.log("$url read memory precache file success");
      if (kIsWeb) {
        // For web, targetFile is a base64 string
        return _buildWebImage(targetFile);
      } else {
        Dev.log("$url displaying mobile cached file: $targetFile");
        try {
          return Image.file(
            targetFile,
            key: ValueKey(url),
            gaplessPlayback: gaplessPlayback,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (context, error, stackTrace) {
              Dev.log("$url Image.file error: $error");
              return Container(
                width: width,
                height: height,
                color: Colors.red[100],
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.error, color: Colors.red),
                    Text('File Error', style: TextStyle(fontSize: 12)),
                  ],
                ),
              );
            },
          );
        } catch (e) {
          Dev.log("$url Exception creating Image.file: $e");
          return Container(
            width: width,
            height: height,
            color: Colors.orange[100],
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.warning, color: Colors.orange),
                Text('Create Error', style: TextStyle(fontSize: 12)),
              ],
            ),
          );
        }
      }
    }
    Dev.log("$url get file from future");
    return FutureBuilder<dynamic>(
        future: _getUrlFile(),
        builder: (BuildContext context, AsyncSnapshot<dynamic> snapshot) {
          if (snapshot.hasData) {
            if (kIsWeb) {
              return _buildWebImage(snapshot.data);
            } else {
              Dev.log(
                  "$url displaying mobile file from future: ${snapshot.data}");
              try {
                return Image.file(
                  snapshot.data!,
                  key: ValueKey(url),
                  gaplessPlayback: gaplessPlayback,
                  width: width,
                  height: height,
                  fit: fit,
                  errorBuilder: (context, error, stackTrace) {
                    Dev.log("$url Image.file future error: $error");
                    return Container(
                      width: width,
                      height: height,
                      color: Colors.red[100],
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.error, color: Colors.red),
                          Text('Future File Error',
                              style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    );
                  },
                );
              } catch (e) {
                Dev.log("$url Exception creating future Image.file: $e");
                return Container(
                  width: width,
                  height: height,
                  color: Colors.orange[100],
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.warning, color: Colors.orange),
                      Text('Future Create Error',
                          style: TextStyle(fontSize: 12)),
                    ],
                  ),
                );
              }
            }
          }
          var isError = false;
          final isRequested =
              PrecachedNetworkImageManager.instance._isRequesteds[url] ?? false;
          final isLoadSuccessful =
              PrecachedNetworkImageManager.instance._isLoadSuccessfuls[url] ??
                  false;

          if (isRequested && !isLoadSuccessful && errorWidget != null) {
            isError = true;
          }
          return SizedBox(
            width: width,
            height: height,
            child: isError
                ? (errorWidget != null
                    ? errorWidget!(context, url,
                        PrecachedNetworkImageManager.instance._statusCodes[url])
                    : null)
                : (placeholder != null
                    ? _handlePlaceholder(context, url)
                    : null),
          );
        });
  }

  Widget _buildWebImage(String base64Data) {
    try {
      final bytes = base64Decode(base64Data);
      return Image.memory(
        bytes,
        key: ValueKey(url),
        width: width,
        height: height,
        fit: fit,
        gaplessPlayback: gaplessPlayback,
      );
    } catch (e) {
      Dev.log("Error decoding image data for $url: $e");
      return Container(
        width: width,
        height: height,
        color: Colors.grey[300],
        child: const Icon(Icons.error),
      );
    }
  }

  Widget _handlePlaceholder(BuildContext context, String url) {
    try {
      return placeholder!(context, url);
    } catch (e, stack) {
      Dev.logError('placeholder error', error: e, stackTrace: stack);
      // fallback to error widget
      return errorWidget != null
          ? errorWidget!(
              context,
              url,
              PrecachedNetworkImageManager.instance._statusCodes[url],
            )
          : const SizedBox.shrink();
    }
  }

  Future<dynamic> _getUrlFile() async {
    if (url.isEmpty) {
      return null;
    }

    if (kIsWeb) {
      return _getWebImageData();
    } else {
      return _getMobileImageFile();
    }
  }

  Future<String?> _getWebImageData() async {
    final key = PrecachedNetworkImageManager.instance._getWebCacheKey(url);

    // Check cache first
    try {
      final cachedData =
          await PrecachedNetworkImageManager.instance._getWebStorage(key);
      if (cachedData != null && cachedData.isNotEmpty) {
        Dev.log("$url read web cache success");
        PrecachedNetworkImageManager.instance.cachedFiles[url] = cachedData;
        return cachedData;
      }
    } catch (e) {
      Dev.log("Error accessing web cache for $url: $e");
    }

    // Fetch from network
    late http.Response response;
    dynamic error;
    try {
      response = await http.get(Uri.parse(url));
    } catch (e) {
      error = e;
    }
    PrecachedNetworkImageManager.instance._isRequesteds[url] = true;

    if (error != null) {
      PrecachedNetworkImageManager.instance._statusCodes[url] = error;
      Dev.log("$url get url image data failed with error code: $error");
      return null;
    }

    PrecachedNetworkImageManager.instance._statusCodes[url] =
        response.statusCode;

    if (response.statusCode == 200) {
      final base64String = base64Encode(response.bodyBytes);
      try {
        await PrecachedNetworkImageManager.instance
            ._setWebStorage(key, base64String);
        Dev.log("$url write web cache success");
      } catch (e) {
        Dev.log("Error writing web cache for $url: $e");
      }
      PrecachedNetworkImageManager.instance._isLoadSuccessfuls[url] = true;
      PrecachedNetworkImageManager.instance.cachedFiles[url] = base64String;
      if (precache) {
        PrecachedNetworkImageManager.instance.addPrecache(url: url);
      }
      return base64String;
    }

    Dev.log(
        "$url get url image data failed with error code: ${response.statusCode}");
    return null;
  }

  Future<dynamic> _getMobileImageFile() async {
    try {
      Dev.log("Starting mobile image file processing for: $url");

      dynamic file =
          await PrecachedNetworkImageManager.instance._getFileWithUrl(url);
      Dev.log("Got file object: $file");

      bool isExists =
          await PrecachedNetworkImageManager.instance._fileExists(file);
      Dev.log("File exists: $isExists");

      if (isExists) {
        int length =
            await PrecachedNetworkImageManager.instance._getFileLength(file);
        Dev.log("File length: $length");
        if (length > 0) {
          Dev.log("$url read existing file success");
          PrecachedNetworkImageManager.instance.cachedFiles[url] = file;
          return file;
        } else {
          Dev.log("File exists but has zero length, will re-download");
        }
      }

      Dev.log("Creating file for download: $url");
      file = await PrecachedNetworkImageManager.instance._createFile(file);
      Dev.log("File created successfully");

      late http.Response response;
      dynamic error;
      try {
        Dev.log("Starting HTTP request for: $url");
        response = await http.get(Uri.parse(url));
        Dev.log("HTTP request completed with status: ${response.statusCode}");
      } catch (e) {
        error = e;
        Dev.log("HTTP request failed with error: $e");
      }
      PrecachedNetworkImageManager.instance._isRequesteds[url] = true;

      if (error != null) {
        PrecachedNetworkImageManager.instance._statusCodes[url] = error;
        Dev.log("$url get url image data failed with error: $error");
        return null;
      }

      PrecachedNetworkImageManager.instance._statusCodes[url] =
          response.statusCode;

      if (response.statusCode == 200) {
        Dev.log("Writing ${response.bodyBytes.length} bytes to file");
        await PrecachedNetworkImageManager.instance
            ._writeFileAsBytes(file, response.bodyBytes);

        // Verify file was written successfully
        bool verifyExists =
            await PrecachedNetworkImageManager.instance._fileExists(file);
        int verifyLength =
            await PrecachedNetworkImageManager.instance._getFileLength(file);
        Dev.log(
            "File verification - exists: $verifyExists, length: $verifyLength");

        Dev.log("$url write file success with save info: $file");
        PrecachedNetworkImageManager.instance._isLoadSuccessfuls[url] = true;
        PrecachedNetworkImageManager.instance.cachedFiles[url] = file;
        if (precache) {
          PrecachedNetworkImageManager.instance.addPrecache(url: url);
        }
        return file;
      }

      Dev.log(
          "$url get url image data failed with error code: ${response.statusCode}");
      return null;
    } catch (e, stackTrace) {
      Dev.log("_getMobileImageFile error for $url: $e");
      Dev.log("Stack trace: $stackTrace");
      return null;
    }
  }
}
