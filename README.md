# Claude Code Sandbox

給 Claude Code 專用的隔離執行環境。這個 repo 是 template:`Dockerfile.claude` 只負責 Claude Code 自己的 sandbox,跟語言/框架無關;實際專案的執行環境(`Dockerfile`、`docker-compose.yml`)由套用此 template 的專案自行準備。

## 目錄結構

```
ONBOARDING.md                      開發規範 — 新人手冊（給人讀一次）
CLAUDE.md                          開發規範 — 執行版（給 Claude 常駐）
sandbox.sh                         啟動器（host 端）：自動偵測專案網路後啟動 sandbox
Dockerfile.claude                  Claude Code sandbox image
docker-compose.claude.yml          啟動 sandbox 的主要 compose 檔
docker-compose.claude.network.yml  選用 overlay：讓 sandbox 加入專案自己的網路
scripts/init-firewall.sh           容器啟動時設定的網路白名單
scripts/entrypoint.sh              root 設定防火牆後降權為非 root 使用者，並印出網路狀態
scripts/setup-git-auth.sh          啟動時把 .env.claude 的 token 變成可用的 git 設定
scripts/git-credential-env.sh      git credential helper：只從環境變數回答，token 不落地
scripts/git-forge-lib.sh           GitHub/GitLab 的 host 與 token 環境變數解讀（三個腳本共用）
scripts/test-git-auth.sh           上面三支的測試（不需要 docker）
scripts/test-init-firewall.sh      白名單組成的測試（用 stub 蓋掉 iptables，不動真網路）
.env.claude.example                ANTHROPIC_API_KEY 與 GitHub/GitLab token 範本
.claude-config/                    (執行時產生) 專案專屬的 Claude Code 設定/登入狀態
```

這個 template 提供兩樣獨立的東西，可以只用其中一樣：

| | 內容 |
|---|---|
| **執行環境** | `Dockerfile.claude` + compose 檔 + `scripts/`：隔離的容器、網路白名單、非 root |
| **開發規範** | `ONBOARDING.md` + `CLAUDE.md`：委託／執行／驗收的共同紀律 |

## 快速開始

支援兩種驗證方式,擇一即可:

**方式一:Claude 訂閱帳號登入(不需要 API key)**

```bash
docker compose -f docker-compose.claude.yml run --rm claude-sandbox claude auth login
```

`.env.claude` 是選用的(`env_file` 已設為 `required: false`),不存在也能正常啟動。照著終端機印出的網址在主機瀏覽器上完成登入、貼回驗證碼即可,不需要對外開任何 port。

**方式二:Anthropic Console API key**

```bash
cp .env.claude.example .env.claude   # 填入 ANTHROPIC_API_KEY
docker compose -f docker-compose.claude.yml run --rm claude-sandbox claude
```

不論用哪一種方式,登入後的 session 都會存在專案內的 `.claude-config/`,不會動到主機全域的 `~/.claude`,也不會跟其他專案共用。`.claude-config/` 與 `.env.claude` 都已加入 `.gitignore`,不會被提交。

## 設計重點

- **基底**：`node:24-bookworm-slim`(Node 24 LTS)。Claude Code CLI 本身是 Node 程式,因此不論專案語言是什麼,sandbox 都需要 Node——這跟專案自己的執行環境版本無關。
- **非 root 使用者**：容器以 `claude`(uid/gid 1000)執行實際指令,只有防火牆設定階段短暫使用 root。
- **網路白名單**：`init-firewall.sh` 預設擋掉所有對外連線,只放行 Claude Code 實際需要的網域(Anthropic API、`platform.claude.com` 登入/token 交換、GitHub、GitLab、npm、PyPI 等)。任何未列在白名單的網域一律被擋。`.env.claude` 裡設的 `GITLAB_HOST`／`GITHUB_HOST`（自架站台）會自動加進白名單,其他網域用 `EXTRA_ALLOWED_DOMAINS` 追加,兩者都不需要改這個檔案。解析不到的網域會印出警告——否則症狀會是連線逾時,讀起來像服務或憑證壞掉。
- **不提供 docker socket / Docker-in-Docker**：sandbox 內刻意不能執行 `docker build`/`docker compose up` 之類的指令。掛載 host 的 `docker.sock` 等同給予 host root 權限,會讓前述的防火牆與非 root 隔離全部失去意義。專案自己的容器建置/啟動應該在 sandbox 外(人工或 CI)執行。

