import 'dart:convert' show jsonEncode, jsonDecode;
import 'dart:ffi' as ffi;
import 'dart:io' show File;
import 'package:ffi/ffi.dart';
import 'dart:isolate';
import 'dart:async';
import 'package:async/async.dart';
import '../lib/llm_engine.dart';
import '../lib/isolate_rpc.dart';
import 'package:test/test.dart';

// Spawns an isolate and asynchronously sends a list of filenames for it to
// read and decode. Waits for the response containing the decoded JSON
// before sending the next.
//
// Returns a stream that emits the JSON-decoded contents of each file.
// Stream<ChatCmd> _sendAndReceive(List<String> filenames) async* {
//   final p = ReceivePort();
//   await Isolate.spawn(_aiDialogService, p.sendPort);
//
//   // Convert the ReceivePort into a StreamQueue to receive messages from the
//   // spawned isolate using a pull-based interface. Events are stored in this
//   // queue until they are accessed by `events.next`.
//   final events = StreamQueue<dynamic>(p);
//
//   // The first message from the spawned isolate is a SendPort. This port is
//   // used to communicate with the spawned isolate.
//   SendPort sendPort = await events.next;
//
//   for (var filename in filenames) {
//     // Send the next filename to be read and parsed
//     sendPort.send(filename);
//
//     // Receive the parsed JSON
//     ChatCmd message = await events.next;
//
//     // Add the result to the stream returned by this async* function.
//     yield message;
//   }
//
//   // Send a signal to the spawned isolate indicating that it should exit.
//   sendPort.send(null);
//
//   // Dispose the StreamQueue.
//   await events.cancel();
// }

//
// class PlusOneRPC<U,T> {
//   @override U process(T data) {
//     return data + 1;
//   }
// }

// class PlusOneRPC<T, U> {
//   // Define state variables here
//   int _counter = 0;
//
//   FutureOr<int> process(int data) {
//     _counter++;
//     return _counter;
//   }
// }

class StatefulProcessor<T, U> extends StatefulRPCProcessor<T, U> {
  // Define state variables here
  int _counter = 1;

  @override
  FutureOr<U> process(T data) {
    _counter += (data as int);
    return (_counter) as FutureOr<U>;
  }
}

void main() async {
  test('IsolateRpc - basic fn', () async {
    // define a single Rpc service with exactly one Isolate, isolate will be spawned immediately.
    IsolateRpc<int, int> rpc = IsolateRpc.single(
        processorFactory: () => StatefulProcessor<int, int>(),
        // the execution logics, i.e. this is a plus one operation
        debugName: "rpc" // this will be used as the Isolate name
        );
    expect((await rpc.execute(1)).result, 2);
    expect((await rpc.execute(0)).result, 2);
    expect((await rpc.execute(1)).result, 3);
    rpc.shutdown();
  });
}
