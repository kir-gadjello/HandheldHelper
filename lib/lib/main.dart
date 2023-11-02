import 'dart:isolate';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:handheld_helper/db.dart';
import 'package:path/path.dart' as Path;
import 'package:flutter/material.dart';
import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:clipboard/clipboard.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'custom_widgets.dart';
import 'conv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_fast_forms/flutter_fast_forms.dart';
import 'package:getwidget/getwidget.dart';
import 'package:external_path/external_path.dart';

Future<int> checkFileSize(String path) async {
  try {
    // Resolve symbolic links
    String resolvedPath = await File(path).resolveSymbolicLinks();

    // Check if file exists
    if (await File(resolvedPath).exists()) {
      // Get file size
      int size = await File(resolvedPath).length();
      return size;
    }
  } catch (e) {
    // If the file does not exist or is a directory, return -1
    return -1;
  }

  return -1;
}

Future<void> requestStoragePermission() async {
  var status = await Permission.manageExternalStorage.request();
  if (status.isGranted) {
    print('Storage permission granted');
  } else if (status.isPermanentlyDenied) {
    openAppSettings();
  }
}

/* widget source code */
class HttpDownloadWidget extends StatefulWidget {
  final String url;
  final String destinationPath;
  final TextStyle? textStyle;
  Function(bool success, String url, String dstPath)? onDownloadEnd;
  final http.Client? client;

  HttpDownloadWidget(
      {Key? key,
      required this.url,
      required this.destinationPath,
      this.onDownloadEnd,
      this.textStyle,
      this.client})
      : super(key: key);

  @override
  _HttpDownloadWidgetState createState() => _HttpDownloadWidgetState();
}

class _HttpDownloadWidgetState extends State<HttpDownloadWidget> {
  late http.StreamedResponse response;
  double progress = 0.0;
  bool isDownloading = false;
  bool downloadSuccess = false;
  bool isContinuingDownload = false;
  int _downloaded = 0;
  String errorCode = '';
  DateTime startTime = DateTime
      .now(); // Added this line to declare and initialize the startTime field

  @override
  void initState() {
    super.initState();
    downloadFile();
  }

  Future<void> downloadFile() async {
    try {
      setState(() {
        isDownloading = true;
      });

      final http.Client client = widget.client ?? http.Client();
      final http.StreamedResponse response =
          await client.send(http.Request('GET', Uri.parse(widget.url)));
      this.response = response;
      var total = response.contentLength ?? 0;
      _downloaded = 0;

      final file = File(widget.destinationPath);

      // Check if the file already exists
      if (await file.exists()) {
        _downloaded = await File(attemptResolveSymlink(file.path)).length();
        // If the file already exists and its size is less than the total file size,
        // initiate a partial download
        if (_downloaded < total) {
          response.request?.headers.addAll({'Range': 'bytes=$_downloaded-'});
          setState(() {
            isContinuingDownload = true;
          });
        } else if (_downloaded == total) {
          setState(() {
            isDownloading = false;
            downloadSuccess = true;
            if (widget.onDownloadEnd != null) {
              widget.onDownloadEnd!(true, widget.url, widget.destinationPath);
            }
          });
          return;
        } else {
          print("HTTP DOWNLOADED: replacing file due to wrong size");
          await file.delete();
        }
      }

      final fileSink = file.openWrite(mode: FileMode.append);

      await response.stream.listen((data) {
        fileSink.add(data);
        progress = _downloaded / total;
        _downloaded += data.length;
        setState(() {
          _downloaded;
        });
      }).asFuture();

      await fileSink.flush();
      await fileSink.close();
      client.close();

      setState(() {
        isDownloading = false;
        downloadSuccess = true;
        if (widget.onDownloadEnd != null) {
          widget.onDownloadEnd!(true, widget.url, widget.destinationPath);
        }
      });
    } catch (e) {
      setState(() {
        isDownloading = false;
        errorCode = e.toString();
        if (widget.onDownloadEnd != null) {
          widget.onDownloadEnd!(false, widget.url, widget.destinationPath);
        }
      });
    }
  }

  // Future<void> downloadFile() async {
  //   try {
  //     setState(() {
  //       isDownloading = true;
  //     });
  //
  //     final http.Client client = http.Client();
  //     final http.StreamedResponse response =
  //         await client.send(http.Request('GET', Uri.parse(widget.url)));
  //     this.response = response;
  //     var total = response.contentLength ?? 0;
  //     var downloaded = 0;
  //
  //     final file = File(widget.destinationPath);
  //     // '${widget.destinationPath}/${response.headers['content-disposition']?.split('filename=')[1] ?? 'unknown_file'}');
  //     final fileSink = file.openWrite();
  //     await response.stream.listen((data) {
  //       fileSink.add(data);
  //       downloaded += data.length;
  //       progress = downloaded / total;
  //       setState(() {});
  //     }).asFuture();
  //
  //     await fileSink.flush();
  //     await fileSink.close();
  //     client.close();
  //
  //     setState(() {
  //       isDownloading = false;
  //       downloadSuccess = true;
  //       if (widget.onDownloadEnd != null) {
  //         widget.onDownloadEnd!(true, widget.url, widget.destinationPath);
  //       }
  //     });
  //   } catch (e) {
  //     setState(() {
  //       isDownloading = false;
  //       errorCode = e.toString();
  //       if (widget.onDownloadEnd != null) {
  //         widget.onDownloadEnd!(false, widget.url, widget.destinationPath);
  //       }
  //     });
  //   }
  // }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'HttpDownloadWidget', // Added this line to provide a unique label for the widget
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (isDownloading)
              const Padding(
                padding: const EdgeInsets.all(8.0),
                child: CircularProgressIndicator(),
              ),
            if (!isDownloading && downloadSuccess)
              const Icon(Icons.check_circle, color: Colors.green),
            if (!isDownloading && errorCode.isNotEmpty)
              const Icon(Icons.error, color: Colors.red),
            if (isDownloading)
              SizedBox(
                  width: 95,
                  child: Text("${getSpeedString(_downloaded)} ",
                      style: widget.textStyle)),
            if (isDownloading)
              Text(
                  isContinuingDownload ? 'Continuing download' : 'Downloading ',
                  style: widget.textStyle),
            Expanded(
                child: Container(
              margin: const EdgeInsets.all(2.0),
              padding: const EdgeInsets.all(2.0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6.0),
                border: Border.all(
                  color:
                      downloadSuccess ? Colors.lightGreen : Colors.blueAccent,
                  width: 1.0,
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  widget.url,
                  style: widget.textStyle,
                ),
              ),
            ))
          ]),
          if (isDownloading)
            Padding(
                padding: const EdgeInsets.all(8.0),
                child: LinearProgressIndicator(
                  value: progress,
                  color: Colors.green,
                )),
          if (downloadSuccess)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Row(children: [
                //   Text('Download completed',
                //       style: TextStyle(color: Colors.green)),
                //   Icon(Icons.check_circle, color: Colors.green)
                // ]),
                SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: EdgeInsets.all(8.0),
                      child: Text(
                          '${getSizeString(response.contentLength ?? 0)}',
                          style: widget.textStyle),
                    ),
                    Container(
                      padding: EdgeInsets.all(8.0),
                      child: Text('${getDurationString()}',
                          style: widget.textStyle),
                    ),
                    Container(
                      padding: EdgeInsets.all(8.0),
                      child: Text(
                          '${getSpeedString(response.contentLength ?? 0)}',
                          style: widget.textStyle),
                    ),
                  ],
                ),
              ],
            ),
          if (errorCode.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Error',
                    style: TextStyle(
                        color: Colors.red,
                        fontSize: widget.textStyle?.fontSize ?? 16)),
                Icon(Icons.error, color: Colors.red),
                SizedBox(height: 8),
                Text(errorCode, style: widget.textStyle),
              ],
            ),
        ],
      ),
    );
  }

  String getSizeString(int size) {
    if (size >= 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    } else if (size >= 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${size.toString()} KB';
    }
  }

  String getDurationString() {
    final duration = DateTime.now().difference(startTime);
    String ret = '';
    if (duration.inHours > 0) ret += '${duration.inHours}';
    ret += '${duration.inMinutes % 60}:${duration.inSeconds % 60}';
    return ret;
  }

  String getSpeedString(int size) {
    final speed = (size / (DateTime.now().difference(startTime).inSeconds)) /
        (1024 * 1024);
    return speed.isFinite ? '${speed.toStringAsFixed(2)} MB/s' : '';
  }
}

