# sandbox 內可使用 docker 指令（經過濾 proxy）

狀態：已完成
強度：L2
日期：2026-09-02

## 目標

sandbox 容器內可以執行 `docker compose exec` / `logs` / `ps` / `restart` /
`up -d` / `build`，**而不掛載 host 的 `docker.sock`**。

判準是可觀察的：在 sandbox 內對一個已啟動的專案服務下 `docker compose exec <svc> <cmd>`
拿得到 stdout，而 `docker run -v /:/host alpine ls /host` 被拒絕。

## 範圍

**包含**：

- 一支持有 socket 的過濾 proxy（端點白名單 + `containers/create` 酬載驗證）
- sandbox image 內裝 docker CLI + compose plugin
- `sandbox.sh` 預設把 proxy 帶起來；entrypoint 印出目前的 docker 存取狀態
- host 端測試（不需要 docker）
- 更新 README 第 59 行那條「不提供 docker socket」的宣稱 —— **它會變成假的**

**不包含**：

- 讓 sandbox 能操作**別的專案**的容器（proxy 按 compose project label 限制）
- BuildKit（強制 `DOCKER_BUILDKIT=0`，只放行 `POST /build`）
- `docker pull`（`POST /images/create` 不放行 —— 能跑的 image 僅限本機已有或自己 build 的）
- 修改任何採用端專案的 `docker-compose.yml`

## 為什麼是 L2 不是 L3

拆得出兩個 phase（① exec/logs/ps/restart ② build/create），但兩者共用同一支 proxy
與同一套測試，而只出 ① 等於交付一個**仍會中斷迴圈**的東西 ——
正是這次要修的缺陷。分 phase 的成本大於收益。

## 驗收

1. sandbox 內 `docker compose exec <svc> php -v`（或等價指令）**印得出內容**，
   不是只有 exit 0（見下方 K-5 以外的踩坑紀錄）
2. sandbox 內 `docker compose up -d --force-recreate <svc>` 成功
3. sandbox 內 `DOCKER_BUILDKIT=0 docker build` 成功
4. sandbox 內建立含 `-v /:/host` 或 `--privileged` 的容器 **被 403 拒絕**
5. sandbox 內 `docker pull alpine` **被拒絕**
6. sandbox 內操作不屬於本專案的容器 **被拒絕**
7. `scripts/test-docker-api-proxy.py` 全綠，且每條規則有 mutation 轉紅紀錄
8. 啟動時無論 docker 存取開或關，**都印出一行說明**（K-5）

## 假設（若不對請說）

- **預設開啟**：`sandbox.sh` 啟動時預設帶起 proxy，`SANDBOX_DOCKER=0` 可關。
  理由是 K-5：選用機制沒有預設路徑就等於預設關閉。
  代價是這改變了既有使用者的安全姿態，所以用「每次啟動印出能做什麼」來補償，
  而不是靜默改預設。
- **proxy 腳本烘進 image，不用 bind mount**。理由：workspace 底下的檔案模型改得到
  （見 D10 實測），若 proxy 從 bind mount 載入腳本，模型可以改了它再透過
  白名單裡的 `restart` 重啟 proxy —— 護欄自己就被繞過了。
- **proxy 自己的容器不在可操作清單內**，即使它屬於同一個 compose project。
- 掛載白名單的根目錄取 `WORKSPACE_DIR`（`sandbox.sh` 已經推導好了）。

## 回查事故紀錄

`grep -n "docker\|network" docs/KNOWN-ISSUES.md` → **命中 K-5**。

K-5 的判準②直接適用：本次設計就是「留了一個選用機制」。避開方式：

- 做成 `sandbox.sh` 的預設路徑（不是要記得帶的旗標）
- `entrypoint.sh` 新增 `print_docker_summary()`，**開和關兩條路徑都印**
  —— 只在成功時印的話，「沒印」和「還沒跑到那裡」分不出來

## 變更清單

| ID | 檔案 | 變更性質 |
|---|---|---|
| C11 | `docker-compose.claude.docker.yml` | 追加：專用的 `sandbox-ctl` internal 網路；workspace 第二份掛載（與 host 同路徑）|
| C1 | `scripts/docker-api-proxy.py` | 新增：過濾 proxy 本體 |
| C2 | `Dockerfile.proxy` | 新增：proxy 的最小 image，腳本 COPY 進去 |
| C3 | `docker-compose.claude.docker.yml` | 新增：proxy 服務 + sandbox 的 `DOCKER_HOST` |
| C4 | `Dockerfile.claude` | 修改：裝 docker CLI + compose plugin |
| C5 | `scripts/entrypoint.sh` | 修改：新增 `print_docker_summary()` |
| C6 | `sandbox.sh` | 修改：預設帶起 proxy overlay，`SANDBOX_DOCKER=0` 可關 |
| C7 | `scripts/test-docker-api-proxy.py` | 新增：規則層測試，不需要 docker |
| C8 | `README.md` | 修改：第 59 行的宣稱已失效，改寫成新的邊界 |
| C9 | `CHANGELOG.md` | 修改：新版本條目 |
| C10 | `docs/DECISIONS.md` | 修改：D12 待決 → 已決議 |

## 驗證步驟

