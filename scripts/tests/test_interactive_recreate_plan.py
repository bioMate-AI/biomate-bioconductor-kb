import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('interactive_recreate_plan', Path(__file__).parents[1] / 'interactive_recreate_plan.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class RecreatePlanTests(unittest.TestCase):
    def fixture(self):
        return {'Config': {'Image': 'old:tag', 'Env': ['PATH=/kept', 'TEST_PRIVATE_VALUE=never-print'], 'User': 'galaxy', 'WorkingDir': '/app', 'Entrypoint': ['/entrypoint.sh'], 'Cmd': ['serve'], 'Labels': {'keep': 'yes'}}, 'HostConfig': {'Binds': ['/db:/app/database:rw', '/tools:/app/tools:ro'], 'GroupAdd': ['1000'], 'NetworkMode': 'dev-net', 'PortBindings': {'8080/tcp': [{'HostIp': '127.0.0.1', 'HostPort': '8081'}]}, 'RestartPolicy': {'Name': 'unless-stopped'}, 'SecurityOpt': ['no-new-privileges'], 'CapDrop': ['NET_RAW'], 'ReadonlyRootfs': False, 'Memory': 4000000}, 'Mounts': [{'Type': 'bind', 'Source': '/db', 'Destination': '/app/database', 'RW': True}, {'Type': 'bind', 'Source': '/tools', 'Destination': '/app/tools', 'RW': False}], 'NetworkSettings': {'Networks': {'dev-net': {'Aliases': ['galaxy'], 'IPAMConfig': {'IPv4Address': '172.20.0.3'}, 'EndpointID': 'generated'}, 'second-net': {'Aliases': ['analysis']}}}}

    def test_preserves_configuration_and_adds_only_reviewed_capabilities(self):
        original = self.fixture(); before = copy.deepcopy(original)
        payload = module.build_payload(original, 'sha256:snapshot', 999, '/opt/biomate/dev-state/nextflow-runs')
        self.assertEqual(original, before)
        for key, value in original['Config'].items():
            if key != 'Image': self.assertEqual(payload[key], value)
        for key, value in original['HostConfig'].items():
            if key not in ('Binds', 'GroupAdd'): self.assertEqual(payload['HostConfig'][key], value)
        self.assertEqual(payload['HostConfig']['GroupAdd'], ['1000', '999'])
        self.assertIn('/var/run/docker.sock:/var/run/docker.sock:rw', payload['HostConfig']['Binds'])
        self.assertIn('/opt/biomate/dev-state/nextflow-runs:/tmp/nextflow_runs:rw', payload['HostConfig']['Binds'])
        self.assertEqual(set(payload['NetworkingConfig']['EndpointsConfig']), {'dev-net', 'second-net'})
        self.assertNotIn('EndpointID', payload['NetworkingConfig']['EndpointsConfig']['dev-net'])

    def test_refuses_conflicting_mount_instead_of_overwriting_it(self):
        original = self.fixture(); original['Mounts'].append({'Type': 'bind', 'Source': '/someone-else', 'Destination': '/tmp/nextflow_runs', 'RW': True})
        with self.assertRaises(ValueError): module.build_payload(original, 'sha256:snapshot', 999, '/opt/biomate/dev-state/nextflow-runs')

    def test_refuses_implicit_volume_data_loss(self):
        original = self.fixture(); original['Mounts'].append({'Type': 'volume', 'Name': 'existing', 'Destination': '/data', 'RW': True})
        with self.assertRaises(ValueError): module.build_payload(original, 'sha256:snapshot', 999, '/opt/biomate/dev-state/nextflow-runs')

    def test_preserves_actual_random_port_assignment(self):
        original = self.fixture(); original['HostConfig']['PortBindings']['8080/tcp'][0]['HostPort'] = ''
        original['NetworkSettings']['Ports'] = {'8080/tcp': [{'HostIp': '127.0.0.1', 'HostPort': '32781'}]}
        payload = module.build_payload(original, 'sha256:snapshot', 999, '/opt/biomate/dev-state/nextflow-runs')
        self.assertEqual(payload['HostConfig']['PortBindings']['8080/tcp'][0]['HostPort'], '32781')

if __name__ == '__main__': unittest.main()
