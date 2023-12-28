import 'dart:convert' show jsonEncode, jsonDecode;
import 'dart:ffi' as ffi;
import 'dart:io' show File, Directory, Platform, FileSystemEntity;
// import 'dart:ui';
// import 'package:handheld_helper/gguf.dart';
import 'package:path/path.dart' as Path;
import 'package:ffi/ffi.dart';
import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:jinja/jinja.dart';
import 'util.dart';
import 'llamarpc_generated_bindings.dart' as binding;

const kDebugMode = true;
const LLAMA_SO = "librpcserver";
const bool __DEBUG = false;

const _IM_END_ = ["<|im_end|>"];

typedef VoidCallback = void Function();

String getFileHash(String filePath) {
  var file = File(filePath);
  if (!(file.existsSync())) {
    return "<file not found>";
  }
  var bytes = file.readAsBytesSync();
  var digest = sha1.convert(bytes);
  return digest.toString();
}

bool validatePromptFormatTemplate(Map<String, dynamic> fmt) {
  return fmt['template'] is String &&
      fmt['historyTemplate'] is String &&
      fmt['char'] is String &&
      fmt['user'] is String;
}

String extractSeparatorFromPromptTemplate(Map<String, dynamic> fmt,
    {String fallback = "<\s>"}) {
  if (fmt['separator'] is String) {
    return fmt['separator'];
  }

  String tpl = fmt['historyTemplate'];
  var tpl_parts = tpl.split("{{message}}");
  if (tpl_parts.length > 1) {
    String prefix = tpl_parts.first;
    String suffix = tpl_parts.last;
    if (!prefix.contains(suffix) && suffix != "\n") {
      return suffix;
    } else {
      return suffix + prefix.split("{{char}}").first + fmt['user'];
    }
  }

  print(
      "Warning: cannot determine separator for template, falling back to $fallback");

  return fallback;
}

var tagRE = RegExp(r'<\|\w+\|>');

String extractSeparatorFromJinjaTemplate(String fmt,
    {String fallback = "<\s>", special_token_heuristic = true}) {
  var msgs = [
    AIChatMessage("assistant", "n9213nsys_msg093485"),
    AIChatMessage("user", "0239475user_msg43546"),
  ];

  String? ret;

  var example = format_chat_jinja(fmt, msgs);

  // TODO: minimize end-of-message suffix
  var p0 = example.split(msgs[0].content);
  var p1 = p0?[1].split(msgs[1].content);

  if (p1 != null && p1.isNotEmpty) {
    var sep = p1[0];
    var match = tagRE.matchAsPrefix(sep);
    if (match != null && match.group(0) != null) {
      ret = match.group(0)!;
    } else {
      ret = sep;
    }
  }

  if (ret != null) {
    print("Heuristically derived separator:\n$ret");
    return ret;
  }

  print(
      "Warning: cannot determine separator for template, falling back to $fallback");

  return fallback;
}

String convertSpecialCharacters(String str) {
  Map<String, int> specialChars = {
    '\\n': 10, // newline
    '\\t': 9, // tab
    '\\r': 13, // carriage return
    '\\b': 8, // backspace
    '\\f': 12, // form feed
    '\\v': 11, // vertical tab
    '\\\\': 92, // backslash
    '\\\'': 39, // single quote
    '\\"': 34, // double quote
  };

  for (var entry in specialChars.entries) {
    str = str.replaceAll(entry.key, String.fromCharCode(entry.value));
  }

  return str;
}

Map<String, dynamic> convertSpecialCharactersInMap(Map<String, dynamic> map) {
  Map<String, dynamic> ret = {};
  map.forEach((key, value) {
    if (value is String) {
      ret[key] = convertSpecialCharacters(value);
    } else {
      ret[key] = value;
    }
  });
  return ret;
}

