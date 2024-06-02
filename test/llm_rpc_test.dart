import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as Path;
import '../lib/llm_engine.dart';
import 'package:test/test.dart';

String MODEL_DIR = Platform.environment["LLM_MODEL_DIR"] ?? "..";

const LOCAL_MODEL_DIR = "local_test_llms";

String MODEL_LARGE = "openhermes-2.5-mistral-7b.Q4_K_M.gguf";
String MODEL_SMALL = "tinyllama-1.1b-1t-openorca.Q4_K_M.gguf";

const hermes_sysmsg =
    "You are a helpful, honest, reliable and smart AI assistant named Hermes doing your best at fulfilling user requests. You are cool and extremely loyal. You answer any user requests to the best of your ability.";
const COUNT_PROMPT = "count from 1 to 3, output only the numbers";
const COUNT_PROMPT_ELI5 =
    "This is a test. Count from 1 to 3 like a kindergartener, output only the numbers";

void expect_llm_fresh(LLMEngine llm) {
  expect(llm.init_in_progress, false);
  expect(llm.initialized, true);
  expect(llm.state, LLMEngineState.INITIALIZED_SUCCESS);
  expect(llm.msgs.isEmpty, true);
}

const default_timeout = Timeout(Duration(seconds: 10));

Future<(bool, List<SUpdate>)> accept_ai_answer_stream(LLMEngine llm,
    {Timeout timeout = default_timeout}) async {
  AIChatMessage? completedMsg;
  bool finished = false;
  double _prompt_processing_progress = 0.0;
  DateTime _prompt_processing_initiated = DateTime.now();
  DateTime? _prompt_processing_completed;
  List<SUpdate> updates = [];

  while (DateTime.now().difference(_prompt_processing_initiated) <
      timeout.duration!) {
    var poll_result = llm.poll_advance_stream();
    updates.addAll(poll_result.completion_updates);

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
      return (true, updates);
    }
  }

  return (false, updates);
}

LLMEngine make_llm() {
  return LLMEngine(
      libpath: Platform.environment['LLMLIBRPC'] ??
          './native/apple_silicon/librpcserver.dylib');
}

String? checkAllFilesExist({
  required List<String> directories,
  required List<String> filenames,
  Map<String, int>? fileSizes,
}) {
  for (final directory in directories) {
    final dir = Directory(directory);
    if (!dir.existsSync()) {
      continue; // skip to next directory
    }

    bool allFilesExist = true;
    for (final filename in filenames) {
      final file = File(Path.join(directory, filename));
      if (!file.existsSync()) {
        allFilesExist = false;
        break;
      }

      if (fileSizes != null && fileSizes.containsKey(filename)) {
        final fileSize = file.lengthSync();
        if (fileSize != fileSizes[filename]) {
          allFilesExist = false;
          break;
        }
      }
    }

    if (allFilesExist) {
      return directory; // return the directory if all files exist
    }
  }

  return null; // return null if no directory has all files
}

