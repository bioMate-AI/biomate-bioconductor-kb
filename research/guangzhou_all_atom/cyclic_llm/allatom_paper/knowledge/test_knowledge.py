"""Unit tests for workstream K (run on EC2).  env: KB_PATH=<knowledge_kb_v1.json>  FETCH_DIR=<fetch dir with index.json + fulltext/> (optional)."""
import copy, hashlib, json, os, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from kb_schema import validate, COMPUTABLE  # noqa
from knowledge_loader import KnowledgePotential, load_kb, rules_text  # noqa

KB = os.environ.get("KB_PATH", os.path.join(HERE, "knowledge_kb_v1.json"))
FETCH = os.environ.get("FETCH_DIR", "")
STATS = {"tpsa": (200.0, 60.0), "hbd": (5.0, 2.0), "hba": (10.0, 3.0), "mw": (900.0, 200.0), "clogp": (3.0, 1.5),
         "nrotb": (12.0, 4.0), "n_heavy_atoms": (65.0, 15.0), "n_nme": (2.0, 1.5), "n_dres": (2.0, 1.5)}


class TestKB(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.doc = load_kb(KB)
        cls.rules = cls.doc["rules"]

    def test_schema_valid(self):
        bad = {e["id"]: validate(e) for e in self.rules if validate(e)}
        self.assertEqual(bad, {})

    def test_ids_unique(self):
        ids = [e["id"] for e in self.rules]
        self.assertEqual(len(ids), len(set(ids)))

    def test_provenance_complete(self):
        for e in self.rules:
            s = e["source"]
            if e["tier"] == "T-internal":
                self.assertTrue(s["path"] and s["text_sha256"], e["id"])
            else:
                self.assertTrue(s["doi"] and s["pmcid"] and s["url"] and s["title"], e["id"])
            self.assertTrue(e["access_date"] and e["extracted_by"], e["id"])
            self.assertLessEqual(len(e["quote"].split()), 30, e["id"])
            self.assertTrue(e["source"]["text_sha256"], e["id"])

    def test_every_quote_verified_in_stored_text(self):
        unver = [e["id"] for e in self.rules if not e["quote_verified"]]
        self.assertEqual(unver, [], f"unverified quotes: {unver}")

    def test_unverified_never_weighted(self):
        for e in self.rules:
            if not e["quote_verified"]:
                self.assertEqual(e["weight"], 0)
                self.assertFalse(e["weight_eligible"])

    def test_weight_only_for_t1_t2_rules_with_computable_feature(self):
        for e in self.rules:
            if e["weight_eligible"]:
                self.assertIn(e["tier"], ("T1", "T2"))
                self.assertIn(e["kind"], ("rule", "fundamental"))
                self.assertTrue(e["feat_mapped"], e["id"])
                self.assertTrue(set(e["feat_mapped"]) <= COMPUTABLE, e["id"])
                self.assertGreater(e["weight"], 0)
            else:
                self.assertEqual(e["weight"], 0)

    def test_conflict_and_caution_rules_have_no_weight(self):
        for e in self.rules:
            if e["direction"] in ("conflict", "caution", "context") or e["kind"] in ("caution", "card"):
                self.assertFalse(e["weight_eligible"], e["id"])

    def test_minimum_content(self):
        self.assertGreaterEqual(len(self.rules), 60)
        t12 = sum(1 for e in self.rules if e["tier"] in ("T1", "T2"))
        self.assertGreaterEqual(t12, 30)

    def test_potential_directions(self):
        kp = KnowledgePotential(self.doc, lam=1.0, stats=STATS)
        base = dict(tpsa=200.0, hbd=5.0, hba=10.0, mw=900.0, clogp=3.0, nrotb=12.0, n_heavy_atoms=65.0, n_nme=2.0)
        p0 = kp.log_potential(base)
        self.assertLess(kp.log_potential({**base, "tpsa": 260.0, "hbd": 8.0}), p0)       # more polar -> lower
        self.assertGreater(kp.log_potential({**base, "n_nme": 5.0}), p0)                    # more N-methyl -> higher
        self.assertLess(kp.log_potential({**base, "n_heavy_atoms": 95.0}), p0)             # bigger -> lower

    def test_window_hinge_penalises_violations_only(self):
        kp = KnowledgePotential(self.doc, lam=1.0, stats=STATS, rule_ids=["LIT-BRO5-001"])
        inside = dict(hbd=5.0, mw=900.0, clogp=3.0)
        self.assertEqual(kp.log_potential(inside), 0.0)
        self.assertLess(kp.log_potential({**inside, "hbd": 12.0}), 0.0)
        # either-or: violating only one of the alternatives (MW) is not penalised when cLogP > 2.5 holds
        self.assertEqual(kp.log_potential({**inside, "mw": 1500.0}), 0.0)
        self.assertLess(kp.log_potential({**inside, "mw": 1500.0, "clogp": 1.0}), 0.0)

    def test_outcome_classes_not_mixed(self):
        perm = KnowledgePotential(self.doc, stats=STATS)                      # default class: permeability
        self.assertTrue(perm.rules)
        self.assertTrue(all(e["outcome_class"] == "permeability" for e in perm.rules))
        stab = KnowledgePotential(self.doc, stats=STATS, outcome_class="stability")
        sol = KnowledgePotential(self.doc, stats=STATS, outcome_class="solubility")
        ids = lambda kp: {e["id"] for e in kp.rules}
        self.assertFalse(ids(perm) & ids(stab))
        self.assertFalse(ids(perm) & ids(sol))
        self.assertIn("LIT-SOL-001", ids(sol))

    def test_cards_have_payload_and_no_weight(self):
        cards = [e for e in self.rules if e["kind"] == "card"]
        self.assertGreaterEqual(len(cards), 10)
        for e in cards:
            self.assertFalse(e["weight_eligible"])
            self.assertEqual(e["weight"], 0)
            self.assertTrue(all(e["card"][k] for k in ("method", "modality", "outcome", "failure_modes", "lessons")), e["id"])

    def test_extra_quotes_verified(self):
        for e in self.rules:
            for q in e.get("quotes", []):
                self.assertLessEqual(len(q.split()), 30, e["id"])

    def test_loader_rejects_unverified_with_weight(self):
        bad = copy.deepcopy(self.doc)
        e = next(x for x in bad["rules"] if x["weight_eligible"])
        e["quote_verified"] = False
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump(bad, f)
        with self.assertRaises(ValueError):
            load_kb(f.name)

    def test_rules_text_deterministic_and_tagged(self):
        a = rules_text(self.doc, max_rules=5)
        b = rules_text(self.doc, max_rules=5)
        self.assertEqual(a, b)
        self.assertIn("[LIT-", a)
        self.assertIn("doi:", a)

    def test_planted_unverified_quote_is_detected(self):
        if not FETCH:
            self.skipTest("FETCH_DIR not set")
        from fetch_fulltext import norm
        from build_kb import load_fetch
        _, text_of = load_fetch(FETCH)
        e = self.rules[0]
        full = text_of(e["source"]["pmcid"])
        self.assertTrue(norm(e["quote"]) in full)
        self.assertFalse(norm("this sentence is not in the paper at all 12345") in full)

    def test_build_is_deterministic(self):
        if not FETCH:
            self.skipTest("FETCH_DIR not set")
        shas = []
        for _ in range(2):
            d = tempfile.mkdtemp()
            subprocess.check_call([sys.executable, os.path.join(HERE, "build_kb.py"), FETCH, d], stdout=subprocess.DEVNULL)
            shas.append(open(os.path.join(d, "knowledge_kb_v1.sha256")).read().split()[0])
        self.assertEqual(shas[0], shas[1])
        self.assertEqual(shas[0], open(os.path.join(os.path.dirname(KB), "knowledge_kb_v1.sha256")).read().split()[0])


if __name__ == "__main__":
    unittest.main()