// class DownloadWidget extends StatefulWidget {
//   final String url;
//   final String savePath;
//   final Function(bool, String?, String?, dynamic) onComplete;
//
//   DownloadWidget(
//       {required this.url, required this.savePath, required this.onComplete});
//
//   @override
//   _DownloadWidgetState createState() => _DownloadWidgetState();
// }
//
// class _DownloadWidgetState extends State<DownloadWidget> {
//   String? downloadId;
//   double downloadProgress = 0;
//
//   @override
//   void initState() {
//     super.initState();
//
//     FlutterDownloader.initialize(debug: true)
//         .then((_) => FlutterDownloader.registerCallback((id, status, progress) {
//               setState(() {
//                 downloadId = id;
//                 downloadProgress = progress / 100;
//               });
//             }));
//
//     final taskId = FlutterDownloader.enqueue(
//       url: widget.url,
//       savedDir: widget.savePath,
//       showNotification: true,
//       openFileFromNotification: true,
//     );
//
//     setState(() async {
//       downloadId = await taskId;
//     });
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Column(
//       children: <Widget>[
//         LinearProgressIndicator(
//           value: downloadProgress,
//           backgroundColor: Colors.grey[200],
//         ),
//         Text(
//           downloadProgress == 1 ? 'Download completed' : 'Downloading',
//           style: TextStyle(fontSize: 16),
//         ),
//         Text(
//           widget.url,
//           style: TextStyle(fontSize: 16, color: Colors.blue),
//         ),
//       ],
//     );
//   }
//
//   @override
//   void dispose() {
//     FlutterDownloader.registerCallback((id, status, progress) {});
//     super.dispose();
//   }
// }

final ChatUser user_SYSTEM = ChatUser(
  id: '0',
  firstName: 'SYSTEM',
);

final ChatUser user = ChatUser(
  id: '1',
  firstName: 'User',
);

final ChatUser user_ai = ChatUser(
  id: '2',
  firstName: 'AI',
);

class RootAppParams {
  String hhh_dir;
  String default_model;
  List<String> model_search_paths;

  RootAppParams(this.hhh_dir, this.default_model, this.model_search_paths);

  Map<String, dynamic> toJson() => {
        'hhh_dir': hhh_dir,
        'default_model': default_model,
        'model_search_paths': model_search_paths,
      };
}

class LLMref {
  List<String> sources;
  String? fileName;
  String name;
  int size;
  Map<String, dynamic>? meta;

  LLMref(
      {required this.sources,
      required this.name,
      required this.size,
      this.meta,
      this.fileName});
}

const DEFAULT_LLM =
    "https://huggingface.co/TheBloke/OpenHermes-2-Mistral-7B-GGUF/resolve/main/openhermes-2-mistral-7b.Q4_K_M.gguf";
const DEFAULT_LLM_FILE = "openhermes-2-mistral-7b.Q4_K_M.gguf";
const DEFAULT_LLM_NAME = "OpenHermes-2-Mistral-7B";
const DEFAULT_LLM_SIZE = 4368450272;

// const DEFAULT_LLM =
//     "https://huggingface.co/TheBloke/TinyLlama-1.1B-1T-OpenOrca-GGUF/resolve/main/tinyllama-1.1b-1t-openorca.Q4_K_M.gguf";
// const DEFAULT_LLM_FILE = "tinyllama-1.1b-1t-openorca.Q4_K_M.gguf";
// const DEFAULT_LLM_NAME = "TinyLLAMA-1t-OpenOrca";
// const DEFAULT_LLM_SIZE = 667814368;

final defaultLLM = LLMref(
    sources: [DEFAULT_LLM], name: DEFAULT_LLM_NAME, size: DEFAULT_LLM_SIZE);

class HHHDefaults {
  final String hhh_dir;
  final String llm_url;
  final String llm_filename;
  final int llm_size;

  HHHDefaults(this.hhh_dir, this.llm_url, this.llm_filename, this.llm_size);

  Map<String, dynamic> toJson() {
    return {
      'hhh_dir': hhh_dir,
      'llm_url': llm_url,
      'llm_filename': llm_filename,
      'llm_size': llm_size,
    };
  }

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

String attemptResolveSymlink(String p) {
  if (File(p).existsSync() && FileSystemEntity.isLinkSync(p)) {
    return File(p).resolveSymbolicLinksSync();
  }
  return p;
}

String? findFile(String filename, List<String> searchPaths,
    [bool Function(File)? validateFn]) {
  // Resolve symbolic links

  print("FINDFILE: $filename in $searchPaths");

  String? ret;

  for (var dir in searchPaths) {
    // Check if file exists
    var initialPath = Path.join(dir, filename);
    var resolvedPath = attemptResolveSymlink(initialPath);
    if (initialPath != resolvedPath) {
      print("FINDFILE: symlink $initialPath --> $resolvedPath");
    }
    if (File(resolvedPath).existsSync()) {
      // If a validation function is given, use it for validation
      if (validateFn != null) {
        if (validateFn(File(resolvedPath))) {
          ret = initialPath;
          break;
        }
      } else {
        ret = initialPath;
        break;
      }
    }
  }

  if (ret != null) {
    print("FINDFILE: found $filename in $ret");
  }

  // If no valid file is found, return null
  return ret;
}

String? resolve_hhh_model(
    String filename, String hhh_dir, List<String>? model_search_paths) {
  print("resolve_hhh_model $filename $hhh_dir $model_search_paths");
  return findFile(filename, [hhh_dir, ...(model_search_paths ?? [])]);
}

bool validate_root_app_params(Map<String, dynamic> j) {
  bool root_dir_ok = false, default_model_ok = false;
  print("validate_root_app_params arg: $j");
  String? hhh_dir, hhh_model_subdir;
  try {
    hhh_dir = j['hhh_dir'];
    hhh_model_subdir = Path.join(j['hhh_dir'], HHH_MODEL_SUBDIR);
    root_dir_ok = Directory(j['hhh_dir']).existsSync() &&
        Directory(hhh_model_subdir).existsSync();
  } catch (e) {
    print("Exception: $e");
  }
  print("$hhh_dir exists = $root_dir_ok");

  String? mpath;
  try {
    mpath = resolve_hhh_model(j['default_model'], hhh_model_subdir!,
        List<String>.from(j['model_search_paths'] ?? []));
    if (mpath != null) {
      default_model_ok = File(mpath).existsSync();
    }
  } catch (e) {
    print("Exception: $e");
  }
  print("$mpath exists = $default_model_ok");
  return root_dir_ok && default_model_ok;
}

class AppInitParams {
  RootAppParams? params;
  HHHDefaults defaults;
  bool storagePermissionGranted;
  AppInitParams(this.defaults,
      {this.params, this.storagePermissionGranted = false});
}

Future<AppInitParams> perform_app_init() async {
  print("ENTER perform_app_init");
  String def_hhh_dir = (await getApplicationDocumentsDirectory()).absolute.path;

  if (Platform.isLinux) {
    def_hhh_dir =
        Path.join(Platform.environment["HOME"] ?? "/home/user", "HHH");
  } else if (Platform.isMacOS) {
    def_hhh_dir = await resolve_db_dir();
    // def_hhh_dir = (await getApplicationDocumentsDirectory())
    //     .absolute
    //     .path; // Path.join(Platform.environment["HOME"] ?? "/home/user", "Documents/HHH");
  } else if (Platform.isAndroid) {
    print("Running Android...");
    Directory? sdcard = await getExternalStorageDirectory();
    List<Directory>? sdcard_dirs =
        await getExternalStorageDirectories(type: StorageDirectory.downloads);
    // List<String> sdcard_dirs = await ExternalPath
    //     .getExternalStorageDirectories(); // Isn't accessible anymore after android 11, have to live with it I guess
    if (sdcard != null && sdcard.existsSync()) {
      try {
        String path = sdcard.absolute.path;
        print("External storage directory: ${path}");
        def_hhh_dir = Path.join(path, "HHH");
      } catch (e) {
        try {
          print("Exception, backing up... $e");
          Directory? sdcard = await getExternalStorageDirectory();
          if (sdcard != null) {
            String path = sdcard.absolute.path;
            def_hhh_dir = Path.join(path, "HHH");
          }
        } catch (e) {
          print("Exception");
        }
      }
    } else {
      print("External storage directory = NULL");
      var path = "/storage/emulated/0/";
      print("WARNING: using default external storage dir: $path");
      def_hhh_dir = Path.join(path, "HHH");
    }
  }

  var hhhd =
      HHHDefaults(def_hhh_dir, DEFAULT_LLM, DEFAULT_LLM_FILE, DEFAULT_LLM_SIZE);

  print("HHHDefaults: $hhhd");

  print("INIT db");

  final DatabaseHelper _databaseHelper = DatabaseHelper();
  var metadb = MetadataManager();
  var root_app_params = await metadb.getMetadata("root_app_params");
  RootAppParams? rp;

  print("INIT validate_root_app_params");

  print("INIT root_app_params from db = $root_app_params");

  if (root_app_params is String) {
    var jr_app_params = jsonDecode(root_app_params);

    print("INIT json root_app_params from db = $jr_app_params");

    if (validate_root_app_params(jr_app_params)) {
      rp = RootAppParams(
          jr_app_params['hhh_dir'] as String,
          jr_app_params['default_model'] as String,
          (List<String>.from(jr_app_params['model_search_paths'] ?? [])));
    }
  }

  print("DONE perform_app_init");

  if (Platform.isAndroid) {
    Map<Permission, PermissionStatus> statuses =
        // await [Permission.storage, Permission.manageExternalStorage].request();
        await [Permission.storage].request();

    var perm_success = true;
    for (var item in statuses.entries) {
      var granted = (item.value?.isGranted ?? false);
      if (granted) {
        print("[OK] PERMISSION ${item.key} GRANTED");
      }
      // else {
      //   print("[ERROR] PERMISSION ${item.key} NOT GRANTED");
      // }
      perm_success &= granted;
    }

    return Future.value(AppInitParams(hhhd,
        params: rp, storagePermissionGranted: perm_success));
  }

  return Future.value(AppInitParams(hhhd, params: rp));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    var colorScheme = ColorScheme.fromSeed(
        seedColor: Colors.cyan.shade500, primary: Colors.cyan.shade100);
    return MaterialApp(
      title: 'HandHeld Helper',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a blue toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: colorScheme,
        useMaterial3: true,
      ),
      home: MyHomePage(title: 'HandHeld Helper'),
    );
  }
}

