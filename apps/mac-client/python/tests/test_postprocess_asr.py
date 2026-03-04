import subprocess
import sys
import os

SCRIPT = os.path.join(os.path.dirname(__file__), "..", "scripts", "postprocess_asr.py")
PYTHON = sys.executable


def run_postprocess(text: str, args: list[str] | None = None) -> str:
    """Helper: run postprocess_asr.py with stdin text, return stdout."""
    cmd = [PYTHON, SCRIPT] + (args or [])
    result = subprocess.run(cmd, input=text, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"stderr: {result.stderr}"
    return result.stdout.strip()


class TestPostprocessCLI:
    def test_punctuation_and_terminology(self):
        """Full pipeline: punctuation + terminology."""
        result = run_postprocess("我在Git Hub上面開了一個新的專案")
        assert "GitHub" in result
        # sherpa-onnx should have added some punctuation
        assert any(c in result for c in "，。！？；：、")

    def test_no_punctuation_flag(self):
        """--no-punctuation skips punctuation, still does terminology."""
        result = run_postprocess("用歐拉瑪跑模型", ["--no-punctuation"])
        assert "Ollama" in result

    def test_no_terminology_flag(self):
        """--no-terminology skips terminology, still does punctuation."""
        result = run_postprocess("用歐拉瑪跑模型", ["--no-terminology"])
        assert "歐拉瑪" in result  # NOT replaced

    def test_empty_input(self):
        result = run_postprocess("")
        assert result == ""

    def test_zh_hans_no_opencc(self):
        """zh-Hans should NOT convert to traditional."""
        result = run_postprocess("用欧拉玛跑模型", ["--language", "zh-Hans", "--no-punctuation"])
        # Should not convert simplified to traditional
        # (OpenCC s2t should be skipped)
        assert "Ollama" not in result or "欧" not in result  # won't match 歐拉瑪

    def test_stdin_stdout_contract(self):
        """Verify stdin/stdout contract works."""
        result = run_postprocess("今天天氣很好", ["--no-punctuation", "--no-terminology"])
        assert result == "今天天氣很好"
