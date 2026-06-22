import os
from pathlib import Path


def stt_output_base():
    return Path(os.environ.get("MINTO2_STT_OUTPUT_ROOT", "/private/tmp"))
