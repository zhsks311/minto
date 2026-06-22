import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

from stt_output_paths import stt_output_base


class SttOutputPathsTests(unittest.TestCase):
    def test_output_base_default_and_env_override(self):
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop("MINTO2_STT_OUTPUT_ROOT", None)
            self.assertEqual(stt_output_base(), Path("/private/tmp"))

        with patch.dict(os.environ, {"MINTO2_STT_OUTPUT_ROOT": "/custom/path"}):
            self.assertEqual(stt_output_base(), Path("/custom/path"))
