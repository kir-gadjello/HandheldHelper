import 'dart:convert' show jsonEncode, jsonDecode;
import 'dart:ffi' as ffi;
import 'dart:io' show File;
import 'package:ffi/ffi.dart';
// import 'dart:isolate';

// import 'package:flutter/foundation.dart';
import 'llamarpc_generated_bindings.dart' as binding;

const kDebugMode = true;
const String LLAMA_SO = "librpcserver";
const bool __DEBUG = false;

class LLAMAChatCompletion {
  String prompt = "";
  int max_tokens;
  double temperature;
  String stop;

  LLAMAChatCompletion(
    this.prompt, {
    this.max_tokens = 512,
    this.temperature = 0.0,
    this.stop = "<|im_end|>",
  });

  Map<String, dynamic> toJson() => {
        'prompt': prompt,
        'n_predict': max_tokens,
        'temperature': temperature,
        'stop': "<|im_end|>",
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

enum AIDialogSTATE {
  NOT_INITIALIZED,
  INITIALIZED_SUCCESS,
  INITIALIZED_FAILURE
}

class AIDialog {
  String system_message = "";
  String libpath = "$LLAMA_SO";
  String modelpath = "";
  String error = "";

  AIDialogSTATE state = AIDialogSTATE.NOT_INITIALIZED;

  late List<AIChatMessage> msgs = [];

  late binding.LLamaRPC rpc;

  AIDialog({this.system_message = "", this.libpath = "", this.modelpath = ""}) {
    rpc = binding.LLamaRPC(ffi.DynamicLibrary.open(libpath));

    if (!File(this.modelpath).existsSync()) {
      print("Avoiding init due to invalid modelpath");
      return;
    }

    reinit(system_message: system_message, modelpath: modelpath);
  }

  bool reinit({String? system_message, required String modelpath}) {

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

      rpc.init("{\"model\":\"$modelpath\"}".toNativeUtf8().cast<ffi.Char>());

      if (kDebugMode) {
        print("[OK] Loaded model... $modelpath");
        print(
            "--------------------------------------------------\nChat mode: ON");
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

  void teardown() {
    rpc.deinit();
    state = AIDialogSTATE.NOT_INITIALIZED;
  }
}

// class BackgroundAIDialog {
//   String system_message = "";
//   String libpath = "$LLAMA_SO";
//   String modelpath = "";
//   String error = "";
//
//   final List<AIChatMessage> msgs = [];
//
//   late binding.LLamaRPC rpc;
//
//   AIDialog({this.system_message = "", this.libpath = "", this.modelpath = ""}) {
//     rpc = binding.LLamaRPC(ffi.DynamicLibrary.open(libpath));
//
//     if (system_message.length > 0) {
//       msgs.add(AIChatMessage("system", system_message));
//       if (kDebugMode) {
//         print("Using system prompt: \"${this.system_message}\"");
//       }
//     }
//
//     if (kDebugMode) print("[OK] Loaded library... $LLAMA_SO");
//
//     rpc.init("server -m $modelpath".toNativeUtf8().cast<ffi.Char>());
//
//     if (kDebugMode) {
//       print("[OK] Loaded model... $modelpath");
//       print(
//           "--------------------------------------------------\nChat mode: ON");
//     }
//   }
//
//   bool advance({String? user_msg}) {
//     if (user_msg != null) {
//       msgs.add(AIChatMessage("user", user_msg));
//     }
//
//     if (msgs.last.role != "user") {
//       error = "Error: last message should have role user";
//       return false;
//     }
//
//     try {
//       String api_query = jsonEncode(LLAMAChatCompletion(format_chatml(msgs)));
//
//       if (__DEBUG) print("DEBUG: api_query=${api_query}");
//
//       final api_resp = rpc
//           .get_completion(api_query.toNativeUtf8().cast<ffi.Char>())
//           .cast<Utf8>()
//           .toDartString();
//
//       if (__DEBUG) print("RESPONSE: $api_resp");
//
//       String resp = jsonDecode(api_resp)["content"] as String;
//
//       while (resp.endsWith("<|im_end|>")) {
//         resp = resp.substring(0, resp.length - "<|im_end|>".length);
//       }
//
//       msgs.add(AIChatMessage("assistant", resp));
//       error = "";
//       return true;
//
//       // print("AI: $resp");
//     } catch (e) {
//       error = e.toString();
//       if (kDebugMode) {
//         print("Error: ${e}");
//       }
//     }
//
//     return false;
//   }
//
//   void teardown() {
//     rpc.deinit();
//   }
// }

// void main() {
//   createIsolate();
// }
//
// Future createIsolate() async {
//   /// Where I listen to the message from Mike's port
//   ReceivePort myReceivePort = ReceivePort();
//
//   /// Spawn an isolate, passing my receivePort sendPort
//   Isolate.spawn<SendPort>(heavyComputationTask, myReceivePort.sendPort);
//
//   /// Mike sends a senderPort for me to enable me to send him a message via his sendPort.
//   /// I receive Mike's senderPort via my receivePort
//   SendPort mikeSendPort = await myReceivePort.first;
//
//   /// I set up another receivePort to receive Mike's response.
//   ReceivePort mikeResponseReceivePort = ReceivePort();
//
//   /// I send Mike a message using mikeSendPort. I send him a list,
//   /// which includes my message, preferred type of coffee, and finally
//   /// a sendPort from mikeResponseReceivePort that enables Mike to send a message back to me.
//   mikeSendPort.send([
//     "Mike, I'm taking an Espresso coffee",
//     "Espresso",
//     mikeResponseReceivePort.sendPort
//   ]);
//
//   /// I get Mike's response by listening to mikeResponseReceivePort
//   final mikeResponse = await mikeResponseReceivePort.first;
//   log("MIKE'S RESPONSE: ==== $mikeResponse");
// }
//
// void heavyComputationTask(SendPort mySendPort) async {
//   /// Set up a receiver port for Mike
//   ReceivePort mikeReceivePort = ReceivePort();
//
//   /// Send Mike receivePort sendPort via mySendPort
//   mySendPort.send(mikeReceivePort.sendPort);
//
//   /// Listen to messages sent to Mike's receive port
//   await for (var message in mikeReceivePort) {
//     if (message is List) {
//       final myMessage = message[0];
//       final coffeeType = message[1];
//       log(myMessage);
//
//       /// Get Mike's response sendPort
//       final SendPort mikeResponseSendPort = message[2];
//
//       /// Send Mike's response via mikeResponseSendPort
//       mikeResponseSendPort
//           .send("You're taking $coffeeType, and I'm taking Latte");
//     }
//   }
// }
