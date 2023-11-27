import 'dart:collection';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:handheld_helper/db.dart';
import 'package:handheld_helper/gguf.dart';
import 'package:path/path.dart' as Path;
import 'package:flutter/material.dart';
import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:clipboard/clipboard.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'custom_widgets.dart';
import 'llm_engine.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_fast_forms/flutter_fast_forms.dart';
import 'package:getwidget/getwidget.dart';
import 'package:handheld_helper/flutter_customizations.dart';
import 'package:flutter_color/flutter_color.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:system_info2/system_info2.dart';
import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:desktop_disk_space/desktop_disk_space.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'util.dart';
import 'commit_hash.dart';

const APP_TITLE_SHORT = "HHH";
const APP_TITLE_FULL = "HandHeld Helper Beta";
const APP_REPO_LINK = "https://github.com/kir-gadjello/handheld-helper";
final String APP_VERSION = "βv0.1.0-${APP_COMMIT_HASH.substring(0, 8)}";
final String APP_TITLE = isMobile() ? APP_TITLE_SHORT : APP_TITLE_FULL;
const APPBAR_WIDTH = 220.0;
const DEFAULT_THEME_DARK = true;
const MOBILE_DRAWER_TP = 84.0;
const WorkspaceRoot = "HHH";
const actionIconSize = 38.0;
const actionIconPadding = EdgeInsets.symmetric(vertical: 0.0, horizontal: 2.0);
const SEND_SHIFT_ENTER = true;
const DEFAULT_CTXLEN = 2048;
final MAX_CTXLEN = int.parse(Platform.environment?["MAXCTX"] ?? "8192");

final MIN_STREAM_PERSIST_INTERVAL = isMobile() ? 1400 : 500;

final APPROVED_LLMS = [
  LLMref(
      name: 'OpenHermes-2.5-Mistral-7B',
      size: 4368450304,
      ctxlen: "8k",
      sources: [
        "https://huggingface.co/TheBloke/OpenHermes-2.5-Mistral-7B-GGUF/resolve/main/openhermes-2.5-mistral-7b.Q4_K_M.gguf"
      ]),
  LLMref(
      name: 'OpenHermes-2-Mistral-7B',
      size: 4368450272,
      ctxlen: "8k",
      sources: [
        "https://huggingface.co/TheBloke/OpenHermes-2-Mistral-7B-GGUF/resolve/main/openhermes-2-mistral-7b.Q4_K_M.gguf"
      ]),
  LLMref(
      name: "TinyLLAMA-1t-OpenOrca",
      size: 667814368,
      ctxlen: "2k",
      sources: [
        "https://huggingface.co/TheBloke/TinyLlama-1.1B-1T-OpenOrca-GGUF/resolve/main/tinyllama-1.1b-1t-openorca.Q4_K_M.gguf"
      ]),
  // Not ready yet
  // LLMref(name: 'OpenChat-3.5-16K', size: 4368450304, sources: [
  //   "https://huggingface.co/TheBloke/openchat_3.5-16k-GGUF/resolve/main/openchat_3.5-16k.Q4_K_M.gguf"
  // ])
  // Dolphin 2.2.1 Mistral 7B
  // https://huggingface.co/TheBloke/dolphin-2.2.1-mistral-7B-GGUF/blob/main/dolphin-2.2.1-mistral-7b.Q4_K_M.gguf

  /*
  https://huggingface.co/afrideva/TinyLlama-1.1B-Chat-v0.6-GGUF
  # <|system|>
  # You are a friendly chatbot who always responds in the style of a pirate.</s>
  # <|user|>
  # How many helicopters can a human eat in one sitting?</s>
  # <|assistant|>
  # ...
   */
];

class HexColor extends Color {
  static bool isHexColor(String s) {
    // Remove the hash if it exists
    s = s.replaceAll("#", "");

    // Check if the length is 6 or 8
    if (s.length == 6 || s.length == 8) {
      // Check if all characters are hexadecimal
      return RegExp(r'^[0-9A-Fa-f]+$').hasMatch(s);
    }

    // If the length is not 6 or 8, or if the string contains non-hexadecimal characters, return false
    return false;
  }

  static int _getColorFromHex(String hexColor) {
    if (!isHexColor(hexColor)) {
      return 0xFFAAAAAA;
    }
    hexColor = hexColor.toUpperCase().replaceAll("#", "");
    if (hexColor.length == 6) {
      hexColor = "FF" + hexColor;
    }
    return int.parse(hexColor, radix: 16);
  }

  HexColor(final String hexColor) : super(_getColorFromHex(hexColor));
}

void Function(AppPage page,
    {VoidCallback? onBeforeNavigate,
    List<String>? parameters}) getNavigate(BuildContext context) {
  final navigationProvider = NavigationProvider.of(context);
  return navigationProvider?.navigate ??
      (AppPage page,
              {VoidCallback? onBeforeNavigate, List<String>? parameters}) =>
          {};
}

class SystemInfo {
  int RAM;
  double freeDisk;
  double totalDisk;

  SystemInfo(this.RAM, this.freeDisk, this.totalDisk);
}

Future<SystemInfo?> getSysInfo() async {
  int? RAM;
  double? freeDisk;
  double? totalDisk;
  try {
    RAM = SysInfo.getTotalPhysicalMemory();
    if (isMobile()) {
      freeDisk = await DiskSpacePlus.getFreeDiskSpace;
      totalDisk = await DiskSpacePlus.getTotalDiskSpace;
    } else {
      totalDisk = (await DesktopDiskSpace.instance.getTotalSpace() ?? -1) * 1.0;
      freeDisk = (await DesktopDiskSpace.instance.getFreeSpace() ?? -1) * 1.0;
    }
  } catch (e) {
    print("Exception in getSysInfo: $e");
  }
  if (RAM != null && freeDisk != null && totalDisk != null) {
    return SystemInfo(RAM!, freeDisk!, totalDisk!);
  }
}

void launchURL(String url) async {
  if (await canLaunch(url)) {
    await launch(url);
  } else {
    throw 'Could not launch $url';
  }
}

Future<bool> requestStoragePermission() async {
  var status = await Permission.storage.request();
  if (status.isGranted) {
    print('Storage permission granted');
    return true;
  } else if (status.isPermanentlyDenied) {
    openAppSettings();
  }
  return false;
}

// Global storage for progress speeds
Map<String, double> progressSpeeds = {};

class SelfCalibratingProgressBar extends StatefulWidget {
  final double progress;
  final double workAmount;
  final String pkey;
  final double speedUnderestimate = 0.8;
  final Function(String, double)? persistCallback;
  final double? Function(String)? restoreCallback;
  final Widget Function(double progress)? progressBarBuilder;

  SelfCalibratingProgressBar({
    required this.progress,
    required this.workAmount,
    required this.pkey,
    this.persistCallback,
    this.restoreCallback,
    this.progressBarBuilder,
  });

  @override
  _SelfCalibratingProgressBarState createState() =>
      _SelfCalibratingProgressBarState();
}

class _SelfCalibratingProgressBarState extends State<SelfCalibratingProgressBar>
    with SingleTickerProviderStateMixin {
  double? progressSpeed;
  late DateTime previousTimestamp;
  late double previousProgress;
  bool initialUpdate = true;
  AnimationController? _controller;

  @override
  void initState() {
    print("SelfCalibratingProgressBar: initState");
    super.initState();
    progressSpeed = restoreSpEst(); // todo
    previousTimestamp = DateTime.now();
    previousProgress = widget.progress;
  }

  @override
  void didUpdateWidget(SelfCalibratingProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (initialUpdate ||
        oldWidget.progress != widget.progress ||
        oldWidget.workAmount != widget.workAmount ||
        oldWidget.pkey != widget.pkey) {
      calibrateProgressSpeed();
    }
  }

  void persistSpEst(double progressSpeed) {
    if (widget.persistCallback != null) {
      widget.persistCallback!(widget.pkey, progressSpeed);
    } else {
      progressSpeeds[widget.pkey] = progressSpeed;
    }
  }

  double? restoreSpEst() {
    double? ret;
    if (widget.persistCallback != null) {
      ret = widget.restoreCallback!(widget.pkey);
    }
    if (progressSpeeds.containsKey(widget.pkey)) {
      ret = progressSpeeds[widget.pkey];
    }
    if (ret != null && widget.speedUnderestimate != 1.0) {
      ret = widget.speedUnderestimate * ret!;
    }
  }

  void calibrateProgressSpeed() {
    print("calibrateProgressSpeed(): $previousProgress -> ${widget.progress}");

    DateTime currentTimestamp = DateTime.now();
    double timeDifference =
        currentTimestamp.difference(previousTimestamp).inMilliseconds * 1.0;

    if (initialUpdate) {
      var _progressSpeed = restoreSpEst();
      if (_progressSpeed != null) {
        progressSpeed = _progressSpeed!;
      }
    } else if (widget.progress != previousProgress && timeDifference > 0) {
      progressSpeed = widget.workAmount *
          (widget.progress - previousProgress) /
          timeDifference;
      persistSpEst(progressSpeed!);
      print("PROGRESS SPEED: ${(progressSpeed! * 1000.0).round()}T/s");
    }

    previousTimestamp = currentTimestamp;
    previousProgress = widget.progress;

    if (initialUpdate) {
      initialUpdate = false;
    }

    if (progressSpeed != null) {
      updateControllerExpectedDuration(progressSpeed!);
    }

    setState(() {});
  }

  void updateControllerExpectedDuration(double progressSpeed) {
    var duration = Duration(
        milliseconds:
            (widget.workAmount * (1.0 - widget.progress) / progressSpeed)
                .round());

    if (_controller == null) {
      print(
          "CREATE ANIMATION CONTROLLER, widget.progress=${widget.progress} DURATION=${duration.inMilliseconds}ms");
      _controller = AnimationController(
        value: widget.progress,
        vsync: this,
        duration: duration,
      );
      _controller!.forward(from: widget.progress);
    } else {
      _controller!.reset();
      _controller!.duration = duration;
      _controller!.value = widget.progress;
      _controller!.forward(from: widget.progress);
    }
  }

  @override
  Widget build(BuildContext context) {
    // if (!_controller.isAnimating) {
    //   updateControllerExpectedDuration(progressSpeed);
    // }
    if (_controller != null) {
      return _buildProgressBar(_controller!.view.value);
    } else {
      return _buildProgressBar(widget.progress);
    }
  }

  Widget _buildProgressBar(double value) {
    return widget.progressBarBuilder != null
        ? widget.progressBarBuilder!(value)
        : LinearProgressIndicator(value: value);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}

Widget showWarningModal({
  required String title,
  required String content,
  required String buttonText,
  VoidCallback? onClose,
}) {
  return Dialog(
    backgroundColor: Colors.transparent,
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.warning,
            size: 100,
            color: Colors.orange,
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Text(
            content,
            style: TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            child: Text(buttonText),
            onPressed: () {
              if (onClose != null) {
                onClose();
              }
              // Navigator.of(context).pop();
            },
          ),
        ],
      ),
    ),
  );
}

Future<File> moveFile(File sourceFile, String newPath) async {
  try {
    // prefer using rename as it is probably faster
    return await sourceFile.rename(newPath);
  } on FileSystemException catch (e) {
    // if rename fails, copy the source file and then delete it
    final newFile = await sourceFile.copy(newPath);
    await sourceFile.delete();
    return newFile;
  }
}

class BackgroundDownloadWidget extends StatefulWidget {
  final String url;
  final String destinationPath;
  final TextStyle? textStyle;
  Function(bool success, String url, String dstPath)? onDownloadEnd;

  BackgroundDownloadWidget(
      {Key? key,
      required this.url,
      required this.destinationPath,
      this.onDownloadEnd,
      this.textStyle})
      : super(key: key);

  @override
  _BackgroundDownloadWidgetState createState() =>
      _BackgroundDownloadWidgetState();
}

class _BackgroundDownloadWidgetState extends State<BackgroundDownloadWidget> {
  int expectedFileSize = 0;
  double progress = 0.0;
  double _downloadSpeed = 0;
  bool isDownloading = false;
  bool downloadSuccess = false;
  bool isContinuingDownload = false;
  int _downloaded = 0;
  String errorCode = '';
  DateTime startTime = DateTime.now();
  String? tempDlPath;

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

      var fileName = Path.basename(widget.destinationPath);

      final task = DownloadTask(
        url: widget.url,
        baseDirectory: BaseDirectory.applicationDocuments,
        filename: Path.basename(widget.destinationPath),
        updates: Updates.statusAndProgress,
      );

      tempDlPath = Path.join(
          (await getApplicationDocumentsDirectory()).absolute.path, fileName);

      expectedFileSize = await task.expectedFileSize();

      final result =
          await FileDownloader().download(task, onProgress: (progress) {
        setState(() {
          this.progress = progress;
        });
      }, onStatus: (status) async {
        if (status == TaskStatus.complete) {
          print(
              "DL complete! Moving file from $tempDlPath to ${widget.destinationPath}");
          try {
            await moveFile(File(tempDlPath!), widget.destinationPath);
          } catch (e) {
            print("Error! could not move file... $e");
          }
          setState(() {
            isDownloading = false;
            downloadSuccess = true;
            if (widget.onDownloadEnd != null) {
              widget.onDownloadEnd!(true, widget.url, widget.destinationPath);
            }
          });
        } else if (status == TaskStatus.canceled ||
            status == TaskStatus.paused) {
          setState(() {
            isDownloading = false;
            errorCode = status.toString();
            if (widget.onDownloadEnd != null) {
              widget.onDownloadEnd!(false, widget.url, widget.destinationPath);
            }
          });
        }
      });

