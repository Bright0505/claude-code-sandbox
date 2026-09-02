# 事故紀錄

**未來任務需要知道的坑。** 只記「下一個碰到這塊的人，不知道這件事會不會出事」的問題 ——
判準、格式、狀態語意、歸檔規則全部見 `record` skill，本檔不重述。

開工前用**要改的檔名**和**功能名**各 grep 一次：

```bash
grep -n "<檔名>" docs/KNOWN-ISSUES.md
```

ID 單一系列 `K-<n>`，遞增，**永不重用**。執行者自己的失誤也記。

> **這是上游 template 自己的事故紀錄，不出貨。** 出貨的是
> `release/skeleton/KNOWN-ISSUES.md` —— 空骨架，套用端的編號從 `K-1` 開始。
> 本檔用到 `K-7`（K-1～K-4、K-6 的判準都已升級進 skill 後移除，編號不重用）。

---

### K-5 機制存在但預設路徑難用，於是「沒啟用」被誤判成「環境故障」

- **影響範圍**：`sandbox.sh`、`docker-compose.claude.network.yml`、
  `scripts/entrypoint.sh`；以及任何「留了選用機制但沒做成預設路徑」的設計
- **狀態**：已修
- **守備**：`scripts/entrypoint.sh`::`print_network_summary` —— 兩種狀態都會印出一行，
  「沒接上網路」不再是無聲的。`sandbox.sh` 則讓接上網路變成預設路徑
- **症狀**：一個 session 在 sandbox 內判定「no network/docker access to the live
  infra」，據此把交接文件上多項工作標為 `literally not executable from here`，
  並要求使用者改變工作方向。實際上專案服務全部正常運行中 —— 只是 sandbox 啟動時
  漏了 network overlay。實測三種症狀同時出現：服務名 `curl` exit 6（解析不到）、
  直接打 IP exit 28（逾時，封包被 `OUTPUT DROP`）、`localhost:<host port>` exit 7
- **根因**：兩層。表層是要正確啟動得同時記住兩個 `-f`、`WORKSPACE_DIR`、
  `APP_NETWORK_NAME` 四件事，且舊版 README 還要求專案改自己的 compose 把網路
  改名 —— 選用機制的門檻高到實務上等於預設關閉。深層是**這個失敗沒有任何輸出**：
  沒有錯誤、沒有警告，只有「什麼都連不到」。而「什麼都連不到」最自然的解釋
  就是環境壞了，不是「我少帶了一個參數」
- **判準**：
  ① 判定「環境沒有 X 能力」之前，先確認**自己處在哪個環境切面** ——
  容器內先看 `ip -4 -o addr show` 的網段、對照目標服務的網段，再下結論
  ② 設計面：**選用機制若沒有預設路徑，就要有失敗時的明確輸出**。
  兩者都缺時，使用者會用「整個壞了」來解釋，而那個解釋會擴散成錯誤的工作決策
  ③ 自檢訊號：**結論是「這件事做不到」而不是「這件事失敗了」** ——
  前者是能力判斷，需要比後者更強的證據
- **關聯**：無同形態條目。本則是**執行環境**的失效（不是規範文件自己的失效形態）
- **日期**：2026-08-12

---

### K-7 HTTP keep-alive 讓「一條連線一個請求」的假設靜默失效

- **影響範圍**：`scripts/docker-api-proxy.py`（HTTP 轉發層）；以及任何
  「解析第一個請求後就把 socket 原樣轉發」的 proxy／記錄器
- **狀態**：已修
- **守備**：`scripts/test-docker-api-proxy.py`::`force_close appends Connection: close`
  ／`force_close drops keep-alive headers`
  （mutation 驗證：把 `force_close` 拿掉、改回原樣轉發 → 三條斷言轉紅）
  以及 `Handler._exchange` 對非 upgrade 請求**不轉發 client→daemon 方向**
- **症狀**：同一個錯誤在同一個 session 內犯了兩次，兩次都無聲：
  ① 量測用的記錄器只記到每條連線的第一個請求，於是 `docker compose up -d`
  的端點清單只剩一個 `HEAD /_ping`。那份清單**格式正常、看起來完整**，
  漏了九成，差點被當成決策依據
  ② 過濾 proxy 的端點白名單完全正確，但只作用在第一個請求上。實測
  `docker pull`（`POST /images/create`，不在白名單）與 `docker inspect`
  一個屬於其他 compose project 的容器，**兩者都成功** —— 因為 docker CLI
  先送 `HEAD /_ping`，通過之後第二個請求走原樣轉發的 socket 穿透過去
- **根因**：docker CLI 對同一個 daemon 重用 TCP 連線。`scripts/docker-api-proxy.py`
  原本讀完第一個請求就把兩個方向交給 raw relay，而 relay 不認識 HTTP 邊界
- **判準**：
  ① **驗 proxy／過濾器一定要測「該被拒絕」的案例**，而且要測在
  **同一條連線的第二個請求**上。只測允許案例時，一個完全失效的護欄
  會呈現 100% 綠燈 —— 允許案例本來就該過
  ② 攔截層若要「批准後轉為原樣轉發」，先問**這條連線之後還能不能出現
  新的請求**。能就是漏洞。可行的收法有兩個：強制 `Connection: close`，
  或不轉發 client→server 那個方向（本檔兩個都做）
  ③ 量測工具本身要有**可否證的計數斷言**。「解析不到東西 → 0 筆 → 綠燈」
  是這類腳本最常見的死法（修正後同一批指令從 5 筆變 44 筆）
- **關聯**：與 K-5 同屬**失敗沒有任何輸出**的形態，但失效的層不同 ——
  K-5 是機制沒啟用，本則是機制啟用了卻只覆蓋一部分輸入
- **日期**：2026-09-02
