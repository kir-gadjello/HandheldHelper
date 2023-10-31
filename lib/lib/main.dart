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

/* TODO
 [] async exec
 [] android version
 [] msg logging & search
 [] tab-like icon lists left and right of the title
 [] markdown or similar highlight in msgs
 [] send by Shift+Enter https://gist.github.com/elliette/d31aec75e000b3e2497a10d61bc6da0c https://api.flutter.dev/flutter/services/LogicalKeyboardKey-class.html
 [] support casualllm-14b
 [] python interpreter (desktops?) https://pub.dev/packages/serious_python https://pub.dev/packages/dartpy https://pub.dev/packages/python_ffi
 [] disable excessive llama.cpp logs
 [] web access with https://github.com/mozilla/readability & webview
 */

Future<void> requestStoragePermission() async {
  var status = await Permission.manageExternalStorage.request();
  if (status.isGranted) {
    print('Storage permission granted');
  } else if (status.isPermanentlyDenied) {
    openAppSettings();
  }
}

class HttpDownloadWidget extends StatefulWidget {
  final String url;
  final String destinationPath;
  final TextStyle? textStyle;

  const HttpDownloadWidget(
      {Key? key,
      required this.url,
      required this.destinationPath,
      this.textStyle})
      : super(key: key);

  @override
  _HttpDownloadWidgetState createState() => _HttpDownloadWidgetState();
}

class _HttpDownloadWidgetState extends State<HttpDownloadWidget> {
  late http.StreamedResponse response;
  double progress = 0.0;
  bool isDownloading = false;
  bool downloadSuccess = false;
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

      final http.Client client = http.Client();
      final http.StreamedResponse response =
          await client.send(http.Request('GET', Uri.parse(widget.url)));
      this.response = response;
      var total = response.contentLength ?? 0;
      var downloaded = 0;

      final file = File(widget.destinationPath);
      // '${widget.destinationPath}/${response.headers['content-disposition']?.split('filename=')[1] ?? 'unknown_file'}');
      final fileSink = file.openWrite();
      await response.stream.listen((data) {
        fileSink.add(data);
        downloaded += data.length;
        progress = downloaded / total;
        setState(() {});
      }).asFuture();

      await fileSink.flush();
      await fileSink.close();
      client.close();

      setState(() {
        isDownloading = false;
        downloadSuccess = true;
      });
    } catch (e) {
      setState(() {
        isDownloading = false;
        errorCode = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'HttpDownloadWidget', // Added this line to provide a unique label for the widget
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isDownloading) Text('Downloading ', style: widget.textStyle),
              Text('${widget.url}', style: widget.textStyle),
              if (isDownloading) CircularProgressIndicator(),
              if (!isDownloading && downloadSuccess)
                Icon(Icons.check_circle, color: Colors.green),
              if (!isDownloading && errorCode.isNotEmpty)
                Icon(Icons.error, color: Colors.red),
            ],
          ),
          if (isDownloading) LinearProgressIndicator(value: progress),
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
                          'File size: ${getSizeString(response.contentLength ?? 0)}',
                          style: widget.textStyle),
                    ),
                    Container(
                      padding: EdgeInsets.all(8.0),
                      child: Text('Time taken: ${getDurationString()}',
                          style: widget.textStyle),
                    ),
                    Container(
                      padding: EdgeInsets.all(8.0),
                      child: Text(
                          'Speed: ${getSpeedString(response.contentLength ?? 0)}',
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
    return '${duration.inHours}:${duration.inMinutes % 60}';
  }

  String getSpeedString(int size) {
    final speed =
        (size / (DateTime.now().difference(startTime).inSeconds * 1000)) /
            1024 /
            1024;
    return '${speed.toStringAsFixed(2)} MB/s';
  }
}

