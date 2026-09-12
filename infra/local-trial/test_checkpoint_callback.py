"""Callback control-flow tests without importing a training runtime."""
import importlib.util,sys,tempfile,types,unittest
from pathlib import Path
from unittest.mock import patch
class Tests(unittest.TestCase):
    def test_periodic_and_interruption_save(self):
        fake=types.ModuleType('transformers');fake.TrainerCallback=object
        with patch.dict(sys.modules,{'transformers':fake}):
            spec=importlib.util.spec_from_file_location('backup_callback',Path(__file__).with_name('checkpoint_callback.py'))
            module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as d:
            flag=Path(d)/'notice';callback=module.BioMateCheckpointBackup('b','p',{},interval_seconds=0,interruption_file=str(flag))
            control=types.SimpleNamespace(should_save=False,should_training_stop=False)
            callback.on_train_begin(types.SimpleNamespace(world_size=1,save_only_model=False),None,control)
            callback.on_step_end(None,None,control);self.assertTrue(control.should_save);self.assertFalse(control.should_training_stop)
            flag.write_text('{}');callback.on_step_end(None,None,control);self.assertTrue(control.should_training_stop)
            with self.assertRaises(ValueError):callback.on_train_begin(types.SimpleNamespace(world_size=2,save_only_model=False),None,control)
            with self.assertRaises(ValueError):callback.on_train_begin(types.SimpleNamespace(world_size=1,save_only_model=True),None,control)
if __name__=='__main__':unittest.main()
