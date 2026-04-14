#!/bin/bash -ue
python3 << 'PYEOF'
import json, csv, math, sys
from datetime import datetime

# -- PK parameters (Overgaard et al. 2019) ---------------------------------
CL_ml_h    = 41.0
V1_ml      = 8.18 * 1000.0     # L -> mL
Q_ml_h     = 89.5
V2_ml      = 4.50 * 1000.0
ka_h       = 0.0116
F_bio      = 0.89
dose_mg    = 1.0
n_weeks    = 30
MW         = 4113.58       # g/mol
tau_h      = 168.0                           # weekly dosing interval (h)

# -- ODE solver (4th-order Runge-Kutta) ------------------------------------
def rk4_step(f, y, t, dt):
    k1 = f(y, t)
    k2 = f([yi + dt/2 * ki for yi, ki in zip(y, k1)], t + dt/2)
    k3 = f([yi + dt/2 * ki for yi, ki in zip(y, k2)], t + dt/2)
    k4 = f([yi + dt   * ki for yi, ki in zip(y, k3)], t + dt)
    return [yi + dt/6 * (k1i + 2*k2i + 2*k3i + k4i)
            for yi, k1i, k2i, k3i, k4i in zip(y, k1, k2, k3, k4)]

def pk_odes(y, t):
    '''2-compartment SC model (apparent parameters; F absorbed into V and CL).'''
    A_depot, A_c, A_p = y
    dA_depot = -ka_h * A_depot
    dA_c     = F_bio * ka_h * A_depot - (CL_ml_h + Q_ml_h)/V1_ml * A_c + Q_ml_h/V2_ml * A_p
    dA_p     = Q_ml_h/V1_ml * A_c - Q_ml_h/V2_ml * A_p
    return [dA_depot, dA_c, dA_p]

# -- Simulate 30 weekly SC doses --------------------------------------------
dose_ng = dose_mg * 1e6    # mg -> ng (1 mg = 1e6 ng)
dt_h    = 0.5              # integration step (h)
t_end   = tau_h * n_weeks

pk_time_h    = []
pk_conc_ngml = []
pk_conc_nm   = []

y = [0.0, 0.0, 0.0]   # [A_depot_ng, A_central_ng, A_peripheral_ng]
t = 0.0
next_dose_t = 0.0

while t <= t_end + dt_h:
    # Administer dose at each weekly interval
    if abs(t - next_dose_t) < dt_h / 2:
        y[0] += dose_ng
        next_dose_t += tau_h

    C_ngml = y[1] / V1_ml          # ng/mL
    C_nm   = C_ngml * 1000.0 / MW  # nM  (ng/mL * 1000 / (g/mol) = nM)

    pk_time_h.append(round(t, 2))
    pk_conc_ngml.append(round(C_ngml, 6))
    pk_conc_nm.append(round(C_nm, 6))

    y = rk4_step(pk_odes, y, t, dt_h)
    t += dt_h

# -- PK metrics (steady-state = last 2 weekly cycles) ---------------------
ss_start = int((n_weeks - 2) * tau_h / dt_h)
ss_conc  = pk_conc_nm[ss_start:]
Cmax_ss  = max(ss_conc)
Cmin_ss  = min(ss_conc)
AUCtau   = sum(ss_conc) * dt_h / 2.0   # trapezoidal, 1 tau

# -- PD model: indirect GLP-1R Emax body weight model ---------------------
Emax_kg_wk  = -0.22
EC50_nm     = 5.0
baseline_wt = 92.0

weight_kg    = baseline_wt
pd_week      = [0]
pd_weight    = [baseline_wt]

steps_per_week = int(tau_h / dt_h)

for w in range(1, n_weeks + 1):
    # Cmax within this week (representative peak)
    wk_start = int((w - 1) * steps_per_week)
    wk_end   = min(wk_start + steps_per_week, len(pk_conc_nm))
    wk_conc  = pk_conc_nm[wk_start:wk_end]
    C_peak   = max(wk_conc) if wk_conc else Cmax_ss

    # Emax PD equation
    E_wk     = Emax_kg_wk * C_peak / (EC50_nm + C_peak)
    weight_kg += E_wk
    pd_week.append(w)
    pd_weight.append(round(weight_kg, 4))

weight_loss_30w = pd_weight[-1] - baseline_wt

