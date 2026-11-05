# 出貨文件深度掃描：一個新功能的啟動失敗、九處過時說明

狀態：已完成（歸檔掃描結論：無可歸檔條目，見下）
強度：L2
日期：2026-11-05

## 目標

`feat/sandbox-peer-messaging` 交付後，對**出貨檔**（`release/release.sh` 的 `PROD` ＋ `release/skeleton`，35 個檔案）
做過時掃描。判準沿用 `2026-09-17-docs-staleness-audit`：**會不會讓讀者做出錯誤動作**，不是措辭。
使用者另要求：清除過時、封存（歸檔）已通過的資訊。

## 範圍

包含：出貨檔的文件與註解；KNOWN-ISSUES 歸檔資格掃描（`record` §7）。
不包含：`docs/tasks/` 各任務檔的歷史內容（禁令 8，不改原文）；CHANGELOG 新區塊（發版時依 `release` 流程寫）。

## 做法

- 機械式（自己跑）：反引號路徑引用是否存在、`檔案:行號` 引用是否仍指向原內容
- 語意層（兩個獨立 agent 平行對讀，未給結論以免錨定）：① README／`.env.claude.example`／程式註解 vs 程式碼
  ② CLAUDE.md／ONBOARDING／skills／skeleton／CHANGELOG 的交叉引用與一致性
- agent 回報的每一項都由主 session 對照原始碼或實跑確認後才列入

## 發現與處理

| ID | 問題 | 處理 | commit |
|---|---|---|---|
| F1 | `SANDBOX_PEER_GROUP` 寫進 `.env.claude` 時，entrypoint 謊稱已加入群組並在 chown 失敗後**容器退出**（實測重現）| 以 mountpoint 判斷是否真的加入；未掛上時警告並以隔離模式啟動；`.env.claude.example` 補列 | `2cdf459` |
| F2 | README 互通章節未說 `sandbox.sh` 需要專案網路 | 補「空網路 + `APP_NETWORK_NAME`」的用法 | `a1ddcff` |
| F4 | Template 保留清單漏 `docker-compose.claude.peer.yml` | 補上 | `a1ddcff` |
| G1 | `verify` description「鐵則 9」應為禁令 9 | 改正 | `6e850f7` |
| G2 | 單元測試 docstring 的 `python3 -m unittest <路徑>` 會報 Empty module name | 改為直接執行 | `6e850f7` |
| G3 | record 結構檢查腳本的呼叫方式沒寫、範例帶 submodule 前綴 | 補呼叫方式（不接受位置參數）| `6e850f7` |
| F3 | `APP_COMPOSE_PROJECT` 只說「供自動偵測」，實際也決定 docker proxy 放行範圍 | README、`sandbox.sh` 檔頭補上 | `6e850f7` |
| F5 | `Dockerfile.claude` 註解指向 `docker-compose.yml` | 改為 `docker-compose.claude.yml` | `6e850f7` |
| F6 | README 的 host 測試漏 `test-docker-api-proxy.py` | 補上 | `6e850f7` |
| F7 | entrypoint 說明只寫網路與 docker 狀態 | 補群組與 git 狀態 | `6e850f7` |
| G4 | CHANGELOG 沒有協作群組功能 | **不處理**，發版時依 `release` 流程寫（MINOR）| — |

## 驗證

- 機械式掃描：34 筆「引用但找不到」逐筆歸類，全是合法形態（fixture、範例路徑、專案自己的 `docker-compose.yml` 等）；
  唯一的行號引用 `init-firewall.sh:32` 仍指向 `find`。過程中兩次假綠（zsh 不做 word splitting、
  bash 3.2 的 `source <(...)` 讀不到內容，`PROD` 為空只掃到 3 個檔）均已重跑
- F1：三情境 × 新舊版。舊版（`HEAD` 的 entrypoint）印「已加入」後 chown 失敗、子程序未執行；新版印警告、
  子程序以 PID 1 執行（`exec`，未進群組路徑）。完整群組：PID 推進到 20814、目錄 `claude:claude`。未設群組：行為不變
- 文件中的指令照抄執行：單元測試 `Ran 14 tests ... OK`；結構檢查腳本帶三個選項可執行、位置參數被拒（與新文件一致）
- regression：`test-git-auth.sh` 42/0、`test-init-firewall.sh` 15/0、`test-docker-api-proxy.py` 52 passed

## 歸檔掃描（`record` §7）—— 結論：**本輪沒有可歸檔的條目**

| 條目 | 狀態 | 不符合的理由 |
|---|---|---|
| K-5、K-7、K-9 | 已修（有守備）| 與 K-8／K-10／K-11／K-12／K-14 在**同一條關聯鏈**上，鏈上有「已修（無守備）」→ 原子性（硬規則 ③）讓整條鏈不能動。K-5、K-9 的守備是 entrypoint 函式／release 守衛，不是可執行測試，另不滿足資格 2 |
| K-8、K-10、K-11、K-12、K-13、K-14 | 已修（無守備）| 永不歸檔 |

依 §7 的兩種讀法：
- **待補測試清單**：K-8、K-10、K-11、K-12（文件性質，無可轉紅斷言）、K-13、K-14（需要 docker 的行為，目前只有手動 mutation 紀錄）
- **散佈度**：K-5 所在的鏈連到 9 則中的 8 則，跨 `scripts/entrypoint.sh`、`sandbox.sh`、`release/release.sh`、
  `scripts/docker-api-proxy.py`、`docs/`、`CHANGELOG.md` —— 形態是「失敗沒有輸出／讀者接收不到」，不夠局部。
  依 §7「歸檔一直不動本身就是訊號」記錄於此，**不設門檻、不自動行動**

「清除過時」：紀錄類檔案依禁令 8 不刪；本輪過時的是出貨文件，已在上表修正。

escalation sweep（`record` §4）：F1 符合「錯誤訊息不指向真正原因」→ 升級為 **K-15**（已修（無守備））。其餘為文件修正，不升級。

## 交付狀態

- 分支 `feat/sandbox-peer-messaging`，未 push、未開 PR
