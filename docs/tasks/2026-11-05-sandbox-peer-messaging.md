# 多個 sandbox 容器的 session 互通（peer messaging）

狀態：已完成（U3 跨帳號互通待測，見「後續」）
強度：L2
日期：2026-11-05

## 目標

同一台機器上的多個 sandbox 容器，**各自登入不同的 Claude 帳號**（跨部門協作），
容器內的 session 能用 `ListAgents`／`SendMessage` 找到彼此並互傳訊息 ——
例如 A 帳號的 session 詢問或請求 B 帳號的 session 執行某件事。

使用情境：一台專屬的跨部門溝通機器，上面跑多個專案的 sandbox。短期是
「一台機器一個協作」，但要保留「一台機器多個協作、彼此隔離」的可能。

## 為什麼不用 Remote Control（路線 A）

Remote Control 的 peer 是**同一個帳號**底下的 session；跨部門是不同帳號，
走不通。所以走本機通訊（路線 B）。決議寫進 `docs/DECISIONS.md`（C5）。

## 一手觀察（host 上實測，2026-11-05，Claude Code 2.1.318）

- session 登記在 `$CLAUDE_CONFIG_DIR/sessions/<PID>.json`，欄位含
  `pid`、`procStart`、`pidDomain`（host 上是 `darwin`）、`cwd`、`name`、
  `messagingSocketPath`、`bridgeSessionId`（開了 Remote Control 才有）
- 同目錄還有 `<PID>.<hash>.key` —— **用途未查證**，推測是訊息認證用
- 訊息通道是 unix socket `/tmp/cc-socks/<PID>.sock` —— **不在 config 目錄裡**
- `ListAgents` 同時列出本機 peer 與 Remote Control peer；同時具備兩種身分的
  session 只列一次

## 範圍

包含：
- 只共用通訊必要的兩樣：`sessions/` 與 `/tmp/cc-socks/`，用 named volume，
  **一個協作群組一個 volume**
- PID namespace：同群組容器共用一個 PID namespace（不用 `pid: host`）
- `sandbox.sh` 選用參數（暫名 `SANDBOX_PEER_GROUP=<名稱>`）：不帶 = 維持完全隔離
- entrypoint 開機摘要：加入／未加入群組兩種狀態都印一行（K-5 判準 ②）
- 協作授權規則**範本**：給各專案自己填進自己的 `CLAUDE.md`，不替任何專案預設授權
- README 用法、`DECISIONS.md` 決議

不包含：
- 共用整個 `.claude-config`（登入憑證、settings、memory 各容器獨立 —— 不同帳號）
- 與 host 上 session 互通（unix socket 跨不過 macOS ↔ Docker VM）
- Remote Control（路線 A）
- 跨機器協作

## 驗收

1. 同群組的兩個容器、兩個不同帳號：雙方 `ListAgents` 都列得出對方，
   `SendMessage` **雙向**送達並收到回覆
2. 不同群組（或未指定群組）的容器互相看不到
3. 兩個容器同時跑時，`sessions/` 裡沒有 PID 衝突造成的覆蓋或誤清
4. 不帶 `SANDBOX_PEER_GROUP` 時行為與現在完全相同（regression）
5. 開機摘要兩種狀態各印一行

## 假設（若不對請說）

- A1：**一個群組 = 一個信任邊界。** 群組內任何容器都能看見、送訊息、改寫登記檔、
  讀取 `.key`（所有容器同 UID，檔案權限分不開）。所以預設關閉、需明確指定
- A2：**「A 請求、B 執行」受 Claude Code 自身規則約束**：peer 訊息是資訊不是指令，
  B 只在 B 的使用者已授權的範圍內行動。授權由 B 方事先寫好（範本，C6），
  不由 A 方決定。本任務不嘗試繞過這條規則
- A3：用 named volume 而不是 host bind mount —— unix socket 在 macOS bind mount
  （virtiofs）上不保證能跨容器運作；named volume 在 Docker VM 內，同一個 kernel
- A4：跨帳號這件事在傳輸層是否會被擋，**目前不知道**，由 P1 實測

## 待驗證的未知（P1 實驗要回答的）

