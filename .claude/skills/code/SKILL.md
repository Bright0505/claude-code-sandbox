---
name: code
description: 寫程式碼 — 改既有程式碼的五個檢查點：impact analysis 讀 implementation、逐 call site 驗證、dead code elimination、mutation testing、防 scope creep。展開 CLAUDE.md 鐵則 1-3 在「動手寫程式碼」這個場景的落地。當要改既有函式/類別的呼叫方式、跨多個檔案套用同一種改法、或改動觸發了看似不相關的既有問題時使用。
---

# 寫程式碼

`CLAUDE.md` 已定義鐵則 1-3。`verify` 講「怎麼證明改對了」，
本 skill 講**動手前怎麼確認改法是對的，以及過程中怎麼守住範圍**。

五個檢查點，按時間順序排。

---

## 1. Impact analysis：讀 implementation，不讀 spec

Spec（migration guide、release note、型別標註）講的是**宣告的契約**，
implementation 才是**實際接受什麼**。兩者的落差直接決定影響範圍大小。

凡是**會讓範圍變動一倍以上**的關鍵假設，讀一次實作再定案。

> 實例：spec 說 handler 要回傳框架自己的物件，照字面理解得重寫整個邏輯層；
> 讀序列化函式才發現它接受裸 dict —— 範圍從 6+ 檔收斂回 3 檔。

---

## 2. Syntactic similarity ≠ semantic equivalence

同一種改法套 N 個 call site，只降低了「猜改法對不對」的成本，
**不能把 full verification 降級成 spot check** —— 長得一樣的地方，
可能各自帶著只有那裡才有的語意差異。

> 實例：三個入口套同一種 handler 改法，前兩個原本就回傳 dict 直接過；
> 第三個是獨立寫的重複邏輯、回傳裸 list，序列化層直接拒收。

---

## 3. Dead code elimination

改動簽名或呼叫方式，會讓支撐舊寫法的 import／型別／分支變成 unreachable，
而它們**不會主動報錯**。改完掃一次該檔頂部，交給 linter 確認 ——
規則通常本來就開著，但沒跑就會進 commit。

---

## 4. Mutation testing：用 VCS 取回舊版當 mutant

`verify` 要求新測試要故意弄壞一次確認轉紅。改既有程式碼時，
最可靠的 mutant 不是手寫的變體，是**真正的舊版**：

```bash
git checkout <base> -- <檔案>   # 舊版即 mutant
# 跑新測試 → 應該全紅
git checkout HEAD -- <檔案>     # 還原 → 應該全綠
```

手寫的「假設會失敗」變體是腦補出來的近似版，會失真。
**確認 mutant 是為了正確的理由被 killed** —— 失敗訊息要對得上預期，
不是隨便哪裡壞了也算數。

---

## 5. 防 scope creep：判準是 Definition of Done

改一個地方時順手發現的既有問題，判準只有一條：
**它會不會擋住「這次改動」的 DoD？**

| 情況 | 動作 |
|---|---|
| 擋住 DoD | 這次修 |
| 不擋 | 只記錄，不動手 |

是不是這次造成的，用 `git show <base>:<檔案>` 查證，不要憑感覺。
不擋 DoD 卻順手修下去，就是 scope creep 在無聲發生。