// class MyHomePage extends StatefulWidget {
//   MyHomePage({super.key, required this.title});
//   // RootAppParams? this.root_app_params,
//   // required HHHDefaults this.resolved_defaults});
//
//   // This widget is the home page of your application. It is stateful, meaning
//   // that it has a State object (defined below) that contains fields that affect
//   // how it looks.
//
//   // This class is the configuration for the state. It holds the values (in this
//   // case the title) provided by the parent (in this case the App widget) and
//   // used by the build method of the State. Fields in a Widget subclass are
//   // always marked "final".
//
//   final String title;
//   // RootAppParams? root_app_params;
//   // HHHDefaults resolved_defaults;
//
//   @override
//   State<MyHomePage> createState() => _MyHomePageState();
// }

class MyHomePage extends StatefulWidget {
  MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

Widget hhhLoader({double size = 50}) {
  return Expanded(
      child: Container(
          color: Colors.white,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Stack(alignment: Alignment.center, children: [
              Center(
                  child: Padding(
                      padding: EdgeInsets.only(right: 0.25 * size / 10),
                      child: Text(
                        textAlign: TextAlign.center,
                        "HHH",
                        style: TextStyle(
                            fontSize: size / 10,
                            color: Colors.lightBlue.shade200,
                            fontStyle: FontStyle.italic,
                            decoration: TextDecoration.none,
                            fontWeight: FontWeight.bold),
                      ))),
              Center(
                  child: Padding(
                      padding: EdgeInsets.all(size / 10),
                      child: GFLoader(
                        type: GFLoaderType.ios,
                        size: size,
                        loaderstrokeWidth: 4.0,
                      )))
            ])
          ])));
}

class _MyHomePageState extends State<MyHomePage> {
  late Future<AppInitParams> futureHHHDefaults;

  @override
  State<MyHomePage> createState() => _MyHomePageState();

  @override
  void initState() {
    super.initState();
    futureHHHDefaults = perform_app_init();
  }

  @override
  Widget build(BuildContext context) {
    var topLeftTitle = "HHH"; // Platform.isAndroid ? "HHH" : "HandHeld Helper";
    return FutureBuilder<AppInitParams>(
      future: futureHHHDefaults,
      builder: (BuildContext context, AsyncSnapshot<AppInitParams> snapshot) {
        if (true && snapshot.connectionState == ConnectionState.waiting) {
          return hhhLoader(
              size: MediaQuery.of(context).size.shortestSide * 0.65);
        } else if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        } else {
          return MyHomePageContent(
              title: widget.title,
              appInitParams: snapshot.data as AppInitParams);
        }
      },
    );
  }
}

class MyHomePageContent extends StatefulWidget {
  MyHomePageContent(
      {Key? key, required this.title, required this.appInitParams})
      : super(key: key);

  final String title;
  final AppInitParams appInitParams;

  @override
  State<MyHomePageContent> createState() => _MyHomePageContentState();
}

const WorkspaceRoot = "HHH";