String formatConversation(
    Map<String, dynamic> json, List<AIChatMessage> history,
    {String prompted_name = "assistant"}) {
  String template = json['template']!;
  String historyTemplate = json['historyTemplate']!;
  String aiName = json['char']!;
  String userName = json['user']!;

  Map<String, String> names = {"user": userName, "assistant": aiName};

  String nameFromRole(String role) {
    return names[role] ?? role;
  }

  String? sysmsg;

  if (history.first.role.toLowerCase() == "system") {
    sysmsg = history[0].content;
    history = history.sublist(1);
  }

  var formattedHistory = history.map((message) {
    return historyTemplate
        .replaceAll('{{name}}', nameFromRole(message.role))
        .replaceAll('{{message}}', message.content);
  }).join();

  return template
      .replaceAll('{{prompt}}', sysmsg ?? '')
      .replaceFirst('{{history}}', formattedHistory)
      .replaceAll('{{char}}', nameFromRole(prompted_name));
}

class LLMPromptFormat {
  String name;
  String separator;
  String Function(List<AIChatMessage>) formatter;
  String Function(String) fixer;
  String? fromKnown;

  LLMPromptFormat(
      {this.name = "chatml",
      this.separator = "<|im_end|>",
      this.formatter = format_chatml,
      this.fixer = fix_chatml_markup,
      this.fromKnown});

  factory LLMPromptFormat.fromTemplate(Map<String, dynamic> fmt, String? name) {
    if (!validatePromptFormatTemplate(fmt)) {
      print("Could not load prompt format, falling back to ChatML");
      return LLMPromptFormat();
    }
    var format = convertSpecialCharactersInMap(fmt);
    name = name ?? "fmt-${genUuidString()}";
    var separator = extractSeparatorFromPromptTemplate(format);
    return LLMPromptFormat(
        name: name,
        separator: separator,
        formatter: (List<AIChatMessage> history) =>
            formatConversation(format, history),
        fixer: create_fixer(separator));
  }

  factory LLMPromptFormat.fromJinjaTemplate(String template, String? name) {
    name = name ?? "fmt-${genUuidString()}";
    var separator = extractSeparatorFromJinjaTemplate(template);
    return LLMPromptFormat(
        name: name,
        separator: separator,
        formatter: (List<AIChatMessage> history) =>
            format_chat_jinja(template, history),
        fixer: create_fixer(separator));
  }
}

final ChatMLPromptFormat = LLMPromptFormat();

// TODO: support general case
String transform_tpl(String tpl) {
  return tpl
      .replaceAll(".title()", "|title")
      .replaceAll(".upper()", "|upper")
      .replaceAll(".lower()", "|lower");
}

var chat_tpl_memoizer = Memoizer();

String format_chat_jinja(String template, List<AIChatMessage> messages,
    {bool add_generation_prompt = true,
    String bos_token = '',
    String eos_token = '',
    String? prompt}) {
  var env = Environment();

  Template t =
      env.fromString(chat_tpl_memoizer.memoize(transform_tpl, template));

  Map<String, Object?> values = {
    'messages': messages.map((m) => ({"role": m.role, "content": m.content})),
    'bos_token': bos_token,
    'eos_token': eos_token, // specify your EOS token
    'add_generation_prompt': add_generation_prompt,
    'prompt': prompt ?? ''
  };

  return t.render(values);
}

bool validate_jinja_chat_template(String tpl) {
  bool success = false;
  var msgs = [
    AIChatMessage("system", "sys_msg"),
    AIChatMessage("user", "user_msg"),
  ];

  try {
    var ret = format_chat_jinja(tpl, msgs);
    success = true;
    // prompt format should show all msgs content
    for (var m in msgs) {
      success = success && ret.contains(m.content);
    }
  } catch (e) {
    print("Chat template validation exception: $e");
    success = false;
  }

  return success;
}

class LLMChatCompletion {
  String prompt = "";
  int max_tokens;
  double temperature;
  List<String> stop;

  LLMChatCompletion(
    this.prompt, {
    this.max_tokens = 1280,
    this.temperature = 0.0,
    this.stop = _IM_END_,
  });

  Map<String, dynamic> toJson() => {
        'prompt': prompt,
        'n_predict': max_tokens,
        'temperature': temperature,
        'stop': stop,
        'stream': false,
        '__debug': __DEBUG
      };
}

