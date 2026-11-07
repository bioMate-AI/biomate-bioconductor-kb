"""Exercise the actual backend staging loop so non-Python skills cannot disappear."""
import pathlib
import subprocess
import tempfile


def test_backend_layout():
    repo = pathlib.Path(__file__).resolve().parents[2]
    source = (repo / "scripts/sync_to_dev.sh").read_text()
    start = source.index("    LAYOUT=/tmp/backend_py_layout")
    end = source.index("    staged=", start)
    block = source[start:end]
    with tempfile.TemporaryDirectory(prefix="biomate-layout-check-") as directory:
        root = pathlib.Path(directory)
        extract, layout = root / "extract", root / "layout"
        fixtures = {
            "lib/galaxy/api.py": "python",
            "lib/galaxy/ai/skills/biomate-universe.md": "skill",
            "lib/galaxy/ai/readme.md": "not a skill",
            "lib/galaxy/ai/skills/._bad.md": "metadata",
            "experiments/check.py": "experiment",
        }
        for name, content in fixtures.items():
            target = extract / "backend" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content)
        block = block.replace("/tmp/backend_py_extract", str(extract))
        block = block.replace("/tmp/backend_py_layout", str(layout))
        subprocess.run(["bash", "-e", "-c", block], check=True)
        actual = {
            str(file.relative_to(layout)): file.read_text()
            for file in layout.rglob("*") if file.is_file()
        }
        assert actual == {
            "app/lib/galaxy/api.py": "python",
            "app/lib/galaxy/ai/skills/biomate-universe.md": "skill",
            "app/experiments/check.py": "experiment",
        }


if __name__ == "__main__":
    test_backend_layout()
    print("PASS: Python and built-in Markdown skills staged; unrelated/AppleDouble files excluded")
