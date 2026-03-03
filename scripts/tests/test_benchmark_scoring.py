import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from benchmark_llm import score_terminology, score_preservation, score_punctuation, call_llm, generate_report, PROMPTS, DEFAULT_PROMPT

class TestTerminologyScoring:
    def test_all_correct(self):
        output = "使用 Ollama 的 Qwen3 8B 搭配 Breeze ASR"
        corrections = ["Ollama", "Qwen3 8B", "Breeze ASR"]
        assert score_terminology(output, corrections) == 100.0

    def test_partial(self):
        output = "使用 Ollama 的 Quant 38B 搭配 Brice ASR"
        corrections = ["Ollama", "Qwen3 8B", "Breeze ASR"]
        result = score_terminology(output, corrections)
        assert abs(result - 33.33) < 1

    def test_none_correct(self):
        output = "使用歐拉瑪的 Quant 38B 搭配 Brice ASR"
        corrections = ["Ollama", "Qwen3 8B", "Breeze ASR"]
        assert score_terminology(output, corrections) == 0.0

    def test_empty_corrections(self):
        output = "今天天氣很好"
        corrections = []
        assert score_terminology(output, corrections) == 100.0

class TestPreservationScoring:
    def test_no_extra_edits(self):
        input_text = "今天天氣很好我們去散步"
        output_text = "今天天氣很好，我們去散步。"
        terminology = []
        score = score_preservation(input_text, output_text, terminology)
        assert score == 100.0

    def test_heavy_rewrite(self):
        input_text = "今天天氣很好我們去散步"
        output_text = "今日天候良好，吾等前往散步。"
        terminology = []
        score = score_preservation(input_text, output_text, terminology)
        assert score <= 60

    def test_terminology_replacement_not_penalized(self):
        input_text = "使用歐拉瑪來跑模型"
        output_text = "使用 Ollama 來跑模型。"
        terminology = ["歐拉瑪→Ollama"]
        score = score_preservation(input_text, output_text, terminology)
        assert score >= 90

class TestPunctuationScoring:
    def test_perfect_punctuation(self):
        expected = "今天天氣很好，我們去散步。"
        output = "今天天氣很好，我們去散步。"
        p, r, f1 = score_punctuation(expected, output)
        assert f1 == 100.0

    def test_missing_punctuation(self):
        expected = "今天天氣很好，我們去散步。"
        output = "今天天氣很好我們去散步。"
        p, r, f1 = score_punctuation(expected, output)
        assert r < 100
        assert f1 < 100

    def test_no_punctuation_in_output(self):
        expected = "今天天氣很好，我們去散步。"
        output = "今天天氣很好我們去散步"
        p, r, f1 = score_punctuation(expected, output)
        assert f1 < 50

class TestCallLLM:
    def test_request_format(self):
        """Verify the request payload structure (mock test)."""
        import unittest.mock as mock

        fake_response = mock.MagicMock()
        fake_response.json.return_value = {
            "choices": [{"message": {"content": "測試結果。"}}],
            "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15},
        }
        fake_response.raise_for_status = mock.MagicMock()

        with mock.patch("benchmark_llm.requests.post", return_value=fake_response) as mock_post:
            result = call_llm("測試輸入", model="qwen3-8b", base_url="http://localhost:1234")
            assert result["content"] == "測試結果。"
            assert result["usage"]["total_tokens"] == 15

            call_args = mock_post.call_args
            payload = call_args[1]["json"]
            assert payload["model"] == "qwen3-8b"
            assert payload["messages"][0]["role"] == "system"
            assert payload["messages"][0]["content"] == PROMPTS[DEFAULT_PROMPT]
            assert payload["messages"][1]["role"] == "user"
            assert payload["messages"][1]["content"] == "測試輸入"
            assert payload["temperature"] == 0

    def test_prompt_key_selection(self):
        """Verify different prompt keys use different system prompts."""
        import unittest.mock as mock

        fake_response = mock.MagicMock()
        fake_response.json.return_value = {
            "choices": [{"message": {"content": "結果"}}],
            "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15},
        }
        fake_response.raise_for_status = mock.MagicMock()

        with mock.patch("benchmark_llm.requests.post", return_value=fake_response) as mock_post:
            call_llm("輸入", model="test", prompt_key="v2-fewshot")
            payload = mock_post.call_args[1]["json"]
            assert payload["messages"][0]["content"] == PROMPTS["v2-fewshot"]

    def test_v4_json_extraction(self):
        """Verify v4-json prompt extracts output from JSON response."""
        import unittest.mock as mock

        fake_response = mock.MagicMock()
        fake_response.json.return_value = {
            "choices": [{"message": {"content": '{"output": "校正後文字。"}'}}],
            "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15},
        }
        fake_response.raise_for_status = mock.MagicMock()

        with mock.patch("benchmark_llm.requests.post", return_value=fake_response):
            result = call_llm("輸入", model="test", prompt_key="v4-json")
            assert result["content"] == "校正後文字。"


class TestReportGeneration:
    def test_generates_markdown(self):
        results = {
            "models": {
                "qwen3-8b-8bit": {
                    "cases": [
                        {
                            "id": "t01",
                            "input": "歐拉瑪",
                            "expected": "Ollama。",
                            "output": "Ollama。",
                            "terminology_score": 100.0,
                            "preservation_score": 100.0,
                            "punctuation_f1": 100.0,
                            "weighted_score": 100.0,
                            "tokens_per_sec": 30.0,
                            "terminology_detail": [("Ollama", True)],
                        }
                    ],
                    "avg_terminology": 100.0,
                    "avg_preservation": 100.0,
                    "avg_punctuation_f1": 100.0,
                    "avg_weighted": 100.0,
                    "avg_tokens_per_sec": 30.0,
                }
            }
        }
        report = generate_report(results)
        assert "# LLM ASR Post-Processing Benchmark" in report
        assert "qwen3-8b-8bit" in report
        assert "100.0" in report
