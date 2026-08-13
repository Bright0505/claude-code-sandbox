# GitHub / GitLab token 認證：容器內用 .env 的 token 直接 commit + push

狀態：已完成（image build 與真實 push 未驗，見「未驗證」）
強度：L2
日期：2026-08-13

## 目標

在 sandbox 容器內，只靠 `.env.claude` 填入的 personal access token，就能對 GitHub
與 GitLab 完成 `git commit` 與 `git push`，並且 `gh` / `glab` 兩個 CLI 都可直接使用。

「可觀察的結果」：容器啟動時印出哪些 forge 有憑證、身分是誰；`git push` 不再詢問
帳號密碼；`glab --version` 有輸出。

## 範圍

包含：

- `Dockerfile.claude`：加裝 `glab`（GitLab CLI）；`gh` 已在 image 內
- `scripts/`：token → git 憑證的執行期設定（新增 credential helper 與 setup 腳本）
- `scripts/init-firewall.sh`：放行 GitLab 網域（含自架站台）
- `.env.claude.example` + `README.md`：設定項與用法

不包含：

- **MCP server 設定**（GitHub/GitLab MCP）—— 2026-08-13 與委託方確認過，這次只做
  CLI + git token 認證。`glab` 自帶 `glab mcp` 子命令，要用是下一件事，不在這次範圍
- **SSH key 認證** —— 防火牆只放行 80/443，port 22 不開；本任務走 HTTPS + token
- 不改 `docker-compose.claude.yml`（`env_file` 已經會把 `.env.claude` 全部帶進容器，
  不需要逐個列 `environment:`）
- 不動任何開發規範文件（`CLAUDE.md`／`ONBOARDING.md`／skills）

## 驗收

| # | 判準 | 怎麼觀察 |
|---|---|---|
| A1 | credential helper 對 github.com / gitlab.com / 自架 host 各回傳正確的 username+token | `git credential fill` 實測（不是讀腳本推論） |
| A2 | 沒設 token 的 host、以及 `store`／`erase` 動作，helper 一律不輸出任何東西 | 同上 |
| A3 | token **不落地**：不寫 `~/.git-credentials`、不寫進 `.gitconfig` | 跑完 setup 後 dump `.gitconfig` 全文 + 確認無 `.git-credentials` |
| A4 | 沒有任何 token 時容器照樣能啟動（`.env.claude` 是選用的） | setup 腳本以空環境執行，exit 0 |
| A5 | 啟動時印得出「哪個 forge 有憑證／身分是誰／沒設什麼」 | 看實際 stdout |
| A6 | `glab` 的下載來源與 checksum 正確 | 實際下載 + `sha256sum -c` |

## 假設（若不對請說）

- **token 用 HTTPS 帶入的 username 慣例**：GitHub 用 `x-access-token`、GitLab 用
  `oauth2`。兩者都可用 `GITHUB_USER` / `GITLAB_USER` 覆寫，所以猜錯的代價是改一行 env
- **身分（user.name／user.email）也從 `.env.claude` 讀**：commit 沒有身分會直接失敗，
  所以「能 commit」必然包含這件事。用 `GIT_USER_NAME` / `GIT_USER_EMAIL`
- **SSH 形式的 remote 自動改寫成 HTTPS**：容器內 port 22 是關的，`git@github.com:` 一定
  失敗。有 token 的 host 才改寫，可用 `SANDBOX_GIT_REWRITE_SSH=0` 關掉
- **`gitlab.com` 無條件加入白名單**（與既有的 `github.com` 對稱），自架站台再靠
  `GITLAB_HOST` 追加

## 變更清單

