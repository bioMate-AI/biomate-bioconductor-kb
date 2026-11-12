"""
Behavioural tests for ROUND 8 of the dataset-profiler audit (2026-11-12, live audit on dev 0fead9b9):
Chinese column names were never recognised. ``_name_tokens`` only read ASCII letter runs, so a
header such as 分组 / 批次 / 编号 produced no tokens and could never be the group (label), batch,
split or identifier column — a Chinese hospital table with a 分组 column of 对照 / 处理 was told
"No group column (e.g. condition) was found".

Chinese compound nouns are head-final (处理时间 is a time, 实验分组 is a grouping), so a Chinese
run in a column name now yields the token of its HEAD noun, mapped onto the existing English
vocabulary; every rule that reads name tokens applies unchanged.

Every test fails on the profiler at 9a5cc0c8f3. Deterministic, no network.

Run standalone (no pytest needed):
    cd backend && python3.9 lib/galaxy/ai/tests/test_dataset_audit_r8_20261112.py
"""
from __future__ import annotations

import importlib.util
import inspect
import os
import random
import sys
import tempfile

_HERE = os.path.dirname(os.path.abspath(__file__))
_AI = os.environ.get("BM_AI_DIR") or os.path.abspath(os.path.join(_HERE, ".."))


def _load(name: str, fname: str):
    spec = importlib.util.spec_from_file_location(name, os.path.join(_AI, fname))
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)  # type: ignore[union-attr]
    return mod


dp = _load("_dp_audit_r8_under_test", "data_perception.py")

try:
    import pytest

    @pytest.fixture
    def tmp():
        with tempfile.TemporaryDirectory() as d:
            yield d
except ImportError:  # standalone main() supplies tmp
    pass


def _csv(tmp, name, header, rows):
    path = os.path.join(tmp, name)
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(",".join(header) + "\n" + "".join(",".join(str(c) for c in r) + "\n" for r in rows))
    return path


def _codes(prof):
    return {f["code"]: f for f in prof["findings"]}


def test_1_chinese_group_column_is_the_label(tmp):
    """样本,分组,表达量 with 对照 / 处理: 分组 is the group; balance is checked."""
    rnd = random.Random(1)
    rows = [[f"S{i:03d}", "对照" if i % 2 else "处理", round(rnd.gauss(10, 2), 3)] for i in range(40)]
    prof = dp.profile_dataset(_csv(tmp, "样本信息.csv", ["样本", "分组", "表达量"], rows))
    assert prof.get("labelColumn") == "分组", (prof.get("labelColumn"), list(_codes(prof)))
    assert "table_clean_unlabelled" not in _codes(prof), list(_codes(prof))


def test_2_chinese_batch_nested_in_groups_is_a_confounded_design(tmp):
    """A 批次 column whose every batch sits in one 分组 group: group_nested on 批次."""
    rnd = random.Random(2)
    rows = []
    for i in range(48):
        grp = "对照" if i < 24 else "处理"
        batch = f"B{i // 8}"  # B0–B2 only in 对照, B3–B5 only in 处理
        rows.append([f"S{i:03d}", grp, batch, round(rnd.gauss(10, 2), 3)])
    prof = dp.profile_dataset(_csv(tmp, "批次.csv", ["样本编号", "实验分组", "批次", "表达量"], rows))
    codes = _codes(prof)
    assert prof.get("labelColumn") == "实验分组", (prof.get("labelColumn"), list(codes))
    assert "group_nested" in codes and codes["group_nested"]["params"].get("column") == "批次", list(codes)


def test_3_id_and_time_columns_are_not_the_group(tmp):
    """编号 (unique per row) and 处理时间 (dates) never become the group, even though 处理 is a
    group word: the head of 处理时间 is 时间. The real group column 组别 is found."""
    rnd = random.Random(3)
    rows = [[f"P{i:04d}", f"2026-0{1 + i % 9}-1{i % 10}", "A" if i % 2 else "B", round(rnd.gauss(5, 1), 3)]
            for i in range(40)]
    prof = dp.profile_dataset(_csv(tmp, "时间.csv", ["编号", "处理时间", "组别", "测量值"], rows))
    assert prof.get("labelColumn") == "组别", (prof.get("labelColumn"), list(_codes(prof)))


def test_4_name_tokens_follow_the_head_noun():
    t = dp._name_tokens
    assert "group" in t("分组") and "group" in t("实验分组") and "group" in t("分组信息")
    assert "treatment" in t("处理") and "treatment" not in t("处理时间")
    assert "batch" in t("批次") and "id" in t("样本编号") and "sample" in t("样本")
    assert "genotype" in t("基因型") and "gene" not in t("基因型")
    assert t("参考基因组") == [] or "group" not in t("参考基因组")  # 基因组 (genome) is not a group
    # ASCII tokenisation is unchanged.
    assert t("patientID") == ["patient", "id"] and t("gene_symbol") == ["gene", "symbol"]


def main():
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    failed = 0
    for t in tests:
        with tempfile.TemporaryDirectory() as d:
            try:
                t(d) if inspect.signature(t).parameters else t()
                print(f"PASS {t.__name__}")
            except Exception as exc:  # noqa: BLE001 — report every failure, then exit non-zero
                failed += 1
                print(f"FAIL {t.__name__}: {type(exc).__name__}: {str(exc)[:300]}")
    print(f"\n{len(tests) - failed}/{len(tests)} round-8 dataset-audit tests passed.")
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