// class HttpDownloadWidget extends StatefulWidget {
//   final String url;
//   final String destinationPath;
//
//   const HttpDownloadWidget(
//       {Key? key, required this.url, required this.destinationPath})
//       : super(key: key);
//
//   @override
//   _HttpDownloadWidgetState createState() => _HttpDownloadWidgetState();
// }
//
// class _HttpDownloadWidgetState extends State<HttpDownloadWidget> {
//   late http.Response response;
//   double progress = 0.0;
//   bool isDownloading = false;
//   bool downloadSuccess = false;
//   String errorCode = '';
//   DateTime startTime = DateTime
//       .now(); // Added this line to declare and initialize the startTime field
//
//   @override
//   void initState() {
//     super.initState();
//     downloadFile();
//   }
//
//   Future<void> downloadFile() async {
//     try {
//       setState(() {
//         isDownloading = true;
//       });
//       response = await http.get(Uri.parse(widget.url));
//       final file = File(
//           '${widget.destinationPath}/${response.headers['content-disposition']?.split('filename=')[1] ?? 'unknown_file'}');
//       await file.writeAsBytes(response.bodyBytes);
//       setState(() {
//         isDownloading = false;
//         downloadSuccess = true;
//       });
//     } catch (e) {
//       setState(() {
//         isDownloading = false;
//         errorCode = e.toString();
//       });
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Column(
//       children: [
//         Row(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             if (isDownloading) CircularProgressIndicator(),
//             if (!isDownloading && downloadSuccess)
//               Icon(Icons.check_circle, color: Colors.green),
//             if (!isDownloading && errorCode.isNotEmpty)
//               Icon(Icons.error, color: Colors.red),
//           ],
//         ),
//         if (isDownloading || downloadSuccess) Text('${widget.url}'),
//         if (isDownloading) LinearProgressIndicator(value: progress),
//         if (downloadSuccess)
//           Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text('Download completed', style: TextStyle(color: Colors.green)),
//               Icon(Icons.check_circle, color: Colors.green),
//               SizedBox(height: 8),
//               Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   Text(
//                       'File size: ${getSizeString(response.contentLength ?? 0)}'),
//                   Text('Time taken: ${getDurationString()}'),
//                   Text('Speed: ${getSpeedString(response.contentLength ?? 0)}'),
//                 ],
//               ),
//             ],
//           ),
//         if (errorCode.isNotEmpty)
//           Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text('Error', style: TextStyle(color: Colors.red)),
//               Icon(Icons.error, color: Colors.red),
//               SizedBox(height: 8),
//               Text(errorCode),
//             ],
//           ),
//       ],
//     );
//   }
//
//   String getSizeString(int size) {
//     if (size >= 1024 * 1024 * 1024) {
//       return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
//     } else if (size >= 1024 * 1024) {
//       return '${(size / (1024 * 1024)).toStringAsFixed(2)} MB';
//     } else {
//       return '${size.toString()} KB';
//     }
//   }
//
//   String getDurationString() {
//     final duration = DateTime.now().difference(startTime);
//     return '${duration.inHours} hours, ${duration.inMinutes % 60} minutes';
//   }
//
//   String getSpeedString(int size) {
//     final speed =
//         (size / (DateTime.now().difference(startTime).inSeconds * 1000)) /
//             1024 /
//             1024;
//     return '${speed.toStringAsFixed(2)} MB/s';
//   }
// }

class DownloadWidget extends StatefulWidget {
  final String url;
  final String savePath;
  final Function(bool, String?, String?, dynamic) onComplete;

  DownloadWidget(
      {required this.url, required this.savePath, required this.onComplete});

  @override
  _DownloadWidgetState createState() => _DownloadWidgetState();
}

class _DownloadWidgetState extends State<DownloadWidget> {
  String? downloadId;
  double downloadProgress = 0;

  @override
  void initState() {
    super.initState();

    FlutterDownloader.initialize(debug: true)
        .then((_) => FlutterDownloader.registerCallback((id, status, progress) {
              setState(() {
                downloadId = id;
                downloadProgress = progress / 100;
              });
            }));

    final taskId = FlutterDownloader.enqueue(
      url: widget.url,
      savedDir: widget.savePath,
      showNotification: true,
      openFileFromNotification: true,
    );

    setState(() async {
      downloadId = await taskId;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        LinearProgressIndicator(
          value: downloadProgress,
          backgroundColor: Colors.grey[200],
        ),
        Text(
          downloadProgress == 1 ? 'Download completed' : 'Downloading',
          style: TextStyle(fontSize: 16),
        ),
        Text(
          widget.url,
          style: TextStyle(fontSize: 16, color: Colors.blue),
        ),
      ],
    );
  }

  @override
  void dispose() {
    FlutterDownloader.registerCallback((id, status, progress) {});
    super.dispose();
  }
}

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
}

const DEFAULT_LLM =
    "https://huggingface.co/TheBloke/OpenHermes-2-Mistral-7B-GGUF/resolve/main/openhermes-2-mistral-7b.Q4_K_M.gguf";
