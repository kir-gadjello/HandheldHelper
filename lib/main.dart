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
import 'llm_engine.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_fast_forms/flutter_fast_forms.dart';
import 'package:getwidget/getwidget.dart';
import 'package:external_path/external_path.dart';
import 'util.dart';

final APP_TITLE = isMobile() ? "HHH" : "HandHeld Helper";

const actionIconSize = 38.0;
const actionIconPadding = EdgeInsets.symmetric(vertical: 0.0, horizontal: 2.0);

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

ChatUser getChatUserByName(String? name) {
  switch (name?.toLowerCase() ?? "") {
    case "system":
      return user_SYSTEM;
    case "user":
      return user;
    case "ai":
      return user_ai;

    default:
      return user;
  }
}

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

  String getFileName() {
    if (fileName != null) {
      return fileName!;
    }
    return Path.basename(sources
        .firstWhere((element) => element.startsWith(RegExp(r"https?://"))));
  }

  LLMref(
      {required this.sources,
      required this.name,
      required this.size,
      this.meta,
      this.fileName}) {
    if (fileName == null) {
      assert(sources.isNotEmpty);
      fileName = getFileName();
    }
  }
}

final APPROVED_LLMS = [
  LLMref(name: 'OpenHermes-2.5-Mistral-7B', size: 4368450304, sources: [
    "https://huggingface.co/TheBloke/OpenHermes-2.5-Mistral-7B-GGUF/resolve/main/openhermes-2.5-mistral-7b.Q4_K_M.gguf"
  ]),
  LLMref(name: 'OpenHermes-2-Mistral-7B', size: 4368450272, sources: [
    "https://huggingface.co/TheBloke/OpenHermes-2-Mistral-7B-GGUF/resolve/main/openhermes-2-mistral-7b.Q4_K_M.gguf"
  ]),
  LLMref(name: "TinyLLAMA-1t-OpenOrca", size: 667814368, sources: [
    "https://huggingface.co/TheBloke/TinyLlama-1.1B-1T-OpenOrca-GGUF/resolve/main/tinyllama-1.1b-1t-openorca.Q4_K_M.gguf"
  ])
];

const DEFAULT_LLM = 'OpenHermes-2.5-Mistral-7B';

final defaultLLM =
    APPROVED_LLMS.firstWhere((element) => element.name == DEFAULT_LLM);

class HHHDefaults {
  final String hhh_dir;
  final String llm_url;
  final String llm_filename;
  final int llm_size;

  HHHDefaults(this.hhh_dir, LLMref defaultLLM)
      : llm_url = defaultLLM.sources[0],
        llm_filename = defaultLLM.fileName!,
        llm_size = defaultLLM.size;

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

String resolve_llm_file(RootAppParams p) {
  var ret = Path.join(p.hhh_dir, "Models", p.default_model);
  final fcand = (String.fromEnvironment("MODELPATH") ?? "");
  final env_cand = (Platform.environment["MODELPATH"] ?? "");
  if (fcand.isNotEmpty && File(fcand).existsSync()) {
    print("OVERRIDING LLM PATH TO $fcand");
    ret = fcand;
  }
  if (env_cand.isNotEmpty && File(env_cand).existsSync()) {
    print("OVERRIDING LLM PATH TO $env_cand");
    ret = env_cand;
  }
  return ret;
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

  var hhhd = HHHDefaults(def_hhh_dir, defaultLLM);

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

Widget hhhLoader(BuildContext context, {double size = 50}) {
  var bgColor = Theme.of(context).listTileTheme.tileColor;
  var textColor = Theme.of(context).listTileTheme.textColor;

  return Container(
      color: bgColor,
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
                        color: textColor,
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
      ]));
}

class ActiveChatPage extends StatefulWidget {
  ActiveChatPage(
      {Key? key,
      required this.title,
      appInitParams,
      Function(AppPage)? this.navigate})
      : super(key: key);

  Function(AppPage)? navigate;
  final String title;
  AppInitParams? appInitParams;

  @override
  State<ActiveChatPage> createState() => _ActiveChatPageState();
}

class _ActiveChatPageState extends State<ActiveChatPage> {
  late Future<AppInitParams> futureHHHDefaults;

  @override
  State<ActiveChatPage> createState() => _ActiveChatPageState();

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
          return hhhLoader(context,
              size: MediaQuery.of(context).size.shortestSide * 0.65);
        } else if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        } else {
          return ActiveChatDialog(
              title: widget.title,
              appInitParams: snapshot.data as AppInitParams,
              navigate: widget.navigate);
        }
      },
    );
  }
}

class ActiveChatDialog extends StatefulWidget {
  ActiveChatDialog(
      {Key? key,
      required this.title,
      required this.appInitParams,
      this.navigate})
      : super(key: key);

  Function(AppPage)? navigate;
  final String title;
  final AppInitParams appInitParams;

  @override
  State<ActiveChatDialog> createState() => ActiveChatDialogState();
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

const hermes_sysmsg =
    "You are a helpful, honest, reliable and smart AI assistant named Hermes doing your best at fulfilling user requests. You are cool and extremely loyal. You answer any user requests to the best of your ability.";

class Settings {
  Map<String, dynamic> data = {'_msg_poll_ms': isMobile() ? 100 : 20};

  dynamic get(key, default_value) {
    if (data.containsKey(key)) {
      return data[key];
    }
    return default_value;
  }

  set(key, value) {
    data[key] = value;
  }
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

