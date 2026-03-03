import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import unittest.mock as mock


class TestPunctuationModel:
    def test_add_punctuation_calls_funasr_and_opencc(self):
        """Verify PunctuationModel chains FunASR generate → OpenCC convert."""
        with mock.patch("benchmark_punctuation.AutoModel") as MockAutoModel, \
             mock.patch("benchmark_punctuation.OpenCC") as MockOpenCC:

            mock_model = mock.MagicMock()
            mock_model.generate.return_value = [{"text": "今天天气很好，我们去散步。"}]
            MockAutoModel.return_value = mock_model

            mock_cc = mock.MagicMock()
            mock_cc.convert.return_value = "今天天氣很好，我們去散步。"
            MockOpenCC.return_value = mock_cc

            from benchmark_punctuation import PunctuationModel
            pm = PunctuationModel()
            result = pm.add_punctuation("今天天气很好我们去散步")

            assert result == "今天天氣很好，我們去散步。"
            mock_model.generate.assert_called_once_with(input="今天天气很好我们去散步")
            MockOpenCC.assert_called_once_with("s2t")
            mock_cc.convert.assert_called_once_with("今天天气很好，我们去散步。")

    def test_add_punctuation_raw_returns_without_opencc(self):
        """Verify add_punctuation_raw returns FunASR output without OpenCC."""
        with mock.patch("benchmark_punctuation.AutoModel") as MockAutoModel, \
             mock.patch("benchmark_punctuation.OpenCC"):

            mock_model = mock.MagicMock()
            mock_model.generate.return_value = [{"text": "今天天气很好，我们去散步。"}]
            MockAutoModel.return_value = mock_model

            from benchmark_punctuation import PunctuationModel
            pm = PunctuationModel()
            result = pm.add_punctuation_raw("今天天气很好我们去散步")

            assert result == "今天天气很好，我们去散步。"

    def test_elapsed_time_tracked(self):
        """Verify add_punctuation_timed returns elapsed time."""
        with mock.patch("benchmark_punctuation.AutoModel") as MockAutoModel, \
             mock.patch("benchmark_punctuation.OpenCC") as MockOpenCC:

            mock_model = mock.MagicMock()
            mock_model.generate.return_value = [{"text": "測試。"}]
            MockAutoModel.return_value = mock_model

            mock_cc = mock.MagicMock()
            mock_cc.convert.return_value = "測試。"
            MockOpenCC.return_value = mock_cc

            from benchmark_punctuation import PunctuationModel
            pm = PunctuationModel()
            result, elapsed = pm.add_punctuation_timed("測試")

            assert result == "測試。"
            assert isinstance(elapsed, float)
            assert elapsed >= 0