- [x] `python3 scripts/test-docker-api-proxy.py`（規則層，不需 docker）→ 52 checks passed
- [x] mutation：11 個 mutant 全數轉紅，且都由對應的斷言殺掉（一輪有存活，已修，見問題紀錄）
- [x] 兩個 image build 成功
- [x] 用樣本專案 `ggr` 實跑驗收 1～6，全數符合
- [x] regression：`test-init-firewall.sh` 15/0、`test-git-auth.sh` 42/0，與 HEAD baseline 相同

## 回退方式

單一 commit。還原後：sandbox image 需重 build（`docker compose -f
docker-compose.claude.yml build`），proxy 容器 `docker rm -f` 掉。
沒有持久化狀態，無資料層副作用。

## 完成紀錄

| 日期 | 項目 | commit | 驗證結果（實際觀察到什麼） |
|---|---|---|---|
| 2026-09-02 | C1～C11 全部 | 見本次 commit | 見下方「驗收對照」 |

### 驗收對照（樣本專案 `ggr`，macOS 15 / Docker Desktop 4.82 / Engine 29.6.1）

| # | 驗收項 | 實際輸出 |
|---|---|---|
| 1 | exec 有內容 | `PHP 8.2.33 (cli)`／`Composer version 2.3.10`／`Laravel Framework 11.56.1` |
| 2 | `up -d --force-recreate php1` | 成功，重建後 exec 仍可用 |
| 3 | `docker build`（legacy） | `Successfully tagged ggr-php1:sandbox-probe` |
| 4 | 拒絕 `-v /:/host` | `Binds: / is outside /Users/brightsu/git/ggr` |
| 4b | 拒絕 symlink 逃逸 | `.../escape-probe resolves outside ... (symlink)` |
| 4c | 拒絕 `--privileged` | `HostConfig.Privileged is not allowed` |
| 5 | 拒絕 `docker pull` | `endpoint not allowed: POST /images/create` |
| 6 | 拒絕其他專案容器 | `container outsider-probe belongs to project 'not-ggr', not 'ggr'` |
| 6b | 拒絕 `docker info` | `endpoint not allowed: GET /info` |
| 7 | 規則測試 + mutation | 52 passed；11 mutant 全紅 |
| 8 | 兩種狀態都印出 | 啟用時印可用／不可用清單；未啟用與連不上 proxy 各有不同輸出 |
| — | 允許 workspace 內掛載 | `docker run -v <workspace>:/w` 列出 `README.md`、`app` |

`docker.sock` 在容器內確認不存在（`ls: cannot access '/var/run/docker.sock'`）。

## 交付狀態

- **分支**：`feat/sandbox-docker-access`，已 push 到 `origin`。
  **沒有直接 commit 在 `dev` 上**（禁令 1：不在主幹 commit）。
- **沒有開 PR**，也**沒有合進 `dev`** —— 這個 repo 的歷史顯示 docs 類改動
  直接落在 `dev`，但歷史不構成核准的先例（`deliver` §1），而「要不要合進主幹」
  是使用者的決定，不是執行者可以順手做的。
- **套用端要怎麼拿**：這個 repo 被當 submodule 掛進其他專案，所以在那邊
  `git -C <submodule> fetch && git -C <submodule> checkout feat/sandbox-docker-access`，
  然後 `docker compose -f docker-compose.claude.yml -f docker-compose.claude.docker.yml build`
  重建兩個 image。合進 `dev` 之後就改用 `dev`。
- **沒有更新任何主 repo 的 submodule pin** —— 這個 commit 還沒進 `main`，
  釘一個尚未穩定的參照會記錄一個不穩定的狀態（`deliver` §4）。

## 問題紀錄

| 日期 | 問題 | 根因 | 處理 | 已升級到 KNOWN-ISSUES？ |
|---|---|---|---|---|
| 2026-09-02 | 量測用轉發器：`compose exec` exit 0 但 stdout 全空 | 雙向轉發過早 shutdown | 對照直連 socket 與 tecnativa 才定位 | 待 proxy 有守備測試後升級 |
| 2026-09-02 | 端點清單漏九成但外觀正常 | 只解析每條連線第一個請求，docker CLI 用 keep-alive | 改成掃描整個位元流；加筆數斷言 | **是 → K-7** |
| 2026-09-02 | proxy 白名單正確，但 `docker pull` 與 inspect 其他專案容器都成功 | 同上的根因，犯在 proxy 自己身上：批准第一個請求後轉為原樣轉發，第二個請求穿透 | 非 upgrade 請求強制 `Connection: close`，且不轉發 client→daemon 方向 | **是 → K-7** |
| 2026-09-02 | mutation 有一個存活：拿掉字面包含檢查仍全綠 | 斷言用的關鍵字 `outside` 同時出現在字面與 symlink 兩種拒絕訊息裡 | 關鍵字改成 `is outside`／`(symlink)`，重跑後轉紅 | 否 —— 判準已寫進測試檔的 docstring |
| 2026-09-02 | sandbox 連不到 proxy（DNS 解析不到） | overlay 給 claude-sandbox 指定 `networks:` 後，它不再在 default 網路上，與 proxy 分屬兩個網路 | 加一個兩者共用的 `sandbox-ctl` internal 網路 | 否 —— entrypoint 的探測當場就報出來了，不是靜默失敗 |
| 2026-09-02 | `up -d` 被自己的規則擋下 | 一律拒絕 `CapAdd`，但樣本專案正當使用 `SYS_PTRACE` | 改成 denylist（見 D12 決議） | 否 —— 已寫進 D12 |