# -- Write PK curve CSV -----------------------------------------------------
with open('pk_simulation.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['time_h', 'time_weeks', 'conc_ngml', 'conc_nM'])
    for i, (th, c_ng, c_nm) in enumerate(zip(pk_time_h, pk_conc_ngml, pk_conc_nm)):
        if i % 4 == 0:  # downsample 2h resolution for readability
            w.writerow([th, round(th / 168, 4), c_ng, c_nm])

# -- Write PD weight curve CSV ----------------------------------------------
with open('pd_weight_curve.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['week', 'weight_kg', 'weight_loss_kg'])
    for wk, wt in zip(pd_week, pd_weight):
        w.writerow([wk, wt, round(wt - baseline_wt, 4)])

# -- Plot -------------------------------------------------------------------
try:
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    import numpy as np

    fig, axes = plt.subplots(1, 3, figsize=(15, 4))

    # Panel 1: PK curve (nM vs weeks)
    t_weeks = [t / 168 for t in pk_time_h]
    axes[0].plot(t_weeks, pk_conc_nm, 'b-', linewidth=0.8, alpha=0.8)
    axes[0].axhline(y=30.0, color='r', linestyle='--', alpha=0.6,
                    label='Overgaard Cmax,ss ref (30 nM)')
    axes[0].set_xlabel('Time (weeks)')
    axes[0].set_ylabel('Semaglutide (nM)')
    axes[0].set_title('Plasma PK (2-compartment SC)')
    axes[0].legend(fontsize=7)
    axes[0].grid(alpha=0.3)

    # Panel 2: Body weight over time
    axes[1].plot(pd_week, pd_weight, 'g-o', markersize=2, linewidth=1.5)
    axes[1].axhline(y=baseline_wt + -6.0, color='r',
                    linestyle='--', alpha=0.6, label='Min threshold (-6 kg)')
    axes[1].axhline(y=baseline_wt + -3.0, color='r',
                    linestyle='--', alpha=0.6, label='Max threshold (-3 kg)')
    axes[1].axhline(y=baseline_wt - 4.53, color='k', linestyle=':', alpha=0.8,
                    label='SUSTAIN-1 observed (-4.53 kg)')
    axes[1].set_xlabel('Week')
    axes[1].set_ylabel('Body Weight (kg)')
    axes[1].set_title('Predicted Body Weight -- GLP-1R Emax Model')
    axes[1].legend(fontsize=7)
    axes[1].grid(alpha=0.3)

    # Panel 3: Concentration-effect relationship
    c_range = [i * 0.5 for i in range(0, 81)]
    e_range = [Emax_kg_wk * c / (EC50_nm + c) for c in c_range]
    axes[2].plot(c_range, e_range, 'purple', linewidth=2)
    axes[2].axvline(x=Cmax_ss, color='b', linestyle='--', alpha=0.8,
                    label=f'Cmax,ss = {Cmax_ss:.1f} nM')
    axes[2].axvline(x=EC50_nm, color='r', linestyle=':', alpha=0.8,
                    label=f'EC50 = {EC50_nm} nM')
    axes[2].set_xlabel('Semaglutide (nM)')
    axes[2].set_ylabel('Weekly Weight Change (kg/wk)')
    axes[2].set_title('PK/PD: Emax Concentration-Effect')
    axes[2].legend(fontsize=7)
    axes[2].grid(alpha=0.3)

    plt.tight_layout()
    plt.savefig('pkpd_plot.png', dpi=150, bbox_inches='tight')
    plt.close()
except Exception as e:
    import base64
    _b64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwADhQGAWjR9awAAAABJRU5ErkJggg=='
    with open('pkpd_plot.png', 'wb') as imgf:
        imgf.write(base64.b64decode(_b64))
    print(f'WARNING: matplotlib unavailable: {e}', file=sys.stderr)

# -- Pass/Fail evaluation ---------------------------------------------------
cmax_ref   = 30.0
cmax_tol   = 0.30
cmax_lo    = cmax_ref * (1 - cmax_tol)
cmax_hi    = cmax_ref * (1 + cmax_tol)
wt_min     = -6.0
wt_max     = -3.0

pass_cmax  = cmax_lo <= Cmax_ss <= cmax_hi
pass_wt    = wt_min  <= weight_loss_30w <= wt_max
overall    = 'PASS' if (pass_cmax and pass_wt) else 'FAIL'

report = {
    'p0_check':    'P0-E: Semaglutide PKPD Validation',
    'references': [
        'Overgaard RV et al. Diabetes Therapy 10:649-662, 2019. doi:10.1007/s13300-019-0581-y',
        'Sorli C et al. (SUSTAIN-1) Lancet Diabetes Endocrinol 5:251-260, 2017. doi:10.1016/S2213-8587(17)30013-X',
    ],
    'pk_model': {
        'type': '2-compartment SC',
        'CL_ml_h': CL_ml_h, 'V1_L': 8.18,
        'Q_ml_h': Q_ml_h,   'V2_L': 4.50,
        'ka_h': ka_h,        'F': F_bio,
        'dose_mg': dose_mg,  'tau_h': tau_h,
    },
    'pk_results': {
        'Cmax_ss_nM':        round(Cmax_ss, 2),
        'Cmin_ss_nM':        round(Cmin_ss, 2),
        'AUCtau_nM_h':       round(AUCtau, 1),
        'Cmax_reference_nM': cmax_ref,
        'Cmax_deviation_pct': round(100 * (Cmax_ss - cmax_ref) / cmax_ref, 1),
        'pass_cmax':         pass_cmax,
    },
    'pd_results': {
        'weight_loss_30w_kg':         round(weight_loss_30w, 2),
        'sustain1_observed_kg':        -4.53,
        'sustain1_ci_95':              '-5.34 to -3.72 kg',
        'pass_criterion_range_kg':     f'{wt_min} to {wt_max}',
        'pass_weight_loss':            pass_wt,
        'emax_kg_wk':                  Emax_kg_wk,
        'ec50_nM':                     EC50_nm,
    },
    'overall':    overall,
    'timestamp':  datetime.utcnow().isoformat() + 'Z',
}

with open('p0_pkpd_report.json', 'w') as jf:
    json.dump(report, jf, indent=2)

print(f'P0-E Semaglutide PKPD Validation')
print(f'  Cmax,ss:           {Cmax_ss:.2f} nM  (ref {cmax_ref} nM +/- {int(cmax_tol*100)}% -> {cmax_lo:.1f}-{cmax_hi:.1f} nM)  {"PASS" if pass_cmax else "FAIL"}')
print(f'  Weight loss 30w:   {weight_loss_30w:.2f} kg  (SUSTAIN-1: -4.53 kg; criterion: {wt_min} to {wt_max} kg)  {"PASS" if pass_wt else "FAIL"}')
print(f'  OVERALL: {overall}')
PYEOF