void main() async {
  var dirs = [MODEL_DIR, LOCAL_MODEL_DIR, ".."];
  var llm_dir = checkAllFilesExist(
      directories: dirs, filenames: [MODEL_LARGE, MODEL_SMALL]);

  if (llm_dir == null) {
    print(
        "This test requires large external files in one of the following directories: $dirs (set alternative llm model directory via environment variable LLM_MODEL_DIR or run the ./download_test_llms.sh script to populate the local directory):");
    print(MODEL_LARGE);
    print(MODEL_SMALL);
    print(
        "Skipping tests, download the AI model files and place them into the outer directory to proceed");
    return;
  }

  MODEL_LARGE = Path.join(llm_dir, MODEL_LARGE);
  MODEL_SMALL = Path.join(llm_dir, MODEL_SMALL);

  var completer = Completer<void>();
  const timeout = Timeout(Duration(seconds: 10));

  // group("MODEL:SMALL, FRESH", () {
  //   LLMEngine llm = LLMEngine();
  //
  //   test("LOAD (INITIAL)", () async {
  //     llm.initialize(
  //         modelpath: MODEL_SMALL,
  //         onInitDone: (success) {
  //          expect(success, true);
  //           completer.complete();
  //         });
//       expect(llm.init_in_progress, true);
  //     await completer.future;
  //     completer = Completer<void>();
  //
  //     expect_llm_fresh(llm);
  //     expect(Path.basename(llm.modelpath), Path.basename(MODEL_SMALL));
  //   }, timeout: timeout);
  //
  //   String completion_initial = "";
  //
  //   test("COMPLETION (INITIAL)", () async {
  //     llm.set_system_prompt(hermes_sysmsg);
  //     var success = llm.advance(user_msg: COUNT_PROMPT_ELI5);
  //     expect(success, true);
  //     expect(llm.streaming, false);
  //     print("MODEL<${Path.basename(llm.modelpath)}>: ${llm.msgs.last}");
  //     expect(llm.msgs.last.role, "assistant");
  //     expect(llm.msgs.last.content.endsWith("1, 2, 3"), true);
  //     completion_initial = llm.msgs.last.content;
  //   });
  //
  //   test("STREAMING COMPLETION (INITIAL)", () async {
  //     llm.clear_state();
  //     llm.set_system_prompt(hermes_sysmsg);
  //     var success = llm.start_advance_stream(user_msg: COUNT_PROMPT_ELI5);
  //     expect(success, true);
  //     expect(llm.streaming, true);
  //
  //     var (streaming_success, updates) = await accept_ai_answer_stream(llm);
  //     expect(streaming_success, true);
  //     expect(updates.last.stop, true);
  //     expect(updates.map((u) => u.content).join(), llm.msgs.last.content);
  //
  //     print("MODEL<${Path.basename(llm.modelpath)}>: ${llm.msgs.last}");
  //     expect(llm.msgs.last.role, "assistant");
  //     expect(llm.msgs.last.content.endsWith("1, 2, 3"), true);
  //     completion_initial = llm.msgs.last.content;
  //   });
  //
  //   test("SMALL DEINIT", () {
  //     llm.deinitialize();
  //     expect(true, true);
  //   });
  // });

  group("MODEL:LARGE, FRESH -> REINIT", () {
    LLMEngine llm = make_llm();
    var completer = Completer<void>();

    test("LOAD (INITIAL)", () async {
      llm.initialize(
          modelpath: MODEL_LARGE,
          onInitDone: (success) {
            expect(success, true);
            completer.complete();
          });
      expect(llm.init_in_progress, true);
      await completer.future;
      completer = Completer<void>();

      expect_llm_fresh(llm);
      expect(Path.basename(llm.modelpath), Path.basename(MODEL_LARGE));
    }, timeout: timeout);

    String completion_initial = "";

    test("COMPLETION (INITIAL)", () async {
      llm.set_system_prompt(hermes_sysmsg);
      var success = llm.advance(user_msg: COUNT_PROMPT);
      expect(success, true);
      print("MODEL<${Path.basename(llm.modelpath)}>: ${llm.msgs.last}");
      expect(llm.msgs.last.role, "assistant");
      expect(llm.msgs.last.content.endsWith("1\n2\n3"), true);
      completion_initial = llm.msgs.last.content;
    });

    test("STREAMING COMPLETION (INITIAL)", () async {
      llm.clear_state();
      llm.set_system_prompt(hermes_sysmsg);
      var success = llm.start_advance_stream(user_msg: COUNT_PROMPT);
      expect(success, true);
      expect(llm.streaming, true);

      var (streaming_success, updates) = await accept_ai_answer_stream(llm);
      expect(streaming_success, true);
      expect(updates.last.stop, true);
      expect(updates.map((u) => u.content).join(), llm.msgs.last.content);

      print("MODEL<${Path.basename(llm.modelpath)}>: ${llm.msgs.last}");
      expect(llm.msgs.last.role, "assistant");
      expect(llm.msgs.last.content.endsWith("1\n2\n3"), true);
      completion_initial = llm.msgs.last.content;
    });

    test("LARGE DEINIT", () {
      llm.deinitialize();
      expect(llm.initialized, false);
      expect(true, true);
    });

    test("LOAD (SMALL, REINIT)", () async {
      completer = Completer<void>();
      llm.initialize(
          modelpath: MODEL_SMALL,
          onInitDone: (success) {
            expect(success, true);
            print("$MODEL_SMALL: init done");
            completer.complete();
          });
      expect(llm.init_in_progress, true);
      await completer.future;
      completer = Completer<void>();

      expect_llm_fresh(llm);
      expect(Path.basename(llm.modelpath), Path.basename(MODEL_SMALL));
    }, timeout: timeout);

    test("COMPLETION (SMALL, REINIT)", () async {
      llm.set_system_prompt(hermes_sysmsg);
      var success = llm.advance(user_msg: COUNT_PROMPT_ELI5);
      expect(success, true);
      print("MODEL<${Path.basename(llm.modelpath)}>: ${llm.msgs.last}");
      expect(llm.msgs.last.role, "assistant");
      expect(llm.msgs.last.content.endsWith("1, 2, 3"), true);
      completion_initial = llm.msgs.last.content;
    });

    test("SMALL DEINIT", () {
      llm.deinitialize();
      expect(llm.initialized, false);
      expect(true, true);
    });
  });

  await Future.delayed(const Duration(seconds: 1));
}
