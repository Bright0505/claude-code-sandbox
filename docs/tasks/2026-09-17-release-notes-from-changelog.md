# 發佈流程補上 GitHub Release，內容從 CHANGELOG 擷取

狀態：已完成
強度：L1
日期：2026-09-17

## 目標

`v0.2.2` 發佈後，使用者指出 GitHub 上只看到裸 tag（顯示 `release: v0.2.2` 這句
commit 訊息），對照另一個專案有分類清楚（Features／Bug Fixes，帶 commit 連結）
的 GitHub Release 頁面，問能不能比照辦理。

判斷：不能直接套用 conventional-commit 自動分類（`gh release create
--generate-notes`）——那是抓兩個 tag 之間、`main` 上的 commit 自動分類，
而這個 repo 的模型下 `main` 兩個 tag 之間永遠只有一個 `release: vX.Y.Z`
commit（`release` skill §8：`main` 是衍生物，每次發版一個 commit）。用它只會
得到一行沒有資訊量的清單。真正的變更內容已經整理在 `CHANGELOG.md` 的版本區塊
（§6：版號語意只放一份），所以正確做法是把那個區塊擷取出來餵給
`gh release create --notes-file`，而不是另外手打或改抓 commit。

## 範圍

**包含**：`release/release.sh`（剩餘手動步驟新增一步）、
`.claude/skills/release/SKILL.md`（§8 補說明與擷取指令、全貌表補一格）。

**不包含**：

- **補發 `v0.2.2` 的 GitHub Release**——這次的改動只影響「下一次發版」，
  不回頭幫已經發過的 `v0.2.2` 建 Release。要補的話是使用者自己決定
- **`gh release create` 沒有實際跑過**（見「沒做什麼」）

## 變更清單

| ID | 檔案 | 變更性質 |
|---|---|---|
| N1 | `release/release.sh` | 剩餘步驟新增「5. 建 GitHub Release」，用 `awk` 精確比對 `"## $VERSION"` 擷取該版 CHANGELOG 區塊；原步驟 5／6 順延為 6／7 |
| N2 | `.claude/skills/release/SKILL.md` | §8 補一節「GitHub Release 的內容從 CHANGELOG.md 擷取，不要另外手打」，講清楚為什麼不用 `--generate-notes`；「一次發佈的全貌」表格補「建 GitHub Release」 |

## 驗證步驟

- [x] `awk` 擷取邏輯獨立測試：對 `CHANGELOG.md` 跑
      `awk -v ver="## v0.2.2" '$0==ver{f=1;next} f&&/^(## |---)/{exit} f' CHANGELOG.md`，
      輸出恰好是 `v0.2.2` 那個區塊（`**README 與 .env.claude.example 補正...**`
      開頭，到「已知未驗」兩點結束），沒有多抓到 `v0.2.1` 的內容
- [x] heredoc 變數替換獨立測試：把 `release.sh` 新增那段抽出來单獨跑一次，
      確認 `$VERSION` 被展開成實際版號、`\$0` 印出來是字面上的 `$0`
      （不是被當成腳本自己的 `$0` 展開）
- [x] `release.sh` 語法：`bash -n release/release.sh` 通過
- [ ] 沒有實際對一個真的版本跑過 `gh release create`（見「沒做什麼」）

## 回退方式

單一 commit（`913e12a`），只動 `release/release.sh` 與 `SKILL.md` 各一段，
`git revert` 即可，不影響已發佈的 `v0.2.2`。

## 交付狀態

**尚未合併**——在分支 `docs/release-notes-from-changelog` 上，等使用者 push 並
開 PR 合併進 `dev`（禁令 1／2）。下一次真的發版時才會第一次實際跑到這個步驟。

## 沒做什麼

- **沒有補發 `v0.2.2` 的 Release**——範圍排除，見上方「範圍」
- **沒有實際跑一次 `gh release create`**——這台環境沒有已經打好、還沒建
  Release 的 tag 可以拿來測；`awk` 擷取邏輯與 heredoc 展開各自獨立驗證過，
  但兩者串起來、真的打進 GitHub 的那個動作沒有實跑過。下一次發版是這個功能
  第一次被真的用到，屆時若擷取結果跟預期不同（例如某版 CHANGELOG 區塊格式
  跟其他版不一致），會是這裡沒驗到的部分
- **沒有處理「怎麼補發已經發過的版本的 Release」這個一般性問題**——只解決
  「下一次發版」，過去的 `v0.1.0`／`v0.1.1`／`v0.2.0`／`v0.2.1`／`v0.2.2`
  都還是裸 tag
