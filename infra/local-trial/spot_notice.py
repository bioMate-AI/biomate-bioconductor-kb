#!/usr/bin/env python3
"""Read IMDSv2 Spot interruption notice; request a clean save at the next training step.

Periodic checkpoints remain essential: a long in-flight step may outlast the notice.
"""
import json,time,urllib.request,urllib.error,subprocess
from pathlib import Path
base='http://169.254.169.254/latest/'
while True:
    try:
        req=urllib.request.Request(base+'api/token',method='PUT',headers={'X-aws-ec2-metadata-token-ttl-seconds':'60'})
        with urllib.request.urlopen(req,timeout=2) as r:token=r.read().decode()
        req=urllib.request.Request(base+'meta-data/spot/instance-action',headers={'X-aws-ec2-metadata-token':token})
        with urllib.request.urlopen(req,timeout=2) as r:notice=json.load(r)
        Path('/opt/biomate-trial/SPOT_INTERRUPTION.json').write_text(json.dumps(notice))
        subprocess.run(['systemctl','start','biomate-backup.service'],timeout=90,check=False)
        break
    except urllib.error.HTTPError as e:
        if e.code!=404:print('Spot notice check unavailable: HTTP '+str(e.code),flush=True)
    except Exception as e:print('Spot notice check unavailable: '+type(e).__name__,flush=True)
    time.sleep(5)