| # | 問題 | 影響 |
|---|---|---|
| U1 | 兩個容器的 claude PID 是否實際衝突 | 決定是否需要共用 PID namespace |
| U2 | 容器內 `pidDomain` 的值；共用 namespace 後存活判定是否正確 | PID 方案可行性 |
| U3 | 不同帳號的 session 能否互列、互傳 | 整條路線可行性 |
| U4 | B 閒置時收到訊息會不會自己被喚醒處理（無人值守的前提）| 無人值守是否可行 |
| U5 | `.key` 檔的用途 | A1 的風險程度 |

## 變更清單

| ID | 檔案 | 變更性質 |
|---|---|---|
| C0 | （無產品檔）| P1 實驗：手動起兩個容器量 U1-U5，結果貼回本檔 |
| C1 | `docker-compose.claude.peer.yml`（新 overlay）| 掛群組專屬的 `sessions/`、`/tmp/cc-socks/` named volume；`init: true`。**不共用 PID namespace** |
| C2 | `sandbox.sh` | `SANDBOX_PEER_GROUP` 參數 → 加上 C1 overlay、帶入 volume 名稱 |
| C3 | `scripts/entrypoint.sh` | 有群組時：root 階段把兩個共用目錄 chown 給 `claude`（新 named volume 預設 root 擁有）；把 PID 推到未登記的號碼後以**子程序**啟動 claude（`exec` 會沿用 entrypoint 的 PID）；`print_peer_summary` 兩種狀態都印 |
| C4 | `README.md` | 用法、信任邊界說明 |
| C5 | `docs/DECISIONS.md` | 決議：走本機通訊不走 Remote Control；推翻 README「不跟其他專案共用」的部分範圍 |
| C6 | `README.md`「多個 sandbox 的 session 互通」內（隨 README 出貨）| B 方事先授權的範本：允許的來源、允許的動作、**到期日**。到期的硬性切斷（hook）另議 |
| C7 | `release/release.sh` | 若 C1／C6 是新出貨檔，要加進產品檔白名單（K-9）|
| C8 | `docs/tasks/README.md` | 索引 |

C1-C3 的具體做法依 P1 結果定，**P1 做完會回來更新本表再動手**。

## 已知坑（開工前回查 KNOWN-ISSUES）

- K-5：選用機制 → 成功與失敗都要印（C3）
- K-8：開機摘要只有啟動容器的人看得到，容器內 agent 看不到 →
  是否需要讓容器內 agent 知道自己在群組裡，P1 後判斷
- K-9：新出貨檔要進 `release.sh` 白名單（C7）

## 驗證步驟

- [x] P1：兩個容器、手動掛共用 volume，逐項量 U1-U5（U3 跨帳號待測）
- [x] 驗收 4（regression）、5（開機摘要）—— 見完成紀錄
- [x] 撞號避讓 + mutation、exit code 透傳、`docker stop` 送達子程序 + mutation
- [x] 驗收 1-3：經 `./sandbox.sh` 啟動兩個真實 claude session 端到端（同一帳號）
- [ ] U3：兩個不同帳號

## 回退方式

功能是選用的：不帶 `SANDBOX_PEER_GROUP` 即等同未安裝。程式變更按 commit `git revert`。
named volume 用 `docker volume rm <名稱>` 清除，不影響各容器自己的 `.claude-config`。

## 完成紀錄

