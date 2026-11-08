"""Single-process Trainer checkpoint backup and Spot interruption handling.

Requires save_only_model=False; restores via Trainer.train(resume_from_checkpoint=...).
Distributed/FSDP/DeepSpeed state layouts require a separate validated adapter.
"""
import json,time
from pathlib import Path
from transformers import TrainerCallback
from checkpoint_store import seal,publish

class BioMateCheckpointBackup(TrainerCallback):
    def __init__(self,bucket,prefix,metadata,interval_seconds=300,interruption_file='/opt/biomate-trial/SPOT_INTERRUPTION.json'):
        self.bucket=bucket;self.prefix=prefix;self.metadata={**metadata,'kind':'training'}
        self.interval=interval_seconds;self.last_save=time.monotonic();self.interruption=Path(interruption_file)
    def on_train_begin(self,args,state,control,**kwargs):
        if args.world_size != 1 or getattr(args,'save_only_model',False):
            raise ValueError('BioMate backup currently requires single-process full-state Trainer checkpoints')
        return control
    def on_step_end(self,args,state,control,**kwargs):
        if time.monotonic()-self.last_save>=self.interval or self.interruption.exists(): control.should_save=True
        if self.interruption.exists():control.should_training_stop=True
        return control
    def on_save(self,args,state,control,**kwargs):
        checkpoint=Path(args.output_dir)/f'checkpoint-{state.global_step}'
        seal(checkpoint,{**self.metadata,'global_step':state.global_step})
        import boto3
        for attempt in range(3):
            try:
                result=publish(checkpoint,self.bucket,self.prefix,boto3.client('s3'));break
            except Exception:
                if attempt==2:raise
                time.sleep(2**(attempt+1))
        locator=Path(args.output_dir)/f'backup-{state.global_step}.json'
        locator.write_text(json.dumps(result,indent=2));self.last_save=time.monotonic()
        return control