## 在容器內 commit / push（GitHub 與 GitLab）

把 token 填進 `.env.claude`，容器內就能直接 `git push`，`gh` 與 `glab` 兩個 CLI 也同時可用：

```bash
cp .env.claude.example .env.claude    # 填 GITHUB_TOKEN / GITLAB_TOKEN 與身分
./sandbox.sh
```

需要的設定只有四項（其餘皆選用，全部見 `.env.claude.example`）：

| 變數 | 用途 |
|---|---|
| `GITHUB_TOKEN` | GitHub PAT。classic 要 `repo` scope；fine-grained 要 Contents: Read and write |
| `GITLAB_TOKEN` | GitLab PAT。要 `write_repository`；要用 `glab` 開 MR 再加 `api` |
| `GIT_USER_NAME` | commit 的作者名。**兩個都設才生效** |
| `GIT_USER_EMAIL` | commit 的作者信箱 |

啟動時會印出實際生效的狀態，例如：

```
sandbox: git 認證 GitHub (github.com)：已載入 token（長度 40，username x-access-token）
sandbox: git 認證 GitLab (gitlab.com)：未設定 token —— push 會要求帳號密碼
sandbox: git 身分：Your Name <you@example.com>
```

**沒設就會明講**，因為「token 沒生效」的下游症狀（跳出帳密提示、或連線逾時）跟環境故障
長得一樣 —— 同一類誤判的紀錄見 `docs/KNOWN-ISSUES.md` **K-5**。

### 幾個要知道的行為

- **走 HTTPS，不走 SSH。** 防火牆只放行 80/443，容器內連不到 port 22，所以 `git@github.com:...`
  形式的 remote 會被自動改寫成 `https://github.com/...`（設 `SANDBOX_GIT_REWRITE_SSH=0` 可關掉）
- **token 不落地。** 憑證由 `git-credential-env.sh` 直接從環境變數回答，不寫
  `~/.git-credentials`、不寫進 `.gitconfig`；`~/.gitconfig` 本身也在容器內，不會回寫主機
- **自架站台**只要設 `GITLAB_HOST` / `GITHUB_HOST`（填 host 或完整 URL 都可以），
  防火牆會自動放行該網域。要放行其他網域用 `EXTRA_ALLOWED_DOMAINS`，不必改 `init-firewall.sh`
- **自架 GitLab 的 `glab` CLI 需要多一步**：實測 `GITLAB_TOKEN` 只有預設 host（gitlab.com）
  會被 `glab` 認得，自架站台要在容器內執行 `glab auth login --hostname <host>`。
  `git push` 不受影響 —— 它走的是 credential helper，跟 `glab` 無關
- **本體有更新過 image 內容時要重新 build**：`docker compose -f docker-compose.claude.yml build`

改動這些腳本後可以直接驗，不需要 docker：

```bash
./scripts/test-git-auth.sh        # credential helper 與啟動設定
./scripts/test-init-firewall.sh   # 白名單組成（iptables 被 stub 蓋掉，不動真網路）
```

## 連接專案自己的服務(跑測試)

如果專案已經用自己的 `docker-compose.yml` 啟動了 API、DB 等服務，想讓 sandbox 連過去執行測試，用 `sandbox.sh` 啟動：

```bash
docker compose -f docker-compose.yml up -d   # 專案服務先起來
./sandbox.sh                                 # 或 ./sandbox.sh bash 取得 shell
```

它做三件手動下指令時最容易漏掉的事：推導 `/workspace` 要掛哪個目錄（submodule 情境自動取主專案根目錄）、照 compose 打在網路上的 `com.docker.compose.project` label 反查專案網路、以及**接不上時直接說下一步做什麼**（服務沒起來？project 名跟目錄名不同？）。