  Future<bool> _checkLLMfile(
      {try_downloads_dir = false, move_from_dir = false}) async {
    final hhh_dir = widget.resolved_defaults.hhh_dir;

    final llm_url = widget.resolved_defaults.llm_url;
    final llm_size = widget.resolved_defaults.llm_size;
    final hhh_llm_dl_path = attemptResolveSymlink(Path.join(
        widget.resolved_defaults.hhh_dir,
        HHH_MODEL_SUBDIR,
        Path.basename(llm_url)));

    if (try_downloads_dir) {
      // TODO
      print("Attempting to find LLM file at user Downloads directory");
    }

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
                                'Accept the data storage defaults and download the recommended LLM (${defaultLLM.name})',
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
                                      'Accept the data storage defaults and download the default LLM (${defaultLLM.name})',
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

// class ChatState {
//   final Chat chat_data;
//   final List<Message> msgs = [];
//   Map<String, dynamic>? meta;
//
//   bool _msg_streaming = false;
//   Timer? _msg_poll_timer;
//   bool _initialized = false;
//   Timer? _token_counter_sync;
//   int _input_tokens = 0;
//
//   ChatState(this.chat_data, {Map<String, dynamic>? meta});
//
//   advance_chat(String user_new_msg, LLMEngine llm, {streaming = true}) {
//     // void addMsg(ChatMessage m, {use_polling = true}) {
//     if (streaming) {
//       var success = llm.start_advance_stream(user_msg: user_new_msg);
//       _msg_streaming = true;
//
//       setState(() {
//         _typingUsers = [user_ai];
//         _messages.insert(0, m);
//         var msg = ChatMessage(
//             user: user_ai,
//             text: "...", // TODO animation
//             createdAt: llm.msgs.last.createdAt);
//         _messages.insert(0, msg);
//
//         _msg_poll_timer = Timer.periodic(
//             Duration(milliseconds: settings._msg_poll_ms), (timer) {
//           updateStreamingMsgView();
//         });
//       });
//     } else {
//       setState(() {
//         var success = llm.advance(user_msg: m.text);
//         if (success) {
//           _messages.insert(0, m);
//           _messages.insert(
//               0,
//               ChatMessage(
//                   user: user_ai,
//                   text: llm.msgs.last.content,
//                   createdAt: llm.msgs.last.createdAt));
//           dlog("MSGS: ${_messages.map((m) => m.text)}");
//         } else {
//           _messages.insert(0, m);
//           _messages.insert(
//               0,
//               ChatMessage(
//                   user: user_SYSTEM,
//                   text: "ERROR: ${llm.error}",
//                   createdAt: DateTime.now()));
//         }
//       });
//     }
//   }
//
//   abort() {}
// }

List<ChatMessage> dbMsgsToDashChatMsgs(List<Message> msgs) {
  return msgs
      .map((m) => ChatMessage(
          user: getChatUserByName(m.username),
          text: m.message,
          createdAt: DateTime.fromMillisecondsSinceEpoch(m.date * 1000)))
      .toList();
}

class ActiveChatDialogState extends State<ActiveChatDialog>
    with WidgetsBindingObserver {
  ChatManager chatManager = ChatManager();
  MetadataManager metaKV = MetadataManager();

  late List<ChatMessage> _messages = [];
  List<ChatUser> _typingUsers = [];

  RootAppParams? _active_app_params;

  bool _msg_streaming = false;
  Timer? _msg_poll_timer;
  Settings settings = Settings();
  bool _initialized = false;
  Timer? _token_counter_sync;
  int _input_tokens = 0;
  Chat? _current_chat;
  DateTime? _last_chat_persist;
  String _current_msg_input = "";

  Map<String, dynamic> llama_init_json = resolve_init_json();

  @override
  void initState() {
    super.initState();
    if (isMobile()) WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (isMobile() && state == AppLifecycleState.paused) {
      print("ANDROID: The app is about to be suspended, persisting...");
      _cancel_timers();
      persistState();
    }
  }

  @override
  void dispose() {
    print("ActiveChatDialogState: attempting to persist state...");
    _cancel_timers();
    persistState();
    super.dispose();
  }

  _cancel_timers() {
    if (_msg_poll_timer?.isActive ?? false) {
      print(
          "WARNING, PERSISTING DURING AI MESSAGE STREAMING, CANCELING POLLING");
      _msg_poll_timer?.cancel();
    }
  }

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

  /* TODO: add app level invariant check for message role order (for a hypothetical
      case where there the normal system->user->ai->user ... order breaks) */
  List<ChatMessage> msgs_fromJson(
      {String? jsonString, Map<String, dynamic>? jsonObject}) {
    Map<String, dynamic> jsonMap = {};
    if (jsonString != null) {
      // Parse the JSON string into a Map object
      Map<String, dynamic> jsonMap = jsonDecode(jsonString);
    } else if (jsonObject != null) {
      jsonMap = jsonObject;
    }
    if (jsonMap != null && jsonMap['messages'] is List) {
      // Extract the 'messages' key from the Map object

      List<dynamic> messagesJson = List<dynamic>.from(jsonMap['messages']);

      // Map each message in 'messagesJson' to a ChatMessage object
      List<ChatMessage> messages = [];
      for (var messageJson in messagesJson) {
        // Check if the message has the required fields
        if (messageJson.containsKey('user') &&
            messageJson.containsKey('text') &&
            messageJson.containsKey('createdAt')) {
          messages.add(ChatMessage(
            user: getChatUserByName(messageJson['user']) ?? user,
            text: messageJson['text'],
            createdAt: DateTime.parse(messageJson['createdAt']),
          ));
        }
      }

      // Reverse the list to maintain the original order of messages
      messages = messages.reversed.toList();

      return messages;
    }
    return [];
  }

  Map<String, dynamic> msgs_toJsonMap() {
    List<Map<String, String>> export_msgs =
        List.from(_messages.reversed.map((e) => <String, String>{
              'user': e.user.getFullName(),
              'text': e.text.toString(),
              'createdAt': e.createdAt.toString()
            }));
    var ret = {
      'meta': {'model': llm.modelpath},
      'messages': export_msgs
    };
    return ret;
  }

  String msgs_toJson({indent = true}) {
    var ret = msgs_toJsonMap();
    if (indent) {
      const JsonEncoder encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(ret);
    } else {
      return jsonEncode(ret);
    }
  }

  Map<String, dynamic> toJson() {
    var ret = {
      '_msg_streaming': _msg_streaming,
      '_initialized': _initialized,
      '_input_tokens': _input_tokens,
      '_last_chat_persist': _last_chat_persist?.millisecondsSinceEpoch ?? null,
      'chat_uuid': _current_chat?.uuid.toJson(),
    };

    if (_msg_streaming && llm.streaming) {
      ret['_ai_msg_stream_acc'] = _messages[0].text;
    }
    print("SERIALIZED_CHAT: $ret");
    return ret;
  }

  Future<bool> fromJson(Map<String, dynamic> json) async {
    if (json['chat_uuid'] != null) {
      _msg_streaming = json['_msg_streaming'] ?? false;
      _initialized = json['_initialized'] ?? false;
      _input_tokens = json['_input_tokens'] ?? 0;
      _last_chat_persist = (json['_last_chat_persist'] != null)
          ? DateTime.fromMillisecondsSinceEpoch(json['_last_chat_persist'])
          : null;

      var chat_uuid = Uuid.fromJson(json['chat_uuid']);
      print("CURRENT CHAT UUID: $chat_uuid");

      _current_chat = await chatManager.getChat(chat_uuid);
      if (_current_chat == null) {
        print("No chat retrieved");
        return false;
      }

      print("CURRENT CHAT UUID: ${_current_chat?.toJson()}");

      // var restored_messages = msgs_fromJson(jsonObject: json['messages']);
      var restored_messages = dbMsgsToDashChatMsgs(await chatManager
          .getMessagesFromChat(_current_chat!.uuid, reversed: true));

      if (restored_messages.isEmpty) {
        print("No messages retrieved");
        return false;
      }

      _messages = restored_messages;
      sync_messages_to_llm();
      return true;
    }
    return false;
  }

  void sync_messages_to_llm() {
    llm.msgs = _messages
        .map((m) => AIChatMessage(m.user.getFullName(), m.text))
        .toList();
  }

  Future<bool> persistState() async {
    try {
      _last_chat_persist = DateTime.now();
      var json = toJson();
      await metaKV.setMetadata("_persist_active_chat_state", json);
    } catch (e) {
      print("Exception in ActiveChatDialogState.persistState: $e");
      return false;
    }
    return true;
  }

  Future<bool> restoreState() async {
    // try {
    var data = await metaKV.getMetadata("_persist_active_chat_state");
    if (data == null) return false;
    var restored = false;

    try {
      restored = await fromJson(data);
    } catch (e) {
      print("Exception while restoring chat from db: $e");
      print("COULD NOT PARSE CHAT PERSIST STATE, CLEARING IT");
      await metaKV.deleteMetadata("_persist_active_chat_state");
    }

    if (!restored) {
      // TODO: cleaner rollback logic
      _msg_streaming = false;
      return false;
    } else {
      // The restored state might not have finished if the persist happened mid of
      // AI writing an answer, we must handle this case and might need to restart polling timer
      if (_msg_streaming) {
        var partial_answer = data['_ai_msg_stream_acc'];
        if (partial_answer is String && partial_answer.isNotEmpty) {
          print("RESTORING PARTIAL AI ANSWER...: $partial_answer");

          /* for now we just add this as a message with metadata _interrupted = true
          and restore the state to initial TODO ... */
          _msg_streaming = false;

          if (llm.streaming) {
            lock_actions();
            llm.clear_state(onComplete: () async {
              await addMessageToActiveChat("ai", partial_answer,
                  meta: {"_interrupted": true});
              unlock_actions();
            });
          } else {
            await addMessageToActiveChat("ai", partial_answer,
                meta: {"_interrupted": true});
            setState(() {});
          }
        }
      }
    }

    return true;
    // } catch (e) {
    //   print("Exception in ActiveChatDialogState.restoreState: $e");
    //   return false;
    // }
    // return true;
  }

  Future<void> create_new_chat() async {
    var firstMsg = ChatMessage(
      text:
          "Beginning of conversation with model at ${llm.modelpath}\nSystem prompt: ${settings.get('system_message', hermes_sysmsg)}",
      user: user_SYSTEM,
      createdAt: DateTime.now(),
    );

    _current_chat = await chatManager.createChat(
        firstMessageText: firstMsg.text, firstMessageUsername: "SYSTEM");

    _messages = [firstMsg];
    sync_messages_to_llm();

    setState(() {
      _msg_streaming = false;
      _input_tokens = 0;
      _last_chat_persist = null;
    });
  }

  Future<Chat> getCurrentChat() async {
    if (_current_chat != null) {
      return _current_chat!;
    } else {
      print("ERROR IN ADD MSG: NO ACTIVE CHAT, THIS SHOULD NOT HAPPEN");
      await create_new_chat();
      return _current_chat!;
    }
  }

  Future<void> addMessageToActiveChat(String username, String msg,
      {Map<String, dynamic>? meta}) async {
    Chat current = await getCurrentChat();
    chatManager.addMessageToChat(current.uuid, msg, username, meta: meta);
    var cmsg = ChatMessage(
        user: getChatUserByName(username),
        createdAt: DateTime.now(),
        text: msg);
    _messages.insert(0, cmsg);
  }

  Future<void> updateStreamingMsgView() async {
    Chat current = await getCurrentChat();

    var poll_result = llm.poll_advance_stream();
    var finished = poll_result.finished;

    if (finished) {
      var completedMsg = llm.msgs.last;
      chatManager.addMessageToChat(current.uuid, completedMsg.content, "AI");
      await metaKV.deleteMetadata("_msg_stream_in_progress_");
    } else {
      await metaKV.setMetadata("_msg_stream_in_progress_", llm.stream_msg_acc);
    }

    setState(() {
      if (finished) {
        _msg_poll_timer?.cancel();
        _msg_streaming = false;

        var completedMsg = llm.msgs.last;

        _messages[0].createdAt = completedMsg.createdAt;
        _messages[0].text = completedMsg.content;

        _typingUsers = [];
      } else {
        _messages[0].text = llm.stream_msg_acc;
      }
    });
  }

  _enable_stream_poll_timer() {
    _msg_poll_timer = Timer.periodic(
        Duration(milliseconds: settings.get("_msg_poll_ms", 100) as int),
        (timer) {
      updateStreamingMsgView();
    });
  }

  Future<void> addMsg(ChatMessage m, {Map<String, dynamic>? meta}) async {
    Chat current = await getCurrentChat();

    await chatManager.addMessageToChat(current.uuid, m.text, "user",
        meta: meta);
    await metaKV.setMetadata("_msg_stream_in_progress_", {
      'chat_uuid': current.uuid,
      'partial_msg': '',
    });

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
      _enable_stream_poll_timer();
    });
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
        onInitDone: () async {
          await create_new_chat();
          unlock_actions();
        });
    create_new_chat();
  }