// String resolve_llm_file(
//     {String llm_file = "openhermes-2-mistral-7b.Q4_K_M.gguf"}) {
//   List<String> paths = [];
//
//   String userDataRoot = ".";
//
//   if (Platform.isMacOS || Platform.isLinux) {
//     userDataRoot = Platform.environment["HOME"] ?? "";
//   } else if (Platform.isAndroid) {
//     // String internalStoragePrefix = "/data/user/0/<package_name>/files/";
//     // const String externalStoragePrefix = "/storage/emulated/0/";
//     userDataRoot = Path.join("/storage/emulated/0/", WorkspaceRoot);
//   }
//
//   paths.add(Path.join(userDataRoot, llm_file));
//   paths.add(String.fromEnvironment("MODELPATH") ?? "");
//   paths.add(Platform.environment["MODELPATH"] ?? "");
//   paths.add(Path.join(".", llm_file));
//
//   for (var p in paths) {
//     if (p.isNotEmpty && File(p).existsSync()) {
//       dlog("MODEL: probing $p");
//       return p;
//     }
//   }
//
//   throw FileSystemException("File not found", llm_file);
// }

String truncateWithEllipsis(int cutoff, String myString) {
  return (myString.length <= cutoff)
      ? myString
      : '${myString.substring(0, cutoff)}...';
}

const hermes_sysmsg =
    "You are a helpful, honest, reliable and smart AI assistant named Hermes doing your best at fulfilling user requests. You are cool and extremely loyal. You answer any user requests to the best of your ability.";

class Settings {
  int _msg_poll_ms = 20;
}

Map<String, dynamic> resolve_init_json() {
  var s = String.fromEnvironment("LLAMA_INIT_JSON") ?? "";
  if (s.isNotEmpty) {
    return jsonDecode(s);
  }

  s = Platform.environment["LLAMA_INIT_JSON"] ?? "";
  if (s.isNotEmpty) {
    return jsonDecode(s);
  }

  s = "./llama_init.json";
  dlog("MODEL: probing $s");
  if (File(s).existsSync()) {
    return jsonDecode(File(s).readAsStringSync());
  }

  return {};
}

void Function(Object?) dlog = (Object? args) {};

// class CollapsibleWidget extends StatefulWidget {
//   final Widget collapsedChild;
//   final Widget expandedChild;
//   final bool blockParentCollapse;
//
//   CollapsibleWidget(
//       {required this.collapsedChild,
//       required this.expandedChild,
//       this.blockParentCollapse = false});
//
//   @override
//   _CollapsibleWidgetState createState() => _CollapsibleWidgetState();
// }
//
// class _CollapsibleWidgetState extends State<CollapsibleWidget> {
//   bool isExpanded = false;
//
//   @override
//   Widget build(BuildContext context) {
//     return GestureDetector(
//       onTap: () {
//         if (widget.blockParentCollapse && isExpanded) {
//           return;
//         }
//         setState(() {
//           isExpanded = !isExpanded;
//         });
//       },
//       child: isExpanded ? widget.expandedChild : widget.collapsedChild,
//     );
//   }
// }

class CollapsibleWidget extends StatefulWidget {
  final Widget collapsedChild;
  final Widget expandedChild;
  final bool blockParentCollapse;
  final bool crossCircle; // New user argument
  final double crossCircleDiameter = 32;
  Function()? onExpand;
  Function()? onCollapse;

  CollapsibleWidget(
      {required this.collapsedChild,
      required this.expandedChild,
      this.onExpand,
      this.onCollapse,
      this.blockParentCollapse = false,
      this.crossCircle = false}); // User argument is now required

  @override
  _CollapsibleWidgetState createState() => _CollapsibleWidgetState();
}

class _CollapsibleWidgetState extends State<CollapsibleWidget> {
  bool isExpanded = false;

  @override
  Widget build(BuildContext context) {
    var child = isExpanded ? widget.expandedChild : widget.collapsedChild;
    // if (isExpanded && widget.crossCircle) {
    //   child = Padding(
    //       padding: EdgeInsets.fromLTRB(0, widget.crossCircleDiameter + 8, 0, 0),
    //       child: child);
    // }
    return Stack(
      children: <Widget>[
        GestureDetector(
          onTap: () {
            if (widget.blockParentCollapse && isExpanded) {
              return;
            }
            if (isExpanded && widget.crossCircle) {
              return;
            }
            if (!isExpanded && widget.onExpand != null) {
              widget.onExpand!();
            }
            if (isExpanded && widget.onCollapse != null) {
              widget.onCollapse!();
            }
            setState(() {
              isExpanded = !isExpanded;
            });
          },
          child: child,
        ),
        if (isExpanded &&
            widget
                .crossCircle) // Check if the widget is expanded and user argument is provided
          Positioned(
            top: 20,
            right: 10,
            child: Container(
              width: widget.crossCircleDiameter, // Set the size of the circle
              height: widget.crossCircleDiameter,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red, // Set the color of the circle
              ),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    isExpanded = false;
                    if (widget.onCollapse != null) {
                      widget.onCollapse!();
                    }
                  });
                },
                child: const MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Icon(Icons.close)), // Cross icon
              ),
            ),
          ),
      ],
    );
  }
}

const colorBlueSelected = Color.fromRGBO(191, 238, 234, 1.0);

Widget plainOutlile(Widget w) => Container(
      padding: EdgeInsets.all(0.0),
      margin: EdgeInsets.symmetric(vertical: 12.0, horizontal: 0.0),
      decoration: BoxDecoration(
        color: colorBlueSelected,
        borderRadius: BorderRadius.circular(24.0),
      ),
      child: w,
    );

class HoverableText extends StatefulWidget {
  final Widget child;
  Function()? onTap;

  HoverableText({required this.child, Function()? onTap});

  @override
  _HoverableTextState createState() => _HoverableTextState();
}

class _HoverableTextState extends State<HoverableText> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          setState(() {
            _isHovering = true;
          });
        },
        onExit: (_) {
          setState(() {
            _isHovering = false;
          });
        },
        child: Container(
          padding: EdgeInsets.all(0.0),
          margin: EdgeInsets.symmetric(vertical: 12.0, horizontal: 0.0),
          decoration: BoxDecoration(
            color: _isHovering
                ? colorBlueSelected
                : Colors.lightBlueAccent.shade100,
            borderRadius: BorderRadius.circular(24.0),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

const BTN_DISABLED_SHADE = 200;

class EnabledButton extends StatelessWidget {
  final bool isDisabled;
  final String disabledText;
  final Widget child;

  EnabledButton(
      {required this.isDisabled,
      required this.disabledText,
      required this.child});

  final btnDisabledCol = Color.fromRGBO(
      BTN_DISABLED_SHADE, BTN_DISABLED_SHADE, BTN_DISABLED_SHADE, 1.0);

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        primary: Colors.lightGreen, // Text color when enabled
        side: BorderSide(color: Colors.lightGreen), // Border color when enabled
      ).merge(
        ButtonStyle(
          padding: MaterialStateProperty.all<EdgeInsets>(
            EdgeInsets.all(20.0), // Padding for all states
          ),
          backgroundColor: MaterialStateProperty.resolveWith<Color>(
            (Set<MaterialState> states) {
              if (states.contains(MaterialState.disabled)) {
                return btnDisabledCol; // Text color when disabled
              }
              return Colors.green; // Text color when enabled
            },
          ),
          foregroundColor: MaterialStateProperty.resolveWith<Color>(
            (Set<MaterialState> states) {
              if (states.contains(MaterialState.disabled)) {
                return Colors.grey; // Text color when disabled
              }
              return Colors.white; // Text color when enabled
            },
          ),
          side: MaterialStateProperty.resolveWith<BorderSide>(
            (Set<MaterialState> states) {
              if (states.contains(MaterialState.disabled)) {
                return BorderSide(
                    color: Colors.grey); // Border color when disabled
              }
              return BorderSide(
                  color: Colors.lightGreen); // Border color when enabled
            },
          ),
        ),
      ),
      onPressed: isDisabled
          ? null // Button is disabled
          : () {
              Navigator.pushNamed(context, '/chat/main'); // Open chat route
            },
      child: isDisabled
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              child,
              Text(
                disabledText,
                style: TextStyle(color: Colors.grey, fontSize: 12),
              )
            ])
          : child, // No text when button is enabled
    );
  }
}