      FileDownloader().updates.listen((update) {
        if (update is TaskStatusUpdate) {
          print(
              'Status update for ${update.task} with status ${update.status}');
        } else if (update is TaskProgressUpdate) {
          print(
              'Progress update for ${update.task} with progress ${update.progress}');
          setState(() {
            _downloadSpeed = update.networkSpeed;
          });
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
                  child: Text("${getSpeedString(expectedFileSize * progress)} ",
                      style: widget.textStyle)),
            if (isDownloading)
              Text(
                  isContinuingDownload ? 'Continuing download' : 'Downloading ',
                  style: widget.textStyle),
          ]),
          Row(children: [
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
                  borderRadius: BorderRadius.circular(5.0),
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
                      child: Text('${getSizeString(expectedFileSize ?? 0)}',
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
                          '${getSpeedString(expectedFileSize * progress)}',
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

  String getSpeedString(double size) {
    final speed = (size / (DateTime.now().difference(startTime).inSeconds)) /
        (1024 * 1024);
    return speed.isFinite ? '${speed.toStringAsFixed(2)} MB/s' : '';
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

// typedef StringOrNumber String | Number;

class LLMref {
  List<String> sources;
  String? fileName;
  String? promptFormat = "chatml";
  String name;
  int size;
  int? native_ctxlen;
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
      this.promptFormat,
      dynamic ctxlen,
      this.meta,
      this.fileName}) {
    native_ctxlen = parse_numeric_shorthand(ctxlen);
    if (fileName == null) {
      assert(sources.isNotEmpty);
      fileName = getFileName();
    }
  }
}

String resolve_default_llm() {
  const defmod = String.fromEnvironment("DEFAULTMODEL", defaultValue: "");
  if (defmod.isNotEmpty) {
    print("Overriding default model: $defmod");
  }

  var ram_size = SysInfo.getTotalPhysicalMemory();

  if (Platform.isAndroid && ram_size < (5.5 * 1024 * 1024 * 1024)) {
    print(
        "LOW RAM DEVICE: $ram_size bytes RAM AVAILABLE, OVERRIDING DEFAULT MODEL");
    var llm = APPROVED_LLMS.firstWhere((llm) => llm.name.contains("TinyLLAMA"));
    return llm.name;
  }

  var llm = APPROVED_LLMS.firstWhere((llm) => llm.name == defmod,
      orElse: () => APPROVED_LLMS[0]);
  return llm.name;
}

String DEFAULT_LLM = resolve_default_llm();

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

String resolve_llm_file(RootAppParams p, {String? model_file}) {
  var model_to_resolve = (model_file == null) ? p.default_model : model_file;

  if (Path.basename(model_to_resolve) != model_to_resolve) {
    return model_to_resolve;
  }

  var ret = Path.join(p.hhh_dir, "Models", model_to_resolve);
  const fcand = (String.fromEnvironment("MODELPATH") ?? "");
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

String? guess_user_home_dir() {
  return Platform.environment["HOME"];
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

Map<String, dynamic> resolve_init_json({int? n_ctx}) {
  var s = const String.fromEnvironment("LLAMA_INIT_JSON") ?? "";
  Map<String, dynamic> ret;

  if (s.isNotEmpty) {
    ret = jsonDecode(s);
  }

  s = Platform.environment["LLAMA_INIT_JSON"] ?? "";
  if (s.isNotEmpty) {
    ret = jsonDecode(s);
  }

  s = "./llama_init.json";
  dlog("MODEL: probing $s");
  if (File(s).existsSync()) {
    ret = jsonDecode(File(s).readAsStringSync());
  }

  ret = {};
  if (n_ctx != null) {
    ret["n_ctx"] = n_ctx;
  }

  return ret;
}

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

Widget plainOutline(
        {required Widget child, Color bgcolor = colorBlueSelected}) =>
    Container(
      padding: const EdgeInsets.all(0.0),
      margin: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 0.0),
      decoration: BoxDecoration(
        color: bgcolor,
        borderRadius: BorderRadius.circular(24.0),
      ),
      child: child,
    );

class HoverableText extends StatefulWidget {
  final Widget child;
  Color hoverBgColor;
  Color bgColor;
  BorderRadiusGeometry borderRadius;
  Function()? onTap;

  HoverableText(
      {required this.child,
      BorderRadiusGeometry? borderRadius,
      Color this.hoverBgColor = Colors.lightBlueAccent,
      Color this.bgColor = Colors.lightBlue,
      Function()? onTap})
      : borderRadius = borderRadius ?? BorderRadius.circular(24.0);

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
          padding: const EdgeInsets.all(0.0),
          margin: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 0.0),
          decoration: BoxDecoration(
            color: _isHovering ? widget.bgColor : widget.hoverBgColor,
            borderRadius: widget.borderRadius,
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
  final VoidCallback onPressed;

  EnabledButton(
      {required this.isDisabled,
      required this.disabledText,
      required this.child,
      required this.onPressed});

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
                return const BorderSide(
                    color: Colors.grey); // Border color when disabled
              }
              return const BorderSide(
                  color: Colors.lightGreen); // Border color when enabled
            },
          ),
        ),
      ),
      onPressed: isDisabled
          ? null // Button is disabled
          : onPressed,
      child: isDisabled
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              child,
              Text(
                disabledText,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              )
            ])
          : child, // No text when button is enabled
    );
  }
}

Future<String?> getMobileUserDownloadPath() async {
  Directory? directory;
  try {
    if (Platform.isIOS) {
      directory = await getApplicationDocumentsDirectory();
    } else {
      var perm = await Permission.manageExternalStorage.request();
      if (perm.isGranted) {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      } else {
        print("Could not get MANAGE_EXTERNAL_STORAGE permission...");
        directory = await getDownloadsDirectory();
      }
    }
  } catch (err, stack) {
    print("Cannot get download folder path");
  }
  return directory?.path;
}

enum Status { initial, succeeded, failed }

class CustomFilePicker extends StatefulWidget {
  final String label;
  final String name;
  final bool isDirectoryPicker;
  String? initialValue;
  String? pickBtnText;
  final Future<bool> Function(String path)? execAdditionalFileCheck;
  Color errBgBtnColor;
  Color? errBgColor;
  Color? errTextColor;
  List<String>? allowedExtensions;

  CustomFilePicker(
      {required this.label,
      required this.name,
      required this.isDirectoryPicker,
      this.pickBtnText,
      this.initialValue,
      this.execAdditionalFileCheck,
      this.errBgColor,
      this.errTextColor,
      this.allowedExtensions,
      this.errBgBtnColor = Colors.redAccent});

  @override
  _CustomFilePickerState createState() => _CustomFilePickerState(
      TextEditingController(text: initialValue),
      isDirectoryPicker,
      execAdditionalFileCheck,
      allowedExtensions);
}

class _CustomFilePickerState extends State<CustomFilePicker> {
  String _path = '';
  bool _succeeded = false;
  Status _status = Status.initial;
  bool _isLoading = false;
  bool isDirectoryPicker;
  final Future<bool> Function(String path)? execAdditionalFileCheck;
  TextEditingController _controller;
  List<String>? allowedExtensions;
  FormFieldState<String>? _field;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  _CustomFilePickerState(this._controller, this.isDirectoryPicker,
      this.execAdditionalFileCheck, this.allowedExtensions) {
    if (_controller.text.isNotEmpty) {
      if (_controller.text.startsWith("__%")) {
        var specialPath = _controller.text;
        _controller.text = "";
        _resolveSpecialDir(specialPath);
      } else {
        _path = _controller.text;
        print("INITIAL PATH: $_path");
        Future.delayed(Duration(milliseconds: 20), () {
          _checkFileOrDirectoryExistsImpl(
              _path, isDirectoryPicker, execAdditionalFileCheck);
        });
      }
    }
  }

  _resolveSpecialDir(String p) async {
    if (p == "__%DOWNLOADS") {
      print("INITIALIZING DOWNLOADS DIR");
      String? downloads = await getMobileUserDownloadPath() ??
          (await getApplicationDocumentsDirectory()).path;
      if (downloads != null) {
        print("DOWNLOADS DIR = $downloads");
        _path = downloads;
        _controller.text = _path;
        _checkFileOrDirectoryExistsImpl(
            _path, isDirectoryPicker, execAdditionalFileCheck);
      }
    }
  }

