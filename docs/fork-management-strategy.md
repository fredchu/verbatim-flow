# Fork 管理與 Git 工作流策略

> 研究日期：2026-03-04
> 適用對象：獨立開發者維護 macOS app（VerbatimFlow）

---

## 一、Fork 分歧管理：同步 vs. 獨立

Fork 與 upstream 的關係只有兩種健康狀態，**停在中間是最危險的**。

### 繼續同步 upstream

**適用時機：**
- upstream 仍活躍，有你需要的安全更新或功能
- 你的改動集中在特定區域，核心框架仍與 upstream 相同
- 同步的衝突處理時間仍可控

**做法：**
```bash
git remote add upstream <原始 repo URL>
git fetch upstream
git merge upstream/main
```

**注意事項：**
- 分歧會指數成長：每增加一個 schema 變更、新欄位、自定義功能，下次同步都更痛苦
- 降低成本的策略：把改動推回 upstream（即使需要妥協）是避免技術債累積的最佳方式
- 用 atomic commits 隔離不同性質的變更，讓 rebase 時更容易處理衝突

### 宣布獨立（Detach Fork）

**適用時機：**
- 專案目標已與原專案根本不同
- 同步所需的衝突處理時間超過重新實作的成本
- 你已不再需要 upstream 的新功能或更新
- upstream 已不活躍或方向與你完全相反

**做法：**
1. GitHub Settings → Danger Zone → Detach fork
2. 或建立全新 repo，複製現有程式碼過去（獲得乾淨歷史）
3. 在 README 中致謝原專案，說明分歧原因

### 最糟的情況：無意識的分歧

既沒刻意同步，也沒正式宣布獨立。結果是 12-18 個月後發現無法整合上游的安全修復。**應該從一開始就有意識地選擇策略。**

---

## 二、獨立開發者的分支策略比較

### Git Flow

- **結構：** main / develop / feature / release / hotfix
- **複雜度：** 高（多條長命分支）
- **適合：** 大型團隊、需要同時維護多個版本
- **獨立開發者：** 不推薦，過度工程

### GitHub Flow（推薦）

- **結構：** main + 短命 feature branch
- **複雜度：** 低
- **適合：** 小團隊、獨立開發者、持續部署
- **核心原則：** main 永遠是穩定版，所有開發都在短命分支進行

### Trunk-based Development

- **結構：** 幾乎只用 main，直接 commit 或極短命分支
- **複雜度：** 最低
- **適合：** 有完善 CI/CD 的團隊
- **獨立開發者：** 可行但需紀律，缺乏分支隔離

### VerbatimFlow 採用的策略

GitHub Flow 變體，加上 `dev` 整合分支：

| 分支 | 用途 | 生命週期 |
|------|------|----------|
| `main` | production，穩定版 | 永久 |
| `dev` | staging，全功能整合，build 安裝來源 | 永久 |
| `feat/<名稱>` | 功能開發 | 短命（完成即 merge + 刪除） |
| `fix/<名稱>` | bug 修正 | 短命（完成即 merge + 刪除） |

**Feature branch 工作流：**
1. 從 `main` 開 feature branch
2. 開發完成後送 PR 到 `main`
3. merge 到 `main` 後，`git checkout dev && git merge main` 同步
4. 需要提前測試整合效果時，可先 merge 到 `dev` build 驗證

---

## 三、Rebase vs. Merge 慣例

### 黃金法則

| 場景 | 建議 | 原因 |
|------|------|------|
| Feature branch 送 PR 前 | `git rebase -i main` | 整理 commit 歷史，合併瑣碎修改 |
| Feature → `dev` 整合 | **merge** | 保留來源分支資訊，方便追溯 |
| `dev` 跟上 `main` | **merge**（`git merge main`） | 長命分支不 rebase，避免改寫 merge commits |
| `git pull` 從 remote 更新 | `git pull --rebase` | 避免無意義的 merge commit |
| 已 push 到 remote 的分支 | **不要 rebase** | 會改寫歷史，影響協作者 |
| GitHub PR merge 按鈕 | 選 "Rebase and merge" | 避免多餘 merge commit |

### 實用技巧

```bash
# 標記要修正的 commit，rebase 時自動合併
git commit --fixup <hash>
git rebase --autosquash -i main

# PR 前整理 commit
git rebase -i main

# 設定 pull 預設用 rebase
git config pull.rebase true
```

---

## 四、分支管理最佳實踐

### 核心原則

1. **一個分支只做一件事** — 每個分支應完成一個具體、可描述的目標
2. **每個 commit 應獨立可測試** — 不要在多個 commit 中反覆修改同一段程式碼
3. **分支名稱要有描述性** — 幫助重新聚焦正在做什麼
4. **短命分支優先** — 完成就 merge + 刪除，避免長期維護負擔
5. **可以丟棄不需要的 commit** — 不用覺得浪費

### `dev` 整合分支的維護

- 每次 `main` 合併 PR 後，同步 `main` → `dev`：`git checkout dev && git merge main`
- Feature branch 合併到 `dev` 時用 merge（不用 rebase）
- `dev` 只用於本地 build 測試和全功能驗證，不直接在上面開發
- 如果 `dev` 與 `main` 差距過大，考慮從 `main` 重建 `dev` 再逐一 merge feature branches

### 安裝到 /Applications 的流程

```bash
git checkout dev
git merge main              # 先同步 main 最新狀態
git merge feat/xxx          # 合併要測試的 feature branch
./scripts/build-native-app.sh
rm -rf /Applications/VerbatimFlow.app
cp -R apps/mac-client/dist/VerbatimFlow.app /Applications/
```

---

## 五、參考資料

- [Lessons learned from maintaining a fork - DEV Community](https://dev.to/bengreenberg/lessons-learned-from-maintaining-a-fork-48i8)
- [The Dynamic Relationship of Forks with their Upstream Repository - rOpenSci (2025)](https://ropensci.org/blog/2025/02/20/forks-upstream-relationship/)
- [Git is my buddy: Effective Git as a solo developer - Mikkel Paulson](https://mikkel.ca/blog/git-is-my-buddy-effective-solo-developer/)
- [Choosing the Right Git Strategy in 2025 - Muhammad Abdullah](https://abdullah.ranktriz.com/blog/29)
- [Stop Forking Around: Hidden Dangers of Fork Drift - Preset](https://preset.io/blog/stop-forking-around-the-hidden-dangers-of-fork-drift-in-open-source-adoption/)
- [Merging vs. Rebasing - Atlassian Git Tutorial](https://www.atlassian.com/git/tutorials/merging-vs-rebasing)
- [Disassociate a fork from upstream - GitHub Community](https://github.com/orgs/community/discussions/45251)