enum Status { initial, succeeded, failed }

class CustomFilePicker extends StatefulWidget {
  final String label;
  final String name;
  final bool isDirectoryPicker;
  final Future<bool> Function(String path)? execAdditionalFileCheck;

  CustomFilePicker({
    required this.label,
    required this.name,
    required this.isDirectoryPicker,
    this.execAdditionalFileCheck,
  });

  @override
  _CustomFilePickerState createState() => _CustomFilePickerState();
}

class _CustomFilePickerState extends State<CustomFilePicker> {
  String _path = '';
  bool _succeeded = false;
  Status _status = Status.initial;
  bool _isLoading = false;
  TextEditingController _controller = TextEditingController();

  Future<void> _pickFileOrDirectory() async {
    setState(() {
      _isLoading = true;
    });

    String? path;
    try {
      if (widget.isDirectoryPicker) {
        path = await FilePicker.platform.getDirectoryPath();
      } else {
        FilePickerResult? result = await FilePicker.platform.pickFiles();
        path = result?.files.single.path;
      }
    } catch (e) {
      print(e);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }

    if (path != null) {
      setState(() {
        _controller.text = path!;
        _path = path!;
      });
      _checkFileOrDirectoryExists();
    }
  }

  Future<void> _checkFileOrDirectoryExists() async {
    bool exists = await (widget.isDirectoryPicker
        ? Directory(_path).exists()
        : File(_path).exists());
    if (exists && widget.execAdditionalFileCheck != null) {
      exists = await widget.execAdditionalFileCheck!(_path);
    }

    setState(() {
      _succeeded = exists;
      _status = exists ? Status.succeeded : Status.failed;
    });
  }

  @override
  Widget build(BuildContext context) {
    var fileOrDir = widget.isDirectoryPicker ? "directory" : "file";
    return Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        decoration: BoxDecoration(
          color: _succeeded ? Colors.lightGreen[100] : Colors.red[50],
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        child: Row(
          children: [
            Expanded(
              child: FastTextField(
                  builder: (FormFieldState<String> field) {
                    return TextField(
                      controller: _controller,
                      onChanged: (value) {
                        field.didChange(value);
                      },
                      decoration: InputDecoration(
                        labelStyle: TextStyle(
                            fontSize: 20,
                            color: _succeeded
                                ? Colors.green.shade400
                                : Colors.red),
                        labelText: widget.label,
                        hintText: widget.isDirectoryPicker
                            ? 'Pick directory'
                            : 'Pick file',
                        fillColor: _succeeded
                            ? Colors.lightGreen
                            : Colors.red.shade100,
                      ),
                    );
                  },
                  name: widget.name,
                  labelText: widget.label,
                  placeholder: 'Pick $fileOrDir or enter path manually',
                  inputFormatters: const [],
                  style: TextStyle(
                    color: _status == Status.succeeded
                        ? Colors.lightGreen
                        : _status == Status.failed
                            ? Colors.redAccent
                            : Colors.grey,
                  ),
                  onChanged: (value) {
                    if (value != null) {
                      _path = value;
                      _checkFileOrDirectoryExists();
                    }
                  }),
            ),
            ElevatedButton(
              onPressed: _isLoading ? null : _pickFileOrDirectory,
              style: ElevatedButton.styleFrom(
                primary: _status == Status.succeeded
                    ? Colors.lightGreen
                    : _status == Status.failed
                        ? Colors.redAccent
                        : Colors.grey[300],
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20.0,
                      width: 20.0,
                      child: CircularProgressIndicator(),
                    )
                  : Text(
                      widget.isDirectoryPicker ? 'Open directory' : 'Open file',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
            ),
          ],
        ));
  }
}

class CheckmarkedTextRow extends StatelessWidget {
  final bool success;
  final bool failure;
  final String text;
  final String? retryLabel;
  final VoidCallback? retryFn;
  final bool showIcon;
  Widget? customChild;

  CheckmarkedTextRow(
      {required this.success,
      this.failure = false,
      this.text = "<no_text_set>",
      this.customChild,
      this.showIcon = true,
      this.retryLabel,
      this.retryFn});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: success
            ? Colors.green[200]
            : (failure ? Colors.red[50] : Colors.blueGrey[50]),
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: (customChild != null)
                ? customChild!
                : Text(
                    text,
                    style: TextStyle(color: Colors.black),
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          if (failure && retryFn != null)
            IconButton(
              icon: Icon(Icons.refresh),
              onPressed: retryFn,
              color: Colors.black,
            ),
          if (showIcon)
            Icon(
              success ? Icons.check : (failure ? Icons.close : Icons.remove),
              color: success
                  ? Colors.green
                  : (failure ? Colors.red : Colors.black),
            ),
          if (failure && retryLabel != null)
            TextButton(
              child: Text(retryLabel!),
              onPressed: retryFn,
              style: TextButton.styleFrom(
                primary: Colors.black,
              ),
            ),
        ],
      ),
    );
  }
}

// class CheckmarkedTextRow extends StatelessWidget {
//   final bool success;
//   final bool failure;
//   final String text;
//
//   CheckmarkedTextRow(
//       {required this.success, this.failure = false, required this.text});
//
//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
//       decoration: BoxDecoration(
//         color: success
//             ? Colors.green[50]
//             : (failure ? Colors.red[50] : Colors.blueGrey[50]),
//         borderRadius: BorderRadius.all(Radius.circular(8)),
//       ),
//       child: Row(
//         children: <Widget>[
//           Expanded(
//             child: Text(
//               text,
//               style: TextStyle(color: Colors.black),
//               overflow: TextOverflow.ellipsis,
//             ),
//           ),
//           Icon(
//             success ? Icons.check : (failure ? Icons.close : Icons.remove),
//             color: Colors.black,
//           ),
//         ],
//       ),
//     );
//   }
// }

class AppSetupForm extends StatefulWidget {
  final HHHDefaults resolved_defaults;
  void Function(RootAppParams rp) onSetupComplete;

  @override
  _AppSetupForm createState() => _AppSetupForm();

  AppSetupForm(
      {Key? key,
      required this.resolved_defaults,
      required this.onSetupComplete});
}

const HHH_MODEL_SUBDIR = "Models";

class _AppSetupForm extends State<AppSetupForm> {
  double btnFontSize = 20;
  bool canUserAdvance = false;
  bool remind_storage_permissions = true;
  bool _downloadCanStart = false;
  bool _downloadNecessary = true;
  bool _downloadSucceeded = false;
  bool _downloadFailed = false;
  bool _downloadCheckedOK = false;
  bool _downloadCheckFailed = false;