  FilesystemPickerThemeBase _buildTheme() {
    return FilesystemPickerAutoSystemTheme(
      darkTheme: FilesystemPickerTheme(
        topBar: FilesystemPickerTopBarThemeData(
          backgroundColor: const Color(0xFF4B4B4B),
        ),
        fileList: FilesystemPickerFileListThemeData(
          folderIconColor: Colors.teal.shade400,
        ),
      ),
      lightTheme: FilesystemPickerTheme(
        backgroundColor: Colors.grey.shade200,
        topBar: FilesystemPickerTopBarThemeData(
          foregroundColor: Colors.blueGrey.shade800,
          backgroundColor: Colors.grey.shade200,
          elevation: 0,
          shape: const ContinuousRectangleBorder(
            side: BorderSide(
              color: Color(0xFFDDDDDD),
              width: 1.0,
            ),
          ),
          iconTheme: const IconThemeData(
            color: Colors.black,
            opacity: 0.3,
            size: 32,
          ),
          titleTextStyle: const TextStyle(fontWeight: FontWeight.bold),
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarBrightness: Brightness.light,
            statusBarIconBrightness: Brightness.light,
            statusBarColor: Colors.blueGrey.shade600,
          ),
          breadcrumbsTheme: BreadcrumbsThemeData(
            itemColor: Colors.blue.shade800,
            inactiveItemColor: Colors.blue.shade800.withOpacity(0.6),
            separatorColor: Colors.blue.shade800.withOpacity(0.3),
          ),
        ),
        fileList: FilesystemPickerFileListThemeData(
          iconSize: 32,
          folderIcon: Icons.folder_open,
          folderIconColor: Colors.orange,
          folderTextStyle: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 18,
              color: Colors.blueGrey.shade700),
          fileIcon: Icons.description_outlined,
          fileIconColor: Colors.deepOrange,
          fileTextStyle: TextStyle(fontSize: 18, color: Colors.grey.shade700),
          upIcon: Icons.drive_folder_upload,
          upIconSize: 32,
          upIconColor: Colors.pink,
          upText: '<up-dir>',
          upTextStyle: const TextStyle(fontSize: 18, color: Colors.pink),
          checkIcon: Icons.add_circle,
          checkIconColor: Colors.deepOrange,
          progressIndicatorColor: Colors.pink,
        ),
        pickerAction: FilesystemPickerActionThemeData(
          foregroundColor: Colors.blueGrey.shade800,
          disabledForegroundColor: Colors.blueGrey.shade500,
          backgroundColor: Colors.grey.shade200,
          shape: const ContinuousRectangleBorder(
            side: BorderSide(
              color: Color(0xFFDDDDDD),
              width: 1.0,
            ),
          ),
        ),
      ),
    );
  }

  Future<String?> _pickPath(BuildContext context,
      {String? rootPath,
      bool isDirectory = false,
      List<String>? allowedExtensions}) async {
    String? ret;
    var text = isDirectory ? 'Select folder' : 'Select file';

    if (rootPath != null && Path.dirname(rootPath) != rootPath) {
      rootPath = Path.dirname(rootPath);
    }

    if (rootPath == null || !Directory(rootPath).existsSync()) {
      rootPath = (await getApplicationDocumentsDirectory()).absolute.path;
      print("PICK PATH: DEFAULTING TO PATH $rootPath");
    }
    debugPrint('Root path: $rootPath allowedExtensions=$allowedExtensions');

    if (context.mounted) {
      String? path = await FilesystemPicker.open(
        theme: _buildTheme(),
        title: text,
        context: context,
        rootDirectory: Directory(rootPath),
        fsType: isDirectory ? FilesystemType.folder : FilesystemType.file,
        pickText: text,
        allowedExtensions: allowedExtensions,
        requestPermission: isMobile()
            ? () async => await Permission.storage.request().isGranted
            : null,
      );

      ret = path;
    }

    return ret;
  }

  void _pickFileOrDirectory(BuildContext context,
      {String? initialPath, List<String>? allowedExtensions}) async {
    setState(() {
      _isLoading = true;
    });

    String? path;
    try {
      if (isMobile()) {
        print("PICK PATH: $isDirectoryPicker $initialPath");
        path = await _pickPath(context,
            rootPath: initialPath,
            isDirectory: isDirectoryPicker,
            allowedExtensions: allowedExtensions);
      } else {
        if (widget.isDirectoryPicker) {
          path = await FilePicker.platform.getDirectoryPath();
        } else {
          FilePickerResult? result = await FilePicker.platform.pickFiles();
          path = result?.files.single.path;
        }
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
        _field?.didChange(path!);
      });
      _checkFileOrDirectoryExistsImpl(path!, isDirectoryPicker, null);
    }
  }

  Future<void> _checkFileOrDirectoryExists() async {
    if (widget != null) {
      _checkFileOrDirectoryExistsImpl(
          _path, widget.isDirectoryPicker, widget.execAdditionalFileCheck);
    }
  }

  Future<void> _checkFileOrDirectoryExistsImpl(String path, bool isDir,
      Future<bool> Function(String path)? execAdditionalFileCheck) async {
    bool exists =
        await (isDir ? Directory(path).exists() : File(path).exists());

    if (exists && execAdditionalFileCheck != null) {
      exists = await execAdditionalFileCheck!(path);
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
        padding: isMobile()
            ? const EdgeInsets.symmetric(vertical: 2, horizontal: 2)
            : const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        decoration: BoxDecoration(
          color: _succeeded
              ? Colors.lightGreen[100]
              : widget.errBgColor ?? Colors.red[50],
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        child: Row(
          children: [
            Expanded(
              child: FastTextField(
                  initialValue: widget.initialValue,
                  builder: (FormFieldState<String> field) {
                    _field = field;
                    return TextField(
                      onChanged: (value) => {field.didChange(value)},
                      controller: _controller,
                      decoration: InputDecoration(
                        contentPadding: isMobile()
                            ? const EdgeInsets.symmetric(
                                vertical: 2, horizontal: 2)
                            : const EdgeInsets.symmetric(
                                vertical: 4, horizontal: 4),
                        labelStyle: TextStyle(
                            fontSize: isMobile() ? 14 : 20,
                            color: _succeeded
                                ? Colors.green.shade400
                                : widget.errTextColor ?? Colors.red),
                        labelText: widget.label,
                        hintText: widget.isDirectoryPicker
                            ? 'Pick directory'
                            : 'Pick file',
                        fillColor: _succeeded
                            ? Colors.lightGreen
                            : widget.errBgBtnColor,
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
                            ? widget.errBgBtnColor
                            : Colors.grey,
                  ),
                  onChanged: (value) {
                    if (value != null && widget != null) {
                      _path = value;
                      _checkFileOrDirectoryExists();
                    }
                  }),
            ),
            ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : () => _pickFileOrDirectory(context,
                      initialPath: _path, allowedExtensions: allowedExtensions),
              style: ElevatedButton.styleFrom(
                primary: _status == Status.succeeded
                    ? Colors.lightGreen
                    : _status == Status.failed
                        ? widget.errBgBtnColor
                        : Colors.grey[300],
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20.0,
                      width: 20.0,
                      child: CircularProgressIndicator(),
                    )
                  : Text(
                      widget.pickBtnText == null
                          ? (widget.isDirectoryPicker
                              ? 'Open directory'
                              : 'Open file')
                          : widget.pickBtnText!,
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
  bool remind_storage_permissions = true; // !Platform.isLinux;
  bool permissions_asked = false;
  bool _downloadCanStart = false;
  bool _downloadNecessary = true;
  bool _downloadSucceeded = false;
  bool _downloadFailed = false;
  bool _downloadCheckedOK = false;
  bool _downloadCheckFailed = false;
  List<String> _advanced_form_errors = [];

  bool _couldNotCreateDirectory = false;
  String? _file;
  final _formKey = GlobalKey<FormState>();

  RootAppParams? _validRootAppParams;

  SystemInfo? sysinfo;

  @override
  void initState() {
    super.initState();
  }

  _getSysInfo() async {
    sysinfo = await getSysInfo();
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
      Timer(const Duration(milliseconds: 500), () {
        widget.onSetupComplete(_getOneClickRootAppParams());
      });
    });
  }

  _updateAdvancedForm(Map<String, dynamic> f) {
    print("SETUP ADVANCED SETTINGS FORM UPDATE: ${jsonEncode(f)}");
    String? hhh_dir;
    String? custom_default_model;
    _advanced_form_errors = [];

    if (f['hhh_root'] != null) {
      hhh_dir = f['hhh_root'] as String;
      if (!directoryExistsAndWritableSync(hhh_dir)) {
        hhh_dir = null;
        _advanced_form_errors
            .add("Custom root directory does not exist or isn't writable");
      }
    }

    if (f['custom_default_model'] != null) {
      custom_default_model = f['custom_default_model'] as String;
      if (!File(custom_default_model).existsSync()) {
        custom_default_model = null;
        _advanced_form_errors.add("Custom model file does not exist.");
      }
    }

    if (hhh_dir != null && custom_default_model != null) {
      Directory(Path.join(hhh_dir, HHH_MODEL_SUBDIR))
          .createSync(recursive: true);

      List<String> custom_model_dirs = [];

      if (!Path.isWithin(custom_default_model, hhh_dir)) {
        custom_model_dirs.add(Path.dirname(custom_default_model));
      }

      if (f['aux_model_root'] != null &&
          Directory(f['aux_model_root'] as String).existsSync()) {
        custom_model_dirs.add(f['aux_model_root'] as String);
      }

      _validRootAppParams =
          RootAppParams(hhh_dir, custom_default_model, custom_model_dirs);

      setState(() {
        print("ADVANCED SETUP FORM SUBMIT UNLOCKED");
        canUserAdvance = true;
      });
    } else {
      setState(() {
        print("ADVANCED SETUP FORM SUBMIT LOCKED");
        canUserAdvance = false;
      });
    }
  }

  _update_permission_status() async {
    remind_storage_permissions = !await requestStoragePermission();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final platform_requires_storage_permissions = false;
    // Platform.isMacOS || Platform.isAndroid;

    double setupTextSize = isMobile() ? 13 : 15;

    final hhh_dir = widget.resolved_defaults.hhh_dir;
    final hhh_model_dir =
        Path.join(widget.resolved_defaults.hhh_dir, HHH_MODEL_SUBDIR);
    final llm_url = widget.resolved_defaults.llm_url;
    final llm_size = widget.resolved_defaults.llm_size;
    final hhh_llm_dl_path = Path.join(widget.resolved_defaults.hhh_dir,
        HHH_MODEL_SUBDIR, Path.basename(llm_url));

    String user_home_dir = guess_user_home_dir() ?? hhh_dir;

    // var mainPadding = isMobile()
    //     ? const EdgeInsets.fromLTRB(6.0, 4.0, 6.0, 4.0)
    //     : const EdgeInsets.fromLTRB(48.0, 24.0, 48.0, 24.0);

    const desktopOuterPadding = 0.5;
    const mainBorderRadius = 0.1;
    const mainSetupBgColor = Colors.black; // Colors.blue[100];
    const mainSetupTextColor = Colors.white;

    var setupSubBorderRadius = BorderRadius.circular(24.0);
    var setupSubBgColor = Colors.lightGreen.shade400;
    var setupSubHoverBgColor = Colors.lightGreen.shade200;
    var setupSubExpandedBgColor = setupSubHoverBgColor;
    var autoInstallerInfoStyle = TextStyle(color: Colors.grey.shade500);
    var desktopSetupWidthConstrn = 820.0;

    var largeBtnFontStyle =
        TextStyle(fontSize: btnFontSize, color: Colors.blue.darker(30));

    var mainPadding = isMobile()
        ? const EdgeInsets.fromLTRB(6.0, 4.0, 6.0, 4.0)
        : const EdgeInsets.fromLTRB(4.5, 0.5, 4.5, 0.5);

    var interButtonPadding = isMobile()
        ? const EdgeInsets.symmetric(vertical: 21.0, horizontal: 12.0)
        : const EdgeInsets.symmetric(vertical: 24.0, horizontal: 24.0);

    if (!permissions_asked) {
      _update_permission_status();
      permissions_asked = true;
    }

    final viewInsets = EdgeInsets.fromViewPadding(
        View.of(context).viewInsets, View.of(context).devicePixelRatio);
    double keyboardHeight = viewInsets.bottom;

    const separator = SizedBox(height: 16);

    return Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height - keyboardHeight - 150,
        ),
        clipBehavior: Clip.hardEdge,
        // height: MediaQuery.of(context).size.height,
        margin: isMobile()
            ? const EdgeInsets.fromLTRB(2.0, 4.0, 2.0, 4.0)
            : const EdgeInsets.all(desktopOuterPadding),
        // : const EdgeInsets.all(48.0),
        decoration: const BoxDecoration(
          color: mainSetupBgColor,
          borderRadius: BorderRadius.all(Radius.circular(mainBorderRadius)),
        ),
        child: Container(
            constraints: isMobile()
                ? null
                : BoxConstraints(
                    maxWidth: min(MediaQuery.of(context).size.width,
                        desktopSetupWidthConstrn)),
            padding: mainPadding,
            child: SingleChildScrollView(
                child: FastForm(
                    formKey: _formKey,
                    onChanged: (m) {
                      _updateAdvancedForm(m);
                    },
                    children: <Widget>[
                  const Text(
                    'Welcome 👋💠',
                    style: TextStyle(fontSize: 48, color: mainSetupTextColor),
                  ),
                  Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4.0, vertical: 12),
                      child: Text(
                        '''HandHeld Helper is a fast and lean app allowing you to run LLM AIs locally, on your device.
HHH respects your privacy: once the LLM is downloaded, it works purely offline and never shares your data.
LLM checkpoints are large binary files. To download, store, manage and operate them, the app needs certain permissions, as well as network bandwidth and storage space – currently 4.1 GB for a standard 7B model.''',
                        textAlign: TextAlign.left,
                        style: TextStyle(
                            fontSize: setupTextSize, color: mainSetupTextColor),
                      )),
                  if (remind_storage_permissions &&
                      platform_requires_storage_permissions)
                    HoverableText(
                        borderRadius: setupSubBorderRadius,
                        bgColor: setupSubBgColor,
                        hoverBgColor: setupSubHoverBgColor,
                        child: Padding(
                          padding: interButtonPadding,
                          child: Row(children: [
                            Expanded(
                                child: Text(
                              'Please accept data storage permissions',
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
                          borderRadius: setupSubBorderRadius,
                          bgColor: setupSubBgColor,
                          hoverBgColor: setupSubHoverBgColor,
                          child: Padding(
                            padding: interButtonPadding,
                            child: Row(children: [
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(
                                      'Accept recommended settings and begin downloading the AI model',
                                      style: largeBtnFontStyle,
                                      // 'Accept the data storage defaults and download the recommended LLM (${defaultLLM.name})',
                                    ),
                                    Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.start,
                                        children: [
                                          Text(
                                              'Download size: ${(defaultLLM.size / 1e9).toStringAsFixed(1)}Gb',
                                              style: autoInstallerInfoStyle)
                                        ])
                                  ])),
                              const Icon(Icons.download_for_offline,
                                  size: 32, color: Colors.grey),
                            ]),
                          )),
                      expandedChild: plainOutline(
                        bgcolor: setupSubExpandedBgColor,
                        child: Padding(
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
                                      customChild: BackgroundDownloadWidget(
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
                                              color: largeBtnFontStyle.color))),
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
                          borderRadius: setupSubBorderRadius,
                          bgColor: setupSubBgColor,
                          hoverBgColor: setupSubHoverBgColor,
                          child: Padding(
                            padding: interButtonPadding,
                            child: Row(children: [
                              Expanded(
                                  child: Text(
                                      'Show advanced model & storage settings',
                                      style: TextStyle(
                                          fontSize: btnFontSize,
                                          color: largeBtnFontStyle.color))),
                              const Icon(Icons.app_settings_alt,
                                  size: 32, color: Colors.grey),
                            ]),
                          )),
                      expandedChild: plainOutline(
                        bgcolor: setupSubExpandedBgColor,
                        child: Padding(
                            padding: interButtonPadding,
                            child: Column(children: [
                              Row(children: [
                                Expanded(
                                    child: Text(
                                        'Advanced model & storage settings',
                                        style: TextStyle(
                                            fontSize: btnFontSize,
                                            color: Colors.blue))),
                                const Icon(Icons.app_settings_alt,
                                    size: 32, color: Colors.grey)
                              ]),
                              separator,
                              CustomFilePicker(
                                  initialValue: hhh_dir,
                                  pickBtnText: "Pick folder",
                                  label: "HandHeld Helper root directory",
                                  name: "hhh_root",
                                  isDirectoryPicker: true),
                              separator,
                              CustomFilePicker(
                                  pickBtnText: "Pick file",
                                  // initialValue: isMobile()
                                  //     ? "__%DOWNLOADS"
                                  //     : user_home_dir,
                                  label: "Custom default LLM file (GGUF)",
                                  name: "custom_default_model",
                                  isDirectoryPicker: false),
                              separator,
                              CustomFilePicker(
                                  pickBtnText: "Pick folder",
                                  label:
                                      "(Optional) Auxiliary custom model directory",
                                  name: "aux_model_root",
                                  isDirectoryPicker: true,
                                  // allowedExtensions: const ["gguf", "GGUF"],
                                  errTextColor: Colors.yellowAccent.shade700,
                                  errBgColor: Colors.white54,
                                  errBgBtnColor: Colors.black12),
                              separator,
                              Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 0, vertical: 12),
                                  child: EnabledButton(
                                      onPressed: () {
                                        if (_validRootAppParams != null) {
                                          Timer(
                                              const Duration(milliseconds: 500),
                                              () {
                                            print(
                                                "COMPLETING ADVANCED APP SETUP WITH PARAMS=${_validRootAppParams!.toJson()}");
                                            widget.onSetupComplete(
                                                _validRootAppParams!);
                                          });
                                        }
                                      },
                                      isDisabled: !canUserAdvance,
                                      disabledText: _advanced_form_errors
                                              .isEmpty
                                          ? 'Complete the necessary steps'
                                          : _advanced_form_errors.join(", "),
                                      child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Center(
                                                child: Text(
                                                    'Start conversation',
                                                    style: TextStyle(
                                                        fontSize: btnFontSize,
                                                        color: canUserAdvance
                                                            ? Colors
                                                                .lightGreenAccent
                                                            : Colors.grey))),
                                            Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8.0,
                                                        vertical: 0.0),
                                                child: Icon(Icons.chat,
                                                    color: canUserAdvance
                                                        ? Colors
                                                            .lightGreenAccent
                                                        : Colors.grey))
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

Future<int> resolve_native_ctxlen(String new_modelpath) async {
  Map<String, dynamic>? metadata;
  try {
    metadata =
        await parseGGUF(new_modelpath, findKeys: {"llama.context_length"});
  } catch (e) {
    print("Error in parseGGUF: $e");
  }

  var model_filename = Path.basename(new_modelpath);

  int native_ctxlen = extract_ctxlen_from_name(new_modelpath) ??
      (metadata?["llama.context_length"] ?? DEFAULT_CTXLEN);

  if (APPROVED_LLMS.map((m) => m.getFileName()).contains(model_filename)) {
    var maybeApprovedLLM =
        APPROVED_LLMS.firstWhere((m) => m.getFileName() == model_filename);
    if (maybeApprovedLLM != null && maybeApprovedLLM.native_ctxlen != null) {
      native_ctxlen = maybeApprovedLLM.native_ctxlen!;
    }
  }

  return native_ctxlen;
}

class CustomButton extends StatefulWidget {
  const CustomButton(
    this.textWidget, {
    this.iconIdle = Icons.copy_rounded,
    this.iconActivated = Icons.check,
    this.iconColor,
    this.onTap,
    super.key,
  });

  final Widget textWidget;
  final Color? iconColor;
  final VoidCallback? onTap;
  final IconData iconIdle;
  final IconData iconActivated;

  @override
  State<CustomButton> createState() => _CustomButtonState();
}

class _CustomButtonState extends State<CustomButton> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        child: SizedBox(
          width: 25,
          height: 25,
          child: Icon(
            _copied ? widget.iconActivated : widget.iconIdle,
            size: 18,
            color: widget.iconColor ?? const Color(0xff999999),
          ),
        ),
        onTap: () async {
          final textWidget = widget.textWidget;
          String text;
          if (textWidget is RichText) {
            text = textWidget.text.toPlainText();
          } else {
            text = textWidget.toString();
          }
          if (widget.onTap != null) {
            widget.onTap!();
          }
          setState(() {
            _copied = true;
            Future.delayed(const Duration(seconds: 1)).then((value) {
              if (mounted) {
                setState(() {
                  _copied = false;
                });
              }
            });
          });
        },
      ),
    );
  }
}

showSnackBarTop(BuildContext context, String msg, {int delay = 750}) {
  var snackBar = SnackBar(
      duration: Duration(milliseconds: delay),
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.only(bottom: MediaQuery.of(context).size.height - 96),
      content: Text(msg),
      dismissDirection: DismissDirection.none);

  // Find the ScaffoldMessenger in the widget tree
  // and use it to show a SnackBar.
  ScaffoldMessenger.of(context).showSnackBar(snackBar);
}

List<String> playablePrefixes = ["<!doctype html>", "<html"];

AutoClearMap<String, bool> playableCache = AutoClearMap(maxAge: 10);

bool isCodePlayable(String? code, {maxCheckLength = 128}) {
  if (code == null || code.isEmpty || code.trim().isEmpty) {
    return false;
  }

  // TODO: more selectivity
  code = code.trim().toLowerCase();

  code = code.substring(0, min(maxCheckLength, code.length));

  if (playableCache.containsKey(code)) {
    return playableCache[code]!;
  }

  bool ret = false;

  for (var p in playablePrefixes) {
    if (code.startsWith(p)) {
      ret = true;
    }
  }

  playableCache[code] = ret;

  return ret;
}

void markChatMessageSpecial(ChatMessage ret, Map<String, dynamic>? flags) {
  if (flags?.containsKey("_canceled_by_user") ?? false) {
    ret.customBackgroundColor = Colors.orange.shade600;
    ret.customTextColor = Colors.black;
  } else if (flags?.containsKey("_interrupted") ?? false) {
    ret.customBackgroundColor = const Color.fromRGBO(200, 80, 80, 1.0);
    ret.customTextColor = Colors.white;
  }
}

List<ChatMessage> dbMsgsToDashChatMsgs(List<Message> msgs) {
  return msgs.map((m) {
    var ret = ChatMessage(
        user: getChatUserByName(m.username),
        text: m.message,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m.date * 1000),
        customProperties: m.meta);

    markChatMessageSpecial(ret, m.meta);

    return ret;
  }).toList();
}

/// {@category Default widgets}
class ProgressTypingBuilder extends StatelessWidget {
  const ProgressTypingBuilder({
    required this.user,
    this.pkey = "undefined",
    this.text = 'is typing',
    this.progress = 0.0,
    this.workAmount = 0.0,
    this.showProgress = false,
    Key? key,
  }) : super(key: key);

  /// User that is typing
  final ChatUser user;

  /// Text to show after user's name in the indicator
  final String text;
  final String pkey;
  final double progress;
  final double workAmount;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    var bgColor = Theme.of(context).primaryColorDark;
    var textColor = Theme.of(context).listTileTheme.textColor;
    var lighterBgColor = Theme.of(context).colorScheme.secondary;

    return Padding(
      padding: const EdgeInsets.only(left: 15, top: 25),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(right: 2),
            child: TypingIndicator(),
          ),
          Text(
            user.getFullName(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          Text(
            ' $text',
            style: TextStyle(
              fontSize: 12,
              color: textColor,
            ),
          ),
          if (showProgress)
            Expanded(
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(8.0, 2.0, 16.0, 2.0),
                    child: LinearProgressIndicator(
                        value: progress,
                        borderRadius: BorderRadius.circular(3.0),
                        backgroundColor: textColor,
                        color: lighterBgColor)))
          // child: SelfCalibratingProgressBar(
          //     pkey: pkey,
          //     progress: progress,
          //     workAmount: workAmount,
          //     progressBarBuilder: (progress) => LinearProgressIndicator(
          //         value: progress,
          //         borderRadius: BorderRadius.circular(3.0),
          //         backgroundColor: textColor,
          //         color: Colors.teal.shade600))))
        ],
      ),
    );
  }
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
  bool _needs_restore = true;
  Timer? _token_counter_sync;
  int _input_tokens = 0;
  Chat? _current_chat;
  DateTime? _last_chat_persist;
  String _current_msg_input = "";
  String? _incomplete_msg;
  double _prompt_processing_progress = 0;
  double _prompt_processing_ntokens = 0.0;
  DateTime? _prompt_processing_completed;
  DateTime? _prompt_processing_initiated;
  double llm_load_progress = 0.0;
  bool suspended = false;
  bool _initial_modelload_done = false;

  TextEditingController dashChatInputController = TextEditingController();
  FocusNode dashChatInputFocusNode = FocusNode();

  Map<String, dynamic> llama_init_json = resolve_init_json();

  String? _htmlCode;

  var _modalState;

  void _showWarningModal({
    String title = 'Warning',
    String content = 'Default warning message.',
    String buttonText = 'OK',
    VoidCallback? onClose,
  }) {
    setState(() {
      _modalState = {
        'title': title,
        'content': content,
        'buttonText': buttonText,
        'onClose': () {
          setState(() {
            _modalState = null;
          });
          if (onClose != null) {
            onClose();
          }
        },
      };
    });
  }

  Widget buildModals(BuildContext context) {
    if (_modalState != null) {
      return showWarningModal(
        title: _modalState['title'],
        content: _modalState['content'],
        buttonText: _modalState['buttonText'],
        onClose: _modalState['onClose'],
      );
    } else {
      return Container();
    }
  }

  Widget buildCodePlayer(BuildContext context) {
    if (isMobile() && _htmlCode != null) {
      // TODO: desktop webview support
      return Container(
        height: MediaQuery.of(context).size.height * 0.9,
        width: MediaQuery.of(context).size.width * 0.95,
        padding: const EdgeInsets.symmetric(vertical: 1.0, horizontal: 2.0),
        alignment: AlignmentDirectional.center,
        decoration: const BoxDecoration(
          color: Colors.lightBlue,
          borderRadius: BorderRadius.all(Radius.circular(10.0)),
        ),
        child: _buildWebView(content: _htmlCode),
      );
    }
    return Container();
  }

  reinitState() {
    _msg_streaming = false;
    _msg_poll_timer;
    settings = Settings();
    _initialized = false;
    _needs_restore = true;
    _token_counter_sync;
    _input_tokens = 0;
    _current_chat;
    _last_chat_persist;
    _current_msg_input = "";
    _incomplete_msg;
    _prompt_processing_progress = 0;
    _prompt_processing_ntokens = 0.0;
    _prompt_processing_completed;
    _prompt_processing_initiated;
    llm_load_progress = 0.0;
    suspended = false;
    llama_init_json = resolve_init_json();
    _modalState = null;
    dashChatInputController.dispose();
    dashChatInputController = TextEditingController();
    _htmlCode = null;
  }

  @override
  void initState() {
    print("LIFECYCLE: ACTIVE CHAT .INITSTATE()");
    super.initState();
    if (isMobile()) WidgetsBinding.instance.addObserver(this);
    // if (!isMobile()) {
    //   ServicesBinding.instance.keyboard.addHandler(_onKey);
    // }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (isMobile() && state == AppLifecycleState.paused) {
      print(
          "ANDROID OS: PAUSED. The app is about to be suspended, persisting...");
      _cancel_timers();
      persistState();
      // llm.deinitialize(); - OS can NOT do this, we could hope for it
      suspended = true;
    }

    if (state == AppLifecycleState.resumed) {
      print(
          "ANDROID OS: RESUMED. The app has been resumed, suspended=$suspended");
      if (suspended && llm.initialized) {
        print("Attempting to restore AI answer streaming...");
        if (_msg_streaming) {
          _enable_stream_poll_timer();
        }
      } else {
        print(
            "suspended=$suspended, llm.initialized=${llm.initialized} => attempting to restart AI & chat...");
        reinitState();
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    print("LIFECYCLE: ACTIVE CHAT .DISPOSE()");
    dashChatInputController.dispose();
    dashChatInputFocusNode.dispose();
    if (isMobile()) {
      WidgetsBinding.instance!.removeObserver(this);
    }
    print("ActiveChatDialogState: attempting to persist state...");
    _cancel_timers();
    // persistState();
    stop_llm_generation(now: true);
    // if (!isMobile()) {
    //   ServicesBinding.instance.keyboard.removeHandler(_onKey);
    // }
    super.dispose();
  }

  // bool _onKey(KeyEvent event) {
  //   final key = event.logicalKey.keyLabel;
  //
  //   if (event is KeyDownEvent) {
  //     print("Key down: $key");
  //   } else if (event is KeyUpEvent) {
  //     print("Key up: $key");
  //   } else if (event is KeyRepeatEvent) {
  //     print("Key repeat: $key");
  //   }
  //
  //   return false;
  // }

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
      '_persist_datetime': DateTime.now().toString(),
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
      _last_chat_persist = DateTime.parse(json['_persist_datetime'] ?? "");

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

  int? sync_messages_to_llm() {
    llm.msgs = _messages.map((m) {
      if (m.customProperties != null &&
          (m.customProperties
                  ?.containsValue("_is_system_message_with_prompt") ??
              false)) {
        return AIChatMessage(m.user.getFullName(),
            m.customProperties!["_is_system_message_with_prompt"] as String);
      }
      return AIChatMessage(m.user.getFullName(), m.text);
    }).toList();
    return llm.sync_token_count();
  }

  Future<bool> persistState() async {
    final t0 = DateTime.now();
    try {
      var json = toJson();
      await metaKV.setMetadata("_persist_active_chat_state", json);
    } catch (e) {
      print("Exception in ActiveChatDialogState.persistState: $e");
      var t1 = DateTime.now();
      print("DB PERSIST [FAILURE] TOOK ${t1.difference(t0).inMilliseconds}ms");
      return false;
    }
    _last_chat_persist = DateTime.now();
    var t1 = DateTime.now();
    print("DB PERSIST [SUCCESS] TOOK ${t1.difference(t0).inMilliseconds}ms");
    return true;
  }

  Future<void> clearPersistedState({onlyStreaming = false}) async {
    try {
      if (onlyStreaming) {
        print("clearPersistedState onlyStreaming = true");

        var data = await metaKV.getMetadata("_persist_active_chat_state");
        if (data == null) {
          return;
        } else {
          var jmap = data as Map<String, dynamic>;
          jmap["_msg_streaming"] = false;
          jmap.remove("_ai_msg_stream_acc");
          await metaKV.setMetadata("_persist_active_chat_state", jmap);
          print("clearPersistedState SUCCESS");
        }
      } else {
        await metaKV.deleteMetadata("_persist_active_chat_state");
      }
    } catch (e) {
      print(
          "Error during clearPersistedState, onlyStreaming=$onlyStreaming, Exception:$e");
    }
  }

  Future<bool> restoreState() async {
    try {
      var data = await metaKV.getMetadata("_persist_active_chat_state");
      if (data == null) {
        print("PERSISTED CHAT STATE SLOT EMPTY");
        return false;
      }
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
        _prompt_processing_ntokens = 0.0;
        _prompt_processing_initiated = null;
        _prompt_processing_completed = null;
        return false;
      } else {
        // The restored state might not have finished if the persist happened mid of
        // AI writing an answer, we must handle this case and might need to restart polling timer
        if (_msg_streaming) {
          /* for now we just add this as a message with metadata _interrupted = true
          and restore the state to initial TODO ... */
          _msg_streaming = false;
          _prompt_processing_ntokens = 0.0;
          _prompt_processing_initiated = null;
          _prompt_processing_completed = null;

          var partial_answer = data['_ai_msg_stream_acc'];
          if (partial_answer is String && partial_answer.isNotEmpty) {
            print("RESTORING PARTIAL AI ANSWER...: $partial_answer");

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
            }
          }

          await clearPersistedState(onlyStreaming: true);
          setState(() {});
        }
      }

      // Clean possible erroneous states, e.g. last msg is user's
      if (_messages[0].user == user) {
        print("LAST MESSAGE IS FROM USER, REWINDING...");
        var rewound = await rewindChat(1);
        if (rewound.isNotEmpty && rewound[0].username == "user") {
          set_chat_input_field(rewound[0].message);
          print("REWIND SUCCESSFUL");
        } else {
          print("REWIND FAIlED, rewound=$rewound");
        }
      }

      return true;
    } catch (e) {
      print("Exception in ActiveChatDialogState.restoreState: $e");
      return false;
    }
  }

  Future<void> create_new_chat(
      {system_prompt = hermes_sysmsg,
      Map<String, dynamic> custom_properties = const {}}) async {
    var firstMsg = ChatMessage(
        text:
            "Beginning of conversation with model at `${llm.modelpath}`\\\nSystem prompt:\\\n__${settings.get('system_message', system_prompt)}__",
        user: user_SYSTEM,
        createdAt: DateTime.now(),
        customProperties: {
          "_is_system_message_with_prompt": system_prompt,
          "_llm_modelpath": llm.modelpath,
          ...custom_properties
        });

    _current_chat = await chatManager.createChat(
        firstMessageText: firstMsg.text,
        firstMessageUsername: "SYSTEM",
        firstMessageMeta: firstMsg.customProperties);

    _messages = [firstMsg];

    await persistState();

    var tokens_used = sync_messages_to_llm();

    setState(() {
      _initialized = true;
      _msg_streaming = false;
      _prompt_processing_ntokens = 0.0;
      _prompt_processing_initiated = null;
      _prompt_processing_completed = null;
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

  Future<List<Message>> rewindChat(int n_items_to_rewind) async {
    Chat current = await getCurrentChat();
    var removed_msgs =
        await chatManager.popMessagesFromChat(current.uuid, n_items_to_rewind);
    var restored_messages = dbMsgsToDashChatMsgs(await chatManager
        .getMessagesFromChat(_current_chat!.uuid, reversed: true));
    _messages = restored_messages;
    sync_messages_to_llm();
    return removed_msgs;
  }

  void set_chat_input_field(String s) {
    _current_msg_input = s;
    _update_token_counter(s);
    dashChatInputController.text = s;
    dashChatInputController.notifyListeners();
    setState(() {});
  }

  Future<void> addMessageToActiveChat(String username, String msg,
      {Map<String, dynamic>? meta}) async {
    Chat current = await getCurrentChat();
    chatManager.addMessageToChat(current.uuid, msg, username, meta: meta);

    var cmsg = ChatMessage(
        user: getChatUserByName(username),
        createdAt: DateTime.now(),
        text: msg,
        customProperties: meta);

    _messages.insert(0, cmsg);
    markChatMessageSpecial(cmsg, meta);
    sync_messages_to_llm();
  }

  Future<void> updateStreamingMsgView(
      {canceled = false, String? final_ai_output}) async {
    Chat current = await getCurrentChat();

    var finished = false;
    var interrupted_by_user = canceled;
    AIChatMessage? completedMsg;

    if (!canceled) {
      var poll_result = llm.poll_advance_stream();
      finished = poll_result.finished;
      _prompt_processing_progress = poll_result.progress;

      if (_prompt_processing_completed == null &&
          (_prompt_processing_progress - 1.0).abs() < 0.01) {
        var now = DateTime.now();
        try {
          print(
              "Completed prompt processing at ${now.toString()}, time taken: ${now.difference(_prompt_processing_initiated!).inMilliseconds}ms");
        } catch (e) {}
        _prompt_processing_completed = now;
      }

      if (finished) {
        completedMsg = llm.msgs.last;
        if (completedMsg.role == "assistant") {
          chatManager.addMessageToChat(
              current.uuid, completedMsg.content, "AI");
          await clearPersistedState(onlyStreaming: true);
        } else {
          print("ERROR: COULD NOT GENERATE STREAMING MESSAGE");
          await clearPersistedState(onlyStreaming: true);
          // TODO handle this hypo case
        }
      } else {
        await metaKV.setMetadata(
            "_msg_stream_in_progress_", llm.stream_msg_acc);
      }
    } else {
      finished = true;

      if (final_ai_output != null) {
        completedMsg = AIChatMessage("assistant", final_ai_output!);
        chatManager.addMessageToChat(current.uuid, final_ai_output!, "AI",
            meta: {"_interrupted": true, "_canceled_by_user": true});
        await metaKV.deleteMetadata("_msg_stream_in_progress_");
      } else {
        print("LLM HAS NOT STARTED GENERATING YET");
        // TODO handle
      }
    }

    setState(() {
      if (finished) {
        _msg_poll_timer?.cancel();
        _msg_streaming = false;
        _prompt_processing_ntokens = 0.0;

        if (completedMsg != null) {
          _messages[0].createdAt = completedMsg.createdAt;
          _messages[0].text = completedMsg.content;
          if (interrupted_by_user) {
            _messages[0].customProperties = {
              "_interrupted": true,
              "_canceled_by_user": true
            };
          }
        }

        markChatMessageSpecial(_messages[0], _messages[0].customProperties);

        print("${_messages[0].customProperties}");

        _typingUsers = [];
        _incomplete_msg = null;
      } else {
        _incomplete_msg = llm.stream_msg_acc;
        _messages[0].text = llm.stream_msg_acc;

        if (_last_chat_persist == null ||
            DateTime.now().difference(_last_chat_persist!).inMilliseconds >
                MIN_STREAM_PERSIST_INTERVAL) {
          persistState();
        }
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

    var now = DateTime.now();
    print("Initiated prompt processing at ${now.toString()}");

    _prompt_processing_ntokens = 1.0 * llm.tokenize(m.text).length;
    _prompt_processing_initiated = now;
    _prompt_processing_completed = null;

    var success = llm.start_advance_stream(user_msg: m.text);
    _msg_streaming = true;

    setState(() {
      _typingUsers = [user_ai];
      _messages.insert(0, m);
      var msg = ChatMessage(
          user: user_ai,
          text: "...", // TODO animation
          createdAt: llm.msgs.last.createdAt,
          customProperties: {"_placeholder_ai": true});
      _messages.insert(0, msg);
      _enable_stream_poll_timer();
    });
  }

  void reload_model_from_file(
      String new_modelpath, VoidCallback? onInitDone) async {
    // final metadata =
    //     await parseGGUF(new_modelpath, findKeys: {"llama.context_length"});
    //
    // int native_ctxlen = extract_ctxlen_from_name(new_modelpath) ??
    //     metadata?["llama.context_length"] ??
    //     DEFAULT_CTXLEN;
    //
    // var model_filename = Path.basename(new_modelpath);
    //
    // if (APPROVED_LLMS.map((m) => m.getFileName()).contains(model_filename)) {
    //   var maybeApprovedLLM =
    //       APPROVED_LLMS.firstWhere((m) => m.getFileName() == model_filename);
    //   if (maybeApprovedLLM != null && maybeApprovedLLM.native_ctxlen != null) {
    //     native_ctxlen = maybeApprovedLLM.native_ctxlen!;
    //   }
    // }

    var native_ctxlen = await resolve_native_ctxlen(new_modelpath);

    setState(() {
      _initialized = false;
      _messages = [
        ChatMessage(
            user: user_SYSTEM,
            text: "... Loading new model from \"$new_modelpath\"",
            createdAt: DateTime.now())
      ];
    });

    print("llm.initialize [2]: $new_modelpath");
    llm.initialize(
        modelpath: new_modelpath,
        llama_init_json:
            resolve_init_json(n_ctx: min(MAX_CTXLEN, native_ctxlen)),
        onProgressUpdate: (double progress) {
          setState(() {
            llm_load_progress = progress;
          });
        },
        onInitDone: (success) async {
          if (success) {
            // await create_new_chat();
            unlock_actions();
            if (onInitDone != null) {
              onInitDone();
            }
          } else {
            // TODO: handle init failure
            _showWarningModal(
                content:
                    "Could not load the model at $new_modelpath\nSystem will try to load the default model when you dismiss this modal.",
                onClose: () {
                  load_default_model();
                });
          }
        });
  }

  void load_default_model({void Function(bool)? onInitDone}) {
    if (llm.initialized) {
      llm.deinitialize();
    }
    initAIifNotAlready(
        force_default_model: true,
        attempt_restore_chat: false,
        onInitDone: onInitDone);
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

  String? getDefaultLLM() {
    var params = getAppInitParams();
    if (params != null) {
      return params.default_model;
    }
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
    if (!_needs_restore) {
      print("attemptToRestartChat(): already tried, avoding restore");
      _initialized = true;
      return;
    }
    print("ActiveChatDialogState: attemptToRestartChat()...");
    restoreState().then((success) {
      _needs_restore = false;
      if (!success) {
        print("[ERROR] RESTORE FAILED, CREATING NEW CHAT");
        create_new_chat();
      } else {
        print("[OK] RESTORE CHAT SUCCEEDED");
        print("Messages: ${msgs_toJson()}");
        setState(() {
          _initialized = true;
        });
      }
    });
  }

  Future<String?> attemptToRestoreChatModelPath() async {
    try {
      var data = await metaKV.getMetadata("_persist_active_chat_state");
      if (data == null) {
        print("PERSISTED CHAT STATE SLOT EMPTY");
        return null;
      } else {
        if (data != null) {
          Map<String, dynamic> metadata = data as Map<String, dynamic>;
          if (metadata.containsKey("chat_uuid")) {
            var msgs = await chatManager
                .getMessagesFromChat(Uuid.fromJson(data!["chat_uuid"]));
            if (msgs.isNotEmpty) {
              print("!!! ${msgs[0]}");
              if (msgs[0].meta != null &&
                  msgs[0].meta.containsKey("_is_system_message_with_prompt")) {
                print("FOUND SYSTEM MESSAGE: ${msgs[0]}");
                if (msgs[0].meta.containsKey("_llm_modelpath")) {
                  return msgs[0].meta!["_llm_modelpath"] as String;
                }
              }
            }
          }
        }
      }
    } catch (e) {
      print("Exception: $e");
    }
    return null;
  }

  Future<void> initAIifNotAlready(
      {bool force_default_model = false,
      bool attempt_restore_chat = true,
      void Function(bool)? onInitDone}) async {
    if (!force_default_model && _initial_modelload_done) {
      return;
    }
    if (llm.init_in_progress ||
        llm.state == LLMEngineState.INITIALIZED_SUCCESS ||
        llm.state == LLMEngineState.INITIALIZED_FAILURE) {
      print("initAIifNotAlready: llm.init_in_progress");
      if (llm.state == LLMEngineState.INITIALIZED_SUCCESS) {
        print("LLM already initialized, unlocking actions");
        unlock_actions();
        if (attempt_restore_chat) {
          attemptToRestartChat();
        }
      }
    } else if (!llm.initialized && // TODO: streamline llm engine states
        llm.init_postponed &&
        getAppInitParams() != null) {
      print("initAIifNotAlready: llm.init_postponed");
      print("INITIALIZING NATIVE LIBRPCSERVER");
      if (Platform.isAndroid) {
        requestStoragePermission();
      }

      RootAppParams p = getAppInitParams()!;

      bool fallback = false;
      var default_modelpath = resolve_llm_file(p);
      String modelpath = default_modelpath;
      String? chat_modelpath = await attemptToRestoreChatModelPath();

      if (!force_default_model && chat_modelpath != null) {
        if (File(chat_modelpath).existsSync()) {
          print("RESTORING CUSTOM MODEL FROM SAVED CHAT: $chat_modelpath");
          modelpath = chat_modelpath;
        } else {
          print(
              "WARNING COULD NOT ACCESS CUSTOM MODEL FROM SAVED CHAT: $chat_modelpath");
          print("FALLBACK TO DEFAULT MODEL");
          fallback = true;
        }
      } else {
        print("LOADING DEFAULT MODEL: $default_modelpath");
      }

      var native_ctxlen = await resolve_native_ctxlen(modelpath);

      print("llm.initialize [1]: $modelpath");
      llm.initialize(
          modelpath: modelpath,
          llama_init_json:
              resolve_init_json(n_ctx: min(MAX_CTXLEN, native_ctxlen)),
          onProgressUpdate: (double progress) {
            setState(() {
              llm_load_progress = progress;
            });
          },
          onInitDone: (success) {
            if (success) {
              _initial_modelload_done = true;
              print("ActiveChatDialogState: attempting to restore state...");
              if (!attempt_restore_chat || fallback) {
                // custom model could not be loaded, the history would be, strictly speaking, invalid
                create_new_chat();
              } else {
                if (attempt_restore_chat) {
                  attemptToRestartChat();
                }
              }
              unlock_actions();
            } else {
              // TODO: handle failure better
              _initial_modelload_done = false;
              _showWarningModal(
                  content:
                      "Could not load the model at $modelpath\nSystem will try to load the default model when you dismiss this modal.",
                  onClose: () {
                    load_default_model();
                  });
            }
            if (onInitDone != null) {
              onInitDone(success);
            }
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
        lock_actions();
        cleanup_llm();
        reload_model_from_file(new_model, () {
          create_new_chat();
          unlock_actions();
        });
      }
    } else {
      // User canceled the picker
    }
  }

  executeChatShare() {
    FlutterClipboard.copy(msgs_toJson());
    showSnackBarTop(context, 'Conversation copied to clipboard');
  }

  cleanup_llm() {
    llm.deinitialize();

    // TODO: make this unnecessary
    print("Reloading LLM Engine ...");
    llm = LLMEngine();
  }

  ui_create_new_active_chat({bool force_default_llm = false}) async {
    var defaultLLM = getDefaultLLM();
    var p = getAppInitParams();
    if (defaultLLM != null && p != null) {
      var current_llm = Path.basename(llm.modelpath);

      print(
          "ui_create_new_active_chat(): current_llm=$current_llm, defaultLLM=$defaultLLM");

      if (false && force_default_llm && current_llm != defaultLLM) {
        print("ui_create_new_active_chat(): llm.deinitialize()");
        cleanup_llm();
        reload_model_from_file(resolve_llm_file(p, model_file: defaultLLM), () {
          setState(() {
            _initialized = true;
          });
          create_new_chat();
        });
        setState(() {
          _initialized = false;
        });
      } else {
        llm.clear_state();
        create_new_chat();
      }
    }
  }

  stop_llm_generation({now = false}) async {
    if (_msg_streaming) {
      await clearPersistedState(onlyStreaming: true);
      _msg_poll_timer?.cancel();

      void onComplete(String? final_ai_output) {
        updateStreamingMsgView(
            canceled: true, final_ai_output: final_ai_output);
      }

      if (now) {
        llm.cancel_advance_stream();
        onComplete(null);
      } else {
        await llm.cancel_advance_stream(onComplete: onComplete);
      }
    }
  }

  ui_show_settings_menu() {
    // TODO
  }

  final _scaffoldKey = new GlobalKey<ScaffoldState>();

  Widget _buildWebView({String? content}) {
    return Container();
  }

  HttpServer? server;

  startCodeServer() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 65123);
    print("Server running on IP : ${server!.address}On Port : ${server!.port}");
    await for (var request in server!) {
      print(
          "HTTPSERVER REQUEST: ${request.method} ${request.uri.path} $request");
      if (request.method == "GET" &&
          request.uri.path == "/code.html" &&
          _htmlCode != null) {
        request.response
          ..headers.contentType = ContentType.html
          ..write(_htmlCode)
          ..close();
      } else {
        print(
            "HTTPSERVER UNKNOWN REQUEST: ${request.method} ${request.uri.path} $request");
      }
    }
  }

  void showDesktopStandaloneCodePlayer() async {
    if (server == null) {
      startCodeServer();
    }

    launchURL("http://localhost:65123/code.html");
  }

  WebViewController? controller;

  void showMobileCodePlayer(String htmlCode) {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            // Update loading bar.
          },
          onPageStarted: (String url) {},
          onPageFinished: (String url) {},
          onWebResourceError: (WebResourceError error) {},
          onNavigationRequest: (NavigationRequest request) {
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadHtmlString(htmlCode, baseUrl: "/");

    Color headerTextColor = Theme.of(context).appBarTheme.foregroundColor!;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
            child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Icon(
                size: actionIconSize,
                Icons.settings_applications,
                color: headerTextColor,
              ),
              Expanded(
                child: Text(
                  'HHH Code Runner',
                  style: TextStyle(color: headerTextColor, fontSize: 20),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ]),
            Container(
                padding: const EdgeInsets.all(10),
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.6,
                ),
                child: Expanded(
                  child: WebViewWidget(controller: controller!),
                )),
          ],
        ));
      },
    );
  }

  void showCodePlayer(String htmlCode) {
    _htmlCode = htmlCode;

    if (isMobile()) {
      showMobileCodePlayer(htmlCode);
    } else {
      showDesktopStandaloneCodePlayer();
    }
    setState(() {});
  }

  List<Widget> attemptToShowCodePlayAction(String? code) {
    if (code == null || !isCodePlayable(code)) {
      return const [];
    }

    return [
      CustomButton(const Text("Play"), iconIdle: Icons.play_arrow, onTap: () {
        print("CODE PLAY: $code");
        showCodePlayer(code);
      })
    ];
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
    Color iconEnabledColor = Colors.white;
    Color iconColor = actionsEnabled ? iconEnabledColor : disabledColor;

    Color warningColor = Theme.of(context).colorScheme.error!;
    bool tokenOverload = (llm.tokens_used + _input_tokens) >= llm.n_ctx;

    Widget mainWidget;

    var activeColor = Theme.of(context).primaryColor;
    Color lighterActiveColor = activeColor.lighter(50);
    var bgColor = Theme.of(context).listTileTheme.tileColor;
    var aiMsgColor = Theme.of(context).listTileTheme.tileColor;
    var userMsgColor = Theme.of(context).listTileTheme.selectedTileColor;
    var textColor = Theme.of(context).listTileTheme.textColor;
    var hintColor = Theme.of(context).hintColor;
    Color headerTextColor = Theme.of(context).appBarTheme.foregroundColor!;

    var now = DateTime.now();

    var showMsgProgress = false;
    var aiIsThinking = false;

    if (_msg_streaming &&
        ((_prompt_processing_completed == null) ||
            (_prompt_processing_completed != null &&
                now.difference(_prompt_processing_completed!).inMilliseconds <
                    100))) {
      showMsgProgress = true;
    }

    if (_msg_streaming && _prompt_processing_completed == null) {
      aiIsThinking = true;
    }

    // print("aiIsThinking: $aiIsThinking, showMsgProgress: $showMsgProgress");

    var _app_setup_done = app_setup_done();

    if (_app_setup_done) {
      initAIifNotAlready();
      mainWidget = Expanded(
        child: DashChat(
          inputOptions: InputOptions(
              textController: dashChatInputController,
              focusNode: dashChatInputFocusNode,
              sendButtonBuilder: (Function fct) => InkWell(
                    onTap: () => fct(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 10),
                      child: Stack(children: [
                        Icon(
                          size: 40,
                          Icons.send,
                          color: _current_msg_input.isNotEmpty
                              ? activeColor
                              : hintColor,
                        ),
                        if (_input_tokens > 0) ...[
                          Transform.translate(
                              offset: const Offset(1.0, -20.0),
                              child: SizedBox(
                                width: 40,
                                child: Center(
                                  child: IntrinsicWidth(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 1.0, horizontal: 2.0),
                                      alignment: AlignmentDirectional.center,
                                      decoration: BoxDecoration(
                                        color: activeColor,
                                        borderRadius: const BorderRadius.all(
                                            Radius.circular(10.0)),
                                      ),
                                      child: Text("$_input_tokens",
                                          style: TextStyle(
                                              fontSize: 15,
                                              color: headerTextColor)),
                                    ),
                                  ),
                                ),
                              ))
                        ]
                      ]),
                    ),
                  ),
              // cursorStyle: CursorStyle({color: Color.fromRGBO(40, 40, 40, 1.0)}),
              sendOnEnter: !SEND_SHIFT_ENTER,
              sendOnShiftEnter: SEND_SHIFT_ENTER,
              newlineOnShiftEnter: !SEND_SHIFT_ENTER,
              alwaysShowSend: true,
              inputToolbarMargin: const EdgeInsets.all(0.0),
              inputToolbarPadding:
                  const EdgeInsets.fromLTRB(8.0, 2.0, 8.0, 4.0),
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
              inputDisabled: !(_msg_streaming || (_initialized ?? false)),
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
          messageListOptions: MessageListOptions(
              // showTypingPlaceholder: const SizedBox(height: 64),
              typingBuilder: (ChatUser user) => ProgressTypingBuilder(
                  user: user,
                  text: (showMsgProgress || aiIsThinking)
                      ? 'is thinking'
                      : 'is typing',
                  pkey: "prompt_processing_${llm.modelpath}",
                  workAmount: _prompt_processing_ntokens,
                  showProgress: showMsgProgress,
                  progress: (_incomplete_msg?.isNotEmpty ?? false)
                      ? 1.0
                      : _prompt_processing_progress)),
          messageOptions: MessageOptions(
              fullWidthRow: true, // || isMobile(),
              containerColor: aiMsgColor!,
              currentUserContainerColor: userMsgColor!,
              textColor: textColor!,
              currentUserTextColor: textColor!,
              messageTextBuilder: customMessageTextBuilder,
              buildCodeBlockActions: attemptToShowCodePlayAction,
              showCurrentUserAvatar: false,
              showOtherUsersAvatar: false,
              onLongPressMessage: (m) {
                String msg = "${m.user.getFullName()}: ${m.text}";
                FlutterClipboard.copy(msg);
                showSnackBarTop(context,
                    "Message \"${truncateWithEllipsis(16, msg)}\" copied to clipboard");
              }),
          currentUser: user,
          typingUsers: _typingUsers,
          onSend: (ChatMessage m) {
            dlog("NEW MSG: ${m.text}");
            _input_tokens = 0;
            addMsg(m);
            dashChatInputController.text = "";
            dashChatInputController.notifyListeners();
            if (isMobile()) {
              dashChatInputFocusNode.unfocus();
              FocusManager.instance.primaryFocus?.unfocus();
            }
            setState(() {});
          },
          messages: _messages,
        ),
      );
      if (!_initialized) {
        mainWidget = Stack(
          children: <Widget>[
            // Your existing widget tree goes here
            Center(
                child: Padding(
                    padding: EdgeInsets.all(isMobile() ? 4.0 : 16.0),
                    child: SizedBox(
                        width: 512,
                        child: Container(
                            padding: EdgeInsets.all(3.0),
                            decoration: BoxDecoration(
                              color: bgColor!,
                              border: Border.all(
                                color: lighterActiveColor,
                                width:
                                    1.0, // Adjust the width of the border here
                              ),
                              borderRadius: BorderRadius.circular(
                                  5.0), // Adjust the radius of the border here
                            ),
                            child: LinearProgressIndicator(
                                value: llm_load_progress,
                                minHeight: 6.0,
                                borderRadius: BorderRadius.circular(3.0),
                                color: activeColor))))),
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
      resizeToAvoidBottomInset: isMobile(),
      appBar: _app_setup_done
          ? AppBar(
              leading: IconButton(
                color: iconEnabledColor,
                padding: actionIconPadding,
                icon: Icon(Icons.menu,
                    color: iconEnabledColor,
                    size: actionIconSize), // change this size and style
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
              backgroundColor: Theme.of(context).colorScheme.primary,
              title: Row(children: [
                if (!isMobile())
                  Expanded(
                      child: Text(APP_TITLE_SHORT,
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
                      color: iconEnabledColor,
                    ),
                    onPressed: stop_llm_generation,
                  ),
                IconButton(
                  padding: actionIconPadding,
                  disabledColor: disabledColor,
                  icon: Icon(
                    size: actionIconSize,
                    Icons.psychology_sharp,
                    color: iconColor,
                  ),
                  onPressed: actionsEnabled ? ui_show_settings_menu : null,
                ),
                IconButton(
                  padding: actionIconPadding,
                  disabledColor: disabledColor,
                  icon: Icon(
                    size: actionIconSize,
                    Icons.add_box_outlined,
                    color: iconColor,
                  ),
                  onPressed: actionsEnabled ? ui_create_new_active_chat : null,
                ),
                PopupMenuButton<String>(
                  padding: actionIconPadding,
                  iconSize: actionIconSize,
                  color: iconEnabledColor,
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
              toolbarHeight: 48.0)
          : null,
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: (_htmlCode != null || _modalState != null)
            ? Stack(children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[mainWidget],
                ),
                // buildCodePlayer(context),
                buildModals(context),
              ])
            : Column(
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

String limitText(String text, int max_out_len,
    {bool ellipsis = true, int? max_n_lines}) {
  int start = 0;
  int end = max_out_len;

  if (end > text.length) {
    end = text.length;
  }

  String limitedText = text.substring(start, end);

  if (max_n_lines != null) {
    var lines = limitedText.split('\n');
    int linesCount = lines.length;
    if (linesCount > max_n_lines) {
      limitedText = lines.sublist(0, max_n_lines).join('\n');
    }
  }

  if (ellipsis && end < text.length) {
    limitedText += '...';
  }

  return limitedText;
}

RichText highlightSearchResult(
    String text, String query, int max_out_len, Color highlight_color,
    {bool matchCase = false, ellipsis = true, int? max_n_lines}) {
  int queryIndex = matchCase
      ? text.indexOf(query)
      : text.toLowerCase().indexOf(query.toLowerCase());
  if (queryIndex == -1) {
    return RichText(text: TextSpan(text: text));
  }

  int start = queryIndex - max_out_len ~/ 2;
  int end = queryIndex + query.length + max_out_len ~/ 2;

  if (start < 0) {
    start = 0;
  }
  if (end > text.length) {
    end = text.length;
  }

  String before = text.substring(start, queryIndex);
  String match = text.substring(queryIndex, queryIndex + query.length);
  String after = text.substring(queryIndex + query.length, end);

  if (max_n_lines != null) {
    var _before = before.split('\n');
    var _after = before.split('\n');

    int before_lines = _before.length;
    int after_lines = _after.length;
    if (before_lines > max_n_lines) {
      before =
          _before.sublist(max_n_lines - before_lines, before_lines).join('\n');
    }
    if (after_lines > max_n_lines) {
      after = _after.sublist(0, max_n_lines).join('\n');
    }
  }

  return RichText(
    text: TextSpan(
      children: [
        if (ellipsis && start > 0) const TextSpan(text: "..."),
        if (before.trim().isNotEmpty) TextSpan(text: before),
        TextSpan(
          text: match,
          style: TextStyle(backgroundColor: highlight_color),
        ),
        if (after.trim().isNotEmpty) TextSpan(text: after),
        if (ellipsis && end < text.length) const TextSpan(text: "..."),
      ],
    ),
  );
}

final SEARCH_THROTTLE = isMobile() ? 500 : 300;
const SEARCH_MAX_SNIPPET_LENGTH = 500;

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
  String? _prevQuery;
  String? _query;
  Future<List<(Chat, List<Message>)>>? _searchResults;
  bool _resValid = false;

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
      if (_searchController.text.isNotEmpty &&
          (!((_prevQuery != null) && _searchController.text == _prevQuery))) {
        _query = _searchController.text;
        var res = _chatManager.searchMessagesGrouped(_searchController.text,
            prefixQuery: true);
        setState(() {
          _prevQuery = _searchController.text;
          _searchResults = res;
          _resValid = true;
        });
      } else {
        setState(() {
          _searchResults = null;
          _resValid = false;
        });
      }
    });
  }

  Widget _buildSearchResults() {
    return FutureBuilder<List<(Chat, List<Message>)>>(
      future: _searchResults,
      builder: (BuildContext context,
          AsyncSnapshot<List<(Chat, List<Message>)>> snapshot) {
        var navigate = getNavigate(context);
        if (snapshot.connectionState == ConnectionState.waiting) {
          return hhhLoader(context);
        } else if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        } else {
          var highlight = Theme.of(context).colorScheme.primary;

          Widget search_result_preprocessor(String s) => highlightSearchResult(
              s, _query!, SEARCH_MAX_SNIPPET_LENGTH, highlight,
              max_n_lines: 4);

          return Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 2.0, horizontal: 0.0),
              child: ListView.builder(
                itemCount: snapshot?.data?.length ?? 0,
                itemBuilder: (context, index) {
                  var (chat, messages) = snapshot.data![index];
                  return buildListOfChatsWithMessages(
                      context,
                      chat,
                      messages.isNotEmpty
                          ? messages
                          : [
                              Message.placeholder(
                                  "system", "<conversation is empty>")
                            ], onChatTap: (Uuid chatId) {
                    navigate(AppPage.chathistory,
                        parameters: [chatId.toString()]);
                  }, preprocessMessage: search_result_preprocessor);
                },
              ));
        }
      },
    );
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

Widget buildDashChatHistory(BuildContext context, List<ChatMessage> messages) {
  var activeColor = Theme.of(context).primaryColor;
  var aiMsgColor = Theme.of(context).listTileTheme.tileColor;
  var userMsgColor = Theme.of(context).listTileTheme.selectedTileColor;
  var textColor = Theme.of(context).listTileTheme.textColor;
  var hintColor = Theme.of(context).hintColor;

  return DashChat(
    inputOptions: InputOptions(
        sendOnEnter: false,
        sendOnShiftEnter: true,
        alwaysShowSend: true,
        inputToolbarMargin: const EdgeInsets.all(0.0),
        inputToolbarPadding: const EdgeInsets.fromLTRB(8.0, 2.0, 8.0, 4.0),
        inputMaxLines: 15,
        sendButtonBuilder: (Function fct) => InkWell(
              onTap: () => fct(),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                child: Stack(children: [
                  Icon(
                    size: 40,
                    Icons.send,
                    color: hintColor,
                  ),
                ]),
              ),
            ),
        inputDecoration: InputDecoration(
          isDense: true,
          hintText:
              "Read-only historical chat view. Use context menu to continue.",
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
        inputDisabled: true),
    messageOptions: MessageOptions(
        fullWidthRow: true, // || isMobile(),
        containerColor: aiMsgColor!,
        currentUserContainerColor: userMsgColor!,
        textColor: textColor!,
        currentUserTextColor: textColor!,
        messageTextBuilder: customMessageTextBuilder,
        showCurrentUserAvatar: false,
        showOtherUsersAvatar: false,
        onLongPressMessage: (m) {
          String msg = "${m.user.getFullName()}: ${m.text}";
          FlutterClipboard.copy(msg);
          showSnackBarTop(context,
              "Message \"${truncateWithEllipsis(16, msg)}\" copied to clipboard");
        }),
    onSend: (value) {},
    currentUser: user,
    messages: messages,
  );
}

class SingleChatHistoryPage extends StatefulWidget {
  final String? chatId;
  SingleChatHistoryPage({this.chatId});

  @override
  _SingleChatHistoryPageState createState() => _SingleChatHistoryPageState();
}

class _SingleChatHistoryPageState extends State<SingleChatHistoryPage> {
  final ChatManager _chatManager = ChatManager();
  Future<List<Message>>? _chatHistory;
  List<ChatMessage>? _chatMessages;
  Uuid? _chatUuid;
  Chat? _chat;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  void loadData() async {
    if (widget.chatId != null) {
      print("Chat History: ${widget.chatId}");
      _chatUuid = Uuid.fromString(widget.chatId!);
      _chat = await _chatManager.getChat(_chatUuid!);
      _chatHistory =
          _chatManager.getMessagesFromChat(_chatUuid!, reversed: true);
      _chatHistory?.then((value) {
        _chatMessages = dbMsgsToDashChatMsgs(value);
        setState(() {});
      });
      setState(() {});
    }
  }

  Widget _buildChatHistory() {
    return FutureBuilder<List<Message>>(
      future: _chatHistory,
      builder: (BuildContext context, AsyncSnapshot<List<Message>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return CircularProgressIndicator();
        } else if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        } else if (_chat != null && _chatMessages != null) {
          return buildDashChatHistory(context, _chatMessages!);
        }
        return CircularProgressIndicator();
      },
    );
  }

  Widget _buildChatBubble(Message message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
      child: Material(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: ListTile(
          tileColor: message.username == "user"
              ? getUserMsgColor(context)
              : getAIMsgColor(context),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          minVerticalPadding: 2.0,
          textColor: Theme.of(context).listTileTheme.textColor,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
          title: Container(child: Text(message.message)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var bgColor = Theme.of(context).appBarTheme.backgroundColor!;
    var fgColor = Theme.of(context).appBarTheme.foregroundColor!;
    return Scaffold(
      drawer: _buildDrawer(context),
      appBar: AppBar(
        titleTextStyle:
            isMobile() ? TextStyle(fontSize: 18, color: fgColor) : null,
        title: _chat == null
            ? Text('Loading chat history...')
            : Text("History of ${_chat!.getHeading()}"),
      ),
      body: _buildChatHistory(),
    );
  }
}

Widget nop_preprocessor(String m) => Text(m);

// highlightSearchResult(m.message, _query!,
//     SEARCH_MAX_SNIPPET_LENGTH, highlight,
//     max_n_lines: 4))
//
// highlightSearchResult(messages[0].message, _query!,
// SEARCH_MAX_SNIPPET_LENGTH, highlight,
// max_n_lines: 4))

Widget buildListOfChatsWithMessages(
    BuildContext context, Chat chat, List<Message> messages,
    {Widget Function(String) preprocessMessage = nop_preprocessor,
    Function(Uuid)? onChatTap,
    Function(Uuid, Uuid)? onMessageTap}) {
  var highlight = Theme.of(context).colorScheme.primary;
  var bgColor = Theme.of(context).listTileTheme.tileColor!;
  var bg2Color = bgColor.lighter(30);
  var textColor = Theme.of(context).listTileTheme.textColor;

  var lighterBgColor = bgColor.lighter(5);
  var chatTileColor = Colors.grey.darker(50);

  Widget msgs;

  const br = 10.0;

  const userBorder = BorderRadius.only(
    topLeft: Radius.circular(br),
    topRight: Radius.circular(br),
    bottomLeft: Radius.circular(br),
    // bottomRight: Radius.circular(18),
  );

  const aiBorder = BorderRadius.only(
    topLeft: Radius.circular(br),
    topRight: Radius.circular(br),
    // bottomLeft: Radius.circular(br),
    bottomRight: Radius.circular(br),
  );

  if (messages.length > 1) {
    msgs = Column(
        children: messages.map((m) {
      var isOwn = m.username == "user";

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
        child: Material(
          shape: RoundedRectangleBorder(
              borderRadius: isOwn ? userBorder : aiBorder),
          child: ListTile(
            tileColor:
                isOwn ? getUserMsgColor(context) : getAIMsgColor(context),
            shape: RoundedRectangleBorder(
                borderRadius: isOwn ? userBorder : aiBorder),
            minVerticalPadding: 2.0,
            textColor: textColor,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
            title: Container(child: preprocessMessage(m.message)),
            onTap: () {
              if (onMessageTap != null) {
                onMessageTap(m.uuid, m.chatUuid);
              } else if (onChatTap != null) {
                onChatTap(m.chatUuid);
              }
            },
          ),
        ),
      );
    }).toList());
  } else if (messages.isNotEmpty) {
    msgs = ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      minVerticalPadding: 2.0,
      tileColor: bg2Color,
      textColor: textColor,
      contentPadding:
          const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
      title: Container(child: preprocessMessage(messages[0].message)),
      onTap: () {
        var m = messages[0];
        if (onMessageTap != null) {
          onMessageTap(m.uuid, m.chatUuid);
        } else if (onChatTap != null) {
          onChatTap(m.chatUuid);
        }
      },
    );
  } else {
    msgs = ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      minVerticalPadding: 2.0,
      tileColor: bg2Color,
      textColor: textColor,
      contentPadding:
          const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
      title: Row(children: [
        const SizedBox(width: 5),
        Icon(
          Icons.warning,
          size: 22,
          color: textColor,
        ),
        const SizedBox(width: 5),
        const Text("No messages found")
      ]),
    );
  }

  return Padding(
    padding: EdgeInsets.symmetric(
        vertical: isMobile() ? 3.0 : 2.0, horizontal: isMobile() ? 2.0 : 6.0),
    child: Container(
      constraints: isMobile()
          ? null
          : BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.33,
            ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: chatTileColor, width: 2),
      ),
      child: ListTile(
        tileColor: chatTileColor,
        textColor: textColor,
        minVerticalPadding: 2.0,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
        subtitle: msgs,
        title: Text(chat.getHeading(), style: const TextStyle(fontSize: 22)),
        onTap: () {
          // Callback with relevant chatId and messageId
          if (onChatTap != null) {
            onChatTap(chat.uuid);
          }
        },
      ),
    ),
  );
}