const DEFAULT_LLM_FILE = "openhermes-2-mistral-7b.Q4_K_M.gguf";
const DEFAULT_LLM_SIZE = 4368450272;

class HHHDefaults {
  final String hhh_dir;
  final String llm_url;
  final String llm_filename;
  final int llm_size;
  HHHDefaults(this.hhh_dir, this.llm_url, this.llm_filename, this.llm_size);
}

bool validate_root_app_params(Map<String, dynamic> j) {
  bool root_dir_ok = false, default_model_ok = false;
  try {
    root_dir_ok = Directory(j['hhh_dir']).existsSync();
  } catch (e) {}
  try {
    default_model_ok = File(j['default_model']).existsSync();
  } catch (e) {}
  return root_dir_ok && default_model_ok;
}

class AppInitParams {
  RootAppParams? params;
  HHHDefaults defaults;
  AppInitParams(this.defaults, {this.params});
}

Future<AppInitParams> perform_app_init() async {
  print("ENTER perform_app_init");
  String def_hhh_dir = (await getApplicationDocumentsDirectory()).absolute.path;

  if (Platform.isLinux) {
    def_hhh_dir =
        Path.join(Platform.environment["HOME"] ?? "/home/user", "HHH");
  } else if (Platform.isMacOS) {
    def_hhh_dir = (await getApplicationDocumentsDirectory())
        .absolute
        .path; // Path.join(Platform.environment["HOME"] ?? "/home/user", "Documents/HHH");
  } else if (Platform.isAndroid) {
    def_hhh_dir = Path.join("/storage/emulated/0/", "HHH");
  }

  var hhhd =
      HHHDefaults(def_hhh_dir, DEFAULT_LLM, DEFAULT_LLM_FILE, DEFAULT_LLM_SIZE);

  print("INIT db");

  final DatabaseHelper _databaseHelper = DatabaseHelper();
  var metadb = MetadataManager();
  var root_app_params = await metadb.getMetadata("root_app_params");
  RootAppParams? rp;

  print("INIT validate_root_app_params");

  if (root_app_params is String) {
    var jr_app_params = jsonDecode(root_app_params);
    if (validate_root_app_params(jr_app_params)) {
      rp = RootAppParams(
          jr_app_params['hhh_dir'] as String,
          jr_app_params['default_model'] as String,
          (jr_app_params['model_search_paths'] ?? []) as List<String>);
    }
  }

  print("DONE perform_app_init");

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
    return FutureBuilder<AppInitParams>(
      future: futureHHHDefaults,
      builder: (BuildContext context, AsyncSnapshot<AppInitParams> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            margin: EdgeInsets.all(128.0),
            decoration: BoxDecoration(
              color: Colors.lightBlue,
              borderRadius: BorderRadius.circular(32.0),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "HandHeld Helper",
                  style: TextStyle(
                      fontSize: 48,
                      color: Colors.white,
                      decoration: TextDecoration.none,
                      fontWeight: FontWeight.bold),
                ),
                // SizedBox(height: 20),
                Padding(
                    padding: EdgeInsets.all(24.0),
                    child: GFLoader(
                      type: GFLoaderType.ios,
                      size: 50,
                      loaderstrokeWidth: 4.0,
                    )),
              ],
            ),
          );
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

String resolve_llm_file(
    {String llm_file = "openhermes-2-mistral-7b.Q4_K_M.gguf"}) {
  List<String> paths = [];

  String userDataRoot = ".";

  if (Platform.isMacOS || Platform.isLinux) {
    userDataRoot = Platform.environment["HOME"] ?? "";
  } else if (Platform.isAndroid) {
    // String internalStoragePrefix = "/data/user/0/<package_name>/files/";
    // const String externalStoragePrefix = "/storage/emulated/0/";
    userDataRoot = Path.join("/storage/emulated/0/", WorkspaceRoot);
  }

  paths.add(Path.join(userDataRoot, llm_file));
  paths.add(String.fromEnvironment("MODELPATH") ?? "");
  paths.add(Platform.environment["MODELPATH"] ?? "");
  paths.add(Path.join(".", llm_file));

  for (var p in paths) {
    if (p.isNotEmpty && File(p).existsSync()) {
      dlog("MODEL: probing $p");
      return p;
    }
  }

  throw FileSystemException("File not found", llm_file);
}

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

class CollapsibleWidget extends StatefulWidget {
  final Widget collapsedChild;
  final Widget expandedChild;
  final bool blockParentCollapse;

