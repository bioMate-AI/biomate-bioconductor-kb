"""Differentiable atom → 2D image forward model.

Pipeline:  atomic coordinates (Cα) → 3D Gaussian-blurred density → rotate by pose
                                  → project along z → CTF → noisy image

All steps are differentiable in PyTorch, allowing ∇_coords log p(image | conformer, pose).

This is the core forward operator used by the per-particle likelihood.
"""

from __future__ import annotations

import math

import torch
import torch.nn.functional as F

from .ctf import ctf2d


# ──────────────────────────────────────────────────────────────────────────────
# Pose representations
# ──────────────────────────────────────────────────────────────────────────────

def quaternion_to_rotation_matrix(q: torch.Tensor) -> torch.Tensor:
    """(..., 4) quaternion (w, x, y, z) → (..., 3, 3) rotation matrix."""
    w, x, y, z = q.unbind(-1)
    B = q.shape[:-1]
    R = torch.stack(
        [
            1 - 2 * (y * y + z * z), 2 * (x * y - z * w),     2 * (x * z + y * w),
            2 * (x * y + z * w),     1 - 2 * (x * x + z * z), 2 * (y * z - x * w),
            2 * (x * z - y * w),     2 * (y * z + x * w),     1 - 2 * (x * x + y * y),
        ],
        dim=-1,
    ).reshape(*B, 3, 3)
    return R


def euler_zyz_to_matrix(alpha: torch.Tensor, beta: torch.Tensor, gamma: torch.Tensor) -> torch.Tensor:
    """RELION-convention Euler angles (rot, tilt, psi) → rotation matrix.

    Each angle is in radians. Output shape: input shape + (3, 3).
    """
    ca, sa = torch.cos(alpha), torch.sin(alpha)
    cb, sb = torch.cos(beta),  torch.sin(beta)
    cg, sg = torch.cos(gamma), torch.sin(gamma)
    R = torch.stack(
        [
            cg * cb * ca - sg * sa,   cg * cb * sa + sg * ca,  -cg * sb,
            -sg * cb * ca - cg * sa, -sg * cb * sa + cg * ca,   sg * sb,
            sb * ca,                  sb * sa,                  cb,
        ],
        dim=-1,
    ).reshape(*alpha.shape, 3, 3)
    return R


# ──────────────────────────────────────────────────────────────────────────────
# Atom → image projection (differentiable)
# ──────────────────────────────────────────────────────────────────────────────