**不需要為此修改專案自己的 `docker-compose.yml`** —— 網路名靠 label 反查，不必取固定名稱。

推導結果一律印出來，每一項都可以用環境變數覆寫：

| 變數 | 用途 |
|---|---|
| `WORKSPACE_DIR` | 掛進 `/workspace` 的目錄 |
| `APP_NETWORK_NAME` | 直接指定網路名，跳過自動偵測（網路不是 compose 建的時候用）|
| `APP_COMPOSE_PROJECT` | 專案的 compose project 名，供自動偵測使用。專案 compose 有 `name:` 或設了 `COMPOSE_PROJECT_NAME` 時會跟目錄名不同 |

### 容器內要用服務名 + **內部** port

容器內的 `localhost` 指的是容器自己，不是 host，所以 host 上發布的 port 一律連不到。要用服務名，而且 port 要用容器內部那個：

| 在 host | 在容器內 |
|---|---|
| `localhost:3000` | `web:8080` |
| `localhost:5432` | `postgres:5432` |

### 手動疊 overlay（備援）

`sandbox.sh` 只是把下面這串包起來，需要時可以直接下：

```bash
WORKSPACE_DIR=$(pwd) APP_NETWORK_NAME=<網路名> docker compose \
    -f docker-compose.claude.yml \
    -f docker-compose.claude.network.yml \
    run --rm claude-sandbox bash
```

⚠️ **漏掉 overlay 時失敗是靜默的** —— 不會有任何錯誤訊息，只是所有服務名都解析不到（`curl` exit 6），繞過 DNS 直接打 IP 則是逾時（exit 28，封包被 DROP）。這組症狀讀起來像整個環境壞掉，實際發生過的誤判見 `docs/KNOWN-ISSUES.md` **K-5**。從 `sandbox.sh` 啟動時 entrypoint 會印出接上了哪個網路，沒接上也會明講。

`init-firewall.sh` 只會放行 sandbox 實際加入的網路子網段，不會因此打開整個私有網段(RFC1918)，對外連線的白名單規則不受影響。

## 開發規範

一套給人與 Claude 共用的開發紀律，跟語言/框架無關。它與 sandbox 的執行環境是**獨立的兩件事** —— 不想用容器隔離、只想用這套規範，把兩個 `.md` 拿走即可；反之亦然。

**預設的工作方式是：人委託、Claude 執行、人驗收。** 所以規範分成兩份，因為兩個讀者的需求相反：

| 檔案 | 讀者 | 讀幾次 | 內容 |
|---|---|---|---|
| `ONBOARDING.md` | **人** | 一次，之後當字典 | 怎麼下委託（目標／範圍／驗收／參考）、怎麼看回報、名詞表、常見情況怎麼辦、禁令與**為什麼** |
| `CLAUDE.md` | **Claude** | 每一輪都載入 | 什麼時候載入哪個 skill、鐵則、禁令、回報格式 |

`CLAUDE.md` 刻意壓在 130 行以內 —— 它每一輪都在付 token，而太長的規範會被部分忽略，被忽略的通常正是最具體有用的後半段。

它的取捨判準是**可觸發 vs 不可觸發**：有明確時機的做法（規劃、寫碼、驗證、交付、記錄、診斷）一律放進 skill 按需載入；**只有無法被觸發的才留在常駐檔** —— 你不會在推論到一半時想到要去載入某個 skill，所以鐵則與禁令必須常駐，而「怎麼寫計畫檔」不必。

規範的核心是三件事：

- **動手前四步**（釐清範圍／定位／講計畫／需求缺口分類）—— 施力點在任務進來的頭兩分鐘，下游所有問題都在那時候決定。展開在 `plan` skill
- **「可以不問直接做」有可檢查的五條門檻** —— 模糊的門檻等於沒有門檻。範圍外發現的問題，判準是它會不會擋住這次的驗收、以及修它要付多少。展開在 `plan` skill 第 0 步
- **回報格式固定**（改了什麼／為什麼／怎麼驗的／沒做什麼）—— 不論改動多小。門檻決定要不要問，回報決定人能不能監督

