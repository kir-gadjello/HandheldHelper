import 'dart:convert' show jsonEncode, jsonDecode;
import 'dart:ffi' as ffi;
import 'dart:io' show File, Directory, Platform, FileSystemEntity;
import 'package:path/path.dart' as Path;
import 'package:ffi/ffi.dart';
import 'dart:async';

import 'llamarpc_generated_bindings.dart' as binding;

const kDebugMode = true;
const String LLAMA_SO = "librpcserver";
const bool __DEBUG = false;

const _IM_END_ = ["<|im_end|>"];

class LLAMAChatCompletion {
  String prompt = "";
  int max_tokens;
  double temperature;
  List<String> stop;
  int? async_slack_ms;

  LLAMAChatCompletion(this.prompt,
      {this.max_tokens = 1280,
      this.temperature = 0.0,
      this.stop = _IM_END_,
      this.async_slack_ms});

  Map<String, dynamic> toJson() {
    var ret = {
      'prompt': prompt,
      'n_predict': max_tokens,
      'temperature': temperature,
      'stop': stop,
      'stream': false,
      '__debug': __DEBUG
    };
    if (async_slack_ms != null) {
      ret['async_slack_ms'] = async_slack_ms!;
    }
    return ret;
  }
}

class AIChatMessage {
  String role = "user";
  String content = "";
  DateTime createdAt;

  AIChatMessage(this.role, this.content) : createdAt = DateTime.now();
}

String format_chatml(List<AIChatMessage> messages,
    {bool add_assistant_preprompt = true}) {
  String ret = "";
  for (final msg in messages) {
    ret += "<|im_start|>${msg.role}\n${msg.content}<|im_end|>\n";
  }
  if (add_assistant_preprompt) {
    ret += "<|im_start|>assistant\n";
  }
  return ret;
}

String fix_chatml_markup(String s) {
  s = trimLastCharacter(s, "<|im_end|>");
  var si = s.indexOf("<|im_end|>");
  if (si > -1) {
    s = s.substring(0, si);
  }
  si = s.indexOf("<|im_start|>");
  if (si > -1) {
    s = s.substring(0, si);
  }
  return s;
}

String trimLastCharacter(String srcStr, String pattern) {
  if (srcStr.length > 0) {
    if (srcStr.endsWith(pattern)) {
      final v = srcStr.substring(0, srcStr.length - pattern.length);
      return trimLastCharacter(v, pattern);
    }
    return srcStr;
  }
  return srcStr;
}

enum LLMEngineState {
  NOT_INITIALIZED,
  INITIALIZED_SUCCESS,
  INITIALIZED_FAILURE
}

class SUpdate {
  String content = "";
  bool stop = false;

  SUpdate.fromJson(Map<String, dynamic> data) {
    content = data['content'] ?? "";
    stop = data['stop'] ?? false;
  }

  toString() {
    var ret = "<$content>";
    if (stop) {
      ret += "<STOP>";
    }
    return ret;
  }
}

class AIChatPollResult {
  bool success = false;
  bool finished = false;
  List<SUpdate> completion_updates = [];

  AIChatPollResult();

  AIChatPollResult.fromJson(Map<String, dynamic> data) {
    success = data['success'] ?? false;
    finished = data['finished'] ?? false;
    if (data['completion_updates'] != null) {
      completion_updates = List<SUpdate>.from(
          data['completion_updates'].map((update) => SUpdate.fromJson(update)));
    }
  }

  String joined({sep = ""}) {
    return completion_updates.map((u) => u.content).join(sep);
  }
}

class Tokenized {
  bool success = false;
  List<String> tokens = [];
  int length = -1;

  Tokenized();

  Tokenized.fromJson(Map<String, dynamic> data) {
    success = data['success'] ?? false;
    length = data['length'] ?? -1;
    if (data['tokens'] != null) {
      tokens = List<String>.from(data['tokens']);
    }
  }
}

String mergeAIChatPollResults(List<AIChatPollResult> updates, {sep = ""}) {
  return updates.map((u) => u.joined(sep: sep)).join(sep);
}

