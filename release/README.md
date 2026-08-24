# 這個目錄不出貨

只有上游 template 自己發佈時用得到，**不在產品檔清單裡**，所以不會被搬到 `main`。

| | |
|---|---|
| `release.sh` | 把 `dev` 的產品檔發佈到 `main` |
| `skeleton/` | `main` 上那三份空骨架的來源 |

為什麼骨架的來源在這裡而不是直接編輯 `main`：**`main` 是衍生物，不是分支** ——
它的每個檔案都從 `dev` 產生。在 `main` 上手改，下次發佈會被靜默覆蓋。

## 一次性設定（不是每次發佈）

- **repo → Settings → General → 勾 Template repository。**
  沒勾的話別人只能 clone、會拿到全部歷史與 `dev`，整套骨架設計空轉，
  而且**沒有任何症狀**。`release.sh` 每次都會去查這個開關並警告。
- `main` 設為 default branch（Template 只複製 default branch 的 HEAD）

完整流程與判準見 `release` skill；每次發佈的手動步驟由 `release.sh` 印出來。