| 日期 | 項目 | commit | 驗證結果（實際觀察到什麼） |
|---|---|---|---|
| 2026-11-05 | C2 群組名驗證 | 904e692 | `SANDBOX_PEER_GROUP='Bad Name'` → 印出字元限制訊息，rc=1 |
| 2026-11-05 | 驗收 4／5（不帶群組）| 904e692 | 開機印「未加入協作群組」兩行；命令 `$$=1`（仍是 exec）；無 `sessions`／`cc-socks` 掛載 |
| 2026-11-05 | C1-C3（帶群組，兩個並行）| 904e692 | 兩個 volume 由 `sandbox.sh` 建立；容器 PID 1 = `docker-init`；兩目錄 `claude:claude`；預告 PID 與子程序實際 `$$` 一致（15331／8715）|
| 2026-11-05 | C3 撞號避讓 | 904e692 | 1..30000 全標已登記 → 正式版選 30001（兩次）；mutant（拿掉未登記檢查）選 9088 ✗ |
| 2026-11-05 | C3 exit code | 904e692 | 子程序 `exit 7` → `sandbox.sh` rc=7 |
| 2026-11-05 | C1 `TINI_KILL_PROCESS_GROUP` | 904e692 | 有：`docker stop` 1 秒、子程序收到 TERM；mutant（拿掉）：子程序沒收到 TERM |
| 2026-11-05 | 驗收 1-3 端到端（`./sandbox.sh`，群組 `e2e`，同一帳號）| 904e692 | 雙方互列；A → B 送達、B 回覆 A 收到。登記 10007／11612，`pidDomain` 不同，socket 各一；兩容器 PID 1 皆 `docker-init`。c1 以 `claude` 讀 `/proc/11612/root/.../.credentials.json` → No such file |
| 2026-11-05 | 正常退出的清理 | 904e692 | 兩個 session `/exit` 後重開一個：volume 只剩新 session（13604）的 `.json`／`.key`／`.sock`，10007／11612 的三種檔案都已移除；新 session `ListAgents` 不列已退出者。`docker stop`／異常終止時是否清理**未測** |
| 2026-11-05 | 既有測試 | 904e692 | `test-git-auth.sh` 42/0、`test-init-firewall.sh` 15/0、`test-docker-api-proxy.py` 52 passed；`check_known_issues_links.py` 結構層通過；`compose config` 無群組名時拒絕、有群組名時 volume 名稱正確 |

## P1 實驗結果（2026-11-05，image `claude-code-sandbox:latest`，只用實驗用 named volume）

**第 1 輪：不共用 PID namespace**
- U1 ✅ 衝突確認：兩個容器的 claude 都是 PID 1，後啟動的 B 把 `sessions/1.json` 覆蓋。
  症狀是不對稱：A 列得到 B，B 什麼都列不到。socket 有避讓（B 的改名為 `1-92117303.sock`），
  登記檔沒有
- U2：`pidDomain` = `linux::pid:[<namespace inode>]` —— Claude Code 有意識到 PID namespace
- U5：每個 session 一個 `<PID>.<hash>.key`，權限 600，但同 UID 所以群組內互相可讀（未讀內容）

**第 2 輪：A、B 加入錨點容器 `peer-exp-anchor` 的 PID namespace**
- PID 不再衝突（564、854），兩邊 `ListAgents` 都列到對方 ✅
- ⚠️ **副作用：A 可以讀 B 的整個檔案系統。** 同一個 PID namespace + 同一個 UID（1000），
  A 容器內以 `claude` 身分可以讀 `/proc/854/environ`（B 的環境變數）與
  `/proc/854/root/`（B 的檔案系統），實測 `test -r /proc/854/root/home/claude/.claude/.credentials.json` 成立
  —— **B 帳號的登入憑證對 A 可讀**。以 root 身分反而被擋（沒有 `CAP_SYS_PTRACE`）。
  只檢查了存在與可讀，沒有讀內容
- U3、U4 尚未測（被上面這點擋下，等決議）

**第 3 輪（方案 A）：共用 PID namespace + 每側不同 UID（1001／1002，同 GID 1000）**
- 共用目錄預設為 `root:1000 1777`。結果雙方 `ListAgents` 連**自己**都沒登記：
  `sessions/` 只有兩個 `.key`，**沒有 `.json`**，`/tmp/cc-socks/` **沒有 socket**
- 對照第 1、2 輪（目錄擁有者 = 執行者 UID）：`.json` 與 socket 都建立，且目錄被設成 `700`
- 判讀：Claude Code 的 peer 通訊只在**同一個 OS 使用者**之間成立；目錄不屬於自己時
  就不登記。**推測**是擁有權／權限檢查（防止別的使用者劫持 socket），**沒有查證原始碼**
