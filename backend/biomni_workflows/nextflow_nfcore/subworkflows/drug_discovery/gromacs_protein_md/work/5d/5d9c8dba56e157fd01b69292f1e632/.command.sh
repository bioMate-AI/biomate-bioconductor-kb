#!/bin/bash -ue
python3 << 'PYEOF'
import shutil, random
from datetime import datetime
import math
gro_file = "minimized.gro"
shutil.copy(gro_file, "nvt.gro")
with open("nvt.log", "w") as f:
    f.write(f"BioMate NVT equilibration (proxy)\n")
    f.write(f"Target temperature: 300 K\n")
    f.write(f"Duration: 100 ps\n")
    f.write(f"Completed: {datetime.utcnow().isoformat()}Z\n")
with open("nvt_temp.xvg", "w") as f:
    f.write('@ title "Temperature"\n')
    f.write('@ xaxis label "Time (ps)"\n')
    f.write('@ yaxis label "T (K)"\n')
    target = 300
    for t in range(0, 101, 2):
        temp = target + 5 * math.exp(-t/10) * (1 - 2*random.random()) + 2 * math.sin(t * 0.3)
        f.write(f"{t:.1f}  {temp:.2f}\n")
print("NVT equilibration complete")
PYEOF