def project_atoms_to_image(
    coords: torch.Tensor,
    R: torch.Tensor,
    t: torch.Tensor,
    *,
    D: int,
    apix: float,
    sigma_a: float = 1.5,
    weights: torch.Tensor | None = None,
) -> torch.Tensor:
    """Project a set of atoms to a 2D image via 3D Gaussian splatting + sum along z.

    Implementation detail: rather than building a 3D volume (memory-heavy at D=256 ⇒ 16M voxels),
    we splat each atom's *projected* 2D Gaussian directly into the image. This is the analytical
    z-integral of a 3D isotropic Gaussian: a 2D Gaussian with the same σ in xy.

    Parameters
    ----------
    coords : (B, N, 3)  atomic Cα coordinates in Å (rest-frame; protein-centered)
    R      : (B, 3, 3)  rotation matrix per particle
    t      : (B, 2)     translation (image-plane shift) in Å
    D      : image size in pixels (square)
    apix   : pixel size in Å
    sigma_a: atomic Gaussian σ in Å (typical: 1.0–2.0 for Cα at 4 Å resolution)
    weights: (N,) or (B, N) optional atom-wise mass / occupancy; defaults to 1.

    Returns
    -------
    images : (B, D, D)  projected images (sum of 2D Gaussians)
    """
    device = coords.device
    dtype = coords.dtype
    B, N, _ = coords.shape

    # Apply rotation: x' = R @ x  →  shape (B, N, 3)
    coords_rot = torch.einsum("bij,bnj->bni", R, coords)
    xy = coords_rot[..., :2] + t.unsqueeze(1)              # (B, N, 2) in Å

    # Convert to pixel coords centered at image middle
    xy_pix = xy / apix + (D - 1) / 2.0                     # (B, N, 2) in pixels

    # Gaussian σ in pixels
    sigma_px = sigma_a / apix

    # Build image. We use the closed-form 2D Gaussian footprint within a bounding box
    # per atom (3σ radius) to avoid evaluating across all D² pixels for every atom.
    radius = max(int(math.ceil(3 * sigma_px)), 2)

    image = torch.zeros(B, D, D, device=device, dtype=dtype)

    # Atom weights
    if weights is None:
        w = torch.ones(N, device=device, dtype=dtype)
    else:
        w = weights.to(device=device, dtype=dtype)
    if w.dim() == 1:
        w = w.unsqueeze(0).expand(B, -1)                   # (B, N)

    # We vectorize by gathering each atom's local footprint.
    # Offsets: (2r+1, 2r+1) grid centered at 0
    offs = torch.arange(-radius, radius + 1, device=device, dtype=dtype)
    oy, ox = torch.meshgrid(offs, offs, indexing="ij")     # (Lk, Lk)
    Lk = 2 * radius + 1
    ox = ox.reshape(1, 1, Lk, Lk)                          # (1, 1, Lk, Lk)
    oy = oy.reshape(1, 1, Lk, Lk)

    # Atom integer pixel centers and fractional shifts
    x0 = torch.floor(xy_pix[..., 0]).long()                # (B, N)
    y0 = torch.floor(xy_pix[..., 1]).long()
    dx = xy_pix[..., 0] - x0.to(dtype)                     # (B, N) in [0,1)
    dy = xy_pix[..., 1] - y0.to(dtype)

    # 2D Gaussian footprint per atom (B, N, Lk, Lk)
    fx = (ox - dx.unsqueeze(-1).unsqueeze(-1))             # (B, N, 1, Lk) → (B, N, Lk, Lk)
    fy = (oy - dy.unsqueeze(-1).unsqueeze(-1))
    g = torch.exp(-(fx**2 + fy**2) / (2 * sigma_px**2))
    g = g / (2 * math.pi * sigma_px**2)                    # normalised so each atom contributes ~weight
    g = g * w.unsqueeze(-1).unsqueeze(-1)

    # Accumulate into image. To stay differentiable AND vectorize, use index_put with accumulate.
    # Build flat indices: target pixel (px, py) = x0 + ox_int, y0 + oy_int
    ox_int = torch.arange(-radius, radius + 1, device=device).reshape(1, 1, 1, Lk)
    oy_int = torch.arange(-radius, radius + 1, device=device).reshape(1, 1, Lk, 1)
    px = x0.unsqueeze(-1).unsqueeze(-1) + ox_int           # (B, N, 1, Lk) → (B, N, Lk, Lk) by broadcast
    py = y0.unsqueeze(-1).unsqueeze(-1) + oy_int
    px = px.expand(-1, -1, Lk, Lk)
    py = py.expand(-1, -1, Lk, Lk)

    # Mask out-of-bounds pixels
    valid = (px >= 0) & (px < D) & (py >= 0) & (py < D)
    px = px.clamp(0, D - 1)
    py = py.clamp(0, D - 1)
    g = g * valid.to(dtype)

    # Per-batch scatter-add (loop on batch dim to keep memory bounded)
    flat_idx = py * D + px                                  # (B, N, Lk, Lk) flat image index
    for b in range(B):
        flat_g = g[b].reshape(-1)                          # (N*Lk*Lk,)
        flat_i = flat_idx[b].reshape(-1)                   # (N*Lk*Lk,)
        image[b].view(-1).index_add_(0, flat_i, flat_g)

    return image


# ──────────────────────────────────────────────────────────────────────────────
# Full forward model: atoms → CTF-corrupted image
# ──────────────────────────────────────────────────────────────────────────────

def render_particle(
    coords: torch.Tensor,
    R: torch.Tensor,
    t: torch.Tensor,
    *,
    D: int,
    apix: float,
    sigma_a: float = 1.5,
    weights: torch.Tensor | None = None,
    # CTF
    defocus_u: torch.Tensor,
    defocus_v: torch.Tensor,
    astig_angle_deg: torch.Tensor,
    voltage_kV: float | torch.Tensor = 300.0,
    cs_mm: float | torch.Tensor = 2.0,
    amp_contrast: float | torch.Tensor = 0.1,
    phase_shift_deg: float | torch.Tensor = 0.0,
    bfactor: float | torch.Tensor = 0.0,
) -> torch.Tensor:
    """Differentiable atom → CTF-corrupted real-space image.

    Returns (B, D, D) real-space image with CTF applied.
    """
    proj = project_atoms_to_image(
        coords, R, t, D=D, apix=apix, sigma_a=sigma_a, weights=weights
    )                                                        # (B, D, D)

    # FFT and CTF in frequency space
    proj_ft = torch.fft.fftshift(torch.fft.fft2(proj), dim=(-2, -1))
    ctf = ctf2d(
        D=D, apix=apix,
        defocus_u=defocus_u, defocus_v=defocus_v, astig_angle_deg=astig_angle_deg,
        voltage_kV=voltage_kV, cs_mm=cs_mm, amp_contrast=amp_contrast,
        phase_shift_deg=phase_shift_deg, bfactor=bfactor,
        device=coords.device, dtype=coords.dtype,
    )                                                        # (B, D, D)
    image_ft = proj_ft * ctf
    image = torch.fft.ifft2(torch.fft.ifftshift(image_ft, dim=(-2, -1))).real
    return image


__all__ = [
    "quaternion_to_rotation_matrix",
    "euler_zyz_to_matrix",
    "project_atoms_to_image",
    "render_particle",
]
