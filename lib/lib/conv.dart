import 'dart:convert' show jsonEncode, jsonDecode;
import 'dart:ffi' as ffi;
import 'dart:io' show File;
import 'package:ffi/ffi.dart';
import 'dart:isolate';
import 'dart:async';
import 'package:async/async.dart';

import 'isolate_rpc.dart';

import 'llamarpc_generated_bindings.dart' as binding;

const kDebugMode = true;
const String LLAMA_SO = "librpcserver";
const bool __DEBUG = false;

class LLAMAChatCompletion {
  String prompt = "";
  int max_tokens;
  double temperature;
  String stop;

  LLAMAChatCompletion(this.prompt, {
    this.max_tokens = 512,
    this.temperature = 0.0,
    this.stop = "<|im_end|>",
  });

  Map<String, dynamic> toJson() =>
      {
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

enum AIDialogSTATE { NOT_INITIALIZED, INITIALIZED_SUCCESS, INITIALIZED_FAILURE }

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

class AIDMsg {}

class AIDReinitMsg extends AIDMsg {
  String? system_message;
  String modelpath;

  AIDReinitMsg({String? system_message = "", this.modelpath = ""});
}

class AIDAdvanceMsg extends AIDMsg {
  String? user_msg;
  bool fix_chatml;

  AIDAdvanceMsg({String? user_msg, this.fix_chatml = true});
}

class AIDget_msgsMsg extends AIDMsg {}

class AIDreset_msgsMsg extends AIDMsg {}

class AIDTeardownMsg extends AIDMsg {}

class AIDGetMsgsMsg extends AIDMsg {}

class AIDMsgRet {}

class AIDMsgsRet extends AIDMsgRet {
  List<AIChatMessage> msgs;

  AIDMsgsRet(this.msgs);
}

class AIDBoolRet extends AIDMsgRet {
  bool flag;

  AIDBoolRet(this.flag);
}

// class _AIDialogServiceProcessor(AIDMsg rpc_msg) {
//   AIDialog? dialog = null;
//
//   switch (rpc_msg) {
//     case AIDReinitMsg(system_message: var sm, modelpath: var mp):
//       {
//         if (dialog == null) {
//           dialog = AIDialog(system_message: sm ?? "", modelpath: mp);
//         }
//       }
//     case AIDAdvanceMsg(user_msg: var user_msg, fix_chatml: var fix_chatml):
//       {
//         dialog.advance(user_msg: user_msg, fix_chatml: fix_chatml)
//       }
//   }
//
//   return AIDBoolRet(false);
// }

class _AIDialogServiceProcessor<T, U> extends StatefulRPCProcessor<T, U> {
  late AIDialog dialog;

  @override FutureOr<U> process(T rpc_incoming) {
    var rpc_msg = rpc_incoming as AIDMsg;

    AIDMsgRet ret = AIDBoolRet(false);

    switch (rpc_msg) {
      case AIDReinitMsg(system_message: var sm, modelpath: var mp):
        {
          if (dialog == null) {
            dialog = AIDialog(system_message: sm ?? "", modelpath: mp);
            ret = AIDBoolRet(true); // TODO init status check
          } else {
            ret = AIDBoolRet(
                dialog.reinit(system_message: sm ?? "", modelpath: mp));
          }
        }
      case AIDAdvanceMsg(user_msg: var user_msg, fix_chatml: var fix_chatml):
        {
          dialog.advance(user_msg: user_msg, fix_chatml: fix_chatml);
          ret = AIDMsgsRet(dialog.msgs);
        }
      case AIDGetMsgsMsg():
        {
          ret = AIDMsgsRet(dialog.msgs);
        }
    }

    return ret as FutureOr<U>;
  }
}

class AIDialogService {
  late IsolateRpc<AIDMsg, AIDMsgRet> _AIDialogRPC;

  AIDialogService({system_message = "", libpath = "", modelpath = ""}) {
    _AIDialogRPC = IsolateRpc.single(
        processorFactory: () => _AIDialogServiceProcessor(),
        // the execution logics, i.e. this is a plus one operation
        debugName: "rpc" // this will be used as the Isolate name
    );
  }

  FutureOr<bool> reinit (
      {String? system_message, required String modelpath}) async {
    var ret = await _AIDialogRPC.execute(AIDReinitMsg(system_message: system_message, modelpath: modelpath));
    return Future.value((ret.result as AIDBoolRet).flag);
  }

  FutureOr<bool> advance({String? user_msg, bool fix_chatml = true}) async {
    var ret = await _AIDialogRPC.execute(AIDAdvanceMsg(user_msg: user_msg, fix_chatml: fix_chatml));
    return Future.value((ret.result as AIDBoolRet).flag);
  }

  FutureOr<List<AIChatMessage>> get_msgs() async {
    var ret = await _AIDialogRPC.execute(AIDGetMsgsMsg());
    return Future.value((ret.result as AIDMsgsRet).msgs);
  }
}

// The entrypoint that runs on the spawned isolate. Receives messages from
// the main isolate, reads the contents of the file, decodes the JSON, and
// sends the result back to the main isolate.
// Future<void> _aiDialogService(SendPort p) async {
//   print('_aiDialogService: Spawned isolate started.');
//
//   // Send a SendPort to the main isolate so that it can send JSON strings to
//   // this isolate.
//   final commandPort = ReceivePort();
//   p.send(commandPort.sendPort);
//
//   // Wait for messages from the main isolate.
//   await for (final message in commandPort) {
//     if (message is ChatCmd) {
//       // Read and decode the file.
//       final contents = await File(message).readAsString();
//
//       // Send the result to the main isolate.
//       p.send(jsonDecode(contents));
//     } else if (message == null) {
//       // Exit if the main isolate sends a null message, indicating there are no
//       // more files to read and parse.
//       break;
//     }
//   }
// }
