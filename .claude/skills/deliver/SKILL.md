---
name: deliver
description: 交付 — commit、branch、push、PR、submodule 的操作規範。atomic commit 的切分判準、convention 與既有實踐衝突時怎麼處理、git identity 不落地、submodule 當獨立 repo 對待、push 前先探測能力。展開 CLAUDE.md 禁令 1-3、6。當要 commit、開分支、push、開 PR/MR、或改動涉及 submodule 時使用。
---

# 交付

`CLAUDE.md` 已定義相關禁令。本 skill 是它們在具體動作上的展開，**不重述禁令本身**。

---

## 1. 發現規範與既有實踐不一致時：policy over convention

歷史 commit 違反禁令（例如直接上 `main`），**不構成核准的先例** ——
git log 記錄的是「當時發生過什麼」，不是「規範允許什麼」。兩者容易混淆，
因為都被說成「這個 repo 一直是這樣做」。

發現落差時，兩個直覺反應都不對：

- 沿用歷史模式（把既有違規當先例）
- 自己默默改成合規做法（單方面改變工作方式，同樣是需要先講的決定）

**正確做法是把落差攤開，列出選項讓使用者選。**

---

## 2. 切 commit 與 branch 時：atomicity

禁令 6 展開到 branch 層一樣成立。判準不是檔案數，是**能不能獨立 revert**：

| 情況 | 切不切 |
|---|---|
| 兩個改動各自有獨立的「為什麼」 | **切開**（各自一個 branch + commit） |
| 功能 + 該功能的測試 | **不切** —— 沒有測試那個功能不成立 |
| 主要改動 + 一個**本身就通用**的配套（忽略規則、格式設定）| **切開** —— 它即使沒有主要改動也站得住 |

---

## 3. 缺 git identity 時：用 `-c` 帶入，不落地

即使 commit 因此失敗，**都不要修改 git config**（local 或 global 都算）。

```bash
git -c user.name="..." -c user.email="..." commit -m "..."
```

身分來源：① 同一 workspace 其他 repo 已在用的（同一個人做的事沒理由用不同身分）
② 查不到就問，不要自己編。

---

## 4. 動到 submodule 時：當它是獨立 repo

Submodule 有自己的 remote、自己的 `main`、自己的歷史。**所有規則原樣套用一次**：

- 它的 `main` 一樣受禁令 1 保護 —— 開自己的 branch
- 改動性質不同時，它裡面也要切開
- **先查 remote owner**（`git -C <submodule> remote -v`）：使用者自己的 repo 可以動；
  真正的第三方套件不要碰。兩者外觀都是 submodule，**只能從 owner 區分**

### gitlink 顯示 dirty 時

在 submodule 裡 commit 後，主 repo 會顯示 `M <submodule目錄>`。
**這是預期行為**，但兩件事不要做：

1. **不要順手把新 commit 釘進主 repo** —— 除非該 commit 已 push 且合併進它自己的
   `main`。釘一個還在本機、隨時可能被 rebase 的 commit，等於記錄一個不穩定的參照
2. **不要放著不解釋** —— 在任務紀錄寫清楚：多了哪些 branch／commit、
   為什麼主 repo 沒更新 pin、之後怎麼推進

---

## 5. Push 與 PR 前：逐次確認，先探測能力

**授權不可沿用。** 「上次類似操作同意過」不等於這次同意 ——
尤其 push／開 PR 這類外部可見的動作。同一個任務裡，
使用者對同一件事在不同時間點可能給出不同答案。每次都當新的一次問。

**PR 顆粒度對齊 branch 顆粒度**：不相關的 branch 開不同 PR，
review 與 revert 的顆粒度要跟改動一致。

**先探測再承諾**（做法見 `verify` §5）。做不到就直接說缺什麼，不要繞過 ——
**憑證不進對話**，理由與禁令 4 同源：一旦出現在非受控管道就製造了洩漏面。

做不到時檢查**替代路徑**而不是卡住：容器化環境常見的是 bind mount ——
容器裡的 commit 已真實存在於主機檔案系統，使用者可在主機端用自己的憑證完成 push。

---

## 收尾：跨 repo 狀態要交代

- [ ] 跨到 submodule 的話，那邊的 branch 狀態乾淨嗎（訊息清楚、無建置產物殘留）
- [ ] gitlink 顯示 dirty 的原因與現況，寫進任務檔了嗎
- [ ] push／PR 的決定（做了／沒做／為什麼）寫進任務檔了嗎 ——
      **對話會被 compact，任務檔不會**
