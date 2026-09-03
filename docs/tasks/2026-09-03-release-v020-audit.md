# v0.2.0 發佈：稽核擋下的三類問題

狀態：已完成
強度：L2
日期：2026-09-03

⚠️ **這份計畫檔是事後補的。** 動手當下沒有先建（走 `/release` 進來，判斷成「跑一次
既有流程」而不是「一個 L2 任務」），實際做完才發現跨 8 個檔案又動到規則，符合 L2 的
判準。補這份是為了讓索引表看得到這件事——**不是**假裝當時有計畫。下面的「驗收」與
「假設」是回頭整理的，不是事前寫的，讀的時候要知道這個差別。

## 目標

發佈 `v0.2.0`（sandbox 內經過濾 proxy 使用 docker）。`release` skill 的稽核步驟
（§3 引用審計、§5 洩漏面掃描、§6 CHANGELOG）在發佈前擋下三類問題，先修完才發佈。

## 範圍

**包含**：`release/release.sh` 的產品檔清單與守衛、出貨檔裡的上游內部編號、
`CHANGELOG.md` 的 v0.2.0 區塊、`release` skill §3 的稽核指令範圍、`docs/KNOWN-ISSUES.md`。

**不包含**：

- `scripts/docker-api-proxy.py` 的功能本身（那是 `2026-09-02-sandbox-docker-access.md`）
- Linux host 上的驗證——沒有那個環境
- `docker-api-proxy.py` 裡幾處寫著實測日期的 rationale 註解。第二角度複讀判定
  它描述的是這支腳本自己的設計約束、載體正確，保留

## 三類問題

### ① 產品檔清單漏掉 v0.2.0 的主要交付（會直接壞掉）

`Dockerfile.proxy` 與 `docker-compose.claude.docker.yml` 不在 `release/release.sh`
的 `PROD` 白名單裡。照原樣發佈的話，`main` 上的 `sandbox.sh` 會**預設**帶
`-f docker-compose.claude.docker.yml`，而那個檔案不存在——套用端一啟動就壞。

發佈當下沒有任何症狀：守衛 1 只驗「匹配數 > 0」（舊清單照樣匹配到十幾個檔案），
守衛 2／3 只看 `docs/`。**白名單天生驗不了「該列而沒列的東西」**。→ `K-9`

### ② 出貨的檔案引用上游內部編號（死連結）

出貨的 `docs/DECISIONS.md`／`KNOWN-ISSUES.md` 是空骨架、套用端從 `D1`／`K-1`
重編，所以出貨檔裡的 `D12`、`K-5` 在套用端指向不存在或意思不同的條目
（`record` skill §6 規則 6）。命中五處，其中兩處在**程式碼註解**裡。

漏掉的原因是稽核指令本身：`release` skill §3 的 grep 只列 `.md` 那幾份，沒有
`sandbox.sh`、`scripts/`、`Dockerfile.*`。**稽核範圍比出貨範圍窄，而且窄得沒有症狀。**
是**第二角度複讀**（另一個 agent 全文讀出貨檔）抓到的，不是 grep。→ `K-9` 判準③

### ③ `CHANGELOG.md` v0.2.0 缺「已知未驗」

那一節是任務檔「不包含／未查證」在出貨端唯一的載體（`release` skill §6）。
同時漏了 `CLAUDE.md` 鐵則第 9 條——那是套用端要重讀的規範變更。

## 變更清單

| ID | 檔案 | 變更性質 |
|---|---|---|
| C1 | `release/release.sh` | 兩個檔案加進 `PROD`；新增守衛 0（`dev` 頂層覆蓋率斷言） |
| C2 | `.claude/skills/release/SKILL.md` | §8 陷阱表補一列；§0「三道守衛」→ 四道 |
| C3 | `docs/KNOWN-ISSUES.md` | 新增 `K-9` |
| C4 | `README.md`／`CHANGELOG.md`／`check_known_issues_links.py` | `D12`／`D7` 改寫成形態描述 |
| C5 | `sandbox.sh`／`scripts/entrypoint.sh` | 註解裡的 `(K-5)` 拿掉，判準敘述保留 |
| C6 | `.claude/skills/release/SKILL.md` §3 | grep 範圍補齊產品檔；補「換工具前先做陽性對照」 |
| C7 | `CHANGELOG.md` | v0.2.0 補鐵則第 9 條與「已知未驗」；「未在 Linux host 驗」抽成檔尾固定小節 |
| C8 | `docs/KNOWN-ISSUES.md` | `K-9` 補判準③（同一形態發生在稽核指令上） |

