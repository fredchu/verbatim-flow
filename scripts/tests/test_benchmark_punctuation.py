import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import unittest.mock as mock


class TestPunctuationModel:
    def test_add_punctuation_calls_sherpa_and_opencc(self):
        """Verify PunctuationModel chains sherpa-onnx → OpenCC convert."""
        with mock.patch("benchmark_punctuation._ensure_model", return_value="/fake/model.onnx"), \
             mock.patch("benchmark_punctuation.sherpa_onnx") as MockSherpa, \
             mock.patch("benchmark_punctuation.OpenCC") as MockOpenCC:

            mock_punct = mock.MagicMock()
            mock_punct.add_punctuation.return_value = "今天天气很好，我们去散步。"
            MockSherpa.OfflinePunctuation.return_value = mock_punct

            mock_cc = mock.MagicMock()
            mock_cc.convert.return_value = "今天天氣很好，我們去散步。"
            MockOpenCC.return_value = mock_cc

            from benchmark_punctuation import PunctuationModel
            pm = PunctuationModel()
            result = pm.add_punctuation("今天天气很好我们去散步")

            assert result == "今天天氣很好，我們去散步。"
            mock_punct.add_punctuation.assert_called_once_with("今天天气很好我们去散步")
            MockOpenCC.assert_called_once_with("s2t")
            mock_cc.convert.assert_called_once_with("今天天气很好，我们去散步。")

    def test_add_punctuation_raw_returns_without_opencc(self):
        """Verify add_punctuation_raw returns sherpa-onnx output without OpenCC."""
        with mock.patch("benchmark_punctuation._ensure_model", return_value="/fake/model.onnx"), \
             mock.patch("benchmark_punctuation.sherpa_onnx") as MockSherpa, \
             mock.patch("benchmark_punctuation.OpenCC"):

            mock_punct = mock.MagicMock()
            mock_punct.add_punctuation.return_value = "今天天气很好，我们去散步。"
            MockSherpa.OfflinePunctuation.return_value = mock_punct

            from benchmark_punctuation import PunctuationModel
            pm = PunctuationModel()
            result = pm.add_punctuation_raw("今天天气很好我们去散步")

            assert result == "今天天气很好，我们去散步。"

    def test_elapsed_time_tracked(self):
        """Verify add_punctuation_timed returns elapsed time."""
        with mock.patch("benchmark_punctuation._ensure_model", return_value="/fake/model.onnx"), \
             mock.patch("benchmark_punctuation.sherpa_onnx") as MockSherpa, \
             mock.patch("benchmark_punctuation.OpenCC") as MockOpenCC:

            mock_punct = mock.MagicMock()
            mock_punct.add_punctuation.return_value = "測試。"
            MockSherpa.OfflinePunctuation.return_value = mock_punct

            mock_cc = mock.MagicMock()
            mock_cc.convert.return_value = "測試。"
            MockOpenCC.return_value = mock_cc

            from benchmark_punctuation import PunctuationModel
            pm = PunctuationModel()
            result, elapsed = pm.add_punctuation_timed("測試")

            assert result == "測試。"
            assert isinstance(elapsed, float)
            assert elapsed >= 0

    def test_ensure_model_called_on_init(self):
        """Verify _ensure_model is called during initialization."""
        with mock.patch("benchmark_punctuation._ensure_model", return_value="/fake/model.onnx") as mock_ensure, \
             mock.patch("benchmark_punctuation.sherpa_onnx"), \
             mock.patch("benchmark_punctuation.OpenCC"):

            from benchmark_punctuation import PunctuationModel
            PunctuationModel()

            mock_ensure.assert_called_once()
