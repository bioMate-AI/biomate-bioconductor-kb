import importlib.util,json,subprocess,tempfile,unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('ancestry',Path(__file__).parents[1]/'dev_deploy_ancestry.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class AncestryTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.repo=Path(self.tmp.name)
  self.g('init','-q');self.g('config','user.email','qa@example.invalid');self.g('config','user.name','QA')
  self.first=self.commit('first');self.second=self.commit('second')
 def tearDown(self):self.tmp.cleanup()
 def g(self,*a):return subprocess.check_output(['git','-C',str(self.repo),*a],stderr=subprocess.DEVNULL,text=True).strip()
 def commit(self,value):
  (self.repo/'data').write_text(value);self.g('add','data');self.g('commit','-qm',value);return self.g('rev-parse','HEAD')
 def test_allows_same_and_descendant(self):
  for deployed in [self.first,self.second]:self.assertFalse(m.preflight(self.repo,deployed)['emergencyOverride'])
 def test_stale_worktree_cannot_overwrite_newer_dev(self):
  self.g('checkout','-q','--detach',self.first)
  with self.assertRaisesRegex(ValueError,'Stale'):m.preflight(self.repo,self.second)
  self.assertEqual(self.g('rev-parse','HEAD'),self.first)
 def test_diverged_branch_refuses(self):
  self.g('checkout','-q','--detach',self.first);self.commit('diverged')
  with self.assertRaisesRegex(ValueError,'Stale'):m.preflight(self.repo,self.second)
 def test_refusal_lists_the_work_that_would_be_removed(self):
  # Deploying an older image (e.g. a stale next-phase build via the GitHub Action) must name
  # the live commits it would drop, so the deployer merges them instead of overwriting.
  with self.assertRaisesRegex(ValueError,r'(?s)REMOVE 1 commit.*second'):m.preflight(self.repo,self.second,head_ref=self.first)
 def test_head_option_checks_a_given_commit_not_the_checkout(self):
  self.assertFalse(m.preflight(self.repo,self.first,head_ref=self.second)['emergencyOverride'])
 def test_unknown_identity_cannot_be_overridden(self):
  with self.assertRaisesRegex(ValueError,'unknown'):m.preflight(self.repo,'f'*40,'Emergency rollback reviewed')
 def test_emergency_requires_reason_and_remains_explicit(self):
  self.g('checkout','-q','--detach',self.first)
  with self.assertRaises(ValueError):m.preflight(self.repo,self.second,'yes')
  self.assertTrue(m.preflight(self.repo,self.second,'Reviewed emergency rollback')['emergencyOverride'])
 def test_identity_rejects_html_missing_abbreviated_and_unbounded(self):
  for raw,typ in [(b'<html>login</html>','text/html'),(b'{}','application/json'),(b'{"commit":"abc"}','application/json'),(b'x'*65537,'application/json')]:
   with self.assertRaises(ValueError):m.parse_identity(raw,typ)
  self.assertEqual(m.parse_identity(json.dumps({'commit':self.first}).encode(),'application/json; charset=utf-8'),self.first)
 def test_unreadable_identity_and_redirect_fail_closed(self):
  from unittest.mock import patch,Mock
  opener=Mock();opener.open.side_effect=OSError('network unavailable')
  with patch.object(m.urllib.request,'build_opener',return_value=opener):
   with self.assertRaisesRegex(ValueError,'verified HTTPS'):m.public_commit()
  with self.assertRaisesRegex(ValueError,'redirected'):m.NoRedirect().redirect_request(None,None,302,'redirect',{},'https://other.example')
 def test_requires_https_without_credentials(self):
  for url in ['http://dev.example/build-info.json','https://user:password@dev.example/build-info.json']:
   with self.assertRaises(ValueError):m.public_commit(url)
 # ledger-head: also refuse to drop a backend-only deploy whose commit never reached
 # the (frontend-only) build-info.json.
 def test_ledger_head_not_in_head_refuses_even_if_build_info_contained(self):
  self.g('checkout','-q','--detach',self.first);third=self.commit('third-backend-only')
  # build-info=first (in HEAD=second) passes step 1; ledger-head=third is NOT in second.
  with self.assertRaisesRegex(ValueError,r'(?s)last-ledger.*REMOVE'):m.preflight(self.repo,self.first,ledger_head=third,head_ref=self.second)
 def test_ledger_head_contained_passes(self):
  r=m.preflight(self.repo,self.first,ledger_head=self.second,head_ref=self.second)
  self.assertFalse(r['emergencyOverride']);self.assertEqual(r['ledgerHead'],self.second)
 def test_ledger_head_unknown_locally_refuses(self):
  with self.assertRaisesRegex(ValueError,r'(?s)last-ledger.*unknown locally'):m.preflight(self.repo,self.second,ledger_head='0'*40)
 def test_ledger_head_absent_behaves_as_before(self):
  self.assertFalse(m.preflight(self.repo,self.second,ledger_head=None)['emergencyOverride'])

 # --- content preservation (blocks `merge -s ours` clobber) ---
 def _commit_path(self, rel, value, msg=None):
  path=self.repo.joinpath(*rel.split('/')); path.parent.mkdir(parents=True,exist_ok=True)
  path.write_text(value); self.g('add',rel); self.g('commit','-qm',msg or value)
  return self.g('rev-parse','HEAD')
 def test_ours_merge_that_drops_live_product_files_refuses(self):
  # Live tip shortens a protected file; other branch keeps the long text and only
  # records ancestry via `merge -s ours` — must refuse (the dig skills clobber).
  self.g('checkout','-q','-b','live',self.first)
  live=self._commit_path('frontend/client/src/skills.txt','short-desc','skills short')
  self.g('checkout','-q','-b','other',self.first)
  self._commit_path('frontend/client/src/skills.txt','LONG wall of routing prose','skills long')
  self.g('merge','-s','ours','-m','merge(sync): record live for ancestry','live')
  ours_head=self.g('rev-parse','HEAD')
  with self.assertRaisesRegex(ValueError,r'(?s)Content clobber.*skills\.txt'):
   m.preflight(self.repo,live,head_ref=ours_head)
 def test_forward_commit_on_path_after_live_tip_allows(self):
  # Real work on top of live (non-merge commit touching the path) may change blobs.
  self.g('checkout','-q','-b','live2',self.first)
  live=self._commit_path('frontend/client/src/skills.txt','short','skills short')
  self._commit_path('frontend/client/src/skills.txt','short+fix','skills follow-up')
  head=self.g('rev-parse','HEAD')
  self.assertFalse(m.preflight(self.repo,live,head_ref=head)['emergencyOverride'])
 def test_ours_merge_clobber_allowed_only_with_emergency_reason(self):
  self.g('checkout','-q','-b','live3',self.first)
  live=self._commit_path('backend/lib/galaxy/ai/skills/x.md','short','skill short')
  self.g('checkout','-q','-b','other3',self.first)
  self._commit_path('backend/lib/galaxy/ai/skills/x.md','LONG','skill long')
  self.g('merge','-s','ours','-m','record live','live3')
  head=self.g('rev-parse','HEAD')
  with self.assertRaises(ValueError):
   m.preflight(self.repo,live,head_ref=head,emergency_reason='too short')
  self.assertTrue(m.preflight(
   self.repo,live,head_ref=head,
   emergency_reason='Reviewed intentional clobber of skills blob')['emergencyOverride'])
 def test_unprotected_paths_may_differ_without_followup_commit(self):
  # docs/ is not gated — ancestry-only doc drift must not block deploys.
  self.g('checkout','-q','-b','live4',self.first)
  live=self._commit_path('docs/note.md','live-doc','doc live')
  self.g('checkout','-q','-b','other4',self.first)
  self._commit_path('docs/note.md','other-doc','doc other')
  self.g('merge','-s','ours','-m','record live','live4')
  head=self.g('rev-parse','HEAD')
  self.assertFalse(m.preflight(self.repo,live,head_ref=head)['emergencyOverride'])

if __name__=='__main__':unittest.main()
