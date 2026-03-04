# 術語替換改進方向：Regex 設計 + 自動學習

> Date: 2026-03-04
> Status: 討論紀錄，尚未實作
> 前置：兩層管線已驗證（bert+regex 加權 87.2），術語替換目前用 `str.replace`

## 問題一：Regex 設計粗糙

### 現狀

目前 `apply_terminology_regex()` 用 `str.replace()`，不是真正的 regex。

```python
# 現在的做法
for wrong, correct in pairs:
    result = result.replace(wrong, correct)
```

### 具體問題

| 問題 | 說明 | 例子 |
|------|------|------|
| 無 word boundary | 可能匹配子串 | `Git` 可能匹配 `GitHub` 內部（目前碰巧沒衝突但很脆弱） |
| 上下文盲目 | 無法區分同形異義 | `Cloud Code → Claude Code` 會把真正的 "Cloud Code 雲端服務" 也改掉 |
| 無法處理變體 | 每個變體都要列一條 | `Super power` / `Super powers` / `Superpower` 需三條規則 |
| 無大小寫容錯 | 大小寫不同要分開列 | `git hub` vs `Git Hub` vs `GIT HUB` |

### 改進方案

用真正的 `re.sub` + word boundary + flags：

```python
TERMINOLOGY_RULES = [
    # (pattern, replacement, flags)

    # 英文術語：\b word boundary + IGNORECASE
    (r'\bGit\s+Hub\b', 'GitHub', re.IGNORECASE),
    (r'\bOpen\s+AI\b', 'OpenAI', re.IGNORECASE),
    (r'\bChat\s+GPT\b', 'ChatGPT', re.IGNORECASE),
    (r'\bCloud\s+Code\b', 'Claude Code', re.IGNORECASE),
    (r'\bSuper\s*powers?\b', 'Superpowers', re.IGNORECASE),
    (r'\b[Ww](?:alk|ork)\s+flow\b', 'workflow', 0),
    (r'\bLIM\s+Studio\b', 'LM Studio', re.IGNORECASE),
    (r'\bEmerald\s+X\b', 'MLX', re.IGNORECASE),
    (r'\bM2X\b', 'MLX', 0),

    # 中文音譯：無 word boundary，但中文字本身就是自然邊界
    (r'歐拉瑪', 'Ollama', 0),
    (r'偷坑', 'token', 0),
    (r'[B逼]肉', 'BROLL', 0),       # B肉 / 逼肉 合併為一條
    (r'集聚', '級距', 0),

    # ASR 音譯模糊匹配：允許多種拼寫
    (r'Bri[sc]e\s+ASR', 'Breeze ASR', re.IGNORECASE),
    (r'Bruce\s+ASR', 'Breeze ASR', re.IGNORECASE),
    (r'Qu[ai]nt\s*3', 'Qwen3', re.IGNORECASE),
]

def apply_terminology(text: str) -> str:
    sorted_rules = sorted(TERMINOLOGY_RULES, key=lambda r: len(r[0]), reverse=True)
    for pattern, replacement, flags in sorted_rules:
        text = re.sub(pattern, replacement, text, flags=flags)
    return text
```

### 關鍵改進總結

| 改進 | 原本 | 改進後 |
|------|------|--------|
| 英文邊界 | `str.replace("Git Hub", "GitHub")` | `re.sub(r'\bGit\s+Hub\b', 'GitHub')` |
| 大小寫 | 每個變體列一條 | `re.IGNORECASE` 一條搞定 |
| 空格容錯 | 固定空格 | `\s+` 或 `\s*` 允許多個空格 |
| 變體合併 | `Super power` + `Super powers` 兩條 | `Super\s*powers?` 一條 |
| 模糊音譯 | `Brise` + `Bruce` + `Brice` 三條 | `Bri[sc]e` + `Bruce` 兩條 |
| 中文同音 | `B肉` + `逼肉` 兩條 | `[B逼]肉` 一條 |

### 注意事項

- 改了 regex 規則後需要重跑 benchmark 驗證
- 中文沒有 word boundary（`\b` 對中文無效），但中文字本身就是自然邊界，子串誤匹配的風險較低
- 按 pattern 長度降序排列仍然重要

---

## 問題二：術語表無自動學習機制

### 現狀

21 條規則全部手動維護。新術語需開發者加入程式碼，一般使用者無法自訂。

### 方向 A：使用者校正追蹤（推薦先做）

使用者手動修改 ASR 輸出後，diff 原文和修正版，自動提取 mapping：

```
原文：我用歐拉瑪跑模型
修正：我用 Ollama 跑模型
→ 自動提取：歐拉瑪 → Ollama
→ 出現 N 次後（如 3 次）自動加入字典
```

實作要點：
- 需要 UI 支援「校正」操作（或偵測使用者在文字欄位的手動編輯）
- 存儲格式：JSON 檔，per-user，記錄 `{wrong: str, correct: str, count: int, last_seen: date}`
- 閾值：出現 N 次後自動啟用，避免單次誤操作污染字典
- 優點：100% 精確，每個使用者的領域術語都能學到
- 缺點：冷啟動問題（使用者要先手動校正幾次）

### 方向 B：拼音相似度比對

ASR 音譯錯誤的本質是發音相似但文字不同。用 `pypinyin` 做拼音比對：

```
"歐拉瑪" → pinyin: "ōu lā mǎ" ≈ "Ollama" 的發音
"偷坑"   → pinyin: "tōu kēng" ≈ "token" 的發音
```

實作要點：
- 需要「正確術語表」作為目標（如使用者提供的專有名詞列表）
- 用拼音距離比對 ASR 輸出中的中文段落
- 超過相似度閾值 → 建議替換
- 優點：不需要使用者手動校正
- 缺點：需要正確術語表；拼音匹配有 false positive；中英混合詞難處理

### 方向 C：混合方案（長期推薦）

1. **內建基礎術語表** — 常見科技/AI 術語，開箱即用（現有 21 條）
2. **使用者校正追蹤**（方向 A）— 自動學習個人化術語
3. **設定檔導入/匯出** — 讓使用者 import/export 術語表，社群共享特定領域的術語包

這樣冷啟動有內建表，日常使用越用越準，社群可以分享。

### 優先順序建議

1. 先改 regex 設計（獨立小任務，不影響其他功能）
2. 再做使用者校正追蹤（需要 UI 配合，但價值最高）
3. 拼音比對作為長期研究方向

---

## 與其他待辦的關係

- **Regex 改進**可以獨立做，改完重跑 benchmark 即可
- **自動學習**需要跟 production 整合一起規劃（涉及 UI、存儲、app bundle）
- 兩者都不依賴分支整理，但建議先整理分支再開新功能