- 結論：方案 A 不可行 —— 「跨 UID 隔離」與「能互傳訊息」在 Claude Code 目前的設計下互斥
- 附帶量測：image 內 fork `/bin/true` 5000 次約 1.3 秒（方案 B 錯開 PID 的成本參考）

**第 4 輪（方案 B）：同 UID 1000、各自 PID namespace、啟動前把 PID 推到未登記的號碼**
- PID 錯開：A 的 claude = 16227，B = 3215；兩個 `pidDomain` 不同；登記檔、socket 各自獨立 ✅
- 雙方 `ListAgents` 互列 ✅；A → B `SendMessage` 送達，B 回覆，A 收到 ✅
- U4 ✅：B 閒置中未輸入任何東西，收到訊息後自行處理並回覆
- 隔離 ✅：A 容器內看不到 B 的程序；以 `claude` 身分 `ls /proc/3215/root/.../.credentials.json`
  → `No such file or directory`（A 的 namespace 裡沒有這個 PID）
- ⚠️ **U3 未成立**：比對兩側 `.claude.json` 的 `oauthAccount.accountUuid` 雜湊（只比雜湊，未印值），
  **兩側相同** —— 這一輪其實是同一個帳號。跨帳號仍待測（`userID` 不同，那是安裝識別，不是帳號）
- 2026-11-05 使用者確認：第二個帳號的同事當天不在，**U3 列為待測**，先以單一帳號推進

**P1 結論**：採方案 B。方案 A（不同 UID）不可行；第 2 輪（共用 PID namespace）會讓同群組互讀
檔案系統與憑證，不採用。撞號／版本相依的檢查機制**等方法確認後再加**（使用者決定）。
`.key` 群組內互讀的風險使用者已知悉，規範由使用者另訂；底線是帳號憑證不可被冒用（第 4 輪已守住）

## 問題紀錄

| 日期 | 問題 | 根因 | 處理 | 已升級到 KNOWN-ISSUES？ |
|---|---|---|---|---|
| 2026-11-05 | 共用 PID namespace 讓群組內容器互讀檔案系統與憑證 | `/proc/<pid>/root`、`environ` 的存取判定是 ptrace-read：同 UID 即通過；所有 sandbox 容器都是 UID 1000 | 停下等決議，見對話中的方案比較 | 否（尚未定案）|

## 交付狀態

- **分支**：`feat/sandbox-peer-messaging`（從 `dev` 開出），2026-11-05 依使用者指示 push 並開 PR
  [#40](https://github.com/Bright0505/claude-code-sandbox/pull/40)（base `dev`），**尚未合併** —— 合不合是使用者的決定
- **commit**：`904e692`（功能 + README + release 白名單）、D13／K-13／K-14 的 docs commit、本任務檔的 docs commit
- **CHANGELOG**：未寫，留到發版時依 `release` 流程（這是 MINOR 級的新功能）
- 實驗用的 `peer-exp-*` volume、`peer-coll-test*` volume 已清除；端到端用的 `peer-test-net` 網路與
  `claude-peer-e2e-*` volume 已於測試 session 關閉後清除

## 後續（不在本次範圍）

1. **U3 跨帳號**：第二個帳號可用時，用兩個不同帳號重跑端到端（`/list-agents` + `SendMessage` 雙向），
   並比對兩側 `oauthAccount.accountUuid` 雜湊確認確實不同
2. **事後檢查**（使用者決定方法確認後再加）：claude 啟動後自己的 `<pid>.json` 沒出現就警告
   （涵蓋 Claude Code 改版改了登記方式、群組內同時啟動的競態）
3. **異常結束的清理**：`docker stop`／當機後登記是否殘留未測；殘留時清單會多一個點不到的 session
4. **非 root 啟動路徑**（使用者自行 `-u`）：無法 chown，可能觸發 K-14，未處理未測
5. **`.key` 在群組內互讀**：規範由使用者另訂
6. **到期的硬性切斷**：授權範本的到期日目前只靠 Claude 判斷；要硬性切斷需另做 hook

> ⚠️ 本檔的 commit hash 是 rebase 合併前的；`dev` 上的對應 hash 見 `2026-11-05-release-v030.md`「rebase 合併造成的 hash 對照」。已於 v0.3.0 出貨。
