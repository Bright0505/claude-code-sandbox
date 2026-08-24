# Changelog

本檔記錄**套用端需要知道的變更**。內部重構、錯字、研發過程的紀錄不列。

## 版號語意

| 級別 | 含義 | 套用端要做什麼 |
|---|---|---|
| MAJOR | 檔案結構或使用方式改變 | 動手遷移 |
| MINOR | 規範或 skill 內容改變 | 重讀 |
| PATCH | 錯字、腳本 bug 修正 | 不用管 |

---

## v0.1.0

第一個可發佈的版本。在此之前這個 repo 同時是產品與它自己的驗證樣本，
本版把研發紀錄移出版本樹（未銷毀，見「移除」一節）。

### 執行環境

- **Claude Code 專用 sandbox**：`node:24-bookworm-slim`、非 root 使用者
  （uid/gid 1000）、不提供 docker socket 也不做 Docker-in-Docker
- **網路白名單**：`init-firewall.sh` 預設擋掉所有對外連線，只放行 Claude Code
  實際需要的網域。自架站台用 `.env.claude` 的 `GITLAB_HOST`／`GITHUB_HOST`
  自動放行，其他網域用 `EXTRA_ALLOWED_DOMAINS` 追加，兩者都不必改檔案
- **兩種驗證方式**：Claude 訂閱帳號登入，或 Anthropic Console API key。
  session 存在專案內的 `.claude-config/`，不動主機全域 `~/.claude`
- **容器內可 commit／push**（GitHub 與 GitLab）：憑證由 credential helper
  直接從環境變數回答，**token 不落地**（不寫 `.gitconfig`、不寫
  `~/.git-credentials`、不出現在啟動輸出）。裝有 `gh` 與 `glab`
- **連接專案自己的服務**：`sandbox.sh` 自動偵測專案的 docker 網路後啟動，
  讓 sandbox 用服務名連到已啟動的 API／DB 跑測試。接不上時會明講，不是靜默失敗
- **可當 git submodule 掛進既有專案**：路徑相對 compose 檔解析，
  只需用 `WORKSPACE_DIR` 指定要掛載的目錄

### 開發規範

- `ONBOARDING.md`（人用手冊）與 `CLAUDE.md`（Claude 常駐執行版）兩份，
  取捨判準是**可觸發 vs 不可觸發**
- 六個 skill 按時機載入：`plan`／`code`／`verify`／`deliver`／`record`／`traps`
- 另有 `release`：template 上游自己發佈時的流程（套用端不會觸發）
- `docs/` 骨架：任務索引、事故紀錄、決議紀錄，以及 `record` skill 的
  KNOWN-ISSUES 結構檢查腳本

### 修正

- `scripts/test-init-firewall.sh` 在 macOS host（bash 3.2）跑不完 —— 兩個獨立根因：
  變數緊接全形字元導致 `set -u` 中止、以及 stub 漏掉 `/sys/class/net`
  與 GNU `find -printf` 這兩個 Linux-only 依賴
- README 補「腳本的執行層」表格。**不需要 docker ≠ 不需要 Linux**

### 移除

- `docs/tasks/` 三份任務檔（上游自己的研發紀錄，不隨產品出貨）
- `docs/KNOWN-ISSUES.md` 的 K-1～K-4（規範文件自己的失效形態，
  判準已全部在 `record` skill §6）
- `docs/KNOWN-ISSUES.md` 的 K-6（三條判準各自都有第二個載體：mutation 流程在
  `verify` §2、清單成員用 `grep -qx` 在 `scripts/test-init-firewall.sh:32-33`、
  權限情境要在非 root 驗在 `scripts/test-git-auth.sh:206-216`）

**未銷毀** —— 在**上游 repo** `v0.1.0` 之前的 git 歷史裡。
⚠️ template 產生的 repo **不帶 commit 歷史**，在那裡跑 `git log` 找不到，要去上游拿：

```bash
git clone https://github.com/Bright0505/claude-code-sandbox /tmp/cc-sandbox-upstream
cd /tmp/cc-sandbox-upstream
git log --diff-filter=D -- docs/tasks/      # 找到移除的那個 commit
git show <commit>^:docs/KNOWN-ISSUES.md     # 移除前的全文
```

### 已知未驗

- **`sandbox.sh` 只在 macOS／Docker Desktop 上驗過，未在 Linux host 驗。**
  網路偵測用的是 `docker network ls` 的 compose label，理論上與 host OS 無關，
  但沒有實測
- **`APP_NETWORK_NAME` 指向非 compose 建立的網路**只驗過「不存在時報錯」，
  沒驗過「存在且非 compose 網路時能正常接上」。該路徑對 compose label 沒有依賴
  （overlay 用 `external: true`，docker 只認名字），殘餘風險在 driver／IPAM 層
