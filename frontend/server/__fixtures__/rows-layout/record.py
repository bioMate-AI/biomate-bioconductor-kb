"""Record real read_rows outputs for the rows->edit round-trip test (project-rows-edit-roundtrip.test.ts).

Run once with the backend reader (python3.9, by file path — no Galaxy package import):
  python3.9 record.py <backend>/lib/galaxy/ai/data_perception.py
Writes <case>.json = {name, text, rows}: `rows` is read_rows(path, 0, 200, name=name) as the
backend returns it. `delimiter` is added from the reader's own table layout (decide().layout.delim)
when read_rows does not report it yet — the contract field the rows route forwards.
"""
import importlib.util, json, os, sys, tempfile

CASES = {
    # featureCounts output: one '# Program:' comment line, tab-separated, named .txt
    "fc_comment_tsv": ("counts.txt", '# Program:featureCounts v2.0.1; Command:"featureCounts" "-a" "g.gtf"\nGeneid\tChr\tStrand\tS1\nG1\tchr1\t+\t5\nG2\tchr1\t+\t7\nG3\tchr1\t-\t9\n'),
    # a CSV whose first line is blank
    "blank_first_csv": ("blank.csv", "\nid,val\nA,1\nB,2\nC,3\n"),
    # header-less numeric table
    "headerless_csv": ("matrix.csv", "1,2,3\n4,5,6\n7,8,9\n"),
    # semicolon CSV with decimal commas (European locale)
    "semicolon_csv": ("semi.csv", "gene;chr;val\nA;chr1;1,5\nB;chr1;2,5\n"),
}

spec = importlib.util.spec_from_file_location("_dp", sys.argv[1])
dp = importlib.util.module_from_spec(spec)
sys.modules["_dp"] = dp
spec.loader.exec_module(dp)
out_dir = os.path.dirname(os.path.abspath(__file__))
for case, (name, text) in CASES.items():
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, name)
        with open(p, "w", encoding="utf-8", newline="") as f:
            f.write(text)
        rows = dp.read_rows(p, 0, 200, name=name)
        if rows.get("tabular") and "delimiter" not in rows:
            rows["delimiter"] = dp.decide(p, name).layout.delim
    with open(os.path.join(out_dir, case + ".json"), "w") as f:
        json.dump({"name": name, "text": text, "rows": rows}, f, indent=1, sort_keys=True)
        f.write("\n")
    print(case, json.dumps({k: rows.get(k) for k in ("tabular", "headerRow", "skipLines", "delimiter", "columns", "rows")}))
