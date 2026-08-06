"""check_known_issues_links.py 的結構層檢查測試。

用標準庫 unittest,不引入 pytest 依賴(本 repo 跟語言/框架無關,腳本本身也只用標準庫)。
每一種紅燈都用故意壞掉的 fixture 觸發一次,確認腳本真的抓得到
(鐵則 4:沒紅過的測試不算測試)。

執行:python3 -m unittest claude-sandbox/.claude/skills/record/scripts/test_check_known_issues_links.py -v
"""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_known_issues_links as ckil  # noqa: E402


def write(path: Path, text: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path


class CheckKnownIssuesLinksTests(unittest.TestCase):
    def setUp(self):
        self._tmpdir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self._tmpdir.name)
        self.addCleanup(self._tmpdir.cleanup)

    # ─── 條目數斷言(直接測函式,防禦解析器本身的 bug)───

    def test_entry_count_assertion_catches_parser_undercount(self):
        text = "### K-1 標題一\n- **狀態**：未處理\n\n### K-2 標題二\n- **狀態**：未處理\n"
        fake_entries = [ckil.Entry(id=1, title="標題一", fields={"狀態": "未處理"})]  # 故意少一則
        errors = ckil.check_entry_count(text, fake_entries)
        self.assertEqual(len(errors), 1)
        self.assertIn("條目數斷言失敗", errors[0])

    def test_entry_count_assertion_passes_when_counts_match(self):
        text = "### K-1 標題一\n- **狀態**：未處理\n"
        entries = ckil.parse_entries(text, source="main")
        errors = ckil.check_entry_count(text, entries)
        self.assertEqual(errors, [])

    # ─── 指向不存在的 K-n ───

    def test_dangling_reference_detected(self):
        known_issues = write(
            self.tmp_path / "KNOWN-ISSUES.md",
            "### K-1 有壞掉的關聯\n"
            "- **影響範圍**：`foo.py`\n"
            "- **狀態**：未處理\n"
            "- **關聯**：與 K-99 同形態\n",
        )
        archive = self.tmp_path / "known-issues-archive.md"
        errors, _ = ckil.run_checks(known_issues, archive, self.tmp_path)
        self.assertTrue(any("K-99" in e and "不存在" in e for e in errors))

    # ─── archive 連結指向不存在的檔案 ───

    def test_archive_anchor_missing_file_detected(self):
        known_issues = write(
            self.tmp_path / "KNOWN-ISSUES.md",
            "## 已歸檔\n\n"
            "| ID | 一句話 | 影響範圍 | 明細 |\n"
            "|---|---|---|---|\n"
            "| K-1 | 測試用 | `foo.py` | [archive](known-issues-archive.md#k-1) |\n",
        )
        archive = self.tmp_path / "known-issues-archive.md"  # 故意不建立
        errors, _ = ckil.run_checks(known_issues, archive, self.tmp_path)
        self.assertTrue(any("K-1" in e and "不存在的檔案" in e for e in errors))

    def test_archive_anchor_valid_no_violation(self):
        known_issues = write(
            self.tmp_path / "KNOWN-ISSUES.md",
            "## 已歸檔\n\n"
            "| ID | 一句話 | 影響範圍 | 明細 |\n"
            "|---|---|---|---|\n"
            "| K-1 | 測試用故障 | `foo.py` | [archive](known-issues-archive.md#k-1-測試用故障) |\n",
        )
        archive = write(
            self.tmp_path / "known-issues-archive.md",
            "### K-1 測試用故障\n- **狀態**：已修（無守備）\n",
        )
        errors, _ = ckil.run_checks(known_issues, archive, self.tmp_path)
        self.assertEqual(errors, [])

    # ─── 關聯群組原子性:一半在主檔、一半已歸檔 ───

    def test_partial_archive_breaks_atomicity(self):
        known_issues = write(
            self.tmp_path / "KNOWN-ISSUES.md",
            "### K-1 還在主檔\n"
            "- **影響範圍**：`foo.py`\n"
            "- **狀態**：未處理\n"
            "- **關聯**：與 K-2 同形態\n",
        )
        archive = write(
            self.tmp_path / "known-issues-archive.md",
            "### K-2 已經被搬走\n- **狀態**：已修（無守備）\n",
        )
        errors, _ = ckil.run_checks(known_issues, archive, self.tmp_path)
        self.assertTrue(any("原子性被破壞" in e for e in errors))

    def test_fully_archived_chain_no_atomicity_violation(self):
        known_issues = write(
            self.tmp_path / "KNOWN-ISSUES.md",
            "## 已歸檔\n\n"
            "| ID | 一句話 | 影響範圍 | 明細 |\n"
            "|---|---|---|---|\n"
            "| K-1 | 一 | `foo.py` | [archive](known-issues-archive.md#k-1-一) |\n"
            "| K-2 | 二 | `bar.py` | [archive](known-issues-archive.md#k-2-二) |\n",
        )
        archive = write(
            self.tmp_path / "known-issues-archive.md",
            "### K-1 一\n- **狀態**：已修（無守備）\n- **關聯**：與 K-2 同形態\n\n"
            "### K-2 二\n- **狀態**：已修（無守備）\n",
        )
        errors, _ = ckil.run_checks(known_issues, archive, self.tmp_path)
        self.assertFalse(any("原子性被破壞" in e for e in errors))

    # ─── 已知未修被誤歸檔 ───

    def test_archived_known_unfixed_detected(self):
        known_issues = write(
            self.tmp_path / "KNOWN-ISSUES.md",
            "## 已歸檔\n\n"
            "| ID | 一句話 | 影響範圍 | 明細 |\n"
            "|---|---|---|---|\n"
            "| K-1 | 刻意不修的問題 | `foo.py` | [archive](known-issues-archive.md#k-1-刻意不修的問題) |\n",
        )
        archive = write(
            self.tmp_path / "known-issues-archive.md",
            "### K-1 刻意不修的問題\n- **狀態**：已知未修\n",
        )
        errors, _ = ckil.run_checks(known_issues, archive, self.tmp_path)
        self.assertTrue(any("已知未修" in e and "K-1" in e for e in errors))

    # ─── 守備路徑檢查(只查存在,不執行) ───

    def test_defense_path_missing_detected(self):
        known_issues = write(
            self.tmp_path / "KNOWN-ISSUES.md",
            "### K-1 守備指向不存在的測試\n"
            "- **影響範圍**：`foo.py`\n"
            "- **狀態**：已修\n"
            "- **守備**：`tests/unit/test_nonexistent_file.py::test_x`\n",
        )
        archive = self.tmp_path / "known-issues-archive.md"
        errors, _ = ckil.run_checks(known_issues, archive, self.tmp_path)
        self.assertTrue(any("守備" in e and "test_nonexistent_file.py" in e for e in errors))

    def test_defense_path_existing_no_violation(self):
        defense_file = self.tmp_path / "tests" / "unit" / "test_real.py"
        write(defense_file, "def test_x():\n    assert True\n")
        known_issues = write(
            self.tmp_path / "KNOWN-ISSUES.md",
            "### K-1 守備指向存在的測試\n"
            "- **影響範圍**：`foo.py`\n"
            "- **狀態**：已修\n"
            "- **守備**：`tests/unit/test_real.py::test_x`\n",
        )
        archive = self.tmp_path / "known-issues-archive.md"
        errors, _ = ckil.run_checks(known_issues, archive, self.tmp_path)
        self.assertEqual(errors, [])

    def test_defense_required_but_empty_detected(self):
        known_issues = write(
            self.tmp_path / "KNOWN-ISSUES.md",
            "### K-1 已修卻沒填守備\n"
            "- **影響範圍**：`foo.py`\n"
            "- **狀態**：已修\n",
        )
        archive = self.tmp_path / "known-issues-archive.md"
        errors, _ = ckil.run_checks(known_issues, archive, self.tmp_path)
        self.assertTrue(any("沒有填「守備」" in e for e in errors))

    # ─── 影響範圍檔案已不存在:只能是「需要人判斷」的 notice,不是 error ───

    def test_affected_file_missing_is_notice_not_error(self):
        known_issues = write(
            self.tmp_path / "KNOWN-ISSUES.md",
            "### K-1 影響範圍的檔案已經不在了\n"
            "- **影響範圍**：`this_file_does_not_exist.py`\n"
            "- **狀態**：未處理\n",
        )
        archive = self.tmp_path / "known-issues-archive.md"
        errors, notices = ckil.run_checks(known_issues, archive, self.tmp_path)
        self.assertEqual(errors, [])
        self.assertTrue(any("需要人判斷" in n and "this_file_does_not_exist.py" in n for n in notices))

    # ─── CLI 輸出:命名與「沒檢查什麼」的免責聲明 ───

    def test_cli_output_has_disclaimer_and_correct_naming(self):
        known_issues = write(self.tmp_path / "KNOWN-ISSUES.md", "### K-1 正常\n- **狀態**：未處理\n")
        archive = self.tmp_path / "known-issues-archive.md"

        import contextlib
        import io

        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            exit_code = ckil.main(
                ["--known-issues", str(known_issues), "--archive", str(archive), "--repo-root", str(self.tmp_path)]
            )
        out = buf.getvalue()
        self.assertEqual(exit_code, 0)
        self.assertNotIn("驗證關聯性", out)
        self.assertIn("不檢查", out)
        self.assertIn("語意層", out)
        self.assertIn("漏連結", out)

    def test_cli_exit_code_nonzero_on_structural_error(self):
        known_issues = write(
            self.tmp_path / "KNOWN-ISSUES.md",
            "### K-1 壞掉的關聯\n- **狀態**：未處理\n- **關聯**：與 K-99 同形態\n",
        )
        archive = self.tmp_path / "known-issues-archive.md"
        exit_code = ckil.main(
            ["--known-issues", str(known_issues), "--archive", str(archive), "--repo-root", str(self.tmp_path)]
        )
        self.assertEqual(exit_code, 1)


if __name__ == "__main__":
    unittest.main()
