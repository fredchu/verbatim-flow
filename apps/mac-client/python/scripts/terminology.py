"""Shared ASR terminology correction rules."""

import re

TERMINOLOGY_RULES = [
    # (pattern, replacement, flags)
    # NOTE: English patterns use re.ASCII so that \b treats only ASCII
    # alphanumerics as word characters, allowing correct matching at
    # Chinese-English boundaries (e.g. "Code的" or "的work").

    # --- 英文術語：\b + IGNORECASE + ASCII ---
    (r'\bGit\s+Hub\b', 'GitHub', re.IGNORECASE | re.ASCII),
    (r'\bOpen\s+AI\b', 'OpenAI', re.IGNORECASE | re.ASCII),
    (r'\bChat\s+GPT\b', 'ChatGPT', re.IGNORECASE | re.ASCII),
    (r'\bOpen\s+CC\b', 'OpenCC', re.IGNORECASE | re.ASCII),
    (r'\bCloud\s+Code\b', 'Claude Code', re.IGNORECASE | re.ASCII),
    (r'\bSuper\s*powers?\b', 'Superpowers', re.IGNORECASE | re.ASCII),
    (r'\bw(?:alk|ork)\s+flow\b', 'workflow', re.IGNORECASE | re.ASCII),
    (r'\bLIM\s+Studio\b', 'LM Studio', re.IGNORECASE | re.ASCII),
    (r'\bEmerald\s+X\b', 'MLX', re.IGNORECASE | re.ASCII),
    (r'\bM2X\b', 'MLX', re.ASCII),
    (r'\bComet\b', 'Commit', re.ASCII),
    (r'\bForced\s+Aligner\b', 'ForcedAligner', re.IGNORECASE | re.ASCII),
    (r'\bOrama\b', 'Ollama', re.IGNORECASE | re.ASCII),
    (r'\bAlarm\s+Studio\b', 'LM Studio', re.IGNORECASE | re.ASCII),

    # ASR 音譯模糊匹配
    (r'\bBri[sc]e\s+ASR\b', 'Breeze ASR', re.IGNORECASE | re.ASCII),
    (r'\bBruce\s+ASR\b', 'Breeze ASR', re.IGNORECASE | re.ASCII),
    (r'\bQu[ai]nt\s*3?\s*8\s*B\b', 'Qwen3 8B', re.IGNORECASE | re.ASCII),
    (r'\bQu[ai]nt\s*3\b', 'Qwen3', re.IGNORECASE | re.ASCII),
    (r'\bLMS\s+Studio\b', 'LM Studio', re.IGNORECASE | re.ASCII),
    (r'\bMLS\b', 'MLX', re.ASCII),
    (r'\bAM2X\b', 'MLX', re.ASCII),

    # --- 中文音譯：無 \b ---
    (r'歐拉瑪', 'Ollama', 0),
    (r'偷坑', 'token', 0),
    (r'[B逼]肉', 'BROLL', 0),
    (r'集聚', '級距', 0),
]

# Pre-sorted by pattern length (longest first) for specificity
_SORTED_RULES = sorted(TERMINOLOGY_RULES, key=lambda r: len(r[0]), reverse=True)


def apply_terminology_regex(text: str) -> str:
    """Apply terminology corrections using regex patterns."""
    for pattern, replacement, flags in _SORTED_RULES:
        text = re.sub(pattern, replacement, text, flags=flags)
    return text
