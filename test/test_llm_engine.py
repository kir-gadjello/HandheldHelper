import os
import json
import time
import json
import re
import pytest

from rpcshell import SharedLibraryCLI

LLM_ENGINE_LIB = os.environ.get(
    "LLM_ENGINE_LIB", "librpcserver.dylib" if os.name == "posix" else "librpcserver.so"
)
MODEL_DIR = os.environ.get("LLM_MODEL_DIR", "..")
LOCAL_MODEL_DIR = "local_test_llms"
MODEL_LARGE = "openhermes-2.5-mistral-7b.Q4_K_M.gguf"
MODEL_SMALL = "tinyllama-1.1b-1t-openorca.Q4_K_M.gguf"

hermes_sysmsg = "You are a helpful, honest, reliable and smart AI assistant named Hermes doing your best at fulfilling user requests. You are cool and extremely loyal. You answer any user requests to the best of your ability."

COUNT_PROMPT = "count from 1 to 3, output only the numbers"
COUNT_PROMPT_ELI5 = (
    "This is a test. Count from 1 to 3 like a kindergartener, output only the numbers"
)


def debug_json(*args):
    def print_json(formatted_json):
        try:
            from pygments import highlight, lexers, formatters

            # Try to highlight the JSON with pygments
            lexer = lexers.JsonLexer()
            formatter = formatters.TerminalFormatter()
            highlighted_json = highlight(formatted_json, lexer, formatter)
            # Print the highlighted JSON
            print(highlighted_json)
        except ImportError:
            # pygments is not available, print the formatted JSON instead
            print(formatted_json)

    for json_str in args:
        try:
            json_obj = json.loads(json_str) if not (isinstance(json_str, dict) or isinstance(json_str, list)) else json_str 
            formatted_json = json.dumps(json_obj, indent=4)
            print_json(formatted_json)
        except json.JSONDecodeError:
            print(json_str)


def make_llama_engine_inference_params(
    model_path, gpu=False, ctx_size=8192, chat_template=None, flash_attention=False
):
    assert os.path.isfile(model_path)
    ret = {
        "model": model_path,
        "n_gpu_layers": 1000 if gpu else 0,
        "use_mmap": False,
        "ctx_size": ctx_size,
    }

    if flash_attention is not None:
        ret["fa"] = flash_attention

    if chat_template is not None:
        ret["chat_template"] = chat_template

    return ret


def find_model_files(model_dir, local_model_dir, model_large, model_small):
    model_large_path = None
    model_small_path = None

    for dir_path in [model_dir, local_model_dir]:
        for filename in os.listdir(dir_path):
            if filename == model_large:
                model_large_path = os.path.join(dir_path, filename)
            elif filename == model_small:
                model_small_path = os.path.join(dir_path, filename)

    return model_large_path, model_small_path


model_large_path, model_small_path = find_model_files(
    MODEL_DIR, LOCAL_MODEL_DIR, MODEL_LARGE, MODEL_SMALL
)


def format_chatml(messages, add_assistant_preprompt=True):
    ret = ""
    for msg in messages:
        ret += "<|im_start|>{}\n{}<|im_end|>\n".format(msg["role"], msg["content"])
    if add_assistant_preprompt:
        ret += "<|im_start|>assistant\n"
    return ret


def fix_chatml_markup(s):
    s = trim_suffix(s, "<|im_end|>")
    si = s.find("<|im_end|>")
    if si > -1:
        s = s[:si]
    si = s.find("<|im_start|>")
    if si > -1:
        s = s[:si]
    return s


def trim_suffix(src_str, pattern):
    if src_str.endswith(pattern):
        return trim_suffix(src_str[: -len(pattern)], pattern)
    return src_str


def format_chatml_msgs(sysmsg=None, usermsg=None, **kwargs):
    msgs = []
    if sysmsg is not None:
        msgs.append(dict(role="system", content=sysmsg))

    if usermsg is not None:
        msgs.append(dict(role="user", content=usermsg))

    cmd = json.dumps(
        dict(
            prompt=format_chatml(msgs),
            stop=["<|im_end|>"],
            temperature=0,
            seed=1337,
            **kwargs,
        )
    )

    return cmd


def assert_json_matches(json_string, expected_dict):
    json_dict = json.loads(json_string)
    assert {k: json_dict[k] for k in expected_dict} == expected_dict


def assert_is_json_string(obj):
    try:
        json.loads(obj)
    except ValueError:
        pytest.fail(f"Not a valid JSON string: {obj}")


MODELS_TO_TEST = [model_small_path, model_large_path]

MODEL_UNDER_TEST = model_small_path
if os.environ.get("TEST_MODEL", "").lower() == "large":
    MODEL_UNDER_TEST = model_large_path
