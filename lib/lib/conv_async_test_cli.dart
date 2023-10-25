import 'dart:convert' show utf8;
import 'dart:io' show stdout, stdin, Platform, sleep, Duration;
import 'conv.dart';

void main() {
  var d = AIDialog(
      system_message:
          "You are a helpful, honest, reliable and smart AI assistant named Hermes doing your best at fulfilling user requests. You are cool and extremely loyal. You answer any user requests to the best of your ability.",
      libpath: "./native/librpcserver.dylib",
      modelpath: Platform.environment["MODELPATH"] ??
          "/Users/LKE/projects/AI/openhermes-2-mistral-7b.Q4_K_M.gguf");

  while (true) {
    stdout.write("User: ");
    var user_msg = stdin.readLineSync(encoding: utf8) as String;
    var success = d.start_advance_stream(user_msg: user_msg);

    stdout.write("AI: ");

    bool finished = false;
    while (!finished) {
      var poll_result = d.poll_advance_stream();
      finished = poll_result.finished;
      // print("poll: ${poll_result.finished} ${poll_result.completion_updates.length} ${poll_result.completion_updates}");
      String upd_str = poll_result.joined();
      if (upd_str.isNotEmpty) {
        stdout.write("$upd_str");
      }
      sleep(const Duration(milliseconds: 500));
    }
    print("");

    // if (success) {
    //   print("AI: ${d.msgs.last.content}");
    // } else {
    //   print("<!!- AI_API_ERROR: ${d.error} -!!>");
    // }
  }
}