| ID | 檔案 | 變更性質 |
|---|---|---|
| C1 | `scripts/git-forge-lib.sh` | 新增：host／token 的環境變數解讀集中在一處（三個腳本共用）|
| C2 | `scripts/git-credential-env.sh` | 新增：git credential helper，只從環境變數回答，不寫磁碟 |
| C3 | `scripts/setup-git-auth.sh` | 新增：啟動時設定 git／glab 並印出狀態 |
| C4 | `scripts/entrypoint.sh` | 修改：降權後呼叫 C3；失敗要大聲，但不阻止容器啟動 |
| C5 | `scripts/init-firewall.sh` | 修改：放行 GitLab 網域、`GITLAB_HOST`、`EXTRA_ALLOWED_DOMAINS`；解析失敗要警告 |
| C6 | `Dockerfile.claude` | 修改：裝 `glab`（版本釘死 + checksum 驗證）、COPY C1-C3 |
| C7 | `scripts/test-git-auth.sh` | 新增：C1／C2／C3 的測試（可在無 docker 的環境跑）|
| C8 | `.env.claude.example` | 修改：加入 token／host／身分等設定項 |
| C9 | `README.md` | 修改：新增「在容器內 commit / push」章節、更新目錄結構與白名單說明 |
| C10 | `scripts/test-init-firewall.sh` | 新增（計畫外）：C5 的測試。用 stub 蓋掉 `iptables`／`ipset`／`dig`／`ip` 後執行**真正的 shipped script**，所以不需要 root 也不會動到真網路 |

C10 不在原計畫裡。加它的理由：C5 是這次唯一「改了但沒有任何自動檢查」的檔案，而它失敗
的形態（放行漏了一個網域）正好就是最難診斷的那種。

C1 的抽取依據 `docs/DECISIONS.md` **D5**「先重複，第三次出現再抽」—— host 正規化
在 C2／C3／C5 是第三次出現，所以這次抽出來，順帶讓 C5 的邏輯變成可測（否則要 root
+ iptables 才能驗）。

## 驗證步驟

- [x] `bash -n` 全部改動與新增的腳本 —— 6 支皆通過
- [x] `scripts/test-git-auth.sh`：**43 通過 / 0 失敗**（沒裝 glab 的環境會 SKIP 一條 → 42；
      本輪把 glab 裝上後補驗了那條）
- [x] `scripts/test-init-firewall.sh`：**15 通過 / 0 失敗**
- [x] mutation test 9 個突變，每一個都只讓「該紅的那條」轉紅（M5／M8／M9 的意外見問題紀錄）
- [x] `git credential fill` 端到端（A1）—— 用真的 git 二進位、真的 PATH 查找
      `git-credential-sandbox-env`，不是模擬
- [x] setup 跑完檢查 `.gitconfig` 全文＋啟動輸出，兩處都不含 token；`~/.git-credentials`
      不存在（A3）
- [x] 空環境跑 setup：exit 0，且輸出明講 GitHub/GitLab 與身分都未設定（A4／A5）
- [x] glab 安裝流程：把 Dockerfile 那段 RUN 的指令原封不動在本機跑一遍，包含
      `sha256sum -c`（OK）、`dpkg -i`（Setting up glab 1.113.0）、`glab --version`（A6）
- [x] `safe.directory` 的前提是真的：以 uid 65534 進入 uid 12345 擁有的 repo，git 回
      `fatal: detected dubious ownership`；加上 `-c safe.directory=<path>` 後恢復正常
- [ ] **`docker build` / 容器內端到端** —— 本執行環境沒有 docker daemon
      （`docker info` → `dial unix /var/run/docker.sock: no such file`），無法驗。
      未驗的部分列在下方「未驗證」

## 未驗證（交接時要知道）

1. **image build 本身沒跑過**。glab 的下載＋checksum＋`dpkg -i` 這段指令是在本機用
   同一組指令實測過的（deb 18MB、checksum OK、`Depends: git` 已在 image 內），但
   `docker build` 沒執行。
2. **真實 push 沒做過** —— 需要真 token。helper 回傳的 username/token 組合正確性
   靠官方文件慣例，不是實測。
3. **驗證環境不是 image 本身**：測試跑在 Ubuntu 容器（bash 5.2 / git 2.43），image 是
   `node:24-bookworm-slim`（Debian 12，git 2.39）。腳本只用到 `safe.directory`（git 2.35+）
   與 `credential.<url>.helper`（更早），沒有版本相關的特性，但這是推論不是實測。
4. **自架 GitLab 的 `glab` CLI**：實測 `GITLAB_TOKEN` 只在預設 host（gitlab.com）被
   `glab auth status` 認得；自訂 `GITLAB_HOST` 會回報「has not been authenticated」。
   `git push` 不受影響（走 credential helper，與 glab 無關），但 `glab` 子命令在自架
   站台需要在容器內另外 `glab auth login --hostname <host>`。已寫進 README。

