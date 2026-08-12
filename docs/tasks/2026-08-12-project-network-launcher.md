# 連接專案服務：從選用 overlay 升為一級功能

狀態：已完成（未 push）
強度：L2
日期：2026-08-12

## 目標

讓「sandbox 連到專案已啟動的服務跑測試」變成一行指令，並且**接不上時會明講**。

起因：一個 session 在 sandbox 內判定「no network/docker access to the live infra」，
把交接文件上多項工作標為 `literally not executable from here`。實際上服務全部
正常運行中，只是啟動時漏了 `docker-compose.claude.network.yml`。事故本體見
`docs/KNOWN-ISSUES.md` **K-5**。

機制本來就存在，問題在它的門檻：要正確用它得同時記住兩個 `-f`、`WORKSPACE_DIR`、
`APP_NETWORK_NAME`，而且舊版 README 還要求**專案去改自己的 `docker-compose.yml`**
把網路改名成 `app-net`。門檻高到實務上等於預設關閉；而漏掉時**沒有任何輸出**，
使用者只能用「環境壞了」來解釋。

## 範圍

包含：host 端啟動器、entrypoint 的狀態輸出、README 該章節改寫、事故紀錄。

不包含（維持既有安全立場，理由已在 README「設計重點」載明）：

- 不 mount `docker.sock`／不做 Docker-in-Docker
- 不放寬 `init-firewall.sh` 的對外網域白名單
- 不改 overlay 的網路加入機制本身 —— 它是對的，只是難用

## 驗收

1. **零設定可用**：專案服務起來後，不設任何環境變數執行 `./sandbox.sh` 即可接上
2. **不侵入專案**：不要求專案修改自己的 `docker-compose.yml`
3. **失敗會說話**：接不上時給的是「下一步做什麼」，不是 compose 的原始錯誤；
   沒接上網路時容器內會印出說明
4. **隔離未被破壞**：容器內仍無 `docker` CLI，對外白名單行為不變

## 假設（若不對請說）

- 專案的網路由 docker compose 建立，因此帶有 `com.docker.compose.project` label。
  不成立時走 `APP_NETWORK_NAME` 直接指定，已保留該出口
- compose project 名預設等於 `WORKSPACE_DIR` 的目錄名。專案有 `name:` 或設了
  `COMPOSE_PROJECT_NAME` 時不成立，已保留 `APP_COMPOSE_PROJECT` 出口
- 啟動器用 bash 3.2 相容寫法（macOS 內建 bash 仍是 3.2，`mapfile` 不可用）

## 變更清單

| ID | 檔案 | 變更性質 |
|---|---|---|
| C1 | `sandbox.sh` | 新增：host 端啟動器（WORKSPACE_DIR 推導、網路自動偵測、preflight） |
| C2 | `scripts/entrypoint.sh` | 新增 `print_network_summary`，兩條分支都呼叫 |
| C3 | `README.md` | 「連接專案自己的服務」整節改寫；目錄結構、Template 用法、submodule 章節同步 |
| C4 | `docker-compose.claude.network.yml` | 標頭註解改寫：移除「把網路改名 app-net」的舊流程 |
| C5 | `docs/KNOWN-ISSUES.md` | 新增 K-5 |
| C6 | `docs/tasks/README.md` | 索引補一列 |

## 驗證步驟

基線（改動前，已跑）：不帶 overlay 啟動，容器內三種症狀全部復現 ——
`getent hosts open-webui` NXDOMAIN、服務名 `curl` exit 6、直接打 IP exit 28、
`localhost:3000` exit 7；同時 `api.anthropic.com` 回 404（對外正常）、
`command -v docker` 為空（隔離正常）。

- [x] N1 preflight：compose project 不存在 → 列出三個可能原因 + 主機上的候選網路
- [x] N2 preflight：`APP_NETWORK_NAME` 指到不存在的網路 → 明確報錯
- [x] N3 preflight：同一 project 有多個網路 → 列出候選並要求指定
      （建兩個帶假 project label 的網路實測，測完移除）
- [x] P1 自動偵測：零設定執行 → `WORKSPACE_DIR=/Users/…/open-webui`（外層 repo，
      且該分支上 sandbox 目錄是 untracked 也偵測正確）、網路 `open-webui_ollama-network`
- [x] P2 容器內：`getent hosts open-webui` → `172.23.0.14`；`open-webui:8080/health` → 200；
      `mcp-health-products-http:8007/api/v1/health` → 200；`postgres:5432` TCP 可連
- [x] P3 容器內：entrypoint 印出「已接上專案網路 open-webui_ollama-network」
- [x] P4 未接網路時：entrypoint 印出兩行警告並明說「不是環境故障」，
      隨後的 `curl open-webui:8080` 如預期 exit 6
- [x] P5 隔離未破壞：`command -v docker` 為空、`api.anthropic.com` → 404（連得上）、
      `example.com` → exit 28（非白名單，被擋）、`localhost:3000` → exit 7
- [x] `docs/KNOWN-ISSUES.md` 結構檢查：`check_known_issues_links.py` 通過
- [x] bash 3.2 相容：本機 `env bash` 與 `/bin/bash` 都是 3.2.57，全部測試即在其上執行

## 完成紀錄

| # | 事實 | 影響 |
|---|---|---|
| 1 | 容器網段從 `172.19.0.x`（改前）變成 `172.23.0.15`（改後），`init-firewall.sh` 的既有子網段迴圈自動放行 | **防火牆一行都沒改** —— 原本就支援，缺的只是「有沒有加入網路」 |
| 2 | 根因不是白名單 —— `ipset allowed-domains` 只管對外 80/443；擋住東西向流量的是 `OUTPUT DROP` 加上子網段規則涵蓋不到 | 若誤判成白名單問題，會去改 `ALLOWED_DOMAINS`，那**完全無效**（服務名解析不出來，灌進 ipset 的是空值，且模組不在 80/443） |
| 3 | 失敗有兩層且症狀不同：解析不到是 `curl` exit 6，繞過 DNS 打 IP 是 exit 28（DROP 所以逾時，不是 refuse） | 這組 exit code 已寫進 README，可當快速判別依據 |
| 4 | `git rev-parse --show-superproject-working-tree` 在「已 clone 但當前分支未 track 該 submodule」時回空字串 | 改用父目錄 `--show-toplevel`，兩種情境都成立（實測） |

**沒做什麼**：

- `APP_NETWORK_NAME` 指向**非 compose 建立**的網路只驗過「不存在時報錯」，
  沒驗過「存在且非 compose 網路時能正常接上」
- 只在 macOS／Docker Desktop 上驗過，沒有在 Linux host 上驗
- 沒有處理「專案有多個網路且應該全部加入」的情境 —— 目前設計是一次一個網路，
  多網路時要求明確指定
