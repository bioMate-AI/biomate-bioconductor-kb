#!/usr/bin/env python3
"""
Wrapper script for model_bacterial_growth_dynamics tool.
Uses scipy directly - no biomni dependency.
"""
import sys
import json
import numpy as np
from scipy.integrate import solve_ivp


def bacterial_dynamics(t, y, growth_rate, clearance_rate, niche_size):
    """ODE for bacterial population dynamics with logistic growth and clearance."""
    population = y[0]
    # Logistic growth with clearance
    dP_dt = growth_rate * population * (1 - population / niche_size) - clearance_rate * population
    return [dP_dt]


def model_bacterial_growth_dynamics(
    initial_population: float,
    growth_rate: float,
    clearance_rate: float,
    niche_size: float,
    simulation_time: float = 24.0,
    time_step: float = 0.1
) -> str:
    """
    Model bacterial population dynamics over time using ODEs.

    Args:
        initial_population: Initial bacterial population size (CFU/ml or cells)
        growth_rate: Bacterial growth rate (per hour)
        clearance_rate: Rate at which bacteria are cleared (per hour)
        niche_size: Maximum carrying capacity (CFU/ml or cells)
        simulation_time: Total simulation time in hours (default: 24)
        time_step: Time step for output (default: 0.1)

    Returns:
        Research log summarizing the simulation results
    """
    # Solve ODE
    t_span = (0, simulation_time)
    t_eval = np.arange(0, simulation_time + time_step, time_step)

    solution = solve_ivp(
        bacterial_dynamics,
        t_span,
        [initial_population],
        t_eval=t_eval,
        args=(growth_rate, clearance_rate, niche_size),
        method='RK45'
    )

    # Calculate key metrics
    final_population = solution.y[0][-1]
    max_population = np.max(solution.y[0])
    max_time = solution.t[np.argmax(solution.y[0])]

    # Determine growth phase
    if final_population > initial_population * 0.9 * niche_size / initial_population:
        phase = "stationary phase (near carrying capacity)"
    elif final_population > initial_population:
        phase = "exponential/log phase (still growing)"
    else:
        phase = "decline phase (clearance exceeds growth)"

    # Generate research log
    log = f"""## Bacterial Growth Dynamics Simulation

### Parameters
- Initial population: {initial_population:.2e} CFU/ml
- Growth rate: {growth_rate:.4f} per hour
- Clearance rate: {clearance_rate:.4f} per hour
- Niche size (carrying capacity): {niche_size:.2e} CFU/ml
- Simulation time: {simulation_time} hours

### Results
- Final population: {final_population:.2e} CFU/ml
- Maximum population: {max_population:.2e} CFU/ml (at t={max_time:.1f} h)
- Growth status: {phase}
- Net growth rate: {growth_rate - clearance_rate:.4f} per hour

### Time Course Data (selected points)
Time (h) | Population (CFU/ml)
---------|--------------------
"""
    # Add selected time points
    indices = np.linspace(0, len(solution.t) - 1, min(10, len(solution.t)), dtype=int)
    for idx in indices:
        log += f"{solution.t[idx]:8.1f} | {solution.y[0][idx]:.2e}\n"

    return log


def main():
    # Parse arguments
    args = {}
    i = 1
    while i < len(sys.argv):
        if sys.argv[i].startswith('--'):
            key = sys.argv[i][2:]
            if i + 1 < len(sys.argv) and not sys.argv[i + 1].startswith('--'):
                val = sys.argv[i + 1]
                # Skip empty values
                if val == '' or val is None:
                    i += 2
                    continue
                # Type conversion
                if val.lower() == 'true':
                    val = True
                elif val.lower() == 'false':
                    val = False
                else:
                    try:
                        val = float(val)
                    except ValueError:
                        pass
                args[key] = val
                i += 2
            else:
                args[key] = True
                i += 1
        else:
            i += 1

    # Get output path and remove from args
    output_path = args.pop('output', '/dev/stdout')

    # Call function
    result = model_bacterial_growth_dynamics(**args)

    # Write output
    with open(output_path, 'w') as f:
        if isinstance(result, str):
            f.write(result)
        elif isinstance(result, (dict, list)):
            json.dump(result, f, indent=2, default=str)
        else:
            f.write(str(result))


if __name__ == '__main__':
    main()
