import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from benchmark_llm import score_terminology, score_preservation, score_punctuation

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
