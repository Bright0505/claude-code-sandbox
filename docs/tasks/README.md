# 任務索引

按時間排序。**完成的不刪不移動** —— 依序讀下來是了解專案演進最快的方式。

計畫檔的骨架與強度判準見 `plan` skill。

| 日期 | 任務 | 涉及範圍 | 一句話 |
|---|---|---|---|
| 2026-09-02 | [sandbox 內可使用 docker 指令](2026-09-02-sandbox-docker-access.md) | `scripts/`、`Dockerfile.claude`、`sandbox.sh` | 經過濾 proxy 提供 docker 存取，不掛 socket |

> 空的。這裡放**你的專案**的任務計畫檔。
>
> 上游 template 自己的研發紀錄（三份任務檔）不隨產品出貨，但沒有銷毀 ——
> 在**上游 repo** `v0.1.0` 之前的 git 歷史裡。這份 repo 若是從 template 產生的，
> 本機不會有那段歷史（template 產物不帶 commit 歷史），要取回得去上游拿：
>
> ```bash
> git clone https://github.com/Bright0505/claude-code-sandbox /tmp/cc-sandbox-upstream
> git -C /tmp/cc-sandbox-upstream log --diff-filter=D -- docs/tasks/
> ```