刻意**不**包含專案特定資訊（架構、路徑、測試指令、領域知識）—— 那些屬於套用端自己的 `CLAUDE.md`。

⚠️ **事故清單留給各專案自己累積。** 規範的可信度來自具體事故，而具體事故沒有人能替你預先寫好。只留通用原則的話，它會慢慢被當成背景噪音跳過。

## Template 用法

套用這個 template 的專案，只需要:

1. 保留 `sandbox.sh`、`Dockerfile.claude`、`docker-compose.claude.yml`、`docker-compose.claude.network.yml`、`scripts/` 原樣（跟語言無關，不需修改）。
2. 依專案實際的語言/框架，另外撰寫自己的 `Dockerfile`、`docker-compose.yml`（可選擇性搭配上方「連接專案自己的服務」章節，讓 sandbox 連得到）。
3. 需要多放行幾個網域時，先用 `.env.claude` 的 `EXTRA_ALLOWED_DOMAINS`（不用改檔案）；要改動預設清單本身才編輯 `scripts/init-firewall.sh` 裡的 `ALLOWED_DOMAINS`。
4. `CLAUDE.md` 在專案根目錄會被 Claude Code 自動載入；專案特定資訊（架構、路徑、測試指令、事故清單）寫在它下方或另開一份引用。當 submodule 用時見下一節。
5. 讓新人先讀一次 `ONBOARDING.md`。它不需要進 Claude 的 context，是純人用文件。

## 作為 Git Submodule 掛進其他專案

想把這個 sandbox 掛進一個原本沒有 Claude Code 的既有專案，不用複製檔案，用 submodule 引用即可：

```bash
# 在主專案根目錄下執行
git submodule add git@github.com:Bright0505/claude-code-sandbox.git claude-sandbox
```

`Dockerfile.claude`、`.claude-config/`、`.env.claude` 這些路徑都是相對於 `docker-compose.claude.yml` 檔案本身的位置解析，所以不管是獨立使用還是當 submodule 用，都不需要修改——它們永遠跟著 sandbox 一起走。唯一需要對外覆寫的是 `/workspace` 要掛載的目錄，因為 submodule 情境下要掛的是主專案根目錄，而不是 submodule 自己的目錄，用 `WORKSPACE_DIR` 環境變數指定（建議用絕對路徑 `$(pwd)`，避免相對路徑解析的疑慮）：

```bash
# 在主專案根目錄下執行
cp claude-sandbox/.env.claude.example claude-sandbox/.env.claude   # 填入 ANTHROPIC_API_KEY／git token

WORKSPACE_DIR=$(pwd) docker compose \
    -f claude-sandbox/docker-compose.claude.yml \
    run --rm claude-sandbox claude
```

或者直接用 `sandbox.sh`，它會偵測到自己位在另一個 git 工作區底下，自動把主專案根目錄當成 `WORKSPACE_DIR`：

```bash
# 在主專案根目錄下執行
./claude-sandbox/sandbox.sh
```

需要連接主專案自己的服務跑測試時，`sandbox.sh` 已經包含 overlay，不需要額外做什麼；用法與注意事項見上方「連接專案自己的服務」章節。

**開發規範在 submodule 情境下需要一行引用。** 子目錄的 `CLAUDE.md` 不會被自動載入，所以要在**主專案根目錄的 `CLAUDE.md`** 加：

```markdown
開發規範見 @claude-sandbox/CLAUDE.md
```

這樣主專案的 `CLAUDE.md` 只放專案特定內容（架構、路徑、指令、事故清單），規範跟著 template 一起更新。`ONBOARDING.md` 不需要引用 —— 直接叫新人去讀 `claude-sandbox/ONBOARDING.md` 就好。

> 掛好後值得驗一次引用真的生效：問 Claude「你現在遵守哪些禁令？」，它應該答得出十條。答不出來就是那行 `@` 沒被讀到。

之後 sandbox template 本身有更新，在主專案裡執行：

```bash
git submodule update --remote claude-sandbox
```

submodule 會把版本釘在特定 commit，更新前建議先看一下 template 端的變更再決定要不要跟進。