## 回退方式

單一 commit，`git revert` 即可。新增檔案（C1／C2／C3／C7）不被任何既有流程引用，
移除後 `entrypoint.sh`／`init-firewall.sh` 回到原狀即恢復原行為；已 build 的 image
需要重新 `docker build` 才會反映。

## 完成紀錄

| 日期 | 項目 | commit | 驗證結果（實際觀察到什麼） |
|---|---|---|---|
| 2026-08-13 | C1-C10 全部 | 單一 commit（一個「為什麼」：讓容器內能用 token push；功能與其測試不切開）| `test-git-auth.sh` 43/43、`test-init-firewall.sh` 15/15；9 個 mutation 全部只讓對應斷言轉紅；`git credential fill` 回 `username=x-access-token` + 正確 token；`.gitconfig` 與啟動輸出皆不含 token |

**交付**：分支 `claude/gitlab-github-integration-srn2kp`（未動 `main`）。委託時已明確指示
commit 並 push 到該分支，故直接 push；未開 PR（沒有被要求）。commit 身分用 `git -c` 帶入，
不寫進任何 git config。

## 問題紀錄

| 日期 | 問題 | 根因 | 處理 | 已升級到 KNOWN-ISSUES？ |
|---|---|---|---|---|
| 2026-08-13 | `glab config set git_protocol https` 印出 `ERROR ... not a Git repository` 但 **exit code 是 0** | 不在 git repo 內時 glab 寫的是 repo 層設定；失敗只印訊息不改 exit code | 改用 `--global`（實測寫入 `~/.config/glab-cli/config.yml` 並讀得回 `https`）| 否 —— 是上游工具的行為，不是本專案的機制。已在 C3 註解標明為什麼一定要 `--global` |
| 2026-08-13 | `glab` 預設 `git_protocol` 是 `ssh`，但容器只放行 80/443 | 上游預設值與本 sandbox 的網路邊界不一致 | C3 在有 GitLab token 時強制設成 `https` | 否 —— 已由 C3 消除，不會再被踩到 |
| 2026-08-13 | **M5**：把靜態白名單裡的 `gitlab.com` 整行刪掉，C10 測試仍全綠 | `forge_gitlab_host` 預設就回 `gitlab.com`，所以derived 路徑補上了它 —— 那條斷言其實沒有守住任何東西 | 補一條「設了自架 `GITLAB_HOST` 時 `gitlab.com`／`github.com` 仍須在白名單」，把「自架是**追加**不是**取代**」這個意圖釘住；重跑 M5／M8 皆轉紅 | 否 —— 是測試設計問題，已在同一輪修掉，且原因寫在測試檔的註解裡 |
| 2026-08-13 | **M8**：刪掉靜態 `github.com` 後測試也沒紅 | 斷言用了 `grep -w github.com`，而 `-w` 的字界把 `api.github.com` 也算成命中 | 改成整項精確比對（`in_list`，`grep -qx`）| ↑ 同上 |
| 2026-08-13 | **M9**：第一版「HOME 不可寫要失敗」的測試以 root 跑會假綠 | 用 `chmod 500` 造情境，但 root 繞過權限檢查，`[ -w ]` 仍為真 | 主斷言改用「路徑不存在」（對任何身分都成立），另外在有 `setpriv` 時以 uid 65534 補驗真正的不可寫 | **是 → K-6** |
| 2026-08-13 | 無法確認 `gosu` 是否會把 `HOME` 換成目標使用者的家目錄（本機沒有 gosu 可實測）| —— | 讀上游 `main.go` 確認它會（`os.Unsetenv("HOME")` + 註解），但**不依賴**：C3 開頭加一道 `[ -w "$HOME" ]` 守衛，寫不進去就 exit 非 0，由 `entrypoint.sh` 印出警告。這條由 `HOME 不存在 → exit 非 0` 守著 | 否 —— 已轉成大聲失敗，不會靜默 |

三則 M 都是同一個形態（測試綠但沒守住東西），已升級成 **K-6**；憑證不落地的設計取捨
寫進 **D11**。