  CollapsibleWidget(
      {required this.collapsedChild,
      required this.expandedChild,
      this.blockParentCollapse = false});

  @override
  _CollapsibleWidgetState createState() => _CollapsibleWidgetState();
}

class _CollapsibleWidgetState extends State<CollapsibleWidget> {
  bool isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (widget.blockParentCollapse && isExpanded) {
          return;
        }
        setState(() {
          isExpanded = !isExpanded;
        });
      },
      child: isExpanded ? widget.expandedChild : widget.collapsedChild,
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

class AppSetupForm extends StatefulWidget {
  late String default_rootdir;
  late String default_modelurl;

  @override
  _AppSetupForm createState() => _AppSetupForm();

  AppSetupForm({Key? key, required HHHDefaults resolved_defaults});
}

class _AppSetupForm extends State<AppSetupForm> {
  double btnFontSize = 20;
  bool canUserAdvance = true;
  bool remind_storage_permissions = false;
  Color btnTextColor = Colors.grey;
  String? _file;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    btnTextColor = canUserAdvance ? Colors.lightGreenAccent : Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final platform_requires_storage_permissions =
        Platform.isMacOS || Platform.isAndroid;

    var largeBtnFontStyle =
        TextStyle(fontSize: btnFontSize, color: Colors.blue);

