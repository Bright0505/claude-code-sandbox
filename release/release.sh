#!/bin/bash
# 把 dev 的產品檔發佈到 main。只有上游 template 自己發佈時用 —— 這支不出貨。
#
#   release/release.sh v0.2.0
#
# 設計：**main 是衍生物，不是分支。** 它的每個檔案都從 dev 產生，所以
#   - 兩邊從不 merge → 不會有 docs/ 的衝突要處理
#   - main 上禁止手改 → 改了下次發佈會被靜默覆蓋
#   - docs/ 不在產品清單裡 → 紀錄不是「被清掉」，是根本不會被搬過去
#
# 不 commit、不打 tag、不 push（禁令 2）—— 只把內容擺好，最後一步留給人。
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

die() { printf 'release: ✗ %s\n' "$1" >&2; exit 1; }
ok()  { printf 'release: ✓ %s\n' "$1"; }

[ -z "$(git status --porcelain)" ] || die "工作區不乾淨，先處理完再發佈"
git rev-parse --verify -q dev >/dev/null || die "找不到 dev 分支"

# 守衛 1：清單真的匹配到檔案。
# pathspec 打錯時 git diff／git ls-tree 回空，而「沒漂移」和「沒比到東西」長得一樣。
n="$(git ls-tree -r --name-only dev -- "${PROD[@]}" | wc -l | tr -d ' ')"
[ "$n" -gt 0 ] || die "產品檔清單在 dev 上匹配到 0 個檔案 —— 清單寫錯了"
ok "產品檔清單匹配到 $n 個檔案"

git checkout -q main || die "切不到 main"

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

# 守衛 2：main 的 docs/ 只准有那三個檔案。
# 少了這條，「發佈的樹裡不會有紀錄」只能靠紀律，不是機制。
actual="$(git ls-files docs/ | LC_ALL=C sort)"
expected="$(printf '%s\n' "${DOCS_ALLOWED[@]}" | LC_ALL=C sort)"
if [ "$actual" != "$expected" ]; then
    printf 'release: ✗ main 的 docs/ 有預期外的檔案：\n' >&2
    printf '%s\n' "$actual" | grep -vxF -f <(printf '%s\n' "$expected") >&2
    exit 1
fi
ok "main 的 docs/ 只有三份骨架"

# 守衛 3：骨架裡不可有條目
if git grep -qnE '^### K-[0-9]|^## D[0-9]' -- docs/; then
    die "docs/ 裡有條目 —— 骨架被污染了"
fi
ok "docs/ 零條目"

printf '\n'
git status --short
printf '\nrelease: 以上是 %s 的內容。確認後自己執行：\n' "$VERSION"
printf '  git commit -m "release: %s"\n  git tag %s\n' "$VERSION" "$VERSION"
printf 'release: 本腳本不 commit、不打 tag、不 push。\n'