if os.path.isfile(os.environ.get("TEST_MODEL", "")):
    MODEL_UNDER_TEST = os.environ.get("TEST_MODEL", "")


lib = SharedLibraryCLI(lib_path=LLM_ENGINE_LIB)


def load_model(lib, model, ctx_size=2048, check=True):
    lib.init(json.dumps(make_llama_engine_inference_params(model, ctx_size=ctx_size, gpu=len(os.environ.get("LLAMA_TEST_GPU", "")))))
    if check:
        ret = lib.poll_system_status()
        assert_json_matches(
            ret, {"init_success": 1, "loading_progress": 1.0, "model": model}
        )


def test_load_unload_model():
    print("INIT")

    load_model(lib, MODEL_UNDER_TEST, ctx_size=2048)

    print("DEINIT")

    lib.deinit()
    ret = lib.poll_system_status()
    
    print("poll_system_status:", ret)
    
    assert_json_matches(ret, {"init_success": 0})
    
    print("INIT")    
    load_model(lib, MODEL_UNDER_TEST, ctx_size=2048)
    ret = lib.poll_system_status()
   
    print("poll_system_status:", ret)

    assert_json_matches(ret, {"init_success": 1})

TEST_TOKENIZE_CMD = json.dumps(
    dict(text=format_chatml([dict(role="user", content=COUNT_PROMPT_ELI5)]))
)


def test_tokenize():
    cmd = TEST_TOKENIZE_CMD
    debug_json(cmd)
    response = lib.tokenize(cmd)
    debug_json(response)
    assert_is_json_string(response)
    # response = json.loads(response)
    r = json.loads(response)
    assert isinstance(r["length"], int)
    assert r["success"] is True
    assert isinstance(r["tokens"], list)
    assert all(map(lambda x: isinstance(x, str), r["tokens"]))


def check_simple_completion():
    cmd = format_chatml_msgs(sysmsg=hermes_sysmsg, usermsg=COUNT_PROMPT_ELI5)
    debug_json(cmd)
    response = lib.get_completion(cmd)
    debug_json(response)
    assert_is_json_string(response)
    response = json.loads(response)
    assert "content" in response
    assert re.search(r"1\s+2\s+3|1\s*,\s*2,\s*3", response["content"])


def test_completion():
    check_simple_completion()


def test_streaming_completion():
    cmd = format_chatml_msgs(sysmsg=hermes_sysmsg, usermsg=COUNT_PROMPT_ELI5)
    debug_json(cmd)
    response = lib.async_completion_init(cmd)
    debug_json(response)
    start_time = time.time()
    poll_results = []
    updates = []

    while True:
        resp = lib.async_completion_poll("")
        assert_is_json_string(resp)
        poll_result = json.loads(resp)

        assert "completion_updates" in poll_result
        assert isinstance(poll_result["completion_updates"], list)
        updates += poll_result["completion_updates"]

        poll_results.append(poll_result)
        # debug_json(resp)

        if poll_result.get("finished", False):
            break
        time.sleep(0.1)
        if time.time() - start_time > 10:
            pytest.fail("Timeout waiting for completion")

    for upd in updates:
        assert "content" in upd and isinstance(upd["content"], str)

    last_result = poll_results[-1]
    assert last_result["finished"] is True
    assert last_result["success"] is True

    last = updates[-1]

    assert {
        "content": "",
        "status": 200,
        "stop": True,
        # "stopped_eos": True,
        # "stopped_limit": False,
        # "stopped_word": False,
    }.items() <= last.items()

    output = "".join(map(lambda o: o["content"], updates))
    assert re.search(r"1\s+2\s+3|1\s*,\s*2,\s*3", output)


CANCEL_ON = [5,20]

def wait_for_async_finish(timeout=10):
    t0 = time.time()
    finished = False
    first = False
    while timeout >= time.time()-t0:
        resp = lib.async_completion_poll("")
        assert_is_json_string(resp)
        poll_result = json.loads(resp)
        if not first:
            debug_json(resp)
            first = True
        finished = poll_result.get("finished", False)
        if finished:
            return True
        time.sleep(0.1)
    
    raise Exception("Timeout while waiting for async finish")


