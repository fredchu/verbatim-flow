import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

from terminology import TERMINOLOGY_RULES, apply_terminology_regex


class TestTerminology:
    def test_rules_exist(self):
        assert len(TERMINOLOGY_RULES) == 20

    def test_basic_replacement(self):
        result = apply_terminology_regex("使用歐拉瑪來跑模型")
        assert result == "使用Ollama來跑模型"

    def test_ignorecase(self):
        result = apply_terminology_regex("用 git hub 管理")
        assert "GitHub" in result

    def test_word_boundary(self):
        result = apply_terminology_regex("上傳到GitHub吧")
        assert result == "上傳到GitHub吧"

    def test_chinese_english_mixed(self):
        result = apply_terminology_regex("用歐拉瑪的work flow跑Chat GPT")
        assert "Ollama" in result
        assert "workflow" in result
        assert "ChatGPT" in result
