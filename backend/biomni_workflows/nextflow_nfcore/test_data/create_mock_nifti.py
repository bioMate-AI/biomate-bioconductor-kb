#!/usr/bin/env python3
"""
Create mock NIfTI files for testing bioimaging workflows.
"""

import os
import numpy as np

def create_mock_nifti(path, shape=(64, 64, 32), dtype=np.float32):
    """
    Create a mock 3D NIfTI file with random data and sphere structures.

    Args:
        path: Output path for the .nii.gz file
        shape: 3D shape tuple (x, y, z)
        dtype: Data type for the array

    Returns:
        Path to created file
    """
    try:
        import nibabel as nib

        # Create array with background noise
        data = np.random.randn(*shape).astype(dtype) * 10 + 50

        # Add some sphere-like structures to simulate brain regions
        for _ in range(5):
            cx = np.random.randint(10, shape[0]-10)
            cy = np.random.randint(10, shape[1]-10)
            cz = np.random.randint(5, shape[2]-5)
            radius = np.random.randint(5, 15)
            intensity = np.random.randint(100, 200)

            for x in range(max(0, cx-radius), min(shape[0], cx+radius)):
                for y in range(max(0, cy-radius), min(shape[1], cy+radius)):
                    for z in range(max(0, cz-radius//2), min(shape[2], cz+radius//2)):
                        dist = np.sqrt((x-cx)**2 + (y-cy)**2 + (z-cz)**2 * 4)
                        if dist < radius:
                            data[x, y, z] = intensity * (1 - dist/radius/2)

        # Create NIfTI image with standard affine
        affine = np.eye(4)
        affine[0, 0] = 1.0  # 1mm voxel size
        affine[1, 1] = 1.0
        affine[2, 2] = 2.0  # 2mm slice thickness

        img = nib.Nifti1Image(data, affine)

        # Ensure directory exists
        os.makedirs(os.path.dirname(path) if os.path.dirname(path) else '.', exist_ok=True)

        # Save the file
        nib.save(img, path)
        print(f"Created mock NIfTI: {path} with shape {shape}")
        return path

    except ImportError as e:
        print(f"Error: nibabel not installed. Install with: pip install nibabel")
        raise


def create_mock_4d_nifti(path, shape=(64, 64, 32, 4), dtype=np.float32):
    """
    Create a mock 4D NIfTI file with multiple modalities (like BRATS data).

    Args:
        path: Output path for the .nii.gz file
        shape: 4D shape tuple (x, y, z, modalities)
        dtype: Data type for the array

    Returns:
        Path to created file
    """
    try:
        import nibabel as nib

        # Create 4D array
        data = np.zeros(shape, dtype=dtype)

        # Fill each modality with different patterns
        modality_names = ['FLAIR', 'T1w', 't1gd', 'T2w']
        for m in range(shape[3]):
            # Base noise
            data[:, :, :, m] = np.random.randn(shape[0], shape[1], shape[2]).astype(dtype) * 10 + 50 + m*20

            # Add structures
            for _ in range(3):
                cx = np.random.randint(10, shape[0]-10)
                cy = np.random.randint(10, shape[1]-10)
                cz = np.random.randint(5, shape[2]-5)
                radius = np.random.randint(5, 12)
                intensity = np.random.randint(100, 200) + m * 30

                for x in range(max(0, cx-radius), min(shape[0], cx+radius)):
                    for y in range(max(0, cy-radius), min(shape[1], cy+radius)):
                        for z in range(max(0, cz-radius//2), min(shape[2], cz+radius//2)):
                            dist = np.sqrt((x-cx)**2 + (y-cy)**2 + (z-cz)**2 * 4)
                            if dist < radius:
                                data[x, y, z, m] = intensity * (1 - dist/radius/2)

        # Create NIfTI image
        affine = np.eye(4)
        img = nib.Nifti1Image(data, affine)

        os.makedirs(os.path.dirname(path) if os.path.dirname(path) else '.', exist_ok=True)
        nib.save(img, path)
        print(f"Created mock 4D NIfTI: {path} with shape {shape}")
        return path

    except ImportError:
        print("Error: nibabel not installed")
        raise


def create_mock_segmentation(path, shape=(64, 64, 32), num_labels=3):
    """
    Create a mock segmentation NIfTI file with labeled regions.

    Args:
        path: Output path
        shape: 3D shape tuple
        num_labels: Number of different labels (0=background)

    Returns:
        Path to created file
    """
    try:
        import nibabel as nib

        # Create array with background (0)
        data = np.zeros(shape, dtype=np.int16)

        # Add labeled regions
        for label in range(1, num_labels + 1):
            cx = np.random.randint(15, shape[0]-15)
            cy = np.random.randint(15, shape[1]-15)
            cz = np.random.randint(8, shape[2]-8)
            radius = np.random.randint(8, 15)

            for x in range(max(0, cx-radius), min(shape[0], cx+radius)):
                for y in range(max(0, cy-radius), min(shape[1], cy+radius)):
                    for z in range(max(0, cz-radius//2), min(shape[2], cz+radius//2)):
                        dist = np.sqrt((x-cx)**2 + (y-cy)**2 + (z-cz)**2 * 4)
                        if dist < radius:
                            data[x, y, z] = label

        affine = np.eye(4)
        img = nib.Nifti1Image(data, affine)

        os.makedirs(os.path.dirname(path) if os.path.dirname(path) else '.', exist_ok=True)
        nib.save(img, path)
        print(f"Created mock segmentation NIfTI: {path} with {num_labels} labels")
        return path

    except ImportError:
        print("Error: nibabel not installed")
        raise


def main():
    """Create test data files."""
    test_dir = os.path.dirname(os.path.abspath(__file__))

    # Create 3D NIfTI files for registration tests
    create_mock_nifti(os.path.join(test_dir, 'mock_fixed_image.nii.gz'), shape=(64, 64, 32))
    create_mock_nifti(os.path.join(test_dir, 'mock_moving_image.nii.gz'), shape=(64, 64, 32))

    # Create 4D NIfTI for segmentation tests
    create_mock_4d_nifti(os.path.join(test_dir, 'mock_4d_brain.nii.gz'), shape=(64, 64, 32, 4))

    # Create segmentation mask
    create_mock_segmentation(os.path.join(test_dir, 'mock_segmentation.nii.gz'), shape=(64, 64, 32))

    print("\nAll mock NIfTI files created successfully!")


if __name__ == '__main__':
    main()
