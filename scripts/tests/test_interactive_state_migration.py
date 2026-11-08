import importlib.util
from pathlib import Path
import tempfile
import unittest
spec = importlib.util.spec_from_file_location('migration', Path(__file__).parents[1] / 'interactive_state_migration.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class MigrationTests(unittest.TestCase):
 def test_append_only_preserves_bytes_owner_mode_and_unrelated_entries(self):
  with tempfile.TemporaryDirectory() as tmp:
   src=Path(tmp)/'source';dst=Path(tmp)/'dest';src.mkdir();(src/'run').mkdir();(src/'run'/'out.csv').write_bytes(b'a,b\n1,2\n');(src/'run'/'out.csv').chmod(0o640)
   result=m.append_only_copy(src,dst);self.assertEqual(result['addedFiles'],1);m.verify(dst,result['manifest'])
   (dst/'unrelated.txt').write_text('keep');self.assertEqual(m.append_only_copy(src,dst)['addedFiles'],0);self.assertEqual((dst/'unrelated.txt').read_text(),'keep')
 def test_collision_aborts_before_any_copy(self):
  with tempfile.TemporaryDirectory() as tmp:
   src=Path(tmp)/'source';dst=Path(tmp)/'dest';src.mkdir();dst.mkdir();(src/'old').write_text('changed');(src/'new').write_text('new');(dst/'old').write_text('original')
   with self.assertRaises(ValueError):m.append_only_copy(src,dst)
   self.assertEqual((dst/'old').read_text(),'original');self.assertFalse((dst/'new').exists())
 def test_refuses_links_and_traversal(self):
  with tempfile.TemporaryDirectory() as tmp:
   src=Path(tmp)/'source';src.mkdir();(src/'link').symlink_to('/etc/passwd')
   with self.assertRaises(ValueError):m.manifest(src)
   with self.assertRaises(ValueError):m._path(Path(tmp),'../outside')
if __name__=='__main__':unittest.main()