def test_streaming_completion_with_late_cancel():
    for cancel_time in CANCEL_ON:
        cmd = format_chatml_msgs(sysmsg=hermes_sysmsg, usermsg=COUNT_PROMPT_ELI5)
        debug_json(cmd)
        response = lib.async_completion_init(cmd)
        debug_json(response)
        
        assert_is_json_string(response)
        response = json.loads(response)
        assert response["success"] is True
 
        start_time = time.time()
        poll_results = []
        updates = []

        while True:
            resp = lib.async_completion_poll("")
            assert_is_json_string(resp)
            poll_result = json.loads(resp)

            assert "completion_updates" in poll_result
            assert isinstance(poll_result["completion_updates"], list)
            updates += poll_result["completion_updates"]

            poll_results.append(poll_result)

            if poll_result.get("finished", False):
                break

            if len(updates) >= cancel_time:
                print("CANCELING!")
                lib.async_completion_cancel("")
                break

            time.sleep(0.1)
            if time.time() - start_time > 10:
                pytest.fail("Timeout waiting for completion")
        
        wait_for_async_finish()

        check_simple_completion()


def test_streaming_completion_with_early_cancel():
    cmd = format_chatml_msgs(sysmsg=hermes_sysmsg, usermsg=COUNT_PROMPT_ELI5)
    debug_json(cmd)
    response = lib.async_completion_init(cmd)
    debug_json(response)

    time.sleep(0.01)

    print("CANCELING!")
    lib.async_completion_cancel("")

    wait_for_async_finish()

    check_simple_completion()

def test_deinit_amidst_of_early_streaming_completion():
    cmd = format_chatml_msgs(sysmsg=hermes_sysmsg, usermsg=COUNT_PROMPT_ELI5)
    debug_json(cmd)
    response = lib.async_completion_init(cmd)
    debug_json(response)

    time.sleep(0.01)

    # while True:
    #     resp = lib.async_completion_poll("")
    #     assert_is_json_string(resp)
    #     poll_result = json.loads(resp)

    #     assert "completion_updates" in poll_result
    #     assert isinstance(poll_result["completion_updates"], list)
    #     if poll_result.get("finished", False):
    #         break

    lib.deinit()

    ret = lib.poll_system_status()
    assert_json_matches(
        ret, {"init_success": 0}
    )

    load_model(lib, MODEL_UNDER_TEST, ctx_size=2048)

    check_simple_completion()

def test_streaming_completion_after_deinit():
    cmd = format_chatml_msgs(sysmsg=hermes_sysmsg, usermsg=COUNT_PROMPT_ELI5)
    debug_json(cmd)
    response = lib.async_completion_init(cmd)
    debug_json(response)
    start_time = time.time()
    poll_results = []
    updates = []

    while True:
        resp = lib.async_completion_poll("")
        assert_is_json_string(resp)
        poll_result = json.loads(resp)

        assert "completion_updates" in poll_result
        assert isinstance(poll_result["completion_updates"], list)
        updates += poll_result["completion_updates"]

        poll_results.append(poll_result)
        # debug_json(resp)

        if poll_result.get("finished", False):
            break
        time.sleep(0.1)
        if time.time() - start_time > 10:
            pytest.fail("Timeout waiting for completion")

    for upd in updates:
        assert "content" in upd and isinstance(upd["content"], str)

    last_result = poll_results[-1]
    assert last_result["finished"] is True
    assert last_result["success"] is True

    last = updates[-1]

    assert {
        "content": "",
        "status": 200,
        "stop": True,
        # "stopped_eos": True,
        # "stopped_limit": False,
        # "stopped_word": False,
    }.items() <= last.items()

    output = "".join(map(lambda o: o["content"], updates))
    assert re.search(r"1\s+2\s+3|1\s*,\s*2,\s*3", output)


def test_deinit_amidst_of_late_streaming_completion():
    deinit_was_called = False
    
    for cancel_time in [3]:
        cmd = format_chatml_msgs(sysmsg=hermes_sysmsg, usermsg=COUNT_PROMPT_ELI5)
        debug_json(cmd)
        response = lib.async_completion_init(cmd)
        debug_json(response)
        
        assert_is_json_string(response)
        response = json.loads(response)
        assert response["success"] is True
 
        start_time = time.time()
        poll_results = []
        updates = []

        while True:
            resp = lib.async_completion_poll("")
            assert_is_json_string(resp)
            poll_result = json.loads(resp)

            assert "completion_updates" in poll_result
            assert isinstance(poll_result["completion_updates"], list)
            updates += poll_result["completion_updates"]

            poll_results.append(poll_result)

            if poll_result.get("finished", False):
                break

            if len(updates) >= cancel_time:
                print("TEST: DEINIT START")
                deinit_was_called = True
                lib.deinit()
                print("TEST: DEINIT DONE")
                break

            time.sleep(0.1)
            if time.time() - start_time > 10:
                pytest.fail("Timeout waiting for completion")
    
    if deinit_was_called:
        print("TEST: POLL")
        ret = lib.poll_system_status()
        assert_json_matches(
            ret, {"init_success": 0}
        )

    load_model(lib, MODEL_UNDER_TEST, ctx_size=2048)

    check_simple_completion()