  bool _couldNotCreateDirectory = false;
  Color btnTextColor = Colors.grey;
  String? _file;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    btnTextColor = canUserAdvance ? Colors.lightGreenAccent : Colors.grey;
  }

  _resetOneClickState() {
    bool _downloadCanStart = false;
    bool _downloadNecessary = true;
    bool _downloadSucceeded = false;
    bool _downloadFailed = false;
    bool _downloadCheckedOK = false;
    bool _downloadCheckFailed = false;
  }

  _oneClickInstallInit() async {
    final hhh_dir = widget.resolved_defaults.hhh_dir;
    // final llm_url = widget.resolved_defaults.llm_url;

    var exists = true;

    for (var dir in [hhh_dir, Path.join(hhh_dir, HHH_MODEL_SUBDIR)]) {
      await Directory(dir).create(recursive: true);
      exists &= await Directory(dir).exists();
    }

    // TODO: attempt to copy/move the LLM checkpoint from user's Downloads
    var llm_file_ok = await _checkLLMfile();
    setState(() {
      _downloadCanStart = exists;
      _downloadNecessary = !llm_file_ok;
      if (!exists) {
        _couldNotCreateDirectory = true;
      }
      if (!_downloadNecessary) {
        _oneClickInstallCheckLLM();
      }
    });
  }

  Future<bool> _checkLLMfile() async {
    final hhh_dir = widget.resolved_defaults.hhh_dir;

    final llm_url = widget.resolved_defaults.llm_url;
    final llm_size = widget.resolved_defaults.llm_size;
    final hhh_llm_dl_path = attemptResolveSymlink(Path.join(
        widget.resolved_defaults.hhh_dir,
        HHH_MODEL_SUBDIR,
        Path.basename(llm_url)));

    var llm_file_exists = await File(hhh_llm_dl_path).exists();
    var llm_file_can_be_opened = false;
    try {
      var f = File(hhh_llm_dl_path).openSync(mode: FileMode.read);
      print("FREAD: $hhh_llm_dl_path => ${f.read(4).toString()}");
      llm_file_can_be_opened = true;
    } catch (e) {
      print("ERROR: CANNOT OPEN AND READ LLM FILE AT $hhh_llm_dl_path, $e");
    }
    if (!llm_file_can_be_opened) {
      print("ERROR: CANNOT OPEN AND READ LLM FILE AT $hhh_llm_dl_path");
      // TODO: Backtrack to a safer llm file location
    }

    if (!(llm_file_exists && llm_file_can_be_opened)) return false;
    var llm_file_size = await File(hhh_llm_dl_path).length();

    print(
        "_checkLLMfile hhh_llm_dl_path = $hhh_llm_dl_path llm_file_exists = $llm_file_exists llm_file_size = $llm_file_size");

    var llm_file_ok = llm_file_exists && (llm_file_size == llm_size);

    return llm_file_ok;
  }

  RootAppParams _getOneClickRootAppParams() {
    final hhh_dir = widget.resolved_defaults.hhh_dir;

    final llm_url = widget.resolved_defaults.llm_url;
    final llm_size = widget.resolved_defaults.llm_size;
    final hhh_llm_dl_path = Path.join(widget.resolved_defaults.hhh_dir,
        HHH_MODEL_SUBDIR, Path.basename(llm_url));

    return RootAppParams(hhh_dir, Path.basename(hhh_llm_dl_path),
        [Path.join(hhh_dir, HHH_MODEL_SUBDIR)]);
  }

  _oneClickInstallCheckLLM() async {
    var llm_file_ok = await _checkLLMfile();
    setState(() {
      _downloadCheckedOK = llm_file_ok;
      _downloadCheckFailed = !llm_file_ok;
      Timer(Duration(milliseconds: 500), () {
        widget.onSetupComplete(_getOneClickRootAppParams());
      });
    });
  }

  _updateAdvancedForm(Map<String, dynamic> f) {
    if (f['hhh_dir'] is String) {}
  }

  @override
  Widget build(BuildContext context) {
    final platform_requires_storage_permissions =
        Platform.isMacOS || Platform.isAndroid;

    var largeBtnFontStyle =
        TextStyle(fontSize: btnFontSize, color: Colors.blue);

    final hhh_dir = widget.resolved_defaults.hhh_dir;
    final hhh_model_dir =
        Path.join(widget.resolved_defaults.hhh_dir, HHH_MODEL_SUBDIR);
    final llm_url = widget.resolved_defaults.llm_url;
    final llm_size = widget.resolved_defaults.llm_size;
    final hhh_llm_dl_path = Path.join(widget.resolved_defaults.hhh_dir,
        HHH_MODEL_SUBDIR, Path.basename(llm_url));

    var mainPadding = Platform.isAndroid
        ? EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0)
        : EdgeInsets.fromLTRB(48.0, 24.0, 48.0, 24.0);

    return Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height - 100,
        ),
        // height: MediaQuery.of(context).size.height,
        margin: EdgeInsets.all(48.0),
        decoration: BoxDecoration(
          color: Colors.blue[100],
          borderRadius: BorderRadius.all(Radius.circular(30)),
        ),
        child: SingleChildScrollView(
            child: Padding(
                padding: mainPadding,
                child: FastForm(
                    formKey: _formKey,
                    onChanged: (m) {
                      print("SETUP FORM: ${jsonEncode(m)}");
                      _updateAdvancedForm(m);
                    },
                    children: <Widget>[
                      const Text(
                        'Welcome 👋💠',
                        style: TextStyle(fontSize: 48),
                      ),
                      Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 0, vertical: 12),
                          child: Text(
                            '''HandHeld Helper is a fast and lean app allowing you to run LLM AIs locally, on your device.
HHH respects your privacy: once the LLM is downloaded, it works purely offline and never shares your data.
LLM checkpoints are large binary files. To download, store, manage and operate them, the app needs certain permissions, as well as network bandwidth and storage space – currently 4.1 GB for a standard 7B model.''',
                            textAlign: TextAlign.left,
                            style: TextStyle(fontSize: btnFontSize),
                          )),
                      if (remind_storage_permissions &&
                          platform_requires_storage_permissions)
                        HoverableText(
                            child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 24.0, horizontal: 24.0),
                          child: Row(children: [
                            Expanded(
                                child: Text(
                              'Please accept data storage permissions.',
                              style: largeBtnFontStyle,
                            )),
                            const Icon(Icons.check,
                                size: 32, color: Colors.grey),
                          ]),
                        )),
                      CollapsibleWidget(
                          crossCircle: true,
                          onExpand: () {
                            print("START HTTP DOWNLOAD SEQUENCE");
                            _oneClickInstallInit();
                          },
                          onCollapse: () {
                            print("CLOSE HTTP DOWNLOAD SEQUENCE");
                            _resetOneClickState();
                          },
                          collapsedChild: HoverableText(
                              child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 24.0, horizontal: 24.0),
                            child: Row(children: [
                              Expanded(
                                  child: Text(
                                'Accept the data storage defaults and download the recommended LLM ($DEFAULT_LLM_NAME)',
                                style: largeBtnFontStyle,
                              )),
                              const Icon(Icons.download_for_offline,
                                  size: 32, color: Colors.grey),
                            ]),
                          )),
                          expandedChild: plainOutlile(
                            Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 44.0, horizontal: 24.0),
                                child: Column(children: [
                                  Row(children: [
                                    Expanded(
                                        child: Text(
                                      'Accept the data storage defaults and download the default LLM ($DEFAULT_LLM_NAME)',
                                      style: largeBtnFontStyle,
                                    )),
                                    const Icon(Icons.download_for_offline,
                                        size: 32, color: Colors.grey),
                                  ]),
                                  const SizedBox(height: 12.0),
                                  CheckmarkedTextRow(
                                      text: "The directory $hhh_dir exists",
                                      success: _downloadCanStart,
                                      failure: _couldNotCreateDirectory),
                                  const SizedBox(height: 12.0),
                                  if (_downloadCanStart) ...[
                                    if (_downloadNecessary) ...[
                                      CheckmarkedTextRow(
                                          success: _downloadSucceeded,
                                          failure: _downloadFailed,
                                          customChild: HttpDownloadWidget(
                                              url: llm_url,
                                              // 'https://example.com/index.html'
                                              destinationPath: hhh_llm_dl_path,
                                              onDownloadEnd: (success, b, c) {
                                                if (success) {
                                                  _downloadSucceeded = true;
                                                  print("CHECKING LLM FILE...");
                                                  _oneClickInstallCheckLLM();
                                                } else {
                                                  _downloadFailed = true;
                                                }
                                              },
                                              textStyle: TextStyle(
                                                  fontSize: btnFontSize * 0.8,
                                                  color: largeBtnFontStyle
                                                      .color))),
                                      SizedBox(height: 12.0)
                                    ],
                                    CheckmarkedTextRow(
                                        text: "LLM checkpoint is available",
                                        success: _downloadCheckedOK,
                                        failure: _downloadCheckFailed),
                                  ]
                                ])),
                          )),
                      CollapsibleWidget(
                          crossCircle: true,
                          collapsedChild: HoverableText(
                              child: Padding(
                            padding: EdgeInsets.symmetric(
                                vertical: 24.0, horizontal: 24.0),
                            child: Row(children: [
                              Expanded(
                                  child: Text(
                                      'Show advanced model & storage settings',
                                      style: TextStyle(
                                          fontSize: btnFontSize,
                                          color: Colors.blue))),
                              Icon(Icons.app_settings_alt,
                                  size: 32, color: Colors.grey),
                            ]),
                          )),
                          expandedChild: plainOutlile(
                            Padding(
                                padding: EdgeInsets.symmetric(
                                    vertical: 44.0, horizontal: 24.0),
                                child: Column(children: [
                                  Row(children: [
                                    Expanded(
                                        child: Text(
                                            'Advanced model & storage settings',
                                            style: TextStyle(
                                                fontSize: btnFontSize,
                                                color: Colors.blue))),
                                    Icon(Icons.app_settings_alt,
                                        size: 32, color: Colors.grey)
                                  ]),
                                  SizedBox(height: 16),
                                  CustomFilePicker(
                                      label: "HandHeld Helper root directory",
                                      name: "hhh_root",
                                      isDirectoryPicker: true),
                                  SizedBox(height: 16),
                                  CustomFilePicker(
                                      label: "Custom default LLM file (GGUF)",
                                      name: "custom_default_model",
                                      isDirectoryPicker: false),
                                  SizedBox(height: 16),
                                  CustomFilePicker(
                                      label: "Auxiliary custom model directory",
                                      name: "aux_model_root",
                                      isDirectoryPicker: true),
                                  SizedBox(height: 16),
                                  Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 0, vertical: 12),
                                      child: EnabledButton(
                                          isDisabled: !canUserAdvance,
                                          disabledText:
                                              'Complete the necessary steps',
                                          child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                // Expanded(child: Text('Start conversation')),
                                                Center(
                                                    child: Text(
                                                        'Start conversation',
                                                        style: TextStyle(
                                                            fontSize:
                                                                btnFontSize,
                                                            color:
                                                                btnTextColor))),
                                                Padding(
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                            horizontal: 8.0,
                                                            vertical: 0.0),
                                                    child: Icon(Icons.chat,
                                                        color: btnTextColor))
                                              ])))
                                ])),
                          )),
                    ]))));
  }
}

