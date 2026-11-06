"""Reproduce the source-assignment defect from the raw CycPeptMPDB CSV only (no analysis code). usage: python3 verify_source_defect.py CycPeptMPDB_Peptide_All.csv
Definitions: loader rows = PAMPA non-null and Permeability > -9.99 (as loop_retro/run_loop.load). Structure key = Structurally_Unique_ID.
OLD (defective) source = Source of the FIRST ROW OF ANY ASSAY for the structure (file order). CORRECT source = Source of the FIRST LOADER ROW (as run_loop.load rs[0])."""
import sys, pandas as pd
raw = pd.read_csv(sys.argv[1], low_memory=False)
loader = raw[raw["PAMPA"].notna() & (raw["Permeability"] > -9.99)]
ids = set(loader["Structurally_Unique_ID"])
old = raw[raw["Structurally_Unique_ID"].isin(ids)].groupby("Structurally_Unique_ID")["Source"].first()      # first row of any assay, file order
new = loader.groupby("Structurally_Unique_ID")["Source"].first()                                           # first loader row, file order
n_multi = (loader.groupby("Structurally_Unique_ID")["Source"].nunique() > 1).sum()
print("labelled structures:", len(ids))
print("sources: old-rule %d | correct (first loader row) %d | any loader row %d | whole file %d" % (old.nunique(), new.nunique(), loader["Source"].nunique(), raw["Source"].nunique()))
print("structures whose OLD-rule source != first-loader-row source:", int((old != new.reindex(old.index)).sum()))
print("structures with PAMPA rows from >1 source (a different quantity):", int(n_multi))
d = pd.DataFrame({"old": old, "new": new.reindex(old.index)}); d = d[d.old != d.new]
print(d.groupby(["old", "new"]).size().sort_values(ascending=False).head(6).to_string())

# --- part 2: the committed pre-fix annotation (data_before_source_fix/annotations.csv.gz) against the correct source
import os
p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data_before_source_fix", "annotations.csv.gz")
if os.path.exists(p):
    ann = pd.read_csv(p, index_col=0); lab = ann[ann["pampa"].notna()]
    bad = lab["Source"] != new.reindex(lab.index)
    print("\nPRE-FIX committed annotation: labelled %d | Source != first loader row (file order): %d" % (len(lab), int(bad.sum())))
    unstable = raw.sort_values("Structurally_Unique_ID").drop_duplicates("Structurally_Unique_ID").set_index("Structurally_Unique_ID")["Source"]   # what the defective build did
    stable = raw.groupby("Structurally_Unique_ID")["Source"].first()
    print("defective build's row choice (unstable sort + drop_duplicates) reproduces the committed Source for all labelled structures:", bool((unstable.reindex(lab.index) == lab["Source"]).all()))
    print("...and differs from a stable file-order 'first row of any assay' for %d labelled structures" % int((unstable.reindex(ids) != stable.reindex(ids)).sum()))
    print("=> two defects: (1) source taken from any assay's row, not the PAMPA row; (2) which row counted as 'first' was arbitrary (unstable sort). Idealised rule (1) alone with stable order gives the 21 mismatches above.")
