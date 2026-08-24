# Changelog

**套用端需要知道的變更。** 每個版本控制在 ~15 行 —— 內部重構、錯字、
上游自己的研發過程都不列。細節在該版本的 tag，以及上游的 `dev` 分支。

## 版號語意

| 級別 | 含義 | 套用端要做什麼 |
|---|---|---|
| MAJOR | 檔案結構或使用方式改變 | 動手遷移 |
| MINOR | 規範或 skill 內容改變 | 重讀 |
| PATCH | 錯字、腳本 bug 修正 | 不用管 |

---

## v0.1.0

第一個可發佈的版本。

- **執行環境** —— Claude Code 專用 sandbox（`node:24-bookworm-slim`、非 root、
  不給 docker socket）。對外連線預設全擋，只放行需要的網域，自架站台與額外網域
  都用 `.env.claude` 設定、不必改檔案。容器內可 commit／push GitHub 與 GitLab，
  而 **token 不落地**。可自動接上專案自己的 docker 網路用服務名跑測試。
  可當 git submodule 掛進既有專案
- **開發規範** —— `ONBOARDING.md`（人看）與 `CLAUDE.md`（Claude 常駐執行）兩份，
  七個 skill 按時機載入，`docs/` 提供任務／事故／決議三份骨架與一支結構檢查腳本
- **修正** —— `scripts/test-*.sh` 在 macOS host（bash 3.2）跑不完，兩個獨立的
  Linux-only 依賴。README 補「腳本的執行層」：**不需要 docker ≠ 不需要 Linux**
- **`docs/` 交付為空骨架** —— 上游自己的紀錄不隨產品出貨，你的編號從 1 開始

### 已知未驗

- `sandbox.sh` 只在 macOS／Docker Desktop 驗過，**未在 Linux host 驗**
- `APP_NETWORK_NAME` 指向**非 compose 建立**的網路只驗過「不存在時報錯」，
  沒驗過「存在時接得上」—— 殘餘風險在 driver／IPAM 層

---

## 上游自己的研發紀錄在哪

出貨的 `docs/` 是空骨架。上游的任務檔、事故紀錄、決議紀錄活在上游 repo 的
**`dev` 分支**，未銷毀：

```bash
git clone -b dev https://github.com/Bright0505/claude-code-sandbox /tmp/cc-upstream
```

⚠️ Template 產生的 repo **不帶 commit 歷史**，所以在你自己的 repo 裡
`git log` 找不到那些紀錄 —— 要去上游拿。