void printTree(Directory dir, [int depth = 0]) {
  if (depth > 100) return; // Max depth of 100 files

  List<FileSystemEntity> entities = [];
  try {
    entities = dir.listSync().toList();
  } catch (e) {
    print("Exception for $dir: $e");
  }
  for (var entity in (entities ?? [])) {
    if (entity is Directory) {
      print('${'\t' * depth}Directory: ${entity.path}');
      printTree(entity, depth + 1);
    } else if (entity is File) {
      print('${'\t' * depth}File: ${entity.path}');
    }
  }
}

String? resolve_shared_library_path(String libname) {
  var binDir = Path.dirname(Platform.resolvedExecutable);
  print("resolve_shared_library_path $binDir $libname");
  // print("FILES: ");
  // printTree(Directory.current);

  // Define possible system directories where shared libraries can be located
  List<String> directories = [
    "",
    binDir,
    'lib/arm64-v8a/',
    'arm64-v8a/',
    Path.join(binDir, 'lib/arm64-v8a/'),
    Path.join(binDir, "../Frameworks/"),
    Path.join(binDir, 'lib/'),
    Path.join(binDir, 'lib64/'),
    '/usr/lib/',
    '/usr/lib64/',
    '/usr/local/lib/',
    // Add other directories as needed
  ];

  // Define standard shared library extensions for different operating systems
  Map<String, String> extensions = {
    'linux': '.so',
    'macos': '.dylib',
    'android': '.so',
  };

  // Get the current operating system
  String os = Platform.operatingSystem;

  // Get the standard extension for the current operating system
  String extension = extensions?[os] ?? ".so";

  if (File("$libname$extension").existsSync()) {
    print("FOUND! $libname$extension");
    return "$libname$extension";
  }

  // Iterate over the directories
  for (String directory in directories) {
    // Construct the full file path with the extension
    String filePath = Path.join(directory, "$libname$extension");
    print('Probing $libname at $filePath');
    // Check if the file exists
    if (File(filePath).existsSync()) {
      // If the file exists, return its path
      print('Found $libname at $filePath');
      return filePath;
    } else {
      // If the file doesn't exist, log the file probing attempt
      print('Checked $filePath but did not find $libname');
    }
  }

  // If the file was not found in any of the directories, return null
  print('Did not find $libname in any of the checked directories');

  return null;
}

const LIBLLAMARPC = "librpcserver";

class LLMEngine {
  String system_message = "";
  String? libpath = "$LLAMA_SO";
  String modelpath = "";
  String error = "";

  bool initialized = false;
  bool init_in_progress = false;
  bool postpone_init = false;
  bool init_postponed = false;
  bool streaming = false;
  String stream_msg_acc = "";
  Function? onInitDone = null;
  int tokens_used = 0;
  int n_ctx = 0;

  LLMEngineState state = LLMEngineState.NOT_INITIALIZED;

  List<AIChatMessage> msgs = [];

  Map<String, dynamic>? llama_init_json;

  late binding.LLamaRPC rpc;

  LLMEngine(
      {this.postpone_init = false,
      this.system_message = "",
      this.libpath,
      this.modelpath = "",
      this.onInitDone,
      this.llama_init_json}) {
    String _libpath;

    if (libpath != null && File(libpath!).existsSync()) {
      _libpath = libpath!;
    } else {
      if (Platform.isAndroid) {
        _libpath = "$LIBLLAMARPC.so";
      } else {
        _libpath =
            resolve_shared_library_path(LIBLLAMARPC) ?? "$LIBLLAMARPC.so";
      }
    }

    if (!Platform.isAndroid &&
        (_libpath == null || !File(_libpath).existsSync())) {
      throw Exception("LLAMARPC: Cannot find shared library $LIBLLAMARPC");
    }

    libpath = _libpath;

    rpc = binding.LLamaRPC(
        ffi.DynamicLibrary.open(_libpath ?? "librpcserver.so"));

    if (kDebugMode && rpc != null) {
      print("[OK] Loaded shared library... $libpath");
    }
    if (postpone_init) {
      print("Avoiding init due to parent request");
      init_postponed = true;
      return;
    }

    if (!File(this.modelpath).existsSync()) {
      print("Avoiding init due to invalid modelpath");
      init_postponed = true;
      return;
    }

    reinit(
        system_message: system_message,
        modelpath: modelpath,
        onInitDone: onInitDone,
        llama_init_json: llama_init_json);
  }