  void _update_token_counter(String upd) {
    setState(() {
      _input_tokens = upd.isNotEmpty ? llm.measure_tokens(upd) : 0;
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

  void attemptToRestartChat() {
    print("ActiveChatDialogState: attempting to restore state...");
    restoreState().then((success) {
      if (!success) {
        print("[ERROR] RESTORE FAILED, CREATING NEW CHAT");
        create_new_chat();
      } else {
        print("[OK] RESTORE CHAT SUCCEEDED");
        print("Messages: ${msgs_toJson()}");
        setState(() {});
      }
    });
  }

  void initAIifNotAlready() {
    if (llm.init_in_progress) {
      print("initAIifNotAlready: llm.init_in_progress");
    } else if (!llm.initialized &&
        llm.init_postponed &&
        getAppInitParams() != null) {
      print("initAIifNotAlready: llm.init_postponed");
      RootAppParams p = getAppInitParams()!;
      print("INITIALIZING NATIVE LIBRPCSERVER");
      if (Platform.isAndroid) requestStoragePermission();
      llm.reinit(
          modelpath: resolve_llm_file(p),
          llama_init_json: resolve_init_json(),
          onInitDone: () {
            print("ActiveChatDialogState: attempting to restore state...");
            attemptToRestartChat();
            unlock_actions();
          });
    } else if (llm.initialized && !_initialized) {
      print("initAIifNotAlready: llm.initialized && !_initialized");
      // reentry
      attemptToRestartChat();
      unlock_actions();
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

  showModelSwitchMenu() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

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

  showSnackBarTop(String msg, {int delay = 750}) {
    var snackBar = SnackBar(
        duration: Duration(milliseconds: delay),
        behavior: SnackBarBehavior.floating,
        margin:
            EdgeInsets.only(bottom: MediaQuery.of(context).size.height - 96),
        content: Text(msg),
        dismissDirection: DismissDirection.none);

    // Find the ScaffoldMessenger in the widget tree
    // and use it to show a SnackBar.
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  executeChatShare() {
    FlutterClipboard.copy(msgs_toJson());
    showSnackBarTop('Conversation copied to clipboard');
  }

  reset_current_chat() async {
    llm.clear_state();
    create_new_chat();
  }

  stop_generation() {
    // TODO
  }

  show_settings_menu() {
    // TODO
  }

  final _scaffoldKey = new GlobalKey<ScaffoldState>();

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

    Color warningColor = Theme.of(context).colorScheme.error!;
    bool tokenOverload = (llm.tokens_used + _input_tokens) >= llm.n_ctx;

    Widget mainWidget;

    var activeColor = Theme.of(context).primaryColor;
    var bgColor = Theme.of(context).listTileTheme.tileColor;
    var textColor = Theme.of(context).listTileTheme.textColor;
    var hintColor = Theme.of(context).hintColor;
    Color headerTextColor = textColor!;

    if (app_setup_done()) {
      initAIifNotAlready();
      mainWidget = Expanded(
        child: DashChat(
          inputOptions: InputOptions(
              sendButtonBuilder: (Function fct) => InkWell(
                    onTap: () => fct(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                      child: Column(children: [
                        Icon(
                          size: 32,
                          Icons.send,
                          color: _current_msg_input.isNotEmpty
                              ? activeColor
                              : hintColor,
                        ),
                        if (_input_tokens > 0)
                          Text("$_input_tokens",
                              style: TextStyle(color: hintColor))
                      ]),
                    ),
                  ),
              // cursorStyle: CursorStyle({color: Color.fromRGBO(40, 40, 40, 1.0)}),
              sendOnEnter: false,
              sendOnShiftEnter: true,
              alwaysShowSend: true,
              inputToolbarMargin: EdgeInsets.all(0.0),
              inputToolbarPadding: EdgeInsets.fromLTRB(8.0, 2.0, 8.0, 4.0),
              inputMaxLines: 15,
              inputDecoration: InputDecoration(
                isDense: true,
                hintText: "Write a message to AI...",
                hintStyle: TextStyle(color: hintColor),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.only(
                  left: 18,
                  top: 10,
                  bottom: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: const BorderSide(
                    width: 0,
                    style: BorderStyle.none,
                  ),
                ),
              ),
              inputToolbarStyle:
                  BoxDecoration(borderRadius: BorderRadius.circular(0.0)),
              inputDisabled: !(_initialized ?? false),
              onTextChange: (String upd) {
                dlog("LOG onTextChange $upd");
                _current_msg_input = upd;
                if (_token_counter_sync != null) {
                  _token_counter_sync?.cancel();
                }
                _token_counter_sync =
                    Timer(const Duration(milliseconds: 300), () {
                  _update_token_counter(upd);
                });
              }),
          messageListOptions: MessageListOptions(),
          messageOptions: MessageOptions(
              containerColor: bgColor!,
              currentUserContainerColor: bgColor!,
              textColor: textColor!,
              currentUserTextColor: textColor!,
              messageTextBuilder: customMessageTextBuilder,
              showCurrentUserAvatar: false,
              showOtherUsersAvatar: false,
              onLongPressMessage: (m) {
                String msg = "${m.user.getFullName()}: ${m.text}";
                FlutterClipboard.copy(msg);
                showSnackBarTop(
                    "Message \"${truncateWithEllipsis(16, msg)}\" copied to clipboard");
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
      key: _scaffoldKey,
      drawer: _buildDrawer(context),
      appBar: AppBar(
          leading: IconButton(
            padding: actionIconPadding,
            icon: const Icon(Icons.menu,
                size: actionIconSize), // change this size and style
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          title: Row(children: [
            if (!isMobile())
              Expanded(
                  child: Text("HHH",
                      style: TextStyle(
                          color: headerTextColor,
                          fontStyle: FontStyle.italic,
                          fontSize: actionIconSize))),
            Text(
              "T:${llm.tokens_used + _input_tokens}/${llm.n_ctx}",
              style: TextStyle(
                  color: actionsEnabled
                      ? (tokenOverload ? warningColor : headerTextColor)
                      : disabledColor),
            )
          ]),
          actions: <Widget>[
            if (_msg_streaming)
              IconButton(
                padding: actionIconPadding,
                icon: Icon(
                  size: actionIconSize,
                  Icons.stop,
                  color: headerTextColor,
                ),
                onPressed: stop_generation,
              ),
            IconButton(
              padding: actionIconPadding,
              disabledColor: disabledColor,
              icon: Icon(
                size: actionIconSize,
                Icons.psychology_sharp,
                color: iconColor,
              ),
              onPressed: actionsEnabled ? show_settings_menu : null,
            ),
            IconButton(
              padding: actionIconPadding,
              disabledColor: disabledColor,
              icon: Icon(
                size: actionIconSize,
                Icons.restart_alt,
                color: iconColor,
              ),
              onPressed: actionsEnabled ? reset_current_chat : null,
            ),
            PopupMenuButton<String>(
              padding: actionIconPadding,
              iconSize: actionIconSize,
              onSelected: (item) {
                switch (item) {
                  case "model_switch":
                    if (actionsEnabled) showModelSwitchMenu();
                    break;
                  case "share":
                    executeChatShare();
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<String>(
                    value: "model_switch",
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.sync_alt,
                            color: Colors.black,
                          ),
                          Text("  Switch model")
                        ])),
                const PopupMenuItem<String>(
                    value: "share",
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.ios_share,
                            color: Colors.black,
                          ),
                          Text("  Share chat")
                        ])),
              ],
            ),
          ],
          toolbarHeight: 48.0),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
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

final SEARCH_THROTTLE = isMobile() ? 500 : 300;

class SearchPage extends StatefulWidget {
  Function(AppPage)? navigate;
  SearchPage({this.navigate});

  @override
  _SearchPageState createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final ChatManager _chatManager = ChatManager();
  Timer? _debounceTimer;
  Future<List<(Chat, Message)>>? _searchResults;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() async {
    if (_debounceTimer?.isActive ?? false) {
      _debounceTimer!.cancel();
    }
    _debounceTimer = Timer(Duration(milliseconds: SEARCH_THROTTLE), () async {
      if (_searchController.text.isNotEmpty) {
        setState(() {
          _searchResults = _chatManager.searchMessages(_searchController.text,
              prefixQuery: true);
        });
      } else {
        setState(() {
          _searchResults = null;
        });
      }
    });
  }

  Widget _buildSearchResults() {
    return FutureBuilder<List<(Chat, Message)>>(
      future: _searchResults,
      builder: (BuildContext context,
          AsyncSnapshot<List<(Chat, Message)>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return hhhLoader(context);
        } else if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        } else {
          return Padding(
              padding: EdgeInsets.symmetric(vertical: 2.0, horizontal: 0.0),
              child: ListView.builder(
                itemCount: snapshot?.data?.length ?? 0,
                itemBuilder: (context, index) {
                  final (chat, message) = snapshot.data![index];
                  return _buildSearchResultItem(chat, message);
                },
              ));
        }
      },
    );
  }

  Widget _buildSearchResultItem(Chat chat, Message message) {
    var bgColor = Theme.of(context).listTileTheme.tileColor;
    var textColor = Theme.of(context).listTileTheme.textColor;

    return Padding(
        padding: EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
        child: Container(
          constraints: isMobile()
              ? null
              : BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.33,
                ),
          decoration: BoxDecoration(
            // borderRadius: BorderRadius.circular(10.0),
            border: Border.all(color: Colors.grey),
          ),
          child: ListTile(
            tileColor: bgColor,
            textColor: textColor,
            minVerticalPadding: 2.0,
            contentPadding:
                EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
            title: Text(message.message),
            subtitle: Text(chat.getHeading()),
            onTap: () {
              // Callback with relevant chatId and messageId
            },
          ),
        ));
  }

  @override
  Widget build(BuildContext context) {
    var bgColor = Theme.of(context).scaffoldBackgroundColor;
    var textColor = Theme.of(context).listTileTheme.textColor;
    var hintColor = Theme.of(context).hintColor;

    return Scaffold(
      drawer: _buildDrawer(context),
      appBar: AppBar(
        backgroundColor: bgColor,
        title: TextField(
          style: TextStyle(color: textColor),
          cursorColor: textColor,
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search message history...',
            hintStyle: TextStyle(color: hintColor),
          ),
        ),
      ),
      body: _buildSearchResults(),
    );
  }
}

// class SearchResultBubble extends StatefulWidget {
//   final String searchQuery;
//   final String text;
//   final Color highlightColor;
//   final int maxNLines;
//   final Color backgroundColor;
//   final Color textColor;
//   final double textSize;
//   final Color hoverColor;
//
//   const SearchResultBubble({
//     Key? key,
//     required this.searchQuery,
//     required this.text,
//     this.highlightColor = Colors.yellow,
//     this.maxNLines = 5,
//     this.backgroundColor = Colors.white,
//     this.textColor = Colors.black,
//     this.textSize = 14.0,
//     this.hoverColor = Colors.grey,
//   }) : super(key: key);
//
//   @override
//   _SearchResultBubbleState createState() => _SearchResultBubbleState();
// }
//
// class _SearchResultBubbleState extends State<SearchResultBubble> {
//   String? _highlightedText;
//
//   @override
//   void initState() {
//     super.initState();
//     _highlightText();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return InkWell(
//       onTap: () {},
//       child: Container(
//         padding: EdgeInsets.symmetric(
//           vertical: 8.0,
//           horizontal: MediaQuery.of(context).size.width * 0.1,
//         ),
//         decoration: BoxDecoration(
//           color: widget.backgroundColor,
//           borderRadius: BorderRadius.circular(16.0),
//         ),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Text(
//               _highlightedText ?? "",
//               style: TextStyle(
//                 color: widget.textColor,
//                 fontSize: widget.textSize,
//               ),
//             ),
//             if (widget.maxNLines > 1) SizedBox(height: 4.0),
//             ...List.generate(
//               widget.maxNLines - 1,
//               (index) => Text(
//                 '...',
//                 style: TextStyle(
//                   color: widget.textColor,
//                   fontSize: widget.textSize,
//                 ),
//               ),
//             )
//           ],
//         ),
//       ),
//     );
//   }
//
//   void _highlightText() {
//     final RegExp regex = RegExp(widget.searchQuery, caseSensitive: false);
//     setState(() {
//       _highlightedText = widget.searchQuery;
//       if (regex.hasMatch(_highlightedText!)) {
//         _highlightedText = _highlightedText!.replaceAll(
//           regex.firstMatch(),
//           '<b style="color: ${widget.highlightColor}">${regex.firstMatch()}</b>',
//         );
//       }
//     });
//   }
// }
//
// class _SearchResultBubble2State extends State<SearchResultBubble2> {
//   Color _backgroundColor;
//
//   @override
//   void initState() {
//     super.initState();
//     _backgroundColor = widget.backgroundColor;
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return GestureDetector(
//       onTap: widget.onTap,
//       onTapDown: (_) => setState(() => _backgroundColor = widget.hoverColor),
//       onTapUp: (_) => setState(() => _backgroundColor = widget.backgroundColor),
//       onTapCancel: () =>
//           setState(() => _backgroundColor = widget.backgroundColor),
//       child: Container(
//         padding: widget.padding,
//         decoration: BoxDecoration(
//           color: _backgroundColor,
//           borderRadius: BorderRadius.circular(16.0),
//         ),
//         child: SelectableText(
//           widget.documentText
//               .replaceAll(widget.searchQuery, '**${widget.searchQuery}**'),
//           style: TextStyle(
//             color: widget.textColor,
//             fontSize: 16.0,
//           ),
//           onTap: () {},
//           selectionControls: MaterialSelectionControls(),
//           selectionColor: widget.highlightColor,
//           maxLines: widget.maxLines,
//           overflow: TextOverflow.ellipsis,
//         ),
//       ),
//     );
//   }
// }
//
// class SearchMessagesWidget extends StatefulWidget {
//   final ChatManager _chatManager;
//
//   SearchMessagesWidget(this._chatManager);
//
//   @override
//   _SearchMessagesWidgetState createState() => _SearchMessagesWidgetState();
// }
//
// class _SearchMessagesWidgetState extends State<SearchMessagesWidget> {
//   TextEditingController _searchController = TextEditingController();
//   FocusNode _searchFocusNode = FocusNode();
//   Timer? _debounce;
//   String _searchQuery = '';
//   bool _isLoading = false;
//   List<(Chat, Message)> _searchResults = [];
//
//   @override
//   void initState() {
//     super.initState();
//     _searchFocusNode.addListener(_onSearchFocusChange);
//   }
//
//   @override
//   void dispose() {
//     _searchController.dispose();
//     _searchFocusNode.dispose();
//     super.dispose();
//   }
//
//   void _onSearchFocusChange() {
//     setState(() {
//       if (_searchFocusNode.hasFocus) {
//         _searchQuery = _searchController.text;
//         if (_debounce?.isActive ?? false) _debounce!.cancel();
//         _debounce = Timer(const Duration(milliseconds: 300), () async {
//           setState(() => _isLoading = true);
//           final results = await widget._chatManager
//               .searchMessages(_searchQuery, prefixQuery: true);
//           setState(() {
//             _searchResults = results;
//             _isLoading = false;
//           });
//         });
//       }
//     });
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//           title: TextField(
//               controller: _searchController, focusNode: _searchFocusNode)),
//       body: Column(children: [
//         if (_isLoading) const Center(child: CircularProgressIndicator()),
//         Expanded(
//           child: ListView.builder(
//             itemCount: _searchResults.length + 1, // +1 for "No results" message
//             itemBuilder: (BuildContext context, int index) {
//               if (index == _searchResults.length) {
//                 return const ListTile(title: Text("No results"));
//               } else {
//                 final Chat chat = _searchResults[index].item1;
//                 final Message message = _searchResults[index].item2;
//                 return ListTile(
//                     title:
//                         Text(_chatMessagePreview(_searchQuery, chat, message)),
//                     onTap: () async {
//                       final chatId = chat.uuid;
//                       final messageId = message.uuid;
//                       final chat = await widget._chatManager.getChat(chatId);
//                       final messages =
//                           await widget._chatManager.getMessagesFromChat(chatId);
//                       if (chat != null && messages.isNotEmpty) {
//                         Navigator.of(context)
//                             .push(_createChatViewRoute(chat, messages));
//                       }
//                     });
//               }
//             },
//           ),
//         )
//       ]),
//     );
//   }
//
//   Route _createChatViewRoute(Chat chat, List<Message> messages) {
//     return PageRouteBuilder(
//         pageBuilder: (context, animation, secondaryAnimation) =>
//             ChatView(chat, messages),
//         transitionsBuilder: (context, animation, secondaryAnimation, child) =>
//             FadeTransition(opacity: animation, child: child),
//         transitionDuration: const Duration(milliseconds: 400));
//   }
//
//   String _chatMessagePreview(String searchQuery, Chat chat, Message message) {
//     final chatTitle = chat.title ??
//         'Chat from ${DateTime.fromMillisecondsSinceEpoch(chat.date * 1000)}';
//     final messageText = message.message;
//     final queryHighlightStart = messageText.indexOf(searchQuery);
//     final queryHighlightEnd = queryHighlightStart + searchQuery.length;
//     final chatNameAndTime =
//         '[$chatTitle] ${DateTime.fromMillisecondsSinceEpoch(message.date * 1000)}';
//     return '$chatNameAndTime\n$messageText\n'.replaceRange(queryHighlightStart,
//         queryHighlightEnd, '<highlight>$searchQuery</highlight>', 0);
//   }
// }

class LifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        print('App is resumed');
        break;
      case AppLifecycleState.paused:
        print('App is paused');
        break;
      case AppLifecycleState.inactive:
        print('App is inactive');
        break;
      case AppLifecycleState.detached:
        print('App is detached');
        break;
      case AppLifecycleState.hidden:
        print('App is hidden');
        break;
      default:
        print('AppLifecycleState: $state');
        break;
    }
  }
}

enum AppPage {
  conversation,
  settings,
  search,
  history,
  models,
  help,
}

String getPageName(AppPage page, {capitalize = false}) => capitalize
    ? capitalizeAllWord(page.toString().split(".").last)
    : page.toString().split(".").last;

AppPage global_current_page = AppPage.conversation;

List<AppPage> _app_pages = [
  AppPage.conversation,
  AppPage.search,
  AppPage.history,
  AppPage.settings,
  AppPage.models,
  AppPage.help,
];

class UnderConstructionWidget extends StatelessWidget {
  final String message;

  const UnderConstructionWidget(
      {Key? key, this.message = 'Under construction'});

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    var bgColor = Theme.of(context).appBarTheme.backgroundColor!;
    var fgColor = Theme.of(context).colorScheme.primary!;

    return Scaffold(
        drawer: _buildDrawer(context),
        appBar: AppBar(backgroundColor: bgColor),
        body: Container(
            width: screenWidth,
            child: Card(
              color: bgColor,
              margin: EdgeInsets.all(20.0),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      Icons.warning_rounded,
                      size: 50,
                      color: fgColor,
                    ),
                    SizedBox(height: 20),
                    Text(
                      message,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: fgColor,
                      ),
                    ),
                  ],
                ),
              ),
            )));
  }
}

