#!/bin/bash -ue
python3 << 'PYEOF'
import json
from biomni.tool.biochemistry import michaelis_menten

# Run the tool
try:
    result = michaelis_menten(
    s="5.0",
    vmax="1.5",
    km="2.0"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("michaelis_menten_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("michaelis_menten_output.txt", "w") as f:
    f.write("Biomni: Michaelis Menten Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("michaelis_menten completed successfully")
PYEOF