  void poll_init() {
    var sysinfo = Map<String, dynamic>.from(
        jsonDecode(rpc.poll_system_status().cast<Utf8>().toDartString()));

    if (sysinfo['init_success'] == 1) {
      initialized = true;
    } else if (sysinfo['init_success'] == -1) {
      initialized = false;
      state = LLMEngineState.INITIALIZED_FAILURE;
    }

    print("LOG sysinfo: $sysinfo");
  }

  void _sync_token_count() {
    if (initialized) {
      var tok = tokenize(format_chatml(msgs));
      if (tok.success) {
        tokens_used = tok.length;
      }
    }
  }

  int measure_tokens(String s) {
    if (s.isEmpty) {
      return 0;
    }
    if (initialized) {
      var tok = tokenize(s);
      if (tok.success) {
        return tok.length;
      }
    }
    return 0;
  }

  bool reinit(
      {String? system_message,
      required String modelpath,
      non_blocking = true,
      Map<String, dynamic>? llama_init_json,
      onInitDone}) {
    if (state == LLMEngineState.INITIALIZED_SUCCESS) {
      teardown();
    }

    if (system_message != null) {
      this.system_message = system_message;
    }

    this.modelpath = modelpath;

    msgs = [];

    try {
      if (this.system_message.isNotEmpty) {
        msgs.add(AIChatMessage("system", this.system_message));
        _sync_token_count();
        if (kDebugMode) {
          print("Using system prompt: \"${this.system_message}\"");
        }
      }

      var t0 = DateTime.now();

      Map<String, dynamic> init_json = {
        "model": modelpath,
        "use_mmap": false,
        "use_mlock": false
      };

      if (llama_init_json != null) {
        llama_init_json.forEach((k, v) {
          init_json[k] = v;
        });
      }

      if (modelpath.toLowerCase().contains("mistral") &&
          init_json['n_ctx'] == null) {
        init_json['n_ctx'] = 8192;
      }

      if (non_blocking) {
        n_ctx = init_json['n_ctx'] ?? 1024;

        print("USING INIT PARAMS = $init_json");
        print("USING CONTEXT LENGTH = $n_ctx");

        init_in_progress = true;

        rpc.init_async(jsonEncode(init_json).toNativeUtf8().cast<ffi.Char>());

        Timer.periodic(Duration(milliseconds: 250), (timer) {
          poll_init();
          if (initialized) {
            init_in_progress = false;
            state = LLMEngineState.INITIALIZED_SUCCESS;
            print("Init complete at ${DateTime.now()}");
            print("[OK] Loaded model... $modelpath");
            timer.cancel();
            if (onInitDone != null) {
              onInitDone();
            }
          }
          if (state == LLMEngineState.INITIALIZED_FAILURE) {
            print("Init FAILED at ${DateTime.now()}");
            timer.cancel();
          }
        });
      } else {
        initialized = (rpc.init(
                jsonEncode(init_json ?? {}).toNativeUtf8().cast<ffi.Char>()) ==
            0);
        print("INITIALIZED: $initialized");
        if (initialized) {
          if (onInitDone != null) {
            onInitDone();
          }
        }
      }

      if (!non_blocking && kDebugMode) {
        print("[OK] Loaded model... $modelpath");
        print(
            "--------------------------------------------------\nChat mode: ON");
      }
    } catch (e) {
      state = LLMEngineState.INITIALIZED_FAILURE;
      return false;
    }

    state = LLMEngineState.INITIALIZED_SUCCESS;
    return true;
  }

  void reset_msgs() {
    print("AiDialog: reset_msgs");
    msgs = [];
    if (system_message.isNotEmpty) {
      msgs.add(AIChatMessage("system", system_message));
      _sync_token_count();
      if (kDebugMode) {
        print("Using system prompt: \"${system_message}\"");
      }
    }
  }

  _on_advance_resp(String api_resp) {
    var jdata = jsonDecode(api_resp);
    if (jdata["prompt_stats"] != null) {
      Map<String, dynamic> prompt_stats = jdata["prompt_stats"];
      // print("LOG PROMPT STATS: $prompt_stats");
      tokens_used = (prompt_stats['total_prompt_tokens'] ?? 0) as int;
      int n_ctx = (prompt_stats['n_ctx'] ?? 0) as int;
      // print("LOG TOKENS USED: $tokens_used of $n_ctx");
    }
  }