LLMEngine llm = LLMEngine();

class _MyHomePageContentState extends State<MyHomePageContent> {
  late ChatManager chatManager;

  late List<ChatMessage> _messages = [];
  List<ChatUser> _typingUsers = [];

  RootAppParams? _active_app_params;

  bool _msg_streaming = false;
  Timer? _msg_poll_timer;
  Settings settings = Settings();
  bool _initialized = false;
  Timer? _token_counter_sync;
  int _input_tokens = 0;

  Map<String, dynamic> llama_init_json = resolve_init_json();

  void lock_actions() {
    setState(() {
      print("ACTIONS LOCKED");
      _initialized = false;
    });
  }

  void unlock_actions() {
    setState(() {
      print("ACTIONS UNLOCKED");
      _initialized = true;
    });
  }

  _MyHomePageContentState() {
    // llama_init_json = resolve_init_json();
    // dlog("LLAMA_INIT_JSON: ${llama_init_json}");
    // dialog = LLMEngine(
    //     system_message: hermes_sysmsg,
    //     libpath: "librpcserver.dylib",
    //     modelpath: resolve_llm_file(),
    //     llama_init_json: llama_init_json,
    //     onInitDone: () {
    //       unlock_actions();
    //     });
    // _reset_msgs();
  }

  void reset_msgs() {
    setState(() {
      _reset_msgs();
    });
  }

  void _reset_msgs() {
    _messages = [
      ChatMessage(
        text:
            "Beginning of conversation with model at ${llm.modelpath}\nSystem prompt: $hermes_sysmsg",
        user: user_SYSTEM,
        createdAt: DateTime.now(),
      ),
    ];
  }

  void updateStreamingMsgView() {
    setState(() {
      var poll_result = llm.poll_advance_stream();
      var finished = poll_result.finished;

      if (finished) {
        _msg_poll_timer?.cancel();
        _msg_streaming = false;

        String upd_str = poll_result.joined();

        // if (upd_str.isNotEmpty) {
        //   stdout.write("$upd_str");
        // }

        var completedMsg = llm.msgs.last;

        _messages[0].createdAt = completedMsg.createdAt;
        _messages[0].text = completedMsg.content;

        _typingUsers = [];
      } else {
        _messages[0].text = llm.stream_msg_acc;
      }
    });
  }

  void addMsg(ChatMessage m, {use_polling = true}) {
    if (use_polling) {
      var success = llm.start_advance_stream(user_msg: m.text);
      _msg_streaming = true;

      setState(() {
        _typingUsers = [user_ai];
        _messages.insert(0, m);
        var msg = ChatMessage(
            user: user_ai,
            text: "...", // TODO animation
            createdAt: llm.msgs.last.createdAt);
        _messages.insert(0, msg);

        _msg_poll_timer = Timer.periodic(
            Duration(milliseconds: settings._msg_poll_ms), (timer) {
          updateStreamingMsgView();
        });
      });
    } else {
      setState(() {
        var success = llm.advance(user_msg: m.text);
        if (success) {
          _messages.insert(0, m);
          _messages.insert(
              0,
              ChatMessage(
                  user: user_ai,
                  text: llm.msgs.last.content,
                  createdAt: llm.msgs.last.createdAt));
          dlog("MSGS: ${_messages.map((m) => m.text)}");
        } else {
          _messages.insert(0, m);
          _messages.insert(
              0,
              ChatMessage(
                  user: user_SYSTEM,
                  text: "ERROR: ${llm.error}",
                  createdAt: DateTime.now()));
        }
      });
    }
  }

  void reload_model_from_file(String new_modelpath) async {
    setState(() {
      _initialized = false;
      _messages = [
        ChatMessage(
            user: user_SYSTEM,
            text: "... Loading new model from \"$new_modelpath\"",
            createdAt: DateTime.now())
      ];
    });

    llm.reinit(
        modelpath: new_modelpath,
        llama_init_json: resolve_init_json(),
        onInitDone: () {
          unlock_actions();
        });
    reset_msgs();
  }

