# 任務索引

按時間排序。**完成的不刪不移動** —— 依序讀下來是了解專案演進最快的方式。

計畫檔的骨架與強度判準見 `plan` skill。

| 日期 | 任務 | 涉及範圍 | 一句話 |
|---|---|---|---|
| 2026-09-02 | [sandbox 內可使用 docker 指令](2026-09-02-sandbox-docker-access.md) | `scripts/`、`Dockerfile.claude`、`sandbox.sh` | 經過濾 proxy 提供 docker 存取，不掛 socket |
| 2026-09-02 | [容器內 agent 看不到開機才印的 docker workspace 指引](2026-09-02-agent-workspace-visibility.md) | `CLAUDE.md`、`docs/KNOWN-ISSUES.md` | 同一份印出來的指引，套用端真實使用時對「容器內的 agent」這種讀者等於沒印過 |
| 2026-09-03 | [v0.2.0 發佈：稽核擋下的三類問題](2026-09-03-release-v020-audit.md) | `release/release.sh`、`release` skill、`CHANGELOG.md`、出貨檔的註解 | 產品檔白名單漏掉這一版的主要交付，而三道守衛全綠；稽核指令的範圍也比出貨範圍窄 |

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
