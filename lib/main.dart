import 'dart:io';
import 'dart:isolate';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:clipboard/clipboard.dart';
import 'conv.dart';

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

void main(List<String> args) async {
  print("CMD ARGS: ${args.join(',')}");

  // var (isolate, isolateToMainStream) = await spawnIsolate();
  //
  // // Send a command to the isolate
  // isolate.send({'command': 'compute', 'value': 10});
  //
  // // Listen for results from the isolate
  // ReceivePort mainToIsolateStream = ReceivePort();
  // isolate.addOnExitListener(mainToIsolateStream.sendPort, response: 'done');
  // mainToIsolateStream.listen((message) {
  //   if (message is int) {
  //     print('Received result: $message');
  //   }
  // });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Handheld Helper',
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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Handheld Helper LLM'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

String resolve_llm_file() {
  var s = Platform.environment["MODELPATH"] ?? "";
  print("MODEL: probing $s");
  if (File(s).existsSync()) {
    return s;
  }

  s = "./openhermes-2-mistral-7b.Q4_K_M.gguf";
  print("MODEL: probing $s");
  if (File(s).existsSync()) {
    return s;
  }

  s = "/Users/LKE/projects/AI/openhermes-2-mistral-7b.Q4_K_M.gguf";
  print("MODEL: probing $s");
  if (File(s).existsSync()) {
    return s;
  }

  throw FileSystemException(s);
}

String truncateWithEllipsis(int cutoff, String myString) {
  return (myString.length <= cutoff)
      ? myString
      : '${myString.substring(0, cutoff)}...';
}

const hermes_sysmsg = "You are a helpful, honest, reliable and smart AI assistant named Hermes doing your best at fulfilling user requests. You are cool and extremely loyal. You answer any user requests to the best of your ability.";

class _MyHomePageState extends State<MyHomePage> {
  final dialog = AIDialog(
      system_message:
          hermes_sysmsg,
      libpath: "librpcserver.dylib",
      modelpath: resolve_llm_file());

  late List<ChatMessage> _messages = [];

  _MyHomePageState() {
    _reset_msgs();
  }

  void reset_msgs() {
    setState(() {
      _reset_msgs();
    });
  }

  void _reset_msgs() {
    _messages = [
      ChatMessage(
        text: "Beginning of conversation with model at ${dialog.modelpath}\nSystem prompt: $hermes_sysmsg",
        user: user_SYSTEM,
        createdAt: DateTime.now(),
      ),
    ];
  }

  void addMsg(ChatMessage m) {
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
        print("MSGS: ${_messages.map((m) => m.text)}");
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

  void reload_model_from_file(String new_modelpath) async {
    setState(() {
      _messages = [
        ChatMessage(
            user: user_SYSTEM,
            text: "... Loading new model from \"$new_modelpath\"",
            createdAt: DateTime.now())
      ];
    });

    await Future.delayed(const Duration(milliseconds: 1000));

    dialog.reinit(modelpath: new_modelpath);
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

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methodsdf
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
          // TRY THIS: Try changing the color here to a specific color (to
          // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
          // change color while the other colors stay the same.
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          // Here we take the value from the MyHomePage object that was created by
          // the App.build method, and use it to set our appbar title.
          title: Text(widget.title),
          actions: <Widget>[
            IconButton(
              icon: Icon(
                Icons.sync_alt,
                color: Colors.white,
              ),
              onPressed: () async {
                FilePickerResult? result =
                    await FilePicker.platform.pickFiles();

                if (result != null) {
                  File file = File(result.files.single.path ?? "");
                  if (file.existsSync()) {
                    var new_model = file.path;
                    print("RELOADING FROM $new_model");
                    reload_model_from_file(new_model);
                  }
                } else {
                  // User canceled the picker
                }
              },
            ),
            IconButton(
              icon: Icon(
                Icons.restart_alt,
                color: Colors.white,
              ),
              onPressed: () async {
                dialog.reset_msgs();
                reset_msgs();
              },
            ),
            IconButton(
              icon: Icon(
                Icons.ios_share,
                color: Colors.white,
              ),
              onPressed: () {
                FlutterClipboard.copy(serialize_msgs());

                final snackBar = SnackBar(
                  content: const Text('Conversation copied to clipboard'),
                );

                // Find the ScaffoldMessenger in the widget tree
                // and use it to show a SnackBar.
                ScaffoldMessenger.of(context).showSnackBar(snackBar);
              },
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
          children: <Widget>[
            Expanded(
              child: DashChat(
                inputOptions: const InputOptions(
                  sendOnEnter: false,
                  alwaysShowSend: true,
                  inputToolbarMargin: EdgeInsets.all(8.0),
                ),
                messageOptions: MessageOptions(
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
                onSend: (ChatMessage m) {
                  print("NEW MSG: ${m.text}");
                  addMsg(m);
                },
                messages: _messages,
              ),
            )
          ],
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