    return Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height - 200,
        ),
        // height: MediaQuery.of(context).size.height,
        margin: EdgeInsets.all(48.0),
        decoration: BoxDecoration(
          color: Colors.blue[100],
          borderRadius: BorderRadius.all(Radius.circular(30)),
        ),
        child: SingleChildScrollView(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(48.0, 24.0, 48.0, 24.0),
                child: FastForm(formKey: _formKey, children: <Widget>[
                  Text(
                    'Welcome 👋💠',
                    style: TextStyle(fontSize: 48),
                  ),
                  Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 0, vertical: 12),
                      child: Text(
                        '''HandHeld Helper is a fast and lean app allowing you to run LLM AIs locally, on your device.
HHH respects your privacy: it works purely offline and never shares your data.
LLM checkpoints are large binary files. To download, store, manage and operate them, the app needs certain permissions, as well as network bandwidth and storage space – currently 4.1 GB for a standard 7B model.''',
                        textAlign: TextAlign.left,
                        style: TextStyle(fontSize: btnFontSize),
                      )),
                  if (remind_storage_permissions &&
                      platform_requires_storage_permissions)
                    HoverableText(
                        onTap: () {
                          print("PERMISSION REQUEST");
                        },
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              vertical: 24.0, horizontal: 24.0),
                          child: Row(children: [
                            Expanded(
                                child: Text(
                              'Please accept data storage permissions.',
                              style: largeBtnFontStyle,
                            )),
                            Icon(Icons.check, size: 32, color: Colors.grey),
                          ]),
                        )),
                  CollapsibleWidget(
                      collapsedChild: HoverableText(
                          onTap: () {
                            print("DL START");
                          },
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                                vertical: 24.0, horizontal: 24.0),
                            child: Row(children: [
                              Expanded(
                                  child: Text(
                                'Accept the default data storage location and download the default LLM (OpenHermes-2-Mistral-7B) from Huggingface',
                                style: largeBtnFontStyle,
                              )),
                              Icon(Icons.download_for_offline,
                                  size: 32, color: Colors.grey),
                            ]),
                          )),
                      expandedChild: plainOutlile(
                        Padding(
                            padding: EdgeInsets.symmetric(
                                vertical: 24.0, horizontal: 24.0),
                            child: Column(children: [
                              Row(children: [
                                Expanded(
                                    child: Text(
                                  'Accept the default data storage location and download the default LLM (OpenHermes-2-Mistral-7B) from Huggingface',
                                  style: largeBtnFontStyle,
                                )),
                                Icon(Icons.download_for_offline,
                                    size: 32, color: Colors.grey),
                              ]),
                              Padding(
                                  padding: EdgeInsets.fromLTRB(0, 12.0, 0, 0),
                                  child: HttpDownloadWidget(
                                      url:
                                          'https://example.com/index.html', // 'https://huggingface.co/roneneldan/TinyStories-3M/resolve/main/pytorch_model.bin',
                                      destinationPath:
                                          "/Users/LKE/openhermes-2-mistral-7b.Q4_K_M.gguf",
                                      textStyle: TextStyle(
                                          fontSize: btnFontSize * 0.8,
                                          color: largeBtnFontStyle.color)))
                            ])),
                      )),
                  // expandedChild: HoverableText(
                  //     child: HttpDownloadWidget(
                  //         url: 'https://example.com/index.html',
                  //         destinationPath: "."))),
                  // CollapsibleWidget(
                  //     collapsedChild: HoverableText(
                  //         onTap: () {
                  //           print("PERMISSION REQUEST");
                  //         },
                  //         child: const Padding(
                  //           padding: EdgeInsets.symmetric(
                  //               vertical: 24.0, horizontal: 24.0),
                  //           child: Row(children: [
                  //             Expanded(
                  //                 child: Text(
                  //               'Download default LLM (OpenHermes-2-Mistral-7B)',
                  //               style: TextStyle(
                  //                   fontSize: btnFontSize - 4, color: Colors.blue),
                  //             )),
                  //             Icon(Icons.download_for_offline,
                  //                 size: 32, color: Colors.grey),
                  //           ]),
                  //         )),
                  //     expandedChild: HttpDownloadWidget(
                  //         url:
                  //             'https://example.com/index.html', // https://huggingface.co/TheBloke/OpenHermes-2-Mistral-7B-GGUF/resolve/main/openhermes-2-mistral-7b.Q4_K_M.gguf
                  //         destinationPath: ".")),
                  CollapsibleWidget(
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
                                vertical: 24.0, horizontal: 24.0),
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
                              FastTextField(
                                name: 'text_field',
                                labelText: 'Text Field',
                                placeholder: 'MM/JJJJ',
                                keyboardType: TextInputType.datetime,
                                maxLength: 7,
                                prefix: const Icon(Icons.calendar_today),
                                buildCounter: inputCounterWidgetBuilder,
                                inputFormatters: const [],
                                validator: Validators.compose([
                                  Validators.required(
                                      (value) => 'Field is required'),
                                  Validators.minLength(
                                      7,
                                      (value, minLength) =>
                                          'Field must contain at least $minLength characters')
                                ]),
                              ),
                            ])),
                      )),
                  Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 0, vertical: 12),
                      child: EnabledButton(
                          isDisabled: !canUserAdvance,
                          disabledText: 'Complete the necessary steps',
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Expanded(child: Text('Start conversation')),
                                Center(
                                    child: Text('Start conversation',
                                        style: TextStyle(
                                            fontSize: btnFontSize,
                                            color: btnTextColor))),
                                Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 8.0, vertical: 0.0),
                                    child:
                                        Icon(Icons.chat, color: btnTextColor))
                              ]))),
                  // Text('Complete the necessary steps before',
                  //     style: TextStyle(fontSize: btnFontSize, color: Colors.blue)),
                  Visibility(
                    visible: false,
                    child: Column(
                      children: <Widget>[
                        Text(
                          'Additional text',
                          style: TextStyle(fontSize: 10),
                        ),
                        // Custom HTTP download component
                      ],
                    ),
                  ),
                  TextFormField(
                    validator: (value) {
                      if (value?.isEmpty ?? false) {
                        return 'Please enter some text';
                      }
                      return null;
                    },
                  ),
                  // ElevatedButton(
                  //   child: Text('Submit'),
                  //   onPressed: () {
                  //     if (_formKey.currentState?.validate() ?? false) {
                  //       ScaffoldMessenger.of(context).showSnackBar(
                  //           SnackBar(content: Text('Processing Data')));
                  //     }
                  //   },
                  // ),
                  // // File field example
                  // ElevatedButton(
                  //   child: Text('Select File'),
                  //   onPressed: () async {
                  //     FilePickerResult? result =
                  //         await FilePicker.platform.pickFiles();
                  //
                  //     if (result != null) {
                  //       File file = File(result.files.single.path ?? "");
                  //       if (file.existsSync()) {
                  //         var new_model = file.path;
                  //         dlog("RELOADING FROM $new_model");
                  //         setState(() {
                  //           _file = file.path;
                  //         });
                  //       }
                  //     } else {
                  //       // User canceled the picker
                  //     }
                  //   },
                  // ),
                ]))));
  }
}

class _MyHomePageContentState extends State<MyHomePageContent> {
  AIDialog dialog = AIDialog();
  late ChatManager chatManager;

  late List<ChatMessage> _messages = [];
  List<ChatUser> _typingUsers = [];

