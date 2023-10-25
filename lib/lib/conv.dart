import 'dart:convert' show jsonEncode, jsonDecode;
import 'dart:ffi' as ffi;
import 'dart:io' show File;
import 'dart:collection';
import 'package:ffi/ffi.dart';
import 'dart:isolate';
import 'dart:async';
import 'package:async/async.dart';

// import 'isolate_rpc.dart';

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

  LLAMAChatCompletion(this.prompt, {
    this.max_tokens = 1280,
    this.temperature = 0.0,
    this.stop = _IM_END_,
  });

  Map<String, dynamic> toJson() =>
      {
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

enum AIDialogSTATE { NOT_INITIALIZED, INITIALIZED_SUCCESS, INITIALIZED_FAILURE }

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

String mergeAIChatPollResults(List<AIChatPollResult> updates, {sep = ""}) {
  return updates.map((u) => u.joined(sep: sep)).join(sep);
}

class AIDialog {
  String system_message = "";
  String libpath = "$LLAMA_SO";
  String modelpath = "";
  String error = "";

  bool initialized = false;
  bool streaming = false;
  String stream_msg_acc = "";
  Function? onInitDone = null;

  AIDialogSTATE state = AIDialogSTATE.NOT_INITIALIZED;

  List<AIChatMessage> msgs = [];

  Map<String,dynamic>? llama_init_json;

  late binding.LLamaRPC rpc;

  AIDialog({this.system_message = "", this.libpath = "", this.modelpath = "", this.onInitDone, this.llama_init_json}) {
    rpc = binding.LLamaRPC(ffi.DynamicLibrary.open(libpath));

    if (!File(this.modelpath).existsSync()) {
      print("Avoiding init due to invalid modelpath");
      return;
    }

    reinit(system_message: system_message, modelpath: modelpath, onInitDone: onInitDone, llama_init_json: llama_init_json);
  }

  void poll_init() {
    var sysinfo = Map<String, dynamic>.from(
        jsonDecode(rpc.poll_system_status()
        .cast<Utf8>()
        .toDartString()));

    if (sysinfo['init_success'] == 1) {
      initialized = true;
    }

    // print("LOG sysinfo: $sysinfo");
  }

  bool reinit({String? system_message, required String modelpath, non_blocking = true, Map<String, dynamic>? llama_init_json, onInitDone}) {
    if (state == AIDialogSTATE.INITIALIZED_SUCCESS) {
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
        if (kDebugMode) {
          print("Using system prompt: \"${this.system_message}\"");
        }
      }

      if (kDebugMode) print("[OK] Loaded library... $LLAMA_SO");

      var t0 = DateTime.now();

      if (non_blocking) {

        Map<String,dynamic> init_json = {"model": modelpath};

        if (llama_init_json != null) {
          llama_init_json.forEach((k,v) {
            init_json[k] = v;
          });
        }

        if (modelpath.toLowerCase().contains("mistral") && init_json['n_ctx'] == null) {
          init_json['n_ctx'] = 8192;
        }

        rpc.init_async(jsonEncode(init_json).toNativeUtf8().cast<ffi.Char>());

        Timer.periodic(Duration(milliseconds: 250), (timer) {
          poll_init();
          if (initialized) {
            print("Init complete at ${DateTime.now()}");
            timer.cancel();
            if (onInitDone != null) {
              onInitDone();
            }
          }
        });
      } else {
        initialized = (rpc.init(
            "{\"model\":\"$modelpath\"}".toNativeUtf8().cast<ffi.Char>()) == 0  );
        print("INITIALIZED: $initialized");
        if (initialized) {
          if (onInitDone != null) {
            onInitDone();
          }
        }
      }

      if (kDebugMode) {
        print("[OK] Loaded model... $modelpath");
        print("--------------------------------------------------\nChat mode: ON");
      }
    } catch (e) {
      state = AIDialogSTATE.INITIALIZED_FAILURE;
      return false;
    }

    state = AIDialogSTATE.INITIALIZED_SUCCESS;
    return true;
  }

  void reset_msgs() {
    print("AiDialog: reset_msgs");
    msgs = [];
    if (system_message.isNotEmpty) {
      msgs.add(AIChatMessage("system", system_message));
      if (kDebugMode) {
        print("Using system prompt: \"${system_message}\"");
      }
    }
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

  bool start_advance_stream({String? user_msg, bool fix_chatml = true}) {
    streaming = true;

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
          .async_completion_init(api_query.toNativeUtf8().cast<ffi.Char>())
          .cast<Utf8>()
          .toDartString();

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
    state = AIDialogSTATE.NOT_INITIALIZED;
  }
}