Drawer _buildDrawer(BuildContext context) {
  final navigationProvider = NavigationProvider.of(context);
  final navigate = navigationProvider?.navigate;

  var bgColor = Theme.of(context).appBarTheme.backgroundColor!;
  var fgColor = Theme.of(context).appBarTheme.foregroundColor!;

  return Drawer(
      child: Container(
    color: bgColor,
    child: ListView(
      children: _app_pages.map((page) {
        final selected = page == global_current_page;
        final textStyle = TextStyle(
            color: selected
                ? fgColor
                : Theme.of(context).colorScheme.inversePrimary,
            fontSize: 28);
        return ListTile(
          selected: selected,
          titleTextStyle: textStyle,
          // tileColor: selected ? Colors.lightBlueAccent : Colors.white,
          title: Text(getPageName(page, capitalize: true)),
          onTap: () {
            if (navigate != null) {
              navigate(page);
            }
            Navigator.pop(context); // Close the drawer
          },
        );
      }).toList(),
    ),
  ));
}

class NavigationProvider extends InheritedWidget {
  final VoidCallback? onBeforeNavigate;
  Function(AppPage)? navigate;

  NavigationProvider({
    required Widget child,
    this.navigate,
    this.onBeforeNavigate,
  }) : super(child: child);

  static NavigationProvider? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<NavigationProvider>();
  }

  @override
  bool updateShouldNotify(NavigationProvider oldWidget) {
    return navigate != oldWidget.navigate ||
        onBeforeNavigate != oldWidget.onBeforeNavigate;
  }
}

