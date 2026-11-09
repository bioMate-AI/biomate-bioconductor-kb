"""Real filesystem/parser tests; no network, Galaxy stubs or mocked skill store."""
import importlib.util
from pathlib import Path
import tempfile
import sys
import unittest
from unittest.mock import patch
from concurrent.futures import ThreadPoolExecutor

SOURCE = Path(__file__).parents[1] / "lib/galaxy/ai/skill_manager.py"
spec = importlib.util.spec_from_file_location("skill_contract", SOURCE)
skills = importlib.util.module_from_spec(spec)
spec.loader.exec_module(skills)
loader_spec = importlib.util.spec_from_file_location("research_skill_contract", SOURCE.parent / "agents/skill_loader.py")
research_loader = importlib.util.module_from_spec(loader_spec)
sys.modules[loader_spec.name] = research_loader
loader_spec.loader.exec_module(research_loader)

STANDARD = "---\nname: scientific-slides\ndescription: >\n  Create a presentation\n  using verified results.\nmetadata:\n  version: '2.1'\n---\nUse verified data, not invented numbers."


class SkillCompatibilityTests(unittest.TestCase):
    def setUp(self):
        # Publish the actual dependency-light module loaded above under its
        # production name; do not import Galaxy's unrelated AI service stack.
        modules = patch.dict(sys.modules, {"galaxy.ai.skill_manager": skills})
        modules.start()
        self.addCleanup(modules.stop)
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.experts = self.root / "experts"
        self.experts.mkdir()
        self.private = self.root / "private"
        self.base = skills.SkillManager(self.experts, self.root / "no-bioc")

    def test_standard_without_triggers_and_folded_description(self):
        meta = skills.validate_skill_upload(STANDARD)
        self.assertEqual(meta["description"].strip(), "Create a presentation using verified results.")
        result = skills.store_private_skill(self.private, 10, STANDARD)
        manager = skills.scoped_skill_manager(10, self.private, self.base)
        skill = manager.get_skill(result["skill_id"])
        self.assertEqual(skill.version, "2.1")
        self.assertEqual(skill.triggers, [])
        self.assertIn("verified results", skill.to_dict()["description"])
        self.assertEqual(skill.to_dict()["sha256"], result["sha256"])

    def test_legacy_and_block_lists_remain_supported(self):
        text = "---\nname: lab-expert\ntriggers:\n  - compare results\ndomains: [genomics]\nversion: 1.0\n---\nCheck controls."
        skills.validate_skill_upload(text)
        result = skills.store_private_skill(self.private, 10, text)
        manager = skills.scoped_skill_manager(10, self.private, self.base)
        self.assertEqual([s.id for s in manager.detect_skills("compare results")], [result["skill_id"]])
        self.assertEqual(manager.get_skill(result["skill_id"]).version, "1.0")

    def test_private_overlay_never_leaks_or_changes_shared_pack(self):
        shared = self.experts / "scientific-slides.md"
        shared.write_text(STANDARD.replace("Use verified data, not invented numbers.", "Shared instructions."))
        base = skills.SkillManager(self.experts, self.root / "no-bioc")
        result = skills.store_private_skill(self.private, 10, STANDARD)
        mine = skills.scoped_skill_manager(10, self.private, base)
        other = skills.scoped_skill_manager(11, self.private, base)
        self.assertIsNone(other.get_skill(result["skill_id"]))
        self.assertIsNone(base.get_skill(result["skill_id"]))
        self.assertIn("Shared instructions", mine.get_skill("scientific-slides").body)
        self.assertIn("not invented", mine.get_skill(result["skill_id"]).body)
        self.assertEqual(shared.read_text(), STANDARD.replace("Use verified data, not invented numbers.", "Shared instructions."))

    def test_duplicate_import_never_overwrites(self):
        skills.store_private_skill(self.private, 10, STANDARD)
        path = self.private / "10/scientific-slides.md"
        original = path.read_bytes()
        with self.assertRaises(FileExistsError):
            skills.store_private_skill(self.private, 10, STANDARD.replace("verified", "changed"))
        self.assertEqual(path.read_bytes(), original)
        self.assertEqual(list(path.parent.glob(".upload-*")), [])

    def test_concurrent_import_has_exactly_one_winner(self):
        def save(_):
            try:
                skills.store_private_skill(self.private, 10, STANDARD)
                return True
            except FileExistsError:
                return False
        with ThreadPoolExecutor(max_workers=4) as executor:
            results = list(executor.map(save, range(8)))
        self.assertEqual(sum(results), 1)
        self.assertEqual((self.private / "10/scientific-slides.md").read_text(), STANDARD)

    def test_fresh_overlay_sees_upload_without_worker_reload(self):
        before = skills.scoped_skill_manager(10, self.private, self.base)
        result = skills.store_private_skill(self.private, 10, STANDARD)
        after = skills.scoped_skill_manager(10, self.private, self.base)
        self.assertIsNone(before.get_skill(result["skill_id"]))
        self.assertIsNotNone(after.get_skill(result["skill_id"]))

    def test_nested_standard_package_is_discovered(self):
        package = self.experts / "scientific-slides"
        package.mkdir()
        (package / "SKILL.md").write_text(STANDARD)
        manager = skills.SkillManager(self.experts, self.root / "no-bioc")
        self.assertIsNotNone(manager.get_skill("scientific-slides"))

    def test_owned_delete_cannot_delete_other_users_or_builtins(self):
        result = skills.store_private_skill(self.private, 10, STANDARD)
        for owner, skill_id in [(11, result["skill_id"]), (10, "scientific-slides"), (10, "user-10-../escape")]:
            with self.subTest(owner=owner, skill_id=skill_id), self.assertRaises(FileNotFoundError):
                skills.delete_private_skill(self.private, owner, skill_id)
        skills.delete_private_skill(self.private, 10, result["skill_id"])
        self.assertIsNone(skills.scoped_skill_manager(10, self.private, self.base).get_skill(result["skill_id"]))

    def test_research_loader_accepts_current_layout_and_preserves_reference(self):
        package = self.root / "upstream/skills/scientific-writing"
        package.mkdir(parents=True)
        (package / "SKILL.md").write_text(STANDARD)
        (package / "references").mkdir()
        (package / "references/evidence.md").write_text("Verify every claim.")
        loader = research_loader.SkillLoader(str(self.root / "upstream"))
        loaded = loader._load_skill_file("scientific-thinking/scientific-writing")
        self.assertIn("verified", loaded.content)
        self.assertIn("Verify every claim", loaded.references[0])
        for path in ["../outside", "/tmp/outside"]:
            with self.subTest(path=path), self.assertRaises(ValueError):
                loader._load_skill_file(path)

    def test_research_loader_rejects_symlink_escape(self):
        outside = self.root / "outside"
        outside.mkdir()
        (outside / "SKILL.md").write_text(STANDARD)
        root = self.root / "research"
        root.mkdir()
        (root / "scientific-writing").symlink_to(outside, target_is_directory=True)
        loader = research_loader.SkillLoader(str(root))
        with self.assertRaises(ValueError):
            loader._load_skill_file("scientific-writing")

    def test_all_bundled_expert_packs_load(self):
        bundled = SOURCE.parent / "skills"
        manager = skills.SkillManager(bundled, self.root / "no-bioc")
        self.assertEqual(len(manager.list_expert_skills()), len(list(bundled.glob("*.md"))))
        self.assertTrue(manager.detect_skills("GWAS association study"))

    def test_invalid_metadata_and_traversal_are_rejected(self):
        invalid = [
            STANDARD.replace("scientific-slides", "../escape"),
            STANDARD.replace("scientific-slides", "UPPER_case"),
            STANDARD.replace("description: >", "triggers: >"),
            "---\n- not-a-mapping\n---\nbody",
            "---\nname: unclosed",
            "---\nname: bad\ntriggers: [broken\n---\nbody",
            "---\nname: empty\ndescription: text\n---\n",
            "x" * 256001,
        ]
        for text in invalid:
            with self.subTest(text=text[:70]), self.assertRaises(ValueError):
                skills.store_private_skill(self.private, 10, text)
        self.assertFalse(self.private.exists())

    def test_invalid_render_metadata_is_rejected_before_publication(self):
        for field in ["metadata: invalid-scalar", "metadata: [invalid]", "metadata: null",
                      "metadata: false", "title: [not, text]", "title: {invalid: text}",
                      "title: null", "title: 42", "title: ''"]:
            text = STANDARD.replace("metadata:\n  version: '2.1'", field)
            with self.subTest(field=field), self.assertRaises(ValueError):
                skills.store_private_skill(self.private, 10, text)
            self.assertFalse(self.private.exists())

    def test_invalid_owner_and_symlink_do_not_escape(self):
        for owner in (None, "../outside", 0, -1, True):
            with self.subTest(owner=owner), self.assertRaises(ValueError):
                skills.store_private_skill(self.private, owner, STANDARD)
        self.private.mkdir()
        outside = self.root / "outside"
        outside.mkdir()
        (self.private / "10").symlink_to(outside, target_is_directory=True)
        with self.assertRaises(ValueError):
            skills.store_private_skill(self.private, 10, STANDARD)
        with self.assertRaises(ValueError):
            skills.scoped_skill_manager(10, self.private, self.base)
        self.assertEqual(list(outside.iterdir()), [])

    def test_bom_crlf_and_embedded_delimiter_text(self):
        text = STANDARD.replace("using verified results.", "using verified results --- still text.")
        text = "\ufeff" + text.replace("\n", "\r\n")
        meta, body = skills._parse_frontmatter(text)
        self.assertEqual(meta["name"], "scientific-slides")
        self.assertIn("not invented", body)

    def test_research_frontmatter_matches_shared_strict_parser(self):
        package = self.root / "research/scientific-slides"
        package.mkdir(parents=True)
        text = STANDARD.replace("using verified results.", "using verified results --- still text.")
        text = "\ufeff" + text.replace("\n", "\r\n")
        (package / "SKILL.md").write_text(text)
        loader = research_loader.SkillLoader(str(package.parent))
        loaded = loader._load_skill_file("scientific-slides")
        self.assertIsNotNone(loaded)
        self.assertEqual(loaded.name, "scientific-slides")
        self.assertEqual(loaded.description, skills._parse_frontmatter(text)[0]["description"])
        self.assertEqual(loaded.content, skills._parse_frontmatter(text)[1])
        self.assertIn("--- still text", loaded.description)

    def test_research_parser_rejects_malformed_frontmatter(self):
        loader = research_loader.SkillLoader(str(self.root))
        for text in ["---\nname: unclosed", "---\n- invalid\n---\nbody",
                     "---\nname: [broken\n---\nbody"]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                loader._parse_frontmatter(text)


if __name__ == "__main__":
    unittest.main()
