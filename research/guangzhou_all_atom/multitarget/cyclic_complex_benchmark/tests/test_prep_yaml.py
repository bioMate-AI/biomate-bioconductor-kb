"""YAML typing regression (14/40 pilot complexes failed with 'CCD component 4 not found': unquoted `ccd: 004` -> int 4).
Run: python3 tests/test_prep_yaml.py   (needs pyyaml)"""
import json, os, re, sys, yaml
here = os.path.dirname(os.path.abspath(__file__))
SRC = open(os.path.join(here, "..", "scripts", "prep_inputs.py")).read()

def test_generator_quotes_strings():
    assert "q = json.dumps" in SRC and 'ccd: {q(str(c))}' in SRC and "sequence: {q(pep_seq)}" in SRC, "generator must JSON-quote ccd and sequences"
    assert not re.search(r"ccd: \{c\}", SRC), "unquoted ccd interpolation is back"

def test_yaml_types_for_hazardous_codes():
    # the exact failure mode: tokens YAML 1.1 turns into int / bool / null when unquoted
    for tok in ["004", "0004", "1E5", "NO", "ON", "Y", "NULL", "YES", "OFF", "007"]:
        raw = yaml.safe_load("ccd: %s" % tok)["ccd"]
        quoted = yaml.safe_load("ccd: %s" % json.dumps(tok))["ccd"]
        assert quoted == tok and isinstance(quoted, str), (tok, quoted)
    assert not isinstance(yaml.safe_load("ccd: 004")["ccd"], str)   # documents that the unquoted form IS broken

if __name__ == "__main__":
    n = 0
    for k, f in sorted(globals().items()):
        if k.startswith("test_"): f(); n += 1; print("PASS", k)
    print(f"{n} tests passed")