class ChatHistoryPage extends StatefulWidget {
  ChatHistoryPage({Key? key}) : super(key: key);

  @override
  _ChatHistoryPageState createState() => _ChatHistoryPageState();
}

class _ChatHistoryPageState extends State<ChatHistoryPage> {
  final ChatManager _chatManager = ChatManager();
  Future<List<(Chat, List<Message>)>>? _chats;

  @override
  void initState() {
    super.initState();
    _chats = _chatManager.getMessagesFromChats([], sort_chats: true, limit: 3);
  }

  @override
  Widget build(BuildContext context) {
    final navigate = getNavigate(context);
    return Scaffold(
      drawer: _buildDrawer(context),
      appBar: AppBar(
        title: const Text('History of conversations'),
      ),
      body: FutureBuilder<List<(Chat, List<Message>)>>(
        future: _chats,
        builder: (BuildContext context,
            AsyncSnapshot<List<(Chat, List<Message>)>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return hhhLoader(context);
          } else if (snapshot.hasError) {
            return Text('Error: ${snapshot.error}');
          } else {
            return ListView.builder(
              itemCount: snapshot.data?.length ?? 0,
              itemBuilder: (context, index) {
                var (chat, messages) = snapshot.data![index];
                return buildListOfChatsWithMessages(
                    context,
                    chat,
                    messages.isNotEmpty
                        ? messages.sublist(1)
                        : [
                            Message.placeholder(
                                "system", "<conversation is empty>")
                          ],
                    onChatTap: (Uuid chatId) {
                      navigate(AppPage.chathistory,
                          parameters: [chatId.toString()]);
                    },
                    preprocessMessage: (m) =>
                        Text(limitText(m, 512, max_n_lines: 5)));
              },
            );
          }
        },
      ),
    );
  }
}

