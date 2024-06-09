import os
import json

init_params_gpu = {
    "model": os.environ["HOME"] + "/projects/AI/Meta-Llama-3-8B-Instruct.i1-Q4_K_M.gguf",
    "n_gpu_layers": 99,
    "use_mmap": False,
    "ctx_size": 8192,
    "fa": True,
    "chat_template": "llama3"
}

init_params_cpu = {
    "model": os.environ["HOME"] + "/projects/AI/Meta-Llama-3-8B-Instruct.i1-Q4_K_M.gguf",
    "n_gpu_layers": 0,
    "use_mmap": False,
    "ctx_size": 8192,
    "fa": True,
    "chat_template": "llama3"
}

lib.init(json.dumps(init_params_cpu))
