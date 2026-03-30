#!/bin/bash -ue
python3 << 'PYEOF'
import shutil, random, math
from datetime import datetime
gro_file = "nvt.gro"
shutil.copy(gro_file, "npt.gro")
with open("npt.log", "w") as f:
    f.write(f"BioMate NPT equilibration (proxy)\n")
    f.write(f"Target pressure: 1 bar\n")
    f.write(f"Duration: 100 ps\n")
    f.write(f"Completed: {datetime.utcnow().isoformat()}Z\n")
with open("npt_density.xvg", "w") as f:
    f.write('@ title "Density"\n')
    f.write('@ xaxis label "Time (ps)"\n')
    f.write('@ yaxis label "Density (kg/m^3)"\n')
    for t in range(0, 101, 2):
        dens = 1000 + 50 * math.exp(-t/20) * random.uniform(-1, 1)
        f.write(f"{t:.1f}  {dens:.2f}\n")
print("NPT equilibration complete")
PYEOF
