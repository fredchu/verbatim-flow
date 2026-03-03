import json
import unittest
from unittest.mock import patch, MagicMock
from verbatim_flow.mlx_whisper_transcriber import (
    _resolve_language, _contains_cjk, _convert_s2t, _model_cache_path,
    _is_native_traditional, _add_punctuation,
)


class TestResolveLanguage(unittest.TestCase):
    def test_zh_hant(self):
        self.assertEqual(_resolve_language("zh-Hant"), ("zh", True))

    def test_zh_hans(self):
        self.assertEqual(_resolve_language("zh-Hans"), ("zh", False))

    def test_zh_bare(self):
        self.assertEqual(_resolve_language("zh"), ("zh", True))

    def test_en(self):
        self.assertEqual(_resolve_language("en"), ("en", False))

    def test_en_us(self):
        self.assertEqual(_resolve_language("en-US"), ("en", False))

    def test_none(self):
        self.assertEqual(_resolve_language(None), (None, None))

    def test_ja(self):
        self.assertEqual(_resolve_language("ja"), ("ja", False))

    def test_unknown_language(self):
        self.assertEqual(_resolve_language("xx"), (None, False))


class TestContainsCjk(unittest.TestCase):
    def test_chinese_text(self):
        self.assertTrue(_contains_cjk("你好世界"))

    def test_english_text(self):
        self.assertFalse(_contains_cjk("hello world"))

    def test_mixed(self):
        self.assertTrue(_contains_cjk("hello 你好"))


class TestConvertS2T(unittest.TestCase):
    def test_simplified_to_traditional(self):
        result = _convert_s2t("简体中文")
        self.assertEqual(result, "簡體中文")

    def test_english_unchanged(self):
        self.assertEqual(_convert_s2t("hello"), "hello")


class TestModelCachePath(unittest.TestCase):
    def test_cache_path_format(self):
        path = _model_cache_path("mlx-community/whisper-large-v3-mlx")
        self.assertEqual(path.name, "models--mlx-community--whisper-large-v3-mlx")
        self.assertTrue(str(path).endswith(
            "huggingface/hub/models--mlx-community--whisper-large-v3-mlx"
        ))


class TestIsNativeTraditional(unittest.TestCase):
    def test_breeze_mlx(self):
        self.assertTrue(_is_native_traditional("eoleedi/Breeze-ASR-25-mlx"))

    def test_breeze_pytorch(self):
        self.assertTrue(_is_native_traditional("MediaTek-Research/Breeze-ASR-25"))

    def test_whisper_large_v3(self):
        self.assertFalse(_is_native_traditional("mlx-community/whisper-large-v3-mlx"))

    def test_empty_string(self):
        self.assertFalse(_is_native_traditional(""))


class TestAddPunctuation(unittest.TestCase):
    @patch("verbatim_flow.mlx_whisper_transcriber.urllib.request.urlopen")
    def test_returns_punctuated_text(self, mock_urlopen):
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps({
            "choices": [{"message": {"content": "好，所以我們繼續。"}}]
        }).encode()
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_resp

        result = _add_punctuation("好所以我們繼續")
        self.assertEqual(result, "好，所以我們繼續。")

    @patch("verbatim_flow.mlx_whisper_transcriber.urllib.request.urlopen")
    def test_fallback_on_error(self, mock_urlopen):
        mock_urlopen.side_effect = Exception("connection refused")

        result = _add_punctuation("好所以我們繼續")
        self.assertEqual(result, "好所以我們繼續")

    @patch("verbatim_flow.mlx_whisper_transcriber.urllib.request.urlopen")
    def test_sends_correct_payload(self, mock_urlopen):
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps({
            "choices": [{"message": {"content": "測試。"}}]
        }).encode()
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_resp

        _add_punctuation("測試")

        call_args = mock_urlopen.call_args
        req = call_args[0][0]
        self.assertEqual(req.full_url, "http://localhost:1234/v1/chat/completions")
        payload = json.loads(req.data)
        self.assertEqual(payload["model"], "qwen/qwen3-vl-8b")
        self.assertEqual(payload["stream"], False)
        self.assertEqual(payload["temperature"], 0.1)
        self.assertEqual(payload["max_tokens"], 2048)
        self.assertEqual(payload["messages"][1]["content"], "測試")
        self.assertIn("/no_think", payload["messages"][0]["content"])

    @patch.dict("os.environ", {
        "VERBATIMFLOW_LLM_BASE_URL": "http://myhost:9999",
        "VERBATIMFLOW_LLM_MODEL": "llama3:latest",
    })
    @patch("verbatim_flow.mlx_whisper_transcriber.urllib.request.urlopen")
    def test_respects_env_vars(self, mock_urlopen):
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps({
            "choices": [{"message": {"content": "結果。"}}]
        }).encode()
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_resp

        _add_punctuation("結果")

        req = mock_urlopen.call_args[0][0]
        self.assertEqual(req.full_url, "http://myhost:9999/v1/chat/completions")
        payload = json.loads(req.data)
        self.assertEqual(payload["model"], "llama3:latest")

    @patch("verbatim_flow.mlx_whisper_transcriber.urllib.request.urlopen")
    def test_empty_text_returned_as_is(self, mock_urlopen):
        result = _add_punctuation("")
        self.assertEqual(result, "")
        mock_urlopen.assert_not_called()

    @patch("verbatim_flow.mlx_whisper_transcriber.urllib.request.urlopen")
    def test_strips_think_tags_from_response(self, mock_urlopen):
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps({
            "choices": [{"message": {"content": "<think>思考中...</think>好，所以我們繼續。"}}]
        }).encode()
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_resp

        result = _add_punctuation("好所以我們繼續")
        self.assertEqual(result, "好，所以我們繼續。")

    @patch("verbatim_flow.mlx_whisper_transcriber.urllib.request.urlopen")
    def test_custom_prompt_from_env(self, mock_urlopen):
        """VERBATIMFLOW_LLM_PROMPT env var should override the default system prompt."""
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps({
            "choices": [{"message": {"content": "自訂結果"}}]
        }).encode()
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_resp

        custom_prompt = "你是測試用的自訂提示詞。/no_think"
        with patch.dict("os.environ", {"VERBATIMFLOW_LLM_PROMPT": custom_prompt}):
            _add_punctuation("測試文字")

        call_data = json.loads(mock_urlopen.call_args[0][0].data)
        self.assertEqual(call_data["messages"][0]["content"], custom_prompt)
