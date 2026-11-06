import hashlib,base64,io,json,tempfile,unittest
from pathlib import Path
from checkpoint_store import seal,publish,restore,READY
class S3:
    def __init__(self):self.objects={};self.keys=[]
    def put_object(self,**kw):
        data=kw['Body'].read() if hasattr(kw['Body'],'read') else kw['Body'];key=kw['Key']
        assert kw['IfNoneMatch']=='*' and key not in self.objects
        checksum=base64.b64encode(hashlib.sha256(data).digest()).decode()
        assert checksum==kw['ChecksumSHA256']
        self.objects[key]=data;self.keys.append(key);return {'ChecksumSHA256':checksum}
    def get_object(self,**kw):return {'Body':io.BytesIO(self.objects[kw['Key']])}
class Tests(unittest.TestCase):
    def setUp(self):self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name);self.src=self.root/'source';self.src.mkdir();(self.src/'data').write_text('verified');self.s3=S3()
    def tearDown(self):self.tmp.cleanup()
    def test_commit_last_and_restore(self):
        seal(self.src,{'kind':'artifact_bundle'});receipt=publish(self.src,'b','p',self.s3)
        self.assertEqual(self.s3.keys[-1],receipt['manifest_key'])
        restore('b',receipt['manifest_key'],self.root/'restored',self.s3,receipt['manifest_sha256'])
        self.assertEqual((self.root/'restored/data').read_text(),'verified')
    def test_changed_source_not_published(self):
        seal(self.src,{'kind':'artifact_bundle'});(self.src/'data').write_text('changed')
        with self.assertRaises(ValueError):publish(self.src,'b','p',self.s3)
        self.assertEqual(self.s3.keys,[])
    def test_corruption_never_promoted(self):
        seal(self.src,{'kind':'artifact_bundle'});r=publish(self.src,'b','p',self.s3)
        self.s3.objects[self.s3.keys[0]]=b'corrupt'
        with self.assertRaises(ValueError):restore('b',r['manifest_key'],self.root/'restored',self.s3)
        self.assertFalse((self.root/'restored').exists())
    def test_partial_training_checkpoint_rejected(self):
        with self.assertRaisesRegex(ValueError,'missing'):seal(self.src,{'kind':'training','base_model_revision':'x','dataset_manifest_sha256':'y'})
    def test_symlinks_rejected(self):
        (self.src/'link').symlink_to(self.src/'data')
        with self.assertRaises(ValueError):seal(self.src,{'kind':'artifact_bundle'})
    def test_manifest_failure_not_committed(self):
        seal(self.src,{'kind':'artifact_bundle'});original=self.s3.put_object
        def fail(**kw):
            if kw['Key'].endswith('manifest.json'):raise OSError('interruption')
            return original(**kw)
        self.s3.put_object=fail
        with self.assertRaises(OSError):publish(self.src,'b','p',self.s3)
        self.assertFalse(any(k.endswith('manifest.json') for k in self.s3.keys))
if __name__=='__main__':unittest.main()
