// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated by `package:ffigen`.
// ignore_for_file: type=lint
import 'dart:ffi' as ffi;

/// Holds bindings to LLama RPC server.
class LLamaRPC {
  /// Holds the symbol lookup function.
  final ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName)
      _lookup;

  /// The symbols are looked up in [dynamicLibrary].
  LLamaRPC(ffi.DynamicLibrary dynamicLibrary) : _lookup = dynamicLibrary.lookup;

  /// The symbols are looked up with [lookup].
  LLamaRPC.fromLookup(
      ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName)
          lookup)
      : _lookup = lookup;

  int init(
    ffi.Pointer<ffi.Char> cmd,
  ) {
    return _init(
      cmd,
    );
  }

  late final _initPtr =
      _lookup<ffi.NativeFunction<ffi.Int Function(ffi.Pointer<ffi.Char>)>>(
          'init');
  late final _init = _initPtr.asFunction<int Function(ffi.Pointer<ffi.Char>)>();

  void init_async(
    ffi.Pointer<ffi.Char> cmd,
  ) {
    return _init_async(
      cmd,
    );
  }

  late final _init_asyncPtr =
      _lookup<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Char>)>>(
          'init_async');
  late final _init_async =
      _init_asyncPtr.asFunction<void Function(ffi.Pointer<ffi.Char>)>();

  ffi.Pointer<ffi.Char> tokenize(
    ffi.Pointer<ffi.Char> req_json,
  ) {
    return _tokenize(
      req_json,
    );
  }

  late final _tokenizePtr = _lookup<
      ffi.NativeFunction<
          ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>)>>('tokenize');
  late final _tokenize = _tokenizePtr
      .asFunction<ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>)>();

  ffi.Pointer<ffi.Char> poll_system_status() {
    return _poll_system_status();
  }

  late final _poll_system_statusPtr =
      _lookup<ffi.NativeFunction<ffi.Pointer<ffi.Char> Function()>>(
          'poll_system_status');
  late final _poll_system_status =
      _poll_system_statusPtr.asFunction<ffi.Pointer<ffi.Char> Function()>();

  ffi.Pointer<ffi.Char> get_completion(
    ffi.Pointer<ffi.Char> req_json,
  ) {
    return _get_completion(
      req_json,
    );
  }

  late final _get_completionPtr = _lookup<
      ffi.NativeFunction<
          ffi.Pointer<ffi.Char> Function(
              ffi.Pointer<ffi.Char>)>>('get_completion');
  late final _get_completion = _get_completionPtr
      .asFunction<ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>)>();

  ffi.Pointer<ffi.Char> async_completion_init(
    ffi.Pointer<ffi.Char> req_json,
  ) {
    return _async_completion_init(
      req_json,
    );
  }

  late final _async_completion_initPtr = _lookup<
      ffi.NativeFunction<
          ffi.Pointer<ffi.Char> Function(
              ffi.Pointer<ffi.Char>)>>('async_completion_init');
  late final _async_completion_init = _async_completion_initPtr
      .asFunction<ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>)>();

  ffi.Pointer<ffi.Char> async_completion_poll(
    ffi.Pointer<ffi.Char> cmd_json,
  ) {
    return _async_completion_poll(
      cmd_json,
    );
  }

  late final _async_completion_pollPtr = _lookup<
      ffi.NativeFunction<
          ffi.Pointer<ffi.Char> Function(
              ffi.Pointer<ffi.Char>)>>('async_completion_poll');
  late final _async_completion_poll = _async_completion_pollPtr
      .asFunction<ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>)>();

  ffi.Pointer<ffi.Char> async_completion_cancel(
    ffi.Pointer<ffi.Char> req_json,
  ) {
    return _async_completion_cancel(
      req_json,
    );
  }

  late final _async_completion_cancelPtr = _lookup<
      ffi.NativeFunction<
          ffi.Pointer<ffi.Char> Function(
              ffi.Pointer<ffi.Char>)>>('async_completion_cancel');
  late final _async_completion_cancel = _async_completion_cancelPtr
      .asFunction<ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>)>();

  ffi.Pointer<ffi.Char> save_state(
    ffi.Pointer<ffi.Char> req_json,
  ) {
    return _save_state(
      req_json,
    );
  }

  late final _save_statePtr = _lookup<
      ffi.NativeFunction<
          ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>)>>('save_state');
  late final _save_state = _save_statePtr
      .asFunction<ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>)>();

  ffi.Pointer<ffi.Char> load_state(
    ffi.Pointer<ffi.Char> req_json,
  ) {
    return _load_state(
      req_json,
    );
  }

  late final _load_statePtr = _lookup<
      ffi.NativeFunction<
          ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>)>>('load_state');
  late final _load_state = _load_statePtr
      .asFunction<ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>)>();

  void deinit() {
    return _deinit();
  }

  late final _deinitPtr =
      _lookup<ffi.NativeFunction<ffi.Void Function()>>('deinit');
  late final _deinit = _deinitPtr.asFunction<void Function()>();
}