  Tokenized tokenize(String s) {
    final api_resp = rpc
        .tokenize(jsonEncode({"text": s}).toNativeUtf8().cast<ffi.Char>())
        .cast<Utf8>()
        .toDartString();

    return Tokenized.fromJson(jsonDecode(api_resp));
  }

  bool advance({String? user_msg, bool fix_chatml = true}) {
    if (!initialized) {
      error = "Error: not initialized just yet";
      return false;
    }

    if (user_msg != null) {
      msgs.add(AIChatMessage("user", user_msg));
    }

    if (msgs.last.role != "user") {
      error = "Error: last message should have role user";
      return false;
    }

    try {
      String api_query = jsonEncode(LLAMAChatCompletion(format_chatml(msgs)));

      if (__DEBUG) print("DEBUG: api_query=${api_query}");

      final api_resp = rpc
          .get_completion(api_query.toNativeUtf8().cast<ffi.Char>())
          .cast<Utf8>()
          .toDartString();

      _on_advance_resp(api_resp);

      if (__DEBUG) print("RESPONSE: $api_resp");

      String resp = jsonDecode(api_resp)["content"] as String;

      if (fix_chatml) {
        resp = fix_chatml_markup(resp);
      }

      msgs.add(AIChatMessage("assistant", resp));
      error = "";
      return true;

      // print("AI: $resp");
    } catch (e) {
      error = e.toString();
      if (kDebugMode) {
        print("Error: ${e}");
      }
    }

    return false;
  }

  bool start_advance_stream(
      {String? user_msg, bool fix_chatml = true, int? async_slack_ms}) {
    streaming = true;

    if (user_msg != null) {
      msgs.add(AIChatMessage("user", user_msg));
    }

    if (msgs.last.role != "user") {
      error = "Error: last message should have role user";
      return false;
    }

    try {
      String api_query = jsonEncode(LLAMAChatCompletion(format_chatml(msgs),
          async_slack_ms: async_slack_ms));

      if (__DEBUG) print("DEBUG: api_query=${api_query}");

      final api_resp = rpc
          .async_completion_init(api_query.toNativeUtf8().cast<ffi.Char>())
          .cast<Utf8>()
          .toDartString();

      _on_advance_resp(api_resp);

      if (__DEBUG) print("RESPONSE: $api_resp");

      // TODO: backoff if busy
      bool resp = jsonDecode(api_resp)["success"] as bool;

      return resp;

      // if (fix_chatml) {
      //   resp = fix_chatml_markup(resp);
      // }
      //
      // msgs.add(AIChatMessage("assistant", resp));
      // error = "";
      // return true;
      //
      // // print("AI: $resp");
    } catch (e) {
      error = e.toString();
      if (kDebugMode) {
        print("Error: ${e}");
      }
    }

    return false;
  }

// TODO: stop async generation with special cmd
  AIChatPollResult poll_advance_stream({fix_chatml = true}) {
    try {
      String api_query = "{}";

      final api_resp = rpc
          .async_completion_poll(api_query.toNativeUtf8().cast<ffi.Char>())
          .cast<Utf8>()
          .toDartString();

      // if (__DEBUG) print("RESPONSE: $api_resp");

      // TODO: backoff if busy
      // bool success = jsonDecode(api_resp)["success"] as bool;
      // bool finished = jsonDecode(api_resp)["finished"] as bool;
      // List<dynamic> completion_updates = jsonDecode(
      //     api_resp)["completion_updates"];

      var stream_update = AIChatPollResult.fromJson(jsonDecode(api_resp));

      stream_msg_acc += stream_update.joined();

      if (stream_update.finished) {
        if (fix_chatml) {
          stream_msg_acc = fix_chatml_markup(stream_msg_acc);
        }

        msgs.add(AIChatMessage("assistant", stream_msg_acc));
        stream_msg_acc = "";
        streaming = false;
        error = "";
      }

      return stream_update;
    } catch (e) {
      error = e.toString();
      if (kDebugMode) {
        print("Error: ${error}");
      }
    }

    return AIChatPollResult();
  }

  void teardown() {
    rpc.deinit();
    state = LLMEngineState.NOT_INITIALIZED;
  }
}
