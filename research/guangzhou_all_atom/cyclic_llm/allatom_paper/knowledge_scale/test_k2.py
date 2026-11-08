import random
from verify import norm, verify_rule, quote_in_text, number_ok, schema_errors, rule_id, benchmark_overlap

TEXT = ("N-methylation of the backbone  amides in cyclic hexapeptides increased PAMPA permeability by 5-fold in this series.\n\n"
        "The compound with three intramolecular hydrogen bonds showed a TPSA of 98 and logD of 3.2 and oral bioavailability of 28%.")
NT = norm(TEXT)
BASE = dict(statement="N-methylation increases permeability", direction="increases", property="permeability",
            substructure_class="n_methylation", scope="cyclic hexapeptides", confidence=0.8,
            effect_size={"value": 5, "unit": "fold"}, quote="increased PAMPA permeability by 5-fold in this series")


def test_exact_quote_accepted_and_whitespace_only_diff_accepted():
    ok, why = verify_rule(dict(BASE), NT, NT)
    assert ok, why
    q = dict(BASE, quote="N-methylation of the backbone amides in cyclic hexapeptides increased PAMPA")
    assert verify_rule(q, NT, NT)[0]  # source has a double space; normalisation makes it match


def test_altered_quotes_rejected():
    for bad in ["increased PAMPA permeability by 6-fold in this series",     # changed number
                "decreased PAMPA permeability by 5-fold in this series",      # changed word
                "increased permeability by 5-fold in this series now",         # inserted/dropped words
                "INCREASED PAMPA PERMEABILITY BY 5-FOLD IN THIS SERIES"]:      # case-sensitive
        assert not verify_rule(dict(BASE, quote=bad), NT, NT)[0], bad


def test_planted_fabricated_quotes_all_rejected():
    rng = random.Random(1)
    words = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau".split()
    for _ in range(20):
        q = " ".join(rng.choice(words) for _ in range(12))
        assert not verify_rule(dict(BASE, quote=q), NT, NT)[0]


def test_quote_length_limits():
    assert not verify_rule(dict(BASE, quote="N-methylation of the backbone"), NT, NT)[0]  # 4 words
    long_q = " ".join(NT.split()[:31])
    assert not verify_rule(dict(BASE, quote=long_q), NT, NT)[0]


def test_shuffled_source_fails():
    other = norm("Totally unrelated paper about kinase inhibitors and crystal structures of lysozyme in buffer.")
    assert not verify_rule(dict(BASE), other, other)[0]


def test_number_sanity_and_schema():
    assert number_ok({"value": 98}, "TPSA", NT)
    assert not number_ok({"value": 77}, "TPSA", NT)
    assert "bad_direction" in schema_errors(dict(BASE, direction="up"))
    assert "missing:quote" in schema_errors({k: v for k, v in BASE.items() if k != "quote"})


def test_rule_id_deterministic_and_benchmark_overlap():
    assert rule_id("PMC1", "a b c", "s") == rule_id("PMC1", "a  b c", "s")
    assert benchmark_overlap("Townsend JA, Smith B.", "2020", ["2020_Townsend", "2013_CHUGAI"]) == ["2020_Townsend"]
    assert benchmark_overlap("Zzz A", "2020", ["2020_Townsend"]) == []


def test_topic_fields_amendment_a1():
    pw = dict(BASE, topic="prior_work", lesson_type="hit_rate", designed_what="macrocyclic binders")
    assert verify_rule(pw, NT, NT)[0]
    assert not verify_rule(dict(pw, lesson_type="miracle"), NT, NT)[0]
    assert not verify_rule({k: v for k, v in pw.items() if k != "designed_what"}, NT, NT)[0]
    ts = dict(BASE, topic="target_structure", target="avb6", structure_feature="key_contact", residues=["TPSA"], pdb="")
    assert verify_rule(ts, NT, NT)[0]
    assert not verify_rule(dict(ts, residues=["Asp218"]), NT, NT)[0]          # residue not in passage -> reject
    assert not verify_rule(dict(ts, target="nope"), NT, NT)[0]
    assert not verify_rule(dict(ts, pdb="9XMM"), NT, NT)[0]                   # pdb id not in passage -> reject
    assert not verify_rule(dict(BASE, topic="folklore"), NT, NT)[0]


def test_strict_filter_a5():
    from verify import strict_ok
    good = dict(BASE, proxy_entailment="YES", confidence=0.8, topic="sar_rule", quote="N-methylation of cyclic peptides increased permeability here")
    assert strict_ok(good)
    assert not strict_ok(dict(good, proxy_entailment="NO"))
    assert not strict_ok(dict(good, confidence=0.5))
    assert not strict_ok(dict(good, quote="Macrocycles stack one into another by shape here", statement="Stacking happens"))   # off-topic: no peptide/cyclic term
    assert not strict_ok(dict(good, property="other"))
    assert not strict_ok(dict(good, direction="no_effect"))
    assert strict_ok(dict(good, topic="prior_work", property="other", direction="qualitative"))     # direction/property rule applies to sar_rule only


def test_strict_filter_a51_property_term_required():
    from verify import strict_ok
    good = dict(BASE, proxy_entailment="YES", confidence=0.8, topic="sar_rule", quote="N-methylation of cyclic peptides increased permeability here")
    # the off-topic chunk-0 example: a 'macrocycle' word but nothing about the rule's property -> rejected under A5.1
    assert not strict_ok(dict(good, quote="the macrocycles stack one into another by shape complementarity", statement="Macrocycles stack by shape"))
    # same words, property that matches -> accepted
    assert strict_ok(dict(good, property="conformation_chameleonicity", quote="the macrocycles adopt a closed conformation by intramolecular hydrogen bonds",
                          statement="Macrocycles adopt closed conformations"))
    # a property label that does not match the text is rejected
    assert not strict_ok(dict(good, property="solubility"))
    # a non-SAR topic with property 'other' needs only the cyclic term
    assert strict_ok(dict(good, topic="prior_work", property="other", direction="qualitative"))