class AIChatMessage {
  String role = "user";
  String content = "";
  DateTime createdAt;

  AIChatMessage(this.role, this.content) : createdAt = DateTime.now();

  @override
  String toString() {
    return "AIChatMessage<role=$role, content=$content>";
  }
}

String format_minichat(List<AIChatMessage> messages,
    {bool add_assistant_preprompt = true}) {
  String ret = "";

  const role_map = {"user": "[|User|]", "assistant": "[|Assistant|]"};
  // TODO: "system": "[|System|]" ?

  print("DUMP $messages");

  for (final msg in messages) {
    var role = msg.role.toLowerCase();
    if (role == "system") {
      ret += "${msg.content}</s>";
    } else {
      ret += "${role_map[role] ?? msg.role} ${msg.content}</s>";
    }
  }
  if (add_assistant_preprompt) {
    ret += "[|Assistant|]";
  }

  return ret;
}

String nop_fixer(String x) {
  return x;
}

final MiniChatPromptFormat = LLMPromptFormat(
    name: "minichat",
    formatter: format_minichat,
    fixer: create_fixer("</s>"),
    separator: "</s>");

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

String Function(String) create_fixer(String sep) => (String s) {
      s = trim_suffix(s, sep);
      var si = s.indexOf(sep);
      if (si > -1) {
        s = s.substring(0, si);
      }
      return s;
    };

