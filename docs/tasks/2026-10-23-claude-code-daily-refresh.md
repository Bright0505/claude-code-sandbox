# Claude Code 版本被 build 快取凍住：sandbox.sh 每天刷新那一層

狀態：已完成，已發佈為 v0.2.4
強度：L2
日期：2026-10-23

## 目標
sandbox 裡的 Claude Code 不再停在第一次 build 時的版本，且不讓每次啟動多付整個 image 重建的代價。

## 範圍
包含：`Dockerfile.claude` 的 Claude Code 安裝層、`sandbox.sh` 啟動前的 build、`README.md` 的說明。
不包含：釘版號、容器內自動更新、`Dockerfile.proxy`、`CHANGELOG.md`（留給發佈時補）。

## 現象（baseline）
- image `claude-code-sandbox:latest` 建於 2026-09-02，裡面 `claude --version` = `2.1.258`；
  當時 npm 上最新是 `2.1.309`
- `Dockerfile.claude` 的 `npm install -g @anthropic-ai/claude-code` 沒釘版本，但那一層
  被 build 快取重用，一般的 `docker compose build` 不會重跑
- 容器內的自動更新也補不了：全域 npm 目錄是 root 擁有（`drwxr-xr-x root root`），
  claude 以 uid 1000 執行（見 `docs/DECISIONS.md` 關於 image 不可變的那則）

## 決策
| 選項 | 代價（實測） | 結論 |
|---|---|---|
| 每次啟動 `build --no-cache` | 每次 +150 秒 | 不用 |
| `./sandbox.sh --rebuild` 選用參數 | 要記得帶 —— `plan` skill：沒有預設路徑的選用機制等於預設關閉 | 不用 |
| **安裝層前放 `ARG CLAUDE_CODE_REFRESH`，`sandbox.sh` 每次帶當天日期** | 每天第一次啟動重裝那一層；其他時候 build 約 1-2 秒 | **採用**（使用者選定）|

## 變更清單
| ID | 檔案 | 變更性質 |
|---|---|---|
| C1 | `sandbox.sh` | 重構：三處重複的 `env ... docker compose -f ...` 抽成 `sandbox_compose`（第三處是 C2 要加的 build） |
| C2 | `Dockerfile.claude` | 安裝層前加 `ARG CLAUDE_CODE_REFRESH`，並在 `RUN` 裡引用 |
| C3 | `sandbox.sh` | 啟動前 `build --build-arg CLAUDE_CODE_REFRESH=<今天>`，失敗時印 build log 並中止 |
| C4 | `README.md` | 說明每日刷新，以及直接 `docker compose build` 不會刷新 |

## 驗證步驟
- [x] `bash -n sandbox.sh` → `syntax ok`
- [x] 同一個 key 連 build 兩次：第二次 `[6/15] RUN echo "claude-code refresh key: test-B" ... CACHED`
- [x] 換 key（test-C）：`[2/15]`～`[5/15]` 為 `CACHED`，`[6/15]` 起重跑
- [x] **mutation**：還原成舊的 Dockerfile（沒有 ARG），key=D 再 key=E → `[6/15] RUN npm install -g @anthropic-ai/claude-code` 仍是 `CACHED`（= 原本的 bug，對照為紅）
- [x] 端到端：`APP_NETWORK_NAME=<另一個專案的 compose 網路> ./sandbox.sh claude --version`
      → 印出 `sandbox: 檢查 image（Claude Code 刷新鍵 = 2026-10-23）`、`2.1.309 (Claude Code)`；
      第一次 92 秒（含重裝），同日第二次 15 秒；單獨量 build 步驟（同日 key）1 秒
- [x] 結束後 `docker ps -a --filter name=docker-api-proxy` 無輸出（清理路徑沒被重構弄壞）

## 回退方式
revert C2–C4 那個 commit 即回到原行為；C1 是純重構，可獨立保留或 revert。

## 已知未驗
- `SANDBOX_DOCKER=0` 路徑沒有端到端跑過（只跑了預設的啟用路徑）
- 「日期換日後會刷新」是用換 key 模擬的，沒有真的跨日跑
- 刷新鍵用的是 host 的本地日期；跨時區的團隊換日時間會不同，不影響正確性
- 沒有在 submodule 形態（sandbox 放在別的專案底下）實測

## 交付狀態

| 項目 | 結果 |
|---|---|
| 修正 | PR #36 → `dev`（rebase 合併） |
| CHANGELOG | PR #37 → `dev`，v0.2.4 列為 PATCH |
| 發佈 | `release/release.sh v0.2.4` 守衛全過；PR #38 → `main`（rebase），`main` = `e199f9e release: v0.2.4` |
| tag／Release | `v0.2.4` → `e199f9e`；GitHub Release 內容由 CHANGELOG 擷取（16 行） |
| 發佈分支 | 已刪（遠端在 PR 合併時被 GitHub 自動刪除） |

產物端驗收（`git clone --depth 1 --branch v0.2.4` 快照）：

- 1 個 commit；頂層沒有 `release/`；`docs/` 只有三份骨架，`^### K-`／`^## D` 命中 0
- `Dockerfile.claude`／`sandbox.sh` 帶有 `CLAUDE_CODE_REFRESH`
- 在快照目錄跑 `claude -p` 問一句：列得出 7 個專案 skill，並照抄出禁令第 1 條
- 相對連結檢查只命中 `record` skill 程式碼區塊裡的格式範本（`known-issues-archive.md`），
  v0.2.3 就已存在，不是死指標；非測試檔的條目 ID 只有骨架裡的「第一則從 K-1／D1 開始」

另：端到端驗證那行原本寫的是另一個專案的實際網路名，修正分支 push 時已公開在
`dev` 的歷史裡；這裡改成佔位字，歷史不改寫（`dev` 是共用分支）。
