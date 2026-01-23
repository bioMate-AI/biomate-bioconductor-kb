#!/bin/bash -ue
python3 << 'PYEOF'
import json
from biomni.tool.microbiology import model_bacterial_growth_dynamics

# Run the tool
try:
    result = model_bacterial_growth_dynamics(
    initial_population="1000",
    growth_rate="0.5",
    clearance_rate="0.1",
    niche_size="100000",
    simulation_time="24",
    time_step="0.1"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("model_bacterial_growth_dynamics_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("model_bacterial_growth_dynamics_output.txt", "w") as f:
    f.write("Biomni: Model Bacterial Growth Dynamics Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("model_bacterial_growth_dynamics completed successfully")
PYEOF