class PseudoRouter extends StatefulWidget {
  final AppInitParams appInitParams;
  PseudoRouter(this.appInitParams);

  @override
  _PseudoRouter createState() => _PseudoRouter();
}

class _PseudoRouter extends State<PseudoRouter> {
  AppPage _currentPage = AppPage.conversation;

  void navigate(AppPage page, {VoidCallback? onBeforeNavigate}) {
    try {
      if (onBeforeNavigate != null) {
        onBeforeNavigate();
      }
      setState(() {
        global_current_page = page;
        _currentPage = page;
      });
    } catch (e) {
      print('Navigation error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return NavigationProvider(
      navigate: navigate,
      child: _buildPage(_currentPage),
    );
  }

  Widget _buildPage(AppPage page) {
    Widget currentPage;

    switch (page) {
      case AppPage.conversation:
        currentPage = ActiveChatPage(
            title: APP_TITLE, appInitParams: widget.appInitParams);
      case AppPage.settings:
        currentPage = UnderConstructionWidget();
      case AppPage.search:
        currentPage = SearchPage();
      case AppPage.history:
        currentPage = UnderConstructionWidget();
      case AppPage.help:
        currentPage = UnderConstructionWidget();
      case AppPage.models:
        currentPage = UnderConstructionWidget();
      default:
        currentPage = UnderConstructionWidget(message: "Unknown page");
    }

    return currentPage;
    // return PageRouteBuilder(
    //   pageBuilder: (context, animation, secondaryAnimation) => currentPage,
    //   transitionsBuilder: (context, animation, secondaryAnimation, child) {
    //     // Add your custom transition here
    //     var begin = Offset(0.0, 1.0);
    //     var end = Offset.zero;
    //     var curve = Curves.ease;
    //     var tween =
    //         Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
    //     return SlideTransition(
    //       position: animation.drive(tween),
    //       child: child,
    //     );
    //   },
    // ).pageBuilder(context);
  }
}

class AppStartup extends StatefulWidget {
  @override
  _AppStartupState createState() => _AppStartupState();
}

class _AppStartupState extends State<AppStartup> {
  Future? _appInitFuture;