String fix_chatml_markup(String s) {
  s = trim_suffix(s, "<|im_end|>");
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

String trim_suffix(String srcStr, String pattern) {
  if (srcStr.length > 0) {
    if (srcStr.endsWith(pattern)) {
      final v = srcStr.substring(0, srcStr.length - pattern.length);
      return trim_suffix(v, pattern);
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
  double progress = 0.0;
  List<SUpdate> completion_updates = [];

  AIChatPollResult();

  AIChatPollResult.fromJson(Map<String, dynamic> data) {
    success = data['success'] ?? false;
    finished = data['finished'] ?? false;
    progress = data['prompt_processing_progress'] ?? 0.0;
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

  @override
  String toString() {
    return ("Tokenized{success:$success, length:$length, tokens:$tokens}");
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
  for (var entity in entities) {
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

  // Define possible system directories where shared libraries can be located
  List<String> directories = [
    "",
    binDir,
    "native",
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
  String? libpath = "$LLAMA_SO";
  String modelpath = "";
  String error = "";

  bool initialized = false;
  bool init_in_progress = false;
  bool postpone_init = false;
  bool init_postponed = false;
  double loading_progress = 0.0;
  bool streaming = false;
  String stream_msg_acc = "";
  void Function(bool)? onInitDone = null;
  int tokens_used = 0;
  int n_ctx = 0;
  late LLMPromptFormat prompt_format;

  LLMEngineState state = LLMEngineState.NOT_INITIALIZED;

  List<AIChatMessage> msgs = [];

  Map<String, dynamic>? llama_init_json;

  void reinitState() {
    state = LLMEngineState.NOT_INITIALIZED;
    msgs = [];
    llama_init_json = null;
    initialized = false;
    init_in_progress = false;
    postpone_init = false;
    init_postponed = false;
    loading_progress = 0.0;
    streaming = false;
    stream_msg_acc = "";
    onInitDone = null;
    tokens_used = 0;
    n_ctx = 0;
  }

  late binding.LLamaRPC rpc;
  late String _libpath;

  @override
  dispose() {
    deinitialize();
  }

  LLMEngine(
      {this.postpone_init = false,
      this.libpath,
      this.modelpath = "",
      this.onInitDone,
      this.llama_init_json}) {
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

    if (Platform.environment.containsKey("TEST") ||
        Platform.environment.containsKey("DEVELOPMENT")) {
      print("$libpath SHA1: ${getFileHash(libpath!)}");
    }

    rpc =
        binding.LLamaRPC(ffi.DynamicLibrary.open(libpath ?? "librpcserver.so"));

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

    initialize(
        modelpath: modelpath,
        onInitDone: onInitDone,
        llama_init_json: llama_init_json);
  }

  void poll_init({VoidCallback? Function(double)? onProgressUpdate}) {
    var sysinfo = Map<String, dynamic>.from(
        jsonDecode(rpc.poll_system_status().cast<Utf8>().toDartString()));

    if (sysinfo['loading_progress'] is double) {
      loading_progress = sysinfo['loading_progress'];
      if (onProgressUpdate != null) {
        onProgressUpdate(loading_progress);
      }
    }

    if (sysinfo['init_success'] == 1) {
      initialized = true;
      state = LLMEngineState.INITIALIZED_SUCCESS;
    } else if (sysinfo['init_success'] == -1) {
      initialized = false;
      state = LLMEngineState.INITIALIZED_FAILURE;
    }

    print("LOG sysinfo: $sysinfo");
  }

  int? sync_token_count() {
    if (initialized) {
      var tok = tokenize(prompt_format.formatter(msgs));
      if (tok.success) {
        tokens_used = tok.length;
        return tokens_used;
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

  bool is_initialized() {
    const init_states = [
      LLMEngineState.INITIALIZED_SUCCESS,
      LLMEngineState.INITIALIZED_FAILURE
    ];

    return !init_in_progress && init_states.contains(state);
  }

  bool initialize(
      {required String modelpath,
      auto_ctxlen = false,
      non_blocking = true,
      Map<String, dynamic>? llama_init_json,
      LLMPromptFormat? custom_format,
      void Function(bool)? onInitDone,
      VoidCallback? Function(double)? onProgressUpdate}) {
    if (init_in_progress) {
      print(
          "LLM ENGINE WARNING: intialize() called on INITIALIZATION IN PROGRESS engine, dismissing.");
      return false;
    }

    if (is_initialized()) {
      print(
          "LLM ENGINE WARNING: intialize() called on intialized engine, performing deinitialize() first");
      deinitialize();
    }

    this.modelpath = modelpath;

    msgs = [];

    prompt_format = custom_format ?? ChatMLPromptFormat;

    try {
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

      // if (modelpath.toLowerCase().contains("mistral") &&
      //     init_json['n_ctx'] == null) {
      //   init_json['n_ctx'] = 8192;
      // }

      if (non_blocking) {
        n_ctx = init_json['n_ctx'] ?? 2048;

        print("USING INIT PARAMS = $init_json");
        print("USING CONTEXT LENGTH = $n_ctx");

        init_in_progress = true;

        rpc.init_async(jsonEncode(init_json).toNativeUtf8().cast<ffi.Char>());

        Timer.periodic(const Duration(milliseconds: 250), (timer) {
          poll_init(onProgressUpdate: onProgressUpdate);
          if (initialized) {
            init_in_progress = false;
            state = LLMEngineState.INITIALIZED_SUCCESS;
            print("Init complete at ${DateTime.now()}");
            print("[OK] Loaded model... $modelpath");
            timer.cancel();
            if (onInitDone != null) {
              onInitDone(true);
            }
          }
          if (state == LLMEngineState.INITIALIZED_FAILURE) {
            init_in_progress = false;
            print("Init FAILED at ${DateTime.now()}");
            timer.cancel();
            if (onInitDone != null) {
              onInitDone(false);
            }
          }
        });
      } else {
        init_in_progress = true;
        initialized = (rpc.init(
                jsonEncode(init_json ?? {}).toNativeUtf8().cast<ffi.Char>()) ==
            0);
        init_in_progress = false;
        if (initialized) {
          state = LLMEngineState.INITIALIZED_SUCCESS;
        }
        print("INITIALIZED: $initialized");
        if (onInitDone != null) {
          onInitDone(initialized);
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

    return true;
  }

  void clear_state({VoidCallback? onComplete}) {
    print("AiDialog: clear_state");
    msgs = [];

    if (streaming) {
      initialized = false;
      init_in_progress = true;
      if (onComplete != null) {
        cancel_advance_stream(onComplete: (String _) {
          initialized = true;
          init_in_progress = false;
          streaming = false;
          onComplete();
        });
      }
    }

    if (onComplete != null) {
      initialized = true;
      init_in_progress = false;
      streaming = false;
      onComplete();
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

  void set_system_prompt(String sys_prompt) {
    var sys_msg = AIChatMessage("system", sys_prompt);
    if (msgs.isEmpty) {
      msgs.add(sys_msg);
    } else {
      msgs[0] = sys_msg;
    }
  }

  bool advance(
      {String? user_msg, bool fix_chatml = true, bool respect_eos = true}) {
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
      String api_query = jsonEncode(LLMChatCompletion(
        prompt_format.formatter(msgs),
        stop: (respect_eos
            ? ["</s>", prompt_format.separator]
            : [prompt_format.separator]),
      ));

      if (__DEBUG) print("DEBUG: api_query=${api_query}");

      final api_resp = rpc
          .get_completion(api_query.toNativeUtf8().cast<ffi.Char>())
          .cast<Utf8>()
          .toDartString();

      _on_advance_resp(api_resp);

      if (__DEBUG) print("RESPONSE: $api_resp");

      String resp = jsonDecode(api_resp)["content"] as String;

      if (fix_chatml) {
        resp = prompt_format.fixer(resp);
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
      {String? user_msg, bool fix_chatml = true, bool respect_eos = true}) {
    if (streaming) {
      error = "Error: already generating completion, cancel to restart";
      return false;
    }

    streaming = true;

    if (user_msg != null) {
      msgs.add(AIChatMessage("user", user_msg));
    }

    if (msgs.last.role != "user") {
      error = "Error: last message should have role user";
      return false;
    }

    try {
      String api_query = jsonEncode(LLMChatCompletion(
        prompt_format.formatter(msgs),
        stop: (respect_eos
            ? ["</s>", prompt_format.separator]
            : [prompt_format.separator]),
      ));

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

      if (__DEBUG) print("RESPONSE: $api_resp");

      // TODO: backoff if busy
      // bool success = jsonDecode(api_resp)["success"] as bool;
      // bool finished = jsonDecode(api_resp)["finished"] as bool;
      // List<dynamic> completion_updates = jsonDecode(
      //     api_resp)["completion_updates"];

      var stream_update = AIChatPollResult.fromJson(jsonDecode(api_resp));

      stream_msg_acc += stream_update.joined();

      if (stream_update.finished) {
        if (fix_chatml) {
          stream_msg_acc = prompt_format.fixer(stream_msg_acc);
        }

        msgs.add(AIChatMessage("assistant", stream_msg_acc));
        _reset_streaming_state();
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

  _reset_streaming_state() {
    stream_msg_acc = "";
    streaming = false;
    error = "";
  }

  Future<bool> cancel_advance_stream(
      {void Function(String cmpl)? onComplete}) async {
    String api_query = "{}";

    String last_stream_acc_state = stream_msg_acc;

    final api_resp = rpc
        .async_completion_cancel(api_query.toNativeUtf8().cast<ffi.Char>())
        .cast<Utf8>()
        .toDartString();

    if (onComplete == null) {
      var resp = jsonDecode(api_resp);
      _reset_streaming_state();
      return (resp != null && (resp?['success'] == true)) ? true : false;
    } else {
      AIChatPollResult poll_res;
      int counter = 20;
      int i = 0;
      do {
        print("LLM: POLLING FOR CANCEL ${i++}");
        await Future.delayed(const Duration(milliseconds: 100));
        counter--;
        poll_res = poll_advance_stream();
      } while (counter > 0 && !poll_res.finished);

      _reset_streaming_state();
      onComplete(last_stream_acc_state);

      return true;
    }
  }

  void deinitialize({bool reload_shared_library = false}) {
    rpc.deinit();
    if (reload_shared_library && _libpath != null) {
      rpc = binding.LLamaRPC(ffi.DynamicLibrary.open(_libpath!));
    }
    state = LLMEngineState.NOT_INITIALIZED;
    reinitState();
  }
}
