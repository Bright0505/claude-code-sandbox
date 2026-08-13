# 任務索引

按時間排序。**完成的不刪不移動** —— 依序讀下來是了解專案演進最快的方式。

計畫檔的骨架與強度判準見 `plan` skill。

| 日期 | 任務 | 涉及範圍 | 一句話 |
|---|---|---|---|
| 2026-08-11 | [skill 收斂：案例集 → 步驟](2026-08-11-skill-case-to-step.md) | `.claude/skills/` 六份 | 讓 skill 成為可執行的步驟，而不是案例的累積；階段 1 以 `code` 試點 |
| 2026-08-12 | [連接專案服務：從選用 overlay 升為一級功能](2026-08-12-project-network-launcher.md) | `sandbox.sh`、`entrypoint.sh`、`README.md` | 選用機制門檻太高＋失敗無輸出，導致「沒啟用」被誤判成「環境故障」 |
| 2026-08-13 | [GitHub / GitLab token 認證](2026-08-13-git-forge-token-auth.md) | `Dockerfile.claude`、`scripts/` 五支、`.env.claude.example`、`README.md` | 只靠 `.env.claude` 的 PAT 就能在容器內 commit + push；token 不落地 |
