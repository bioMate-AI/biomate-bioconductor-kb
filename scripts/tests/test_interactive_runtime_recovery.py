import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from interactive_runtime_recovery import require_quiescent, source_matches, reviewed_identity, rollback

class RuntimeTests(unittest.TestCase):
    def test_active_jobs_or_heads_refuse(self):
        for p in [{'activeHeads':['java'],'activeJobs':[]},{'activeHeads':[],'activeJobs':[['running',1]]}]:
            with self.assertRaises(RuntimeError): require_quiescent(p)
        require_quiescent({'activeHeads':[],'activeJobs':[]})

    def test_source_and_existing_state_cannot_change(self):
        before={'codeManifest':{'a':'sha'},'SOABI':'abi','runManifest':{'x':{'sha':'1'}}}
        source_matches(before, before)
        for after in [{**before,'SOABI':'other'},{**before,'codeManifest':{}},{**before,'runManifest':{}}]:
            with self.assertRaises(RuntimeError): source_matches(before,after)

    def test_rollback_removes_only_owned_replacement_and_restores_network(self):
        class Fake:
            calls=[]
            def inspect(self,n): return {'Id':'replacement' if n=='live' else 'original'}
            def docker(self,*a): self.calls.append(a)
            def network(self,*a): self.calls.append(('network',*a))
            def health(self,u): return True
            def probe(self,n): return {'codeManifest':{},'SOABI':'abi','runManifest':{}}
        r=Fake();before=r.probe('')
        rollback(r,'live','retained','original','replacement',before,'health',{'net':{'Aliases':['live']}})
        self.assertEqual(r.calls,[('stop','--time','30','live'),('rm','live'),('network','net','connect','original',{'Aliases':['live']}),('rename','retained','live'),('start','live')])
        r.inspect=lambda n:{'Id':'unrelated'}
        with self.assertRaises(RuntimeError): rollback(r,'live','retained','original','replacement',before,'health')

    def test_review_digest_changes_with_environment_or_source(self):
        i={'Id':'id','Config':{'Env':['PATH=/bin']},'HostConfig':{},'NetworkSettings':{},'Image':'image'}
        p={'codeManifest':{},'runManifest':{}}
        first=reviewed_identity(i,p,'sha',999,0o660,Path('/state'))
        self.assertNotEqual(first,reviewed_identity({**i,'Config':{'Env':['PATH=/other']}},p,'sha',999,0o660,Path('/state')))
        self.assertNotEqual(first,reviewed_identity(i,{**p,'codeManifest':{'a':'new'}},'sha',999,0o660,Path('/state')))

if __name__=='__main__': unittest.main()

class ApplyTests(unittest.TestCase):
    def run_case(self, failure=None, collision=False):
        import tempfile, shutil, os
        from unittest.mock import patch
        from types import SimpleNamespace
        from interactive_runtime_recovery import apply_recovery
        from interactive_state_migration import manifest
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); source=root/'source';source.mkdir();(source/'state').write_text('preserve')
            journal=root/'journal';journal.mkdir();dest=root/'persist'
            if collision:
                dest.mkdir();(dest/'state').write_text('different')
            probe={'activeHeads':[],'activeJobs':[],'codeManifest':{'live':'hash'},'SOABI':'abi','runManifest':manifest(source)}
            inspection={'Name':'/live','Id':'old','Config':{'Env':['PATH=/usr/bin'],'User':'galaxy'},'HostConfig':{},'Mounts':[],'NetworkSettings':{'Networks':{'net':{'Aliases':['live']}}}}
            class Fake:
                def __init__(self):self.calls=[];self.replacement=False;self.renamed=False
                def docker(self,*a,**kw):
                    self.calls.append(a)
                    if a[0]=='cp' and a[1]=='-a':shutil.copytree(source,a[-1])
                    if a[0]=='commit':return 'sha256:snapshot'
                    if a[0]=='rename':self.renamed=a[1]=='live'
                    if a[0]=='rm':self.replacement=False
                    if a[0]=='exec' and 'python3' in a:
                        return '{"regular":true,"uid":0,"mode":493,"sha":"sha"}'
                    if a[0]=='exec' and 'ldd' in a and failure=='libraries':raise RuntimeError('bad libraries')
                    return ''
                def inspect(self,n):
                    if n=='retained':return {'Id':'old'}
                    if n=='live' and self.renamed and not self.replacement:raise RuntimeError('absent')
                    return {'Id':'new' if self.replacement and n=='live' else 'old'}
                def probe(self,n):return probe
                def network(self,*a):self.calls.append(('network',*a))
                def create(self,n,p):
                    self.calls.append(('create',n))
                    if failure=='create':raise RuntimeError('create failed')
                    self.replacement=True;return 'new'
                def health(self,u):return True
            runtime=Fake()
            actual_stat=os.stat
            with patch('interactive_runtime_recovery.os.stat', wraps=actual_stat) as st:
                st.side_effect=lambda p,*a,**kw:SimpleNamespace(st_mode=0o140660,st_uid=0,st_gid=999) if str(p)=='/var/run/docker.sock' else actual_stat(p,*a,**kw)
                if failure or collision:
                    with self.assertRaises((RuntimeError,ValueError)):apply_recovery(runtime,inspection,probe,dest,journal,root/'cli','sha',999,0o660,'health')
                else:
                    self.assertTrue(apply_recovery(runtime,inspection,probe,dest,journal,root/'cli','sha',999,0o660,'health')['success'])
            return runtime.calls

    def test_success_snapshot_after_stop_before_cli(self):
        calls=self.run_case(); stop=next(i for i,a in enumerate(calls) if a[0]=='stop');commit=next(i for i,a in enumerate(calls) if a[0]=='commit');cli=next(i for i,a in enumerate(calls) if a[0]=='cp' and a[-1]=='live:/usr/bin/docker')
        self.assertLess(stop,commit);self.assertLess(commit,cli)
    def test_create_failure_restores_original(self):
        calls=self.run_case('create');self.assertEqual(calls[-1],('start','live'));self.assertTrue(any(a[:3]==('network','net','connect') for a in calls))
    def test_postcreate_failure_removes_replacement_then_restores(self):
        calls=self.run_case('libraries');self.assertIn(('rm','live'),calls);self.assertEqual(calls[-1],('start','live'))
    def test_collision_refuses_before_stop(self):
        calls=self.run_case(collision=True);self.assertFalse(any(a[0]=='stop' for a in calls))
