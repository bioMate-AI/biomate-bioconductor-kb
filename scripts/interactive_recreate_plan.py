#!/usr/bin/env python3
"""Build a private Docker Engine create payload from an actual container inspect.

Planning only: no Docker calls, filesystem migration, container stop or restart.
Using the Engine payload preserves HostConfig options that a reconstructed shell
`docker run` line would silently discard. The caller must finish and verify the
append-only run-state migration and approve a rollback snapshot before applying.
"""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path


def build_payload(inspect, snapshot_image, socket_gid, state_root):
    if not snapshot_image.startswith('sha256:'):
        raise ValueError('Use the immutable reviewed snapshot image ID')
    if not isinstance(socket_gid, int) or socket_gid < 0:
        raise ValueError('A real host socket group ID is required')
    if not os.path.isabs(state_root) or state_root in ('/', '/tmp', '/var', '/opt'):
        raise ValueError('Use a dedicated absolute persistent state directory')
    config = copy.deepcopy(inspect['Config'])
    host = copy.deepcopy(inspect['HostConfig'])
    config['Image'] = snapshot_image
    for item in inspect.get('Mounts', []):
        if item.get('Type') != 'bind':
            raise ValueError('Non-bind mount requires explicit preserved-volume review: ' + item['Destination'])
    mounts = {item['Destination']: item for item in inspect.get('Mounts', [])}
    binds = list(host.get('Binds') or [])
    for destination, source in [('/var/run/docker.sock', '/var/run/docker.sock'), ('/tmp/nextflow_runs', state_root)]:
        previous = mounts.get(destination)
        if previous:
            if previous.get('Type') != 'bind' or previous.get('Source') != source or not previous.get('RW'):
                raise ValueError('Existing mount differs from the reviewed writable bind: ' + destination)
        else:
            binds.append(source + ':' + destination + ':rw')
    host['Binds'] = binds
    groups = [str(group) for group in host.get('GroupAdd') or []]
    if str(socket_gid) not in groups:
        groups.append(str(socket_gid))
    host['GroupAdd'] = groups
    # Preserve assigned public ports even when original create requested a random port.
    ports = host.get('PortBindings') or {}
    assigned = inspect.get('NetworkSettings', {}).get('Ports') or {}
    for port, values in ports.items():
        if any(not item.get('HostPort') for item in values or []):
            if not assigned.get(port):
                raise ValueError('Cannot preserve an unallocated host port: ' + port)
            ports[port] = copy.deepcopy(assigned[port])
    if host.get('PortBindings') is not None:
        host['PortBindings'] = ports
    endpoints = {}
    for name, original in inspect.get('NetworkSettings', {}).get('Networks', {}).items():
        # Generated endpoint IDs/address caches are not create inputs. Preserve
        # declared aliases/static IPAM/links/driver options on every network.
        endpoints[name] = {key: copy.deepcopy(original[key]) for key in ('IPAMConfig', 'Links', 'Aliases', 'DriverOpts', 'GwPriority', 'MacAddress') if original.get(key) is not None}
    return {**config, 'HostConfig': host, 'NetworkingConfig': {'EndpointsConfig': endpoints}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inspect', required=True)
    parser.add_argument('--snapshot-image', required=True)
    parser.add_argument('--socket-gid', type=int, required=True)
    parser.add_argument('--state-root', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    data = json.loads(Path(args.inspect).read_text())
    inspection = data[0] if isinstance(data, list) else data
    payload = build_payload(inspection, args.snapshot_image, args.socket_gid, args.state_root)
    raw = (json.dumps(payload, sort_keys=True, indent=2) + '\n').encode()
    fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'wb') as handle:
        handle.write(raw)
    print(json.dumps({'planned': True, 'sha256': hashlib.sha256(raw).hexdigest(), 'networks': len(payload['NetworkingConfig']['EndpointsConfig']), 'mountCount': len(inspection.get('Mounts', [])), 'addedSocketGroup': args.socket_gid}))


if __name__ == '__main__':
    main()