  bool _msg_streaming = false;
  Timer? _msg_poll_timer;
  Settings settings = Settings();
  bool _initialized = false;
  Timer? _token_counter_sync;
  int _input_tokens = 0;

  Map<String, dynamic> llama_init_json = {};

  void unlock_actions() {
    setState(() {
      _initialized = true;
    });
  }

  _MyHomePageContentState() {
    // llama_init_json = resolve_init_json();
    // dlog("LLAMA_INIT_JSON: ${llama_init_json}");
    // dialog = AIDialog(
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
            "Beginning of conversation with model at ${dialog.modelpath}\nSystem prompt: $hermes_sysmsg",
        user: user_SYSTEM,
        createdAt: DateTime.now(),
      ),
    ];
  }

  void updateStreamingMsgView() {
    setState(() {
      var poll_result = dialog.poll_advance_stream();
      var finished = poll_result.finished;

      if (finished) {
        _msg_poll_timer?.cancel();
        _msg_streaming = false;

        String upd_str = poll_result.joined();

        // if (upd_str.isNotEmpty) {
        //   stdout.write("$upd_str");
        // }

        var completedMsg = dialog.msgs.last;

        _messages[0].createdAt = completedMsg.createdAt;
        _messages[0].text = completedMsg.content;

        _typingUsers = [];
      } else {
        _messages[0].text = dialog.stream_msg_acc;
      }
    });
  }

  void addMsg(ChatMessage m, {use_polling = true}) {
    if (use_polling) {
      var success = dialog.start_advance_stream(user_msg: m.text);
      _msg_streaming = true;

      setState(() {
        _typingUsers = [user_ai];
        _messages.insert(0, m);
        var msg = ChatMessage(
            user: user_ai,
            text: "...", // TODO animation
            createdAt: dialog.msgs.last.createdAt);
        _messages.insert(0, msg);

        _msg_poll_timer = Timer.periodic(
            Duration(milliseconds: settings._msg_poll_ms), (timer) {
          updateStreamingMsgView();
        });
      });
    } else {
      setState(() {
        var success = dialog.advance(user_msg: m.text);
        if (success) {
          _messages.insert(0, m);
          _messages.insert(
              0,
              ChatMessage(
                  user: user_ai,
                  text: dialog.msgs.last.content,
                  createdAt: dialog.msgs.last.createdAt));
          dlog("MSGS: ${_messages.map((m) => m.text)}");
        } else {
          _messages.insert(0, m);
          _messages.insert(
              0,
              ChatMessage(
                  user: user_SYSTEM,
                  text: "ERROR: ${dialog.error}",
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

    dialog.reinit(
        modelpath: new_modelpath,
        llama_init_json: llama_init_json,
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
      'meta': {'model': dialog.modelpath},
      'messages': export_msgs
    });
  }

  void _update_token_counter(String upd) {
    setState(() {
      _input_tokens = dialog.measure_tokens(upd);
      dlog("LOG _update_token_counter $_input_tokens");
    });
  }

  bool app_setup_done() {
    var ret = widget.appInitParams.params != null;
    print("MAIN: app_setup_done = $ret");
    return ret;
  }

  Widget buildAppSetupScreen() {
    // return Center(child: Text("Please setup the app"));
    return AppSetupForm(resolved_defaults: widget.appInitParams.defaults);
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
    bool tokenOverload = (dialog.tokens_used + _input_tokens) >= dialog.n_ctx;

    Widget mainWidget;

    if (app_setup_done()) {
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
            Expanded(child: Text("${widget.title}")),
            Text(
              "T:${dialog.tokens_used + _input_tokens}/${dialog.n_ctx}",
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
                      dialog.reset_msgs();
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

/*
  var metadb = MetadataManager();
  var root_app_params = jsonDecode(await metadb.getMetadata("root_app_params"));
  RootAppParams? rp;

  if (validate_root_app_params((root_app_params))) {
    rp = RootAppParams(
        root_app_params['hhh_dir'] as String,
        root_app_params['default_model'] as String,
        (root_app_params['model_search_paths'] ?? []) as List<String>);
  } else {}

  root_app_params: rp, resolved_defaults: await resolve_defaults())
 */

void main(List<String> args) async {
  if ((Platform.environment["DEBUG"] ?? "").isNotEmpty) {
    dlog = print;
  }
  dlog("CMD ARGS: ${args.join(',')}");

  runApp(const MyApp());
}