## 驗證步驟

- [x] **守衛 0 轉紅過**：把 `Dockerfile.proxy` 從 `PROD` 拿掉 → `✗ dev 頂層有沒歸類的
      條目：Dockerfile.proxy`，exit 1；放回去 → `✓`，exit 0
- [x] **完整演練**：clone 到暫存目錄、把 `dev` 指到工作分支後跑 `release/release.sh v0.2.0`
      → 四道守衛全綠、匹配 31 檔、發佈樹 34 個檔案、`docs/` 只有三份骨架、
      `release/` 不存在、`sandbox.sh` 引用的五個 compose／Dockerfile 全部到位
- [x] 漂移檢查 `git diff --stat release/v0.2.0 dev -- "${PROD[@]}"` 輸出為空
      （先確認 pathspec 匹配數 = 31，不是「沒比到東西」）
- [x] `bash -n sandbox.sh`／`bash -n scripts/entrypoint.sh`；`python3 -m unittest`（record
      skill 腳本）→ OK；結構檢查腳本通過（`K-9` 少填 `守備` 時它有報錯，補上才過）
- [x] **產物端驗收（§9）**：`gh repo create --template` 生一份 private repo，
      `git log` 只有 `Initial commit`、無 tag、無 `dev` 分支；在那個目錄跑
      `claude -p` 要求不讀檔直接作答，它答出禁令第 1／6 條並列出七個專案 skill
      （**skill 真的載得到**，不是只確認檔案在）；`CHANGELOG.md` 檔尾的
      `git clone -b dev ...` 解析到真實的 `dev` HEAD，上游 repo 是 PUBLIC

## 問題紀錄

| 日期 | 問題 | 根因 | 處理 | 已升級到 KNOWN-ISSUES？ |
|---|---|---|---|---|
| 2026-09-03 | 產品檔白名單漏掉新檔案，所有守衛全綠 | 白名單只驗列出來的，驗不了漏掉的 | 守衛 0：來源側全集覆蓋率斷言 | **是 → K-9** |
| 2026-09-03 | §3 的稽核 grep 掃不到 `.sh` 註解裡的 `K-5` | 稽核範圍比出貨範圍窄 | §3 範圍補齊產品檔 | **是 → K-9 判準③** |
| 2026-09-03 | 在演練樹上 `git grep -E "\bK-[0-9]+\b"` 回零命中 | `git grep -E` 不吃 `\b`，連 fixture 裡的 `K-99` 都掃不到 | 改用 `grep -rnE`，並做陽性對照；§3 補上警告 | 否——判準已寫進 `release` skill §3 |

## 回退方式

`release/release.sh` 的守衛 0 可單獨 revert（C1）。已發佈的 `v0.2.0` tag 不動——
要撤的話是發 `v0.2.1`，不是移動 tag。

## 完成紀錄

| 日期 | 項目 | 去向 | 驗證結果 |
|---|---|---|---|
| 2026-09-03 | C1-C8 | PR [#22](https://github.com/Bright0505/claude-code-sandbox/pull/22) → `dev` (`2944388`) | 見上方驗證步驟 |
| 2026-09-03 | 發佈 | PR [#23](https://github.com/Bright0505/claude-code-sandbox/pull/23) → `main` (`b6623a0`)，tag `v0.2.0` | 產物端驗收四項全過 |

## 交付狀態

- `main` = `v0.2.0` = `b6623a0`，`main` 的歷史是一版一個 commit（`v0.1.0` → `v0.1.1` → `v0.2.0`）
- 發佈分支 `release/v0.2.0` 已在 tag 推上去**之後**刪除（遠端＋本機）
- 產物端試用 repo `cc-sandbox-v020-probe` 已刪除。第一次刪失敗——`gh` 的 token 沒有
  `delete_repo` scope（`HTTP 403`），使用者跑過 `gh auth refresh -h github.com -s delete_repo`
  （互動式，只能由使用者自己跑）之後才刪掉。
  **下次做 §9 驗收前先確認這個 scope**，否則會卡在最後一步
- **沒有在 Linux host 上驗過任何東西**（這條已抽進 `CHANGELOG.md` 檔尾的固定小節）
