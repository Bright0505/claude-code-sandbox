# Claude Code Sandbox

給 Claude Code 專用的隔離執行環境。這個 repo 是 template:`Dockerfile.claude` 只負責 Claude Code 自己的 sandbox,跟語言/框架無關;實際專案的執行環境(`Dockerfile`、`docker-compose.yml`)由套用此 template 的專案自行準備。

## 目錄結構

```
Dockerfile.claude                  Claude Code sandbox image
docker-compose.claude.yml          啟動 sandbox 的主要 compose 檔
docker-compose.claude.network.yml  選用 overlay：讓 sandbox 加入專案自己的網路
scripts/init-firewall.sh           容器啟動時設定的網路白名單
scripts/entrypoint.sh              root 設定防火牆後降權為非 root 使用者
.env.claude.example                ANTHROPIC_API_KEY 範本
.claude-config/                    (執行時產生) 專案專屬的 Claude Code 設定/登入狀態
```

## 快速開始

```bash
cp .env.claude.example .env.claude   # 填入 ANTHROPIC_API_KEY
docker compose -f docker-compose.claude.yml run --rm claude-sandbox claude
```

第一次登入的 session 會存在專案內的 `.claude-config/`,不會動到主機全域的 `~/.claude`,也不會跟其他專案共用。`.claude-config/` 與 `.env.claude` 都已加入 `.gitignore`,不會被提交。

## 設計重點

- **基底**：`node:24-bookworm-slim`(Node 24 LTS)。Claude Code CLI 本身是 Node 程式,因此不論專案語言是什麼,sandbox 都需要 Node——這跟專案自己的執行環境版本無關。
- **非 root 使用者**：容器以 `claude`(uid/gid 1000)執行實際指令,只有防火牆設定階段短暫使用 root。
- **網路白名單**：`init-firewall.sh` 預設擋掉所有對外連線,只放行 Claude Code 實際需要的網域(Anthropic API、GitHub、npm、PyPI 等)。任何未列在白名單的網域一律被擋。
- **不提供 docker socket / Docker-in-Docker**：sandbox 內刻意不能執行 `docker build`/`docker compose up` 之類的指令。掛載 host 的 `docker.sock` 等同給予 host root 權限,會讓前述的防火牆與非 root 隔離全部失去意義。專案自己的容器建置/啟動應該在 sandbox 外(人工或 CI)執行。

## 連接專案自己的服務(跑測試)

如果專案已經用自己的 `docker-compose.yml` 啟動了 API、DB 等服務,想讓 sandbox 連過去執行測試,可以用 `docker-compose.claude.network.yml` 這個選用 overlay:

1. 專案的 `docker-compose.yml` 把網路取一個固定名稱,不依賴 compose 專案/目錄名稱:
   ```yaml
   networks:
     default:
       name: app-net
   ```
2. 啟動專案本身：
   ```bash
   docker compose -f docker-compose.yml up -d
   ```
3. 啟動 sandbox 並加入同一個網路：
   ```bash
   docker compose -f docker-compose.claude.yml \
                  -f docker-compose.claude.network.yml \
                  run --rm claude-sandbox bash
   ```
   容器內可以用服務名稱當 hostname,例如 `curl http://api:3000/health`。

網路名稱預設是 `app-net`,可用 `APP_NETWORK_NAME=my-net` 覆寫。`init-firewall.sh` 只會放行 sandbox 實際加入的網路子網段,不會因此打開整個私有網段(RFC1918),對外連線的白名單規則不受影響。

## Template 用法

套用這個 template 的專案，只需要:

1. 保留 `Dockerfile.claude`、`docker-compose.claude.yml`、`docker-compose.claude.network.yml`、`scripts/` 原樣（跟語言無關，不需修改）。
2. 依專案實際的語言/框架，另外撰寫自己的 `Dockerfile`、`docker-compose.yml`（可選擇性搭配上方「連接專案自己的服務」章節，讓 sandbox 連得到）。
3. 需要調整白名單網域時，編輯 `scripts/init-firewall.sh` 裡的 `ALLOWED_DOMAINS`。
