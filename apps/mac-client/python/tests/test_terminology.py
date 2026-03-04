import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

from terminology import TERMINOLOGY_RULES, apply_terminology_regex


class TestTerminology:
    def test_rules_exist(self):
        assert len(TERMINOLOGY_RULES) == 25

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

    def test_quint_38b(self):
        assert apply_terminology_regex("用Quint 38B") == "用Qwen3 8B"
        assert apply_terminology_regex("Quint38B模型") == "Qwen3 8B模型"

    def test_lms_studio(self):
        assert apply_terminology_regex("用LMS Studio跑") == "用LM Studio跑"

    def test_mls_to_mlx(self):
        assert apply_terminology_regex("Qwen3 8B MLS版本") == "Qwen3 8B MLX版本"

    def test_orama(self):
        assert apply_terminology_regex("用Orama跑模型") == "用Ollama跑模型"

    def test_alarm_studio(self):
        assert apply_terminology_regex("用Alarm Studio搭配") == "用LM Studio搭配"
