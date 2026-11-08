#!/usr/bin/env python3
"""Append-only migration of a quiescent, preserved-owner run-state copy.

Rejects symlinks/special files, collisions and path escapes. Existing destination
entries are never modified. New files publish atomically without overwriting.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import tempfile


def file_hash(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def manifest(root):
    root = Path(root)
    if root.is_symlink() or not root.is_dir():
        raise ValueError('Run-state source must be a real directory')
    entries = {}
    for path in [root, *sorted(root.rglob('*'))]:
        info = path.lstat()
        if not stat.S_ISDIR(info.st_mode) and not stat.S_ISREG(info.st_mode):
            raise ValueError('Unsupported link/special file in run state')
        relative = path.relative_to(root).as_posix()
        entries[relative] = {'type': 'dir' if stat.S_ISDIR(info.st_mode) else 'file', 'mode': stat.S_IMODE(info.st_mode), 'uid': info.st_uid, 'gid': info.st_gid}
        if stat.S_ISREG(info.st_mode):
            entries[relative].update({'size': info.st_size, 'sha256': file_hash(path)})
    return entries


def _path(root, relative):
    part = Path(relative)
    if part.is_absolute() or '..' in part.parts:
        raise ValueError('Unsafe manifest path')
    result = root / part
    # Never traverse a pre-existing symlink, including a destination parent.
    for parent in [root, *result.parents]:
        if parent == root.parent:
            break
        if parent.is_symlink():
            raise ValueError('Symlink in destination path')
    return result


def verify(root, expected):
    root = Path(root)
    actual = manifest(root)
    for name, entry in expected.items():
        if actual.get(name) != entry:
            raise ValueError('Run-state manifest verification failed: ' + name)
    return True


def append_only_copy(source, destination):
    source, destination = Path(source), Path(destination)
    if source.resolve() == destination.resolve() or source.resolve() in destination.resolve().parents:
        raise ValueError('Source and destination must not overlap')
    expected = manifest(source)
    existing = manifest(destination) if destination.exists() else {}
    # Check every collision before writing any file.
    for name, entry in expected.items():
        path = _path(destination, name)
        if path.exists() or path.is_symlink():
            if existing.get(name) != entry:
                raise ValueError('Run-state collision; nothing overwritten: ' + name)
    added = 0
    for name, entry in sorted(expected.items(), key=lambda item: (len(Path(item[0]).parts), item[0])):
        target = _path(destination, name)
        if name in existing:
            continue
        if entry['type'] == 'dir':
            target.mkdir(mode=0o700)
            os.chown(target, entry['uid'], entry['gid'])
            target.chmod(entry['mode'])
        else:
            fd, temporary = tempfile.mkstemp(prefix='.biomate-run-copy-', dir=target.parent)
            try:
                with os.fdopen(fd, 'wb') as handle, open(source / name, 'rb') as incoming:
                    shutil.copyfileobj(incoming, handle)
                    handle.flush(); os.fsync(handle.fileno())
                os.chown(temporary, entry['uid'], entry['gid'])
                os.chmod(temporary, entry['mode'])
                if file_hash(temporary) != entry['sha256']:
                    raise ValueError('Source changed during migration')
                os.link(temporary, target)  # exclusive publish: never overwrite
            finally:
                os.unlink(temporary)
            added += 1
    verify(destination, expected)
    return {'manifest': expected, 'addedFiles': added}
