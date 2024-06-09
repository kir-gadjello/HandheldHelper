import ctypes
import argparse
import code
import os
import readline
import atexit
import json

lib = None


def llm_chat(msgs):
    if isinstance(msgs, str):
        msgs = [dict(role="user", content=msgs)]

    return lib.rpc_call(
        json.dumps(
            dict(
                method="POST",
                path="/v1/chat/completions",
                body=json.dumps(dict(messages=msgs)),
            )
        )
    )


class SharedLibraryCLI_v0:
    def __init__(self, lib_path):
        self.lib = ctypes.CDLL(lib_path)

        # Define the argument and return types for the shared library functions
        self.lib.init.argtypes = [ctypes.c_char_p]
        self.lib.init.restype = ctypes.c_int

        self.lib.init_async.argtypes = [ctypes.c_char_p]
        self.lib.init_async.restype = None

        self.lib.poll_system_status.argtypes = []
        self.lib.poll_system_status.restype = ctypes.c_char_p

        self.lib.rpc_call.argtypes = [ctypes.c_char_p]
        self.lib.rpc_call.restype = ctypes.c_char_p

        self.lib.get_completion.argtypes = [ctypes.c_char_p]
        self.lib.get_completion.restype = ctypes.c_char_p

        self.lib.deinit.argtypes = []
        self.lib.deinit.restype = None

    def init(self, arg):
        result = self.lib.init(arg.encode("utf-8"))
        print(f"Result: {result}")

    def init_async(self, arg):
        self.lib.init_async(arg.encode("utf-8"))
        print("Asynchronous initialization started.")

    def get_completion(self, cmd):
        ret = self.lib.get_completion(cmd.encode("utf-8")).decode("utf-8")
        print(f'Ret: {ret}')
        return ret

    def poll_system_status(self):
        status = self.lib.poll_system_status()
        print(f'Status: {status.decode("utf-8")}')
        return status.decode("utf-8")

    def rpc_call(self, arg):
        response = self.lib.rpc_call(arg.encode("utf-8"))
        print(f'Response: {response.decode("utf-8")}')
        return response.decode("utf-8")

    def deinit(self):
        self.lib.deinit()
        print("System deinitialized.")

class SharedLibraryCLI:
    def __init__(self, lib_path):
        self.lib = ctypes.CDLL(lib_path)

        # Define the argument and return types for the shared library functions
        self.lib.init.argtypes = [ctypes.c_char_p]
        self.lib.init.restype = ctypes.c_int

        self.lib.init_async.argtypes = [ctypes.c_char_p]
        self.lib.init_async.restype = None

        self.lib.tokenize.argtypes = [ctypes.c_char_p]
        self.lib.tokenize.restype = ctypes.c_char_p

        self.lib.poll_system_status.argtypes = []
        self.lib.poll_system_status.restype = ctypes.c_char_p

        self.lib.get_completion.argtypes = [ctypes.c_char_p]
        self.lib.get_completion.restype = ctypes.c_char_p

        self.lib.async_completion_init.argtypes = [ctypes.c_char_p]
        self.lib.async_completion_init.restype = ctypes.c_char_p

        self.lib.async_completion_poll.argtypes = [ctypes.c_char_p]
        self.lib.async_completion_poll.restype = ctypes.c_char_p

        self.lib.async_completion_cancel.argtypes = [ctypes.c_char_p]
        self.lib.async_completion_cancel.restype = ctypes.c_char_p

        # self.lib.save_state.argtypes = [ctypes.c_char_p]
        # self.lib.save_state.restype = ctypes.c_char_p

        # self.lib.load_state.argtypes = [ctypes.c_char_p]
        # self.lib.load_state.restype = ctypes.c_char_p

        self.lib.deinit.argtypes = []
        self.lib.deinit.restype = None

    def init(self, cmd):
        result = self.lib.init(cmd.encode("utf-8"))
        print(f"Result: {result}")

    def init_async(self, cmd):
        self.lib.init_async(cmd.encode("utf-8"))
        print("Asynchronous initialization started.")

    def tokenize(self, req_json):
        ret = self.lib.tokenize(req_json.encode("utf-8")).decode("utf-8")
        print(f'Ret: {ret}')
        return ret

    def poll_system_status(self):
        status = self.lib.poll_system_status()
        print(f'Status: {status.decode("utf-8")}')
        return status.decode("utf-8")

    def get_completion(self, req_json):
        ret = self.lib.get_completion(req_json.encode("utf-8")).decode("utf-8")
        print(f'Ret: {ret}')
        return ret

    def async_completion_init(self, req_json):
        ret = self.lib.async_completion_init(req_json.encode("utf-8")).decode("utf-8")
        print(f'Ret: {ret}')
        return ret

    def async_completion_poll(self, cmd_json):
        ret = self.lib.async_completion_poll(cmd_json.encode("utf-8")).decode("utf-8")
        print(f'Ret: {ret}')
        return ret

    def async_completion_cancel(self, req_json):
        ret = self.lib.async_completion_cancel(req_json.encode("utf-8")).decode("utf-8")
        print(f'Ret: {ret}')
        return ret

    def save_state(self, req_json):
        ret = self.lib.save_state(req_json.encode("utf-8")).decode("utf-8")
        print(f'Ret: {ret}')
        return ret

    def load_state(self, req_json):
        ret = self.lib.load_state(req_json.encode("utf-8")).decode("utf-8")
        print(f'Ret: {ret}')
        return ret

    def deinit(self):
        self.lib.deinit()
        print("System deinitialized.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("lib_path", help="Path to shared library")
    parser.add_argument(
        "-b", "--bootstrap", help="Python file to execute after lib creation"
    )
    args = parser.parse_args()

    assert os.path.isfile(args.lib_path)

    lib = SharedLibraryCLI(args.lib_path)

    if args.bootstrap:
        assert os.path.isfile(args.bootstrap)
        with open(args.bootstrap, "r") as f:
            exec(f.read(), {**globals(), **locals()}, globals())

    # Create an interactive shell
    vars = globals().copy()
    vars.update(locals())
    shell = code.InteractiveConsole(locals=vars)
    # Set up shell history
    histfile = os.path.join(os.path.expanduser("~"), ".rpcshell_history")
    try:
        readline.read_history_file(histfile)
    except FileNotFoundError:
        pass

    def save_history():
        readline.write_history_file(histfile)

    shell.interact(
        "Interactive shell. Type 'lib.' to access the SharedLibraryCLI instance."
    )
    atexit.register(save_history)
