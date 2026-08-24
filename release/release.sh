#!/bin/bash
# 把 dev 的產品檔發佈到 main。只有上游 template 自己發佈時用 —— 這支不出貨。
#
#   release/release.sh v0.2.0        ← 在 dev 上執行（這支只存在於 dev）
#
# 設計：**main 是衍生物，不是分支。** 它的每個檔案都從 dev 產生，所以
#   - 兩邊從不 merge → 不會有 docs/ 的衝突要處理
#   - main 上禁止手改 → 改了下次發佈會被靜默覆蓋
#   - docs/ 不在產品清單裡 → 紀錄不是「被清掉」，是根本不會被搬過去
#
# 從 main 開一支 release/<版號> 分支作業，之後走 PR 進 main（禁令 1）。
# 不 commit、不 merge、不打 tag、不 push —— 只把內容擺好，最後一步留給人。
set -uo pipefail

VERSION="${1:-}"
[ -n "$VERSION" ] || { printf '用法：release/release.sh <版號，例 v0.2.0>\n' >&2; exit 1; }

# ---- 產品檔清單 ----
# 用陣列，不要用空白分隔的字串：某些 shell（zsh）不做 word splitting，
# "a b" 會被當成**一個**路徑，於是 git rm 報錯、git diff 回空 —— 兩個假象同時出現。
PROD=(
    sandbox.sh
    Dockerfile.claude
    docker-compose.claude.yml
    docker-compose.claude.network.yml
    scripts
    .claude
    CLAUDE.md
    README.md
    ONBOARDING.md
    CHANGELOG.md
    .gitignore
    .dockerignore
    .env.claude.example
)
# main 的 docs/ 只准有這三個檔案
DOCS_ALLOWED=(docs/DECISIONS.md docs/KNOWN-ISSUES.md docs/tasks/README.md)

START_BR="$(git rev-parse --abbrev-ref HEAD)"

# 守衛擋下來之後要清場。少了這段，失敗會把 repo 留在「發佈分支 + 一堆 staged
# 變更」的半成品狀態 —— 下一個動作（切分支）會再失敗一次，而錯誤訊息完全不指向
# 真正的原因（實測 2026-08-24：C4 觸發後 git checkout 報的是 local changes）。
die() {
    printf 'release: ✗ %s\n' "$1" >&2
    if [ -n "${BR:-}" ] && [ "$(git rev-parse --abbrev-ref HEAD)" = "$BR" ]; then
        git reset -q --hard HEAD
        git checkout -q "$START_BR" \
            && git branch -q -D "$BR" \
            && printf 'release: 已清場 —— 回到 %s，刪掉半成品分支 %s\n' "$START_BR" "$BR" >&2
    fi
    exit 1
}
ok()  { printf 'release: ✓ %s\n' "$1"; }

[ -z "$(git status --porcelain)" ] || die "工作區不乾淨，先處理完再發佈"
git rev-parse --verify -q dev >/dev/null || die "找不到 dev 分支"

# 守衛 1：清單真的匹配到檔案。
# pathspec 打錯時 git diff／git ls-tree 回空，而「沒漂移」和「沒比到東西」長得一樣。
n="$(git ls-tree -r --name-only dev -- "${PROD[@]}" | wc -l | tr -d ' ')"
[ "$n" -gt 0 ] || die "產品檔清單在 dev 上匹配到 0 個檔案 —— 清單寫錯了"
ok "產品檔清單匹配到 $n 個檔案"

# 不直接在 main 上 commit（禁令 1）—— 從 main 開一支發佈分支，之後走 PR 進 main。
BR="release/$VERSION"
if git rev-parse --verify -q "$BR" >/dev/null; then
    die "$BR 已存在 —— 先處理掉它（這個版號發佈過了？）"
fi
git checkout -q -b "$BR" main || die "從 main 開 $BR 失敗"
ok "在 $BR 上作業（不直接動 main）"

# 先刪再取。git checkout <ref> -- <path> 只做「加入與更新」，**不傳遞刪除** ——
# 不先刪的話，dev 上已移除的產品檔會永遠留在 main，而且 diff 看不出來。
git rm -rq --ignore-unmatch "${PROD[@]}"
git checkout dev -- "${PROD[@]}" \
    || die "取產品檔失敗 —— 清單過期了？（有檔案被改名或移除）"

