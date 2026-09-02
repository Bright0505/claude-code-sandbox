# 容器內 agent 看不到開機時才印的 docker workspace 指引

狀態：已完成
強度：L2
日期：2026-09-02

## 目標

`D12`／`K-5` 已經讓「操作專案自己的 docker compose 要 `cd` 到 `$SANDBOX_HOST_WORKSPACE`」
這件事在容器開機時印出來（README 也寫了），但這個管道只有**啟動容器的人**讀得到。
`ggr` 專案的 Laravel 升級任務（第一個把 `sandbox-docker-access` 用在真實多階段工作的
套用端案例）實測時，**在容器裡工作的 Claude session 一樣先撞到 `Binds: ... is outside
...` 才發現**——這個 session 是透過個別 tool call 跟一個已經在跑的容器互動，讀不到
PID 1 開機瞬間的那份 stdout。目標是把這件事寫進**每輪都會被載入的地方**，讓容器內的
agent 不用先撞一次錯誤才知道。

## 範圍

包含：`CLAUDE.md`（鐵則加一條）、`docs/KNOWN-ISSUES.md`（K-8，記錄「讀者身分不同，
同一份印出來的指引對另一種讀者等於沒印」這個形態）、`docs/tasks/README.md`（索引）。
不包含：`ggr` 專案自己在這次升級過程中踩到的 Laravel/PHP 領域問題（opcache、composer
版本、PDO 常數改名、webpack/OpenSSL）——那些跟 `claude-sandbox` 本身無關，已經記在
`ggr` 自己的 `docs/KNOWN-ISSUES.md`，不混進本檔（比照 D2 的判斷原則，也是本任務檔
開頭「本任務同時是 claude-sandbox 的真實驗證案例」那句原本的分工）。

## 驗收

- `CLAUDE.md` 的鐵則清單包含這條規則，且**不引用本 repo 內部的 `K-<n>` 編號**
  （`CLAUDE.md` 會原樣出貨給套用端，套用端的 `KNOWN-ISSUES.md` 從 `K-1` 開始，
  引用上游的 ID 在套用端是死連結——見 `record` skill §6 第 6 點）
- `docs/KNOWN-ISSUES.md` 新增一則，`影響範圍`／`症狀`／`根因`／`判準` 齊全

## 假設（若不對請說）

- A1：這則不需要新測試——`CLAUDE.md` 有沒有那一行沒有可 mutation 驗證的斷言，
  狀態記「已修（無守備）」，永不歸檔（`record` skill §3 狀態語意）
- A2：mysql container 在這次 `ggr` 實測中被 compose 改名成
  `b0de2af3dbbc_ggr-mysql-1`（第一次在 `/workspace` 下 `docker compose up -d`
  被拒絕、換到 `$SANDBOX_HOST_WORKSPACE` 重跑之後發生），**沒有查證根因**——
  不確定是 docker-api-proxy 的行為還是 compose 本身在部分失敗後的行為，
  只記錄症狀在「問題紀錄」，不升級成 KNOWN-ISSUES（沒有根因就寫判準等於編造）

## 變更清單

| ID | 檔案 | 變更性質 |
|---|---|---|
| C1 | `docs/KNOWN-ISSUES.md` | 新增 K-8 |
| C2 | `CLAUDE.md` | 鐵則新增第 9 條，指向 README「兩件要知道的事」，不寫 K-8 這個內部 ID |
| C3 | `docs/tasks/README.md` | 索引加一列 |

## 驗證步驟

- [x] `grep -n "K-8" CLAUDE.md docs/KNOWN-ISSUES.md` —— 確認 `CLAUDE.md` 沒有命中
      （沒有引用內部 ID），`docs/KNOWN-ISSUES.md` 命中一次（條目本身）
- [x] 讀一遍新增的鐵則第 9 條，確認不需要額外解釋術語就看得懂規則本身
      （不依賴讀者已經知道 `$SANDBOX_HOST_WORKSPACE` 是什麼）

## 回退方式

單一 commit，`git revert`。沒有持久化狀態，純文件變更。

## 完成紀錄

| 日期 | 項目 | commit | 驗證結果（實際觀察到什麼） |
|---|---|---|---|
| 2026-09-02 | C1-C3 | (待 commit) | `grep -n "K-8" CLAUDE.md` 無命中；`grep -n "K-8" docs/KNOWN-ISSUES.md` 命中一次（條目標題）|

## 問題紀錄

| 日期 | 問題 | 根因 | 處理 | 已升級到 KNOWN-ISSUES？ |
|---|---|---|---|---|
| 2026-09-02 | `ggr-mysql-1` 在一次失敗又重跑的 `docker compose up -d` 之後被改名成 `b0de2af3dbbc_ggr-mysql-1` | **未查證**——mysql 本身沒有改 image，理論上不該被這次操作動到 | 只記錄症狀，不處理（沒有根因無法寫判準，見 A2） | 否——沒有根因，寫成 KNOWN-ISSUES 等於編造，留在這裡等下次有樣本再查 |