class SettingsNotifier extends StateNotifier<Map<String, dynamic>> {
  final MetadataManager _metadataManager = MetadataManager();

  SettingsNotifier() : super({});

  Future<void> updateSettings(Map<String, dynamic> newSettings) async {
    await persist(newSettings);
    state = newSettings;
  }

  Future<void> persist(Map<String, dynamic> settings) async {
    await _metadataManager.setMetadata("_app_settings", settings);
  }

  Future<void> restore() async {
    // Your async restore logic here
    final restoredSettings = await restoreSettings();
    state = restoredSettings;
  }

  Future<Map<String, dynamic>> restoreSettings() async {
    // Your logic to restore settings here
    return _metadataManager.getMetadata("_app_settings", defaultValue: {})
        as Map<String, dynamic>;
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, Map<String, dynamic>>(
        (ref) => SettingsNotifier());

final persistSettingsProvider = FutureProvider.autoDispose
    .family<void, Map<String, dynamic>>((ref, newSettings) async {
  final settingsNotifier = ref.watch(settingsProvider.notifier);
  await settingsNotifier.persist(newSettings);
  settingsNotifier.state = newSettings;
});

final restoreSettingsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final settingsNotifier = ref.watch(settingsProvider.notifier);
  await settingsNotifier.restore();
  return settingsNotifier.state;
});