# docs/ 從 skeleton 產生，不從 dev 的 docs/ 取
mkdir -p docs/tasks
git show dev:release/skeleton/DECISIONS.md    > docs/DECISIONS.md
git show dev:release/skeleton/KNOWN-ISSUES.md > docs/KNOWN-ISSUES.md
git show dev:release/skeleton/tasks-README.md > docs/tasks/README.md
git add -A

# docs/ 裡預期外的檔案一律移除，並逐個印出 —— 這是衍生分支，
# 上面不該有任何不是從 dev 產生的東西。印出來是為了讓它出現在 PR 的 diff 裡。
expected="$(printf '%s\n' "${DOCS_ALLOWED[@]}" | LC_ALL=C sort)"
stray="$(git ls-files docs/ | LC_ALL=C sort | grep -vxF -f <(printf '%s\n' "$expected") || true)"
if [ -n "$stray" ]; then
    printf '%s\n' "$stray" | while IFS= read -r f; do
        printf 'release: - 移除非骨架檔案 %s\n' "$f"
    done
    printf '%s\n' "$stray" | tr '\n' '\0' | xargs -0 git rm -q --
fi

# 守衛 2：docs/ 只准剩那三個檔案。
# 少了這條，「發佈的樹裡不會有紀錄」只能靠紀律，不是機制。
actual="$(git ls-files docs/ | LC_ALL=C sort)"
[ "$actual" = "$expected" ] || die "docs/ 的內容不等於預期的三份骨架：
$actual"
ok "docs/ 只有三份骨架"

# 守衛 3：骨架裡不可有條目
if git grep -qnE '^### K-[0-9]|^## D[0-9]' -- docs/; then
    die "docs/ 裡有條目 —— 骨架被污染了"
fi
ok "docs/ 零條目"

printf '\n'
git status --short
# 一次性設定的檢查：Template repository 開關沒開的話，整套骨架設計是空轉的
# —— 別人只能 clone，會拿到全部歷史與 dev。這是最容易忘、而且忘了沒有症狀的一項，
# 所以在這裡主動量，不是寫在文件裡等人想起來。
if command -v gh >/dev/null 2>&1; then
    tmpl="$(gh repo view --json isTemplate --jq .isTemplate 2>/dev/null || echo unknown)"
    case "$tmpl" in
        true)    ok "Template repository 開關已開" ;;
        false)   printf 'release: ⚠️ Template repository 開關是關的 —— 別人只能 clone，\n' >&2
                 printf 'release:    會拿到全部歷史與 dev。去 Settings → General 勾起來。\n' >&2 ;;
        *)       printf 'release: （沒查到 Template 開關狀態，gh 未認證？自己確認一次）\n' ;;
    esac
else
    printf 'release: （沒有 gh，無法檢查 Template repository 開關 —— 自己確認一次）\n'
fi

cat <<REMAINING

release: 以上是 $VERSION 的內容，在分支 $BR 上。剩下的步驟（本腳本都不做）：

  1. commit
       git commit -m "release: $VERSION"

  2. 推發佈分支
       git push -u origin $BR
       # 如果這個分支是「重建」的（之前推過同名的），要加 --force-with-lease：
       #   git push --force-with-lease origin $BR

  3. 把 main 移過來 —— 選一個，都不算在 main 上 commit（禁令 1）
       a) 本機 fast-forward，hash 完全一致：
            git checkout main && git merge --ff-only $BR && git push origin main
       b) 開 PR 留紀錄：GitHub 上 $BR 的頁面 → Compare & pull request
            → 合併時選 "Rebase and merge"（**不要** Create a merge commit）

  4. 打 tag，在 main 上
       git checkout main && git pull
       git tag $VERSION && git push origin $VERSION

  5. 刪掉發佈分支 —— **一定要等第 4 步的 tag 推上去之後**
       git push origin --delete $BR
       git branch -D $BR
       # tag 之前它是那份內容的唯一指標；tag 之後它不帶任何獨有資訊。
       # 留著的代價：多一個會動的「這一版是什麼」來源，而且會擋住同版號重建。

  6. 產物端驗收（見 release skill §9）
       gh repo create <試用名> --template <本 repo> --private
       # 驗：skill 載得到、骨架的指針沒斷、git log 是空的

release: 本腳本不 commit、不 push、不 merge、不打 tag（禁令 1-3）。
REMAINING
