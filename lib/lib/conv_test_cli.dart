import 'dart:convert';
import 'dart:io';
import 'conv.dart';

Map<String, dynamic> resolve_init_json() {
  var s = String.fromEnvironment("LLAMA_INIT_JSON");
  if (s.isNotEmpty) {
    return jsonDecode(s);
  }

  s = Platform.environment["LLAMA_INIT_JSON"] ?? "";
  if (s.isNotEmpty) {
    print("LOG LLAMA_INIT_JSON: ${jsonDecode(s)}");
    return jsonDecode(s);
  }

  s = "./llama_init.json";
  print("LLAMA_INIT_JSON: probing $s");
  if (File(s).existsSync()) {
    return jsonDecode(File(s).readAsStringSync());
  }

  return {};
}

void main() async {
  var d = LLMEngine(
      system_message:
          "You are a helpful, honest, reliable and smart AI assistant named Hermes doing your best at fulfilling user requests. You are cool and extremely loyal. You answer any user requests to the best of your ability.",
      libpath: "./native/librpcserver.dylib",
      modelpath: Platform.environment["MODELPATH"] ??
          "/Users/LKE/projects/AI/tinyllama-1.1b-1t-openorca.Q4_K_M.gguf",
      llama_init_json: resolve_init_json());

  stdout.write("Loading");

  while (!d.initialized) {
    stdout.write(".");
    d.poll_init();
    await Future.delayed(const Duration(milliseconds: 100));
  }

  // var tok = d.tokenize("test input");
  // print(tok.tokens);

  int msg_counter = 0;

  while (true) {
    String user_msg;

    if (msg_counter == 0 &&
        (Platform.environment["PROMPTFILE"] ?? "").isNotEmpty) {
      var ppath = Platform.environment["PROMPTFILE"] ?? "";
      print("Using first user message from PROMPTFILE...");
      String promptfile = File(ppath).readAsStringSync();
      var tok = d.tokenize(promptfile);
      print("PROMPTFILE@$ppath size: ${tok.length} tokens");
      stdout.write("User: <PROMPTFILE@$ppath>");
      user_msg = promptfile;
    } else {
      stdout.write("User: ");
      user_msg = stdin.readLineSync(encoding: utf8) as String;
    }

    var success = d.advance(user_msg: user_msg);

    if (success) {
      print("AI: ${d.msgs.last.content}");
    } else {
      print("<!!- AI_API_ERROR: ${d.error} -!!>");
    }

    msg_counter++;
  }
}