class SettingsPage extends ConsumerStatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final MetadataManager _metadataManager = MetadataManager();
  final TextEditingController _userMessageColorController =
      TextEditingController();
  final TextEditingController _aiMessageColorController =
      TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final persistSettings = ref.watch(persistSettingsProvider(settings));
    final restoreSettings = ref.watch(restoreSettingsProvider);

    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;

    var bgColor = Theme.of(context).appBarTheme.backgroundColor!;
    var bgColor2 = Colors.black;
    var formBgColor = Colors.grey.lighter(50); // getUserMsgColor(context);
    var formBgColorLighter = formBgColor.lighter(30);
    var lighterBgColor = Theme.of(context).colorScheme.secondary;
    var fgColor =
        Colors.black; // Theme.of(context).appBarTheme.foregroundColor!;
    var textColor = Theme.of(context).listTileTheme.textColor;
    var hintColor = Theme.of(context).hintColor;

    return Scaffold(
        drawer: _buildDrawer(context),
        appBar: AppBar(backgroundColor: bgColor, title: const Text("Settings")),
        body: Center(
            child: Container(
                padding: const EdgeInsets.all(20.0),
                decoration: BoxDecoration(
                    color: formBgColor,
                    borderRadius: BorderRadius.circular(8.0)),
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height,
                  maxWidth: isMobile()
                      ? MediaQuery.of(context).size.width * 0.95
                      : 820.0,
                ),
                child: SingleChildScrollView(
                    child: FastForm(
                  onChanged: (data) {
                    // persistSettings.
                  },
                  adaptive: false,
                  formKey: _formKey,
                  children: [
                    Column(
                      children: [
                        FastFormSection(children: [
                          FastDropdown<String>(
                            dropdownColor: formBgColor,
                            name: 'default_model',
                            labelText: 'Default Model',
                            items: ['Model 1', 'Model 2', 'Model 3'],
                            initialValue: 'Model 1',
                            onChanged: (value) {
                              _metadataManager.setMetadata(
                                  'default_model', value);
                            },
                            style: TextStyle(color: fgColor),
                          ),
                          FastDropdown<String>(
                            dropdownColor: formBgColor,
                            name: 'default_system_prompt',
                            labelText: 'Default system prompt',
                            items: ['Prompt 1', 'Prompt 2', 'Prompt 3'],
                            initialValue: 'Prompt 1',
                            onChanged: (value) {
                              _metadataManager.setMetadata(
                                  'default_system_prompt', value);
                            },
                            style: TextStyle(color: fgColor),
                          ),
                          FastTextField(
                            name: 'max_context_size',
                            labelText: 'Max context size',
                            style: TextStyle(color: fgColor),
                            placeholderStyle:
                                TextStyle(color: fgColor.darker(30)),
                          ),
                          FastTextField(
                            name: 'userMessageColor',
                            labelText: 'User Message Color',
                            style: TextStyle(color: fgColor),
                            placeholderStyle:
                                TextStyle(color: fgColor.darker(30)),
                          ),
                          FastTextField(
                            name: 'aiMessageColor',
                            labelText: 'AI Message Color',
                            style: TextStyle(color: fgColor),
                            placeholderStyle:
                                TextStyle(color: fgColor.darker(30)),
                          ),
                        ])
                      ],
                    )
                  ],
                )))));
  }
}

