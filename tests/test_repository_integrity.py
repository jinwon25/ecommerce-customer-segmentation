import ast
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MARKDOWN_LINK = re.compile(r"!?(?:\[[^]]*\])\(([^)]+)\)")


class RepositoryIntegrityTest(unittest.TestCase):
    def test_python_files_parse(self) -> None:
        for path in [*ROOT.glob("scripts/*.py"), *ROOT.glob("tests/*.py")]:
            with self.subTest(path=path.relative_to(ROOT)):
                ast.parse(path.read_text(encoding="utf-8"), filename=str(path))

    def test_local_markdown_links_exist(self) -> None:
        missing: list[str] = []
        for markdown in ROOT.rglob("*.md"):
            text = markdown.read_text(encoding="utf-8")
            for raw_target in MARKDOWN_LINK.findall(text):
                target = raw_target.strip().split("#", 1)[0]
                if not target or "://" in target or target.startswith("mailto:"):
                    continue
                target = target.strip("<>")
                if not (markdown.parent / target).resolve().exists():
                    missing.append(f"{markdown.relative_to(ROOT)} -> {raw_target}")
        self.assertEqual(missing, [], "Missing local links:\n" + "\n".join(missing))


if __name__ == "__main__":
    unittest.main()
