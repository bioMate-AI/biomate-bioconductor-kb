"""Contrast transfer function — differentiable, PyTorch.

CTF model: cosine-form astigmatic CTF with envelope decay.

    Λ(s) = π λ s² (Δf − ½ λ² s² Cs)            (defocus phase)
    χ(s) = Λ(s) + arcsin(w)                       (amplitude contrast offset)
    CTF(s, φ) = sin(Λ(s) + ½(Δf_u − Δf_v) · cos(2(φ − α)))   (astigmatic)

where s = spatial frequency (1/Å), φ = azimuth in Fourier plane,
Δf_u/Δf_v = principal defocuses (Å), α = astigmatism angle,
λ = electron wavelength (Å), Cs = spherical aberration (Å),
w = amplitude contrast (0–1).
"""

from __future__ import annotations

import math

import torch


def electron_wavelength(voltage_kV: float) -> float:
    """Relativistic de Broglie wavelength (Å) for an electron at given voltage."""
    h = 6.62607015e-34
    m = 9.1093837015e-31
    e = 1.602176634e-19
    c = 299_792_458.0
    V = voltage_kV * 1e3
    return float(h / math.sqrt(2 * m * e * V * (1 + e * V / (2 * m * c**2))) * 1e10)


def fourier_grid(D: int, apix: float, device=None, dtype=torch.float32) -> tuple[torch.Tensor, torch.Tensor]:
    """Return spatial frequency grids (s_x, s_y) for an D×D real-space image of pixel size apix Å.

    Frequency units: 1/Å. Origin is image center (consistent with fftshift convention).
    """
    f = torch.fft.fftshift(torch.fft.fftfreq(D, d=apix, device=device)).to(dtype)
    sy, sx = torch.meshgrid(f, f, indexing="ij")
    return sx, sy


def ctf2d(
    D: int,
    apix: float,
    defocus_u: torch.Tensor,
    defocus_v: torch.Tensor,
    astig_angle_deg: torch.Tensor,
    voltage_kV: torch.Tensor | float,
    cs_mm: torch.Tensor | float,
    amp_contrast: torch.Tensor | float = 0.1,
    phase_shift_deg: torch.Tensor | float = 0.0,
    bfactor: torch.Tensor | float = 0.0,
    device=None,
    dtype=torch.float32,
) -> torch.Tensor:
    """Compute per-particle CTF on an D×D Fourier-space grid.

    Inputs broadcast over a particle batch dimension B.

    Returns
    -------
    Tensor of shape (B, D, D), values in [-1, 1], with B-leading batching if defocus_u has shape (B,).
    """
    # Coerce scalars to tensors
    def _t(x):
        if isinstance(x, torch.Tensor):
            return x.to(device=device, dtype=dtype)
        return torch.tensor(x, device=device, dtype=dtype)

    du = _t(defocus_u)            # (B,) or scalar — Å
    dv = _t(defocus_v)            # Å
    ast = _t(astig_angle_deg) * math.pi / 180.0  # rad
    kv = _t(voltage_kV)
    cs = _t(cs_mm) * 1e7          # mm → Å
    w = _t(amp_contrast)
    phase = _t(phase_shift_deg) * math.pi / 180.0
    bf = _t(bfactor)

    # Wavelength: convert voltage → Å (scalar)
    if kv.dim() == 0:
        lam = electron_wavelength(float(kv))
    else:
        lam = torch.stack([torch.tensor(electron_wavelength(float(v)), device=device, dtype=dtype) for v in kv])

    sx, sy = fourier_grid(D, apix, device=device, dtype=dtype)
    s2 = (sx**2 + sy**2)         # (D, D)
    phi = torch.atan2(sy, sx)    # (D, D)

    # Add batch dim so broadcasting is explicit
    s2 = s2.unsqueeze(0)         # (1, D, D)
    phi = phi.unsqueeze(0)       # (1, D, D)
    du = du.reshape(-1, 1, 1)
    dv = dv.reshape(-1, 1, 1)
    ast = ast.reshape(-1, 1, 1)
    cs = cs.reshape(-1, 1, 1) if cs.dim() else cs
    bf = bf.reshape(-1, 1, 1) if bf.dim() else bf
    w = w.reshape(-1, 1, 1) if w.dim() else w
    phase = phase.reshape(-1, 1, 1) if phase.dim() else phase

    # Effective defocus at azimuth phi (astigmatic average + half-difference cos(2(phi-α)))
    df = 0.5 * (du + dv) + 0.5 * (du - dv) * torch.cos(2 * (phi - ast))   # (B, D, D)

    # Phase function χ(s) = π λ s² Δf − ½ π λ³ s⁴ Cs + phase shift − arcsin(w)
    lam_t = lam if isinstance(lam, torch.Tensor) else torch.tensor(lam, device=device, dtype=dtype)
    chi = math.pi * lam_t * s2 * df - 0.5 * math.pi * lam_t**3 * s2**2 * cs + phase - torch.asin(w)

    ctf = -torch.sin(chi)
    if torch.any(bf != 0):
        ctf = ctf * torch.exp(-bf * s2 / 4.0)
    return ctf


__all__ = ["electron_wavelength", "fourier_grid", "ctf2d"]