// FastDropdown<String>(
//   name: 'default_system_prompt',
//   labelText: 'Default System Prompt',
//   items: ['Basic', 'Prompt 2', 'Prompt 3'],
//   initialValue: 'Basic',
//   onChanged: (value) {
//     _metadataManager.setMetadata(
//         'default_system_prompt', value);
//   },
// ),
// FastTextField(
//   name: 'user_message_color',
//   labelText: 'User Message Color',
//   onChanged: (value) {
//     if (value != null && HexColor.isHexColor(value)) {
//       _metadataManager.setMetadata(
//           'user_message_color', value);
//     }
//   },
// ),
// FastTextField(
//   name: 'ai_message_color',
//   labelText: 'AI Message Color',
//   onChanged: (value) {
//     _metadataManager.setMetadata(
//         'ai_message_color', value);
//   },
// ),
// ])

class LifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        print('LIFECYCLE: App is resumed');
        break;
      case AppLifecycleState.paused:
        print('LIFECYCLE: App is paused');
        break;
      case AppLifecycleState.inactive:
        print('LIFECYCLE: App is inactive');
        break;
      case AppLifecycleState.detached:
        print('LIFECYCLE: App is detached');
        break;
      case AppLifecycleState.hidden:
        print('LIFECYCLE: App is hidden');
        break;
      default:
        print('LIFECYCLE: AppLifecycleState: $state');
        break;
    }
  }
}