  @override
  void initState() {
    super.initState();
    _appInitFuture = perform_app_init();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: _appInitFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return hhhLoader(context,
                size: MediaQuery.of(context).size.shortestSide * 0.65);
          }
          return PseudoRouter(snapshot.data!);
        });
  }
}

class HexColor extends Color {
  static int _getColorFromHex(String hexColor) {
    hexColor = hexColor.toUpperCase().replaceAll("#", "");
    if (hexColor.length == 6) {
      hexColor = "FF" + hexColor;
    }
    return int.parse(hexColor, radix: 16);
  }

  HexColor(final String hexColor) : super(_getColorFromHex(hexColor));
}

class HandheldHelper extends StatelessWidget {
  const HandheldHelper({super.key});

  ThemeData getAppTheme(BuildContext context, bool isDarkTheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: isDarkTheme
          ? ColorScheme.fromSeed(
              seedColor: Colors.deepOrange,
              primary: const Color.fromRGBO(255, 90, 0, 1.0),
              background: Colors.black,
              error: Colors.purple)
          : ColorScheme.fromSeed(
              seedColor: Colors.cyan.shade500,
              primary: Colors.cyan.shade100,
              background: Colors.white,
              error: Colors.purple),
      scaffoldBackgroundColor: isDarkTheme ? Colors.black : Colors.white,
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.all(
            isDarkTheme ? Colors.orange : Colors.purple),
      ),
      hintColor: const Color.fromRGBO(121, 107, 107, 1.0),
      listTileTheme: ListTileThemeData(
          iconColor: isDarkTheme ? Colors.orange : Colors.purple,
          textColor: isDarkTheme ? Colors.white : Colors.black,
          tileColor:
              isDarkTheme ? Colors.grey.shade900 : Colors.lightBlue.shade50),
      appBarTheme: AppBarTheme(
          backgroundColor:
              isDarkTheme ? Colors.grey.shade800 : Colors.lightBlue.shade600,
          foregroundColor: isDarkTheme ? Colors.white70 : Colors.black,
          iconTheme: IconThemeData(
              color: isDarkTheme ? Colors.white : Colors.black54)),
      // Additional custom color fields
      // primaryColor: isDarkTheme ? Colors.blueGrey : Colors.lightBlue,
    );
  }

  // ThemeMode _themeMode = ThemeMode.system;
  //
  // void changeTheme(ThemeMode themeMode) {
  //   setState(() {
  //     _themeMode = themeMode;
  //   });
  // }

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    var colorScheme = ColorScheme.fromSeed(
        seedColor: Colors.cyan.shade500, primary: Colors.cyan.shade100);
    return MaterialApp(
      title: 'HandHeld Helper',
      debugShowCheckedModeBanner: false,

      theme: getAppTheme(context, true),

      //theme: ThemeData(
      //   colorScheme: colorScheme,
      //   useMaterial3: true,
      // ),
      home: AppStartup(),
    );
  }
}

void main(List<String> args) async {
  if (isMobile()) {
    print("[LOG] Initializing app lifecycle observer...");
    WidgetsFlutterBinding.ensureInitialized();
    final observer = LifecycleObserver();
    WidgetsBinding.instance!.addObserver(observer);
  }

  if ((Platform.environment["DEBUG"] ?? "").isNotEmpty) {
    dlog = print;
  }
  dlog("CMD ARGS: ${args.join(',')}");

  runApp(const HandheldHelper());
}
