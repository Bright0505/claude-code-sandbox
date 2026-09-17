# 任務索引

按時間排序。**完成的不刪不移動** —— 依序讀下來是了解專案演進最快的方式。

計畫檔的骨架與強度判準見 `plan` skill。

| 日期 | 任務 | 涉及範圍 | 一句話 |
|---|---|---|---|
| 2026-09-02 | [sandbox 內可使用 docker 指令](2026-09-02-sandbox-docker-access.md) | `scripts/`、`Dockerfile.claude`、`sandbox.sh` | 經過濾 proxy 提供 docker 存取，不掛 socket |
| 2026-09-02 | [容器內 agent 看不到開機才印的 docker workspace 指引](2026-09-02-agent-workspace-visibility.md) | `CLAUDE.md`、`docs/KNOWN-ISSUES.md` | 同一份印出來的指引，套用端真實使用時對「容器內的 agent」這種讀者等於沒印過 |
| 2026-09-03 | [v0.2.0 發佈：稽核擋下的三類問題](2026-09-03-release-v020-audit.md) | `release/release.sh`、`release` skill、`CHANGELOG.md`、出貨檔的註解 | 產品檔白名單漏掉這一版的主要交付，而三道守衛全綠；稽核指令的範圍也比出貨範圍窄 |
| 2026-09-12 | [v0.2.1 發佈：TERM 透傳與一個跨版死指標](2026-09-12-release-v021.md) | `docker-compose.claude.yml`、`CHANGELOG.md`、`scripts/test-git-auth.sh` | 稽核的 pattern 只涵蓋條目 ID，涵蓋不到指名的任務檔名，於是一個死指標跟著出貨了三版 |
| 2026-09-17 | [文件過時掃描](2026-09-17-docs-staleness-audit.md) | `README.md`、`.env.claude.example`、`docs/DECISIONS.md`、`docs/tasks/2026-09-12-release-v021.md` | 全文件掃描：一個把「已修」讀成「現存限制」的反向引用、決議自己打掉的行號指標、清單漏項三處 |
| 2026-09-17 | [v0.2.2 發佈：更正錯誤的「不需發版」結論](2026-09-17-release-v022.md) | `CHANGELOG.md`、`docs/KNOWN-ISSUES.md`、`docs/tasks/2026-09-17-docs-staleness-audit.md` | 上一輪的收尾斷言複述了中途的舊結果，沒有對著最終 commit 重跑量測，實際上產品檔有變動 |
| 2026-09-17 | [發佈流程補上 GitHub Release，內容從 CHANGELOG 擷取](2026-09-17-release-notes-from-changelog.md) | `release/release.sh`、`release` skill §8 | 裸 tag 只顯示 release commit 訊息；不用 `--generate-notes`（`main` 兩個 tag 間永遠只有一個 commit），改用 `awk` 擷取 CHANGELOG 該版區塊 |
| 2026-09-17 | [v0.2.3 發佈：release skill 補 GitHub Release 步驟](2026-09-17-release-v023.md) | `CHANGELOG.md` | 上一輪加的發佈步驟正式出貨；PATCH，套用端不用做事 |

> **這是上游 template 自己的索引**（出貨的是 `release/skeleton/tasks-README.md` ——
> 空表格）。上面幾列是上游拿自己當樣本留下的。
>
> `v0.1.0` 之前還有三份任務檔，在收斂發佈樹時從工作樹移除、**但沒有銷毀**（禁令 8）——
> 它們在 `2d24251` 之前的 git 歷史裡，本機就查得到：
>
> ```bash
> git log --diff-filter=D --name-only -- docs/tasks/
> git show 2d24251^:docs/tasks/2026-08-12-project-network-launcher.md
> ```