enum AppPage {
  conversation,
  settings,
  search,
  chathistory,
  history,
  models,
  help,
  generic_error
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
  // AppPage.models,
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
    var fgColor = Theme.of(context).appBarTheme.foregroundColor!;
    var bgColor2 = Colors.black;

    return Scaffold(
        drawer: _buildDrawer(context),
        appBar: AppBar(backgroundColor: bgColor),
        body: Container(
            width: screenWidth,
            color: bgColor2,
            child: Card(
              color: bgColor,
              margin: const EdgeInsets.all(20.0),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      Icons.warning_rounded,
                      size: 80,
                      color: fgColor,
                    ),
                    const SizedBox(height: 20),
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
  var lighterBgColor = Theme.of(context).colorScheme.secondary;
  var fgColor = Theme.of(context).appBarTheme.foregroundColor!;
  var textColor = Theme.of(context).listTileTheme.textColor;
  var hintColor = Theme.of(context).hintColor;

  return Drawer(
      width: APPBAR_WIDTH,
      shape: isMobile()
          ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
          : const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height,
          ),
          color: bgColor,
          // This column breaks rendering with exceptions
          child: Padding(
              padding: isMobile()
                  ? const EdgeInsets.only(top: MOBILE_DRAWER_TP)
                  : EdgeInsets.zero,
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: _app_pages.map((page) {
                        final selected = page == global_current_page;
                        return Material(
                            child: ListTile(
                          tileColor: selected ? lighterBgColor : bgColor,
                          title: Text(getPageName(page, capitalize: true),
                              style: TextStyle(
                                  color: selected ? fgColor : textColor,
                                  fontSize: 28)),
                          onTap: () {
                            if (navigate != null) {
                              navigate(page);
                            }
                            Navigator.pop(context); // Close the drawer
                          },
                        ));
                      }).toList(),
                    ),
                    Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 3.0, horizontal: 2.0),
                        child: Container(
                            decoration: BoxDecoration(
                                color: lighterBgColor,
                                borderRadius: BorderRadius.circular(8.0)),
                            child: Column(children: [
                              const SizedBox(height: 3.0),
                              Text(APP_TITLE_FULL,
                                  style:
                                      TextStyle(color: fgColor, fontSize: 19)),
                              const SizedBox(height: 6.0),
                              Row(children: [
                                Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 0.0, horizontal: 6.0),
                                    child: Icon(Icons.info, color: hintColor)),
                                Text(APP_VERSION,
                                    style: TextStyle(
                                        color: hintColor, fontSize: 14))
                              ]),
                              const SizedBox(height: 6.0),
                              Row(children: [
                                Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 0.0, horizontal: 6.0),
                                    child: Icon(
                                      Icons.code_rounded,
                                      color: hintColor,
                                    )),
                                RichText(
                                  text: TextSpan(
                                    style: TextStyle(
                                        color: hintColor, fontSize: 12),
                                    children: <TextSpan>[
                                      TextSpan(
                                        text: APP_REPO_LINK.replaceFirst(
                                            "https://github.com/", ""),
                                        recognizer: TapGestureRecognizer()
                                          ..onTap = () {
                                            // Define what happens when the text is tapped here
                                            launchURL(APP_REPO_LINK);
                                          },
                                      ),
                                    ],
                                  ),
                                )
                              ]),
                              const SizedBox(height: 6.0),
                            ])))
                  ]))));
}

class NavigationProvider extends InheritedWidget {
  final VoidCallback? onBeforeNavigate;
  Function(AppPage, {VoidCallback? onBeforeNavigate, List<String>? parameters})?
      navigate;

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
  List<String> _parameters = [];
  List<AppPage> _pageStack = [AppPage.conversation];

  void navigate(AppPage page,
      {VoidCallback? onBeforeNavigate, List<String>? parameters}) {
    try {
      if (onBeforeNavigate != null) {
        onBeforeNavigate();
      }
      global_current_page = page;
      setState(() {
        _parameters = parameters ?? [];
        _pageStack.add(page);
        _currentPage = page;
      });
    } catch (e) {
      print('Navigation error: $e');
    }
  }

  void back() {
    if (_pageStack.length > 1) {
      setState(() {
        _pageStack.removeLast();
        _currentPage = _pageStack.last;
      });
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
    Widget currentPage = const Text("");

    switch (page) {
      case AppPage.conversation:
        currentPage = ActiveChatPage(
            title: APP_TITLE, appInitParams: widget.appInitParams);
      case AppPage.settings:
        currentPage = SettingsPage();
      case AppPage.search:
        currentPage = SearchPage();
      case AppPage.history:
        currentPage = ChatHistoryPage();
      case AppPage.chathistory:
        var chatId = _parameters.elementAtOrNull(0);
        if (chatId != null) {
          currentPage = SingleChatHistoryPage(chatId: chatId);
        } else {
          navigate(AppPage.generic_error,
              parameters: ["Wrong navigation route"]);
        }
      case AppPage.help:
        currentPage = UnderConstructionWidget();
      case AppPage.models:
        currentPage = UnderConstructionWidget();
      case AppPage.generic_error:
        currentPage = UnderConstructionWidget(
            message:
                "Wrong navigation route, this is a bug in the application.\nReturn to the relevant route by using the hamburger menu.");
      default:
        currentPage = UnderConstructionWidget(message: "Unknown page");
    }

    return currentPage;
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

Color getUserMsgColor(BuildContext context) =>
    Theme.of(context).listTileTheme.selectedTileColor ??
    Colors.deepPurple.shade900;

Color getAIMsgColor(BuildContext context) =>
    Theme.of(context).listTileTheme.tileColor ??
    Color.fromRGBO(21, 33, 59, 1.0);

class HandheldHelper extends StatelessWidget {
  const HandheldHelper({super.key});
  // const Color.fromRGBO(21, 33, 59, 1.0)
  // const Color.fromRGBO(39, 49, 39, 1.0)

  ThemeData getAppTheme(BuildContext context, bool isDarkTheme) {
    var baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: isDarkTheme
          ? ColorScheme.fromSeed(
              seedColor: Colors.deepOrange,
              primary: const Color.fromRGBO(255, 90, 0, 1.0),
              secondary: const Color.fromRGBO(224, 125, 72, 1.0),
              background: Colors.black,
              error: Colors.purple)
          : ColorScheme.fromSeed(
              seedColor: Colors.cyan.shade400,
              primary: Colors.cyan.shade400,
              secondary: Colors.cyan.shade300,
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
          // user msg color
          selectedTileColor: isDarkTheme
              ? /* Colors.deepPurple.shade800 */ const Color.fromRGBO(
                  12, 42, 47, 1.0) /* HexColor(
                  "212f46") */
              : Colors.purple.shade50,
          tileColor: isDarkTheme
              ? /* Colors.grey.shade900 */ const Color.fromRGBO(20, 15, 42, 1.0)
              : Colors.lightBlue.shade50),
      appBarTheme: AppBarTheme(
          backgroundColor:
              isDarkTheme ? Colors.grey.shade800 : Colors.lightBlue.shade600,
          foregroundColor: isDarkTheme ? Colors.white : Colors.white,
          iconTheme: IconThemeData(
              color: isDarkTheme ? Colors.white : Colors.black54)),
      // Additional custom color fields
      // primaryColor: isDarkTheme ? Colors.blueGrey : Colors.lightBlue,
    );

    return baseTheme.copyWith(
      extensions: <ThemeExtension<dynamic>>[
        ExtendedThemeData(
            warning: const Color.fromRGBO(210, 170, 98, 1.0),
            info: const Color.fromRGBO(141, 134, 124, 1.0),
            chatMsgWarningFontSize: 14,
            codeBackgroundColor: isDarkTheme
                ? const Color.fromRGBO(55, 55, 55, 1.0)
                : Colors.grey.shade300,
            codeTextColor: isDarkTheme
                ? const Color.fromRGBO(147, 224, 161, 1.0)
                : const Color.fromRGBO(7, 49, 6, 1.0)),
      ],
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
    var isDarkMode =
        MediaQuery.of(context).platformBrightness == Brightness.dark;
    return MaterialApp(
      title: 'HandHeld Helper',
      debugShowCheckedModeBanner: false,

      theme: getAppTheme(context, isDarkMode), //  DEFAULT_THEME_DARK),

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

  runApp(const ProviderScope(child: HandheldHelper()));
}