  String serialize_msgs() {
    List<Map<String, String>> export_msgs =
        List.from(_messages.reversed.map((e) => <String, String>{
              'user': e.user.getFullName(),
              'text': e.text.toString(),
              'createdAt': e.createdAt.toString()
            }));
    const JsonEncoder encoder = JsonEncoder.withIndent('  ');
    return encoder.convert({
      'meta': {'model': llm.modelpath},
      'messages': export_msgs
    });
  }

  void _update_token_counter(String upd) {
    setState(() {
      _input_tokens = llm.measure_tokens(upd);
      dlog("LOG _update_token_counter $_input_tokens");
    });
  }

  RootAppParams? getAppInitParams() {
    if (_active_app_params != null) return _active_app_params;
    return widget.appInitParams.params;
  }

  bool app_setup_done() {
    var ret = getAppInitParams() != null;
    if (Platform.isAndroid) {
      var sp = widget.appInitParams.storagePermissionGranted;
      if (!sp) {
        print("SETUP INCOMPLETE: STORAGE PERMISSION NOT GRANTED");
        return false;
      }
    }
    return ret;
  }

  void initAIifNotAlready() {
    if (llm.init_in_progress || llm.initialized) return;
    if (llm.init_postponed && getAppInitParams() != null) {
      RootAppParams p = getAppInitParams()!;
      print("INITIALIZING NATIVE LIBRPCSERVER");
      if (Platform.isAndroid) requestStoragePermission();
      llm.reinit(
          modelpath: Path.join(p.hhh_dir, "Models", p.default_model),
          system_message: hermes_sysmsg,
          llama_init_json: resolve_init_json(),
          onInitDone: () {
            unlock_actions();
          });
    }
  }

  onAppSetupComplete(RootAppParams p) async {
    print("!!! SETUP COMPLETE, RECEIVED PARAMS: ${p.toJson()}");
    var metadb = MetadataManager();
    await metadb.setMetadata("root_app_params", jsonEncode(p.toJson()));
    widget.appInitParams.params = p;
    if (widget.appInitParams.params != null) {
      _active_app_params = widget.appInitParams.params;
    }
    setState(() {});
  }

  Widget buildAppSetupScreen() {
    // return Center(child: Text("Please setup the app"));
    return AppSetupForm(
      resolved_defaults: widget.appInitParams.defaults,
      onSetupComplete: onAppSetupComplete,
    );
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methodsdf
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.

    bool actionsEnabled = _initialized && !_msg_streaming;
    const Color disabledColor = Colors.white60;
    Color iconColor = actionsEnabled ? Colors.white : disabledColor;

    const Color warningColor = Colors.deepOrangeAccent;
    bool tokenOverload = (llm.tokens_used + _input_tokens) >= llm.n_ctx;

    Widget mainWidget;

    if (app_setup_done()) {
      initAIifNotAlready();
      mainWidget = Expanded(
        child: DashChat(
          inputOptions: InputOptions(
              // cursorStyle: CursorStyle({color: Color.fromRGBO(40, 40, 40, 1.0)}),
              sendOnEnter: false,
              sendOnShiftEnter: true,
              alwaysShowSend: true,
              inputToolbarMargin: EdgeInsets.all(8.0),
              inputDisabled: !(_initialized ?? false),
              onTextChange: (String upd) {
                dlog("LOG onTextChange $upd");
                if (_token_counter_sync != null) {
                  _token_counter_sync?.cancel();
                }
                _token_counter_sync =
                    Timer(const Duration(milliseconds: 300), () {
                  _update_token_counter(upd);
                });
              }),
          messageOptions: MessageOptions(
              messageTextBuilder: customMessageTextBuilder,
              showCurrentUserAvatar: false,
              showOtherUsersAvatar: false,
              onLongPressMessage: (m) {
                String msg = "${m.user.getFullName()}: ${m.text}";
                FlutterClipboard.copy(msg);
                final snackBar = SnackBar(
                  content: Text(
                      "Message \"${truncateWithEllipsis(16, msg)}\" copied to clipboard"),
                );
                ScaffoldMessenger.of(context).showSnackBar(snackBar);
              }),
          currentUser: user,
          typingUsers: _typingUsers,
          onSend: (ChatMessage m) {
            dlog("NEW MSG: ${m.text}");
            _input_tokens = 0;
            addMsg(m);
          },
          messages: _messages,
        ),
      );
      if (!_initialized) {
        mainWidget = Stack(
          children: <Widget>[
            // Your existing widget tree goes here
            const Center(
                child: Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 200, vertical: 200),
                    child: SizedBox(
                        width: 512,
                        child: GFLoader(
                          type: GFLoaderType.ios,
                          size: 50,
                          loaderstrokeWidth: 4.0,
                        )))),
            Container(
              color: Colors.black.withOpacity(0.5),
            ),
          ],
        );
      }
    } else {
      mainWidget = buildAppSetupScreen();
    }

    return Scaffold(
      appBar: AppBar(
          // TRY THIS: Try changing the color here to a specific color (to
          // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
          // change color while the other colors stay the same.
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          // Here we take the value from the MyHomePage object that was created by
          // the App.build method, and use it to set our appbar title.
          title: Row(children: [
            Expanded(
                child: Text(
              "${widget.title}",
              style:
                  TextStyle(color: Colors.white, fontStyle: FontStyle.italic),
            )),
            Text(
              "T:${llm.tokens_used + _input_tokens}/${llm.n_ctx}",
              style: TextStyle(
                  color: actionsEnabled
                      ? (tokenOverload ? warningColor : Colors.white)
                      : disabledColor),
            )
          ]),
          actions: <Widget>[
            IconButton(
                disabledColor: disabledColor,
                icon: Icon(
                  Icons.sync_alt,
                  color: iconColor,
                ),
                onPressed: actionsEnabled
                    ? () async {
                        FilePickerResult? result =
                            await FilePicker.platform.pickFiles();

                        if (result != null) {
                          File file = File(result.files.single.path ?? "");
                          if (file.existsSync()) {
                            var new_model = file.path;
                            dlog("RELOADING FROM $new_model");
                            reload_model_from_file(new_model);
                          }
                        } else {
                          // User canceled the picker
                        }
                      }
                    : null),
            IconButton(
              disabledColor: disabledColor,
              icon: Icon(
                Icons.restart_alt,
                color: iconColor,
              ),
              onPressed: actionsEnabled
                  ? () async {
                      llm.reset_msgs();
                      reset_msgs();
                    }
                  : null,
            ),
            IconButton(
              disabledColor: disabledColor,
              icon: Icon(
                Icons.ios_share,
                color: iconColor,
              ),
              onPressed: actionsEnabled
                  ? () {
                      FlutterClipboard.copy(serialize_msgs());

                      const snackBar = SnackBar(
                        content: Text('Conversation copied to clipboard'),
                      );

                      // Find the ScaffoldMessenger in the widget tree
                      // and use it to show a SnackBar.
                      ScaffoldMessenger.of(context).showSnackBar(snackBar);
                      Timer(Duration(milliseconds: 500), () {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      });
                    }
                  : null,
            )
          ],
          toolbarHeight: 48.0),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[mainWidget],
        ),
      ),
      // floatingActionButton: FloatingActionButton(
      //   onPressed: _incrementCounter,
      //   tooltip: 'Increment',
      //   child: const Icon(Icons.add),
      // ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}

void main(List<String> args) async {
  if ((Platform.environment["DEBUG"] ?? "").isNotEmpty) {
    dlog = print;
  }
  dlog("CMD ARGS: ${args.join(',')}");

  runApp(const MyApp());
}
