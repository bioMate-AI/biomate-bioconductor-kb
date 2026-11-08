"""Public-source disease-name verification; only the external HTTP transport is faked."""
import unittest
from unittest.mock import patch

from galaxy.ai.target_id.data_channels import OPENTARGETS_GQL, resolve_disease_name


class DiseaseResolution(unittest.TestCase):
    def response(self, hits):
        return {'data': {'search': {'hits': hits}}}

    def test_exact_name_and_hyphen_normalization_ignore_wrong_first_hit(self):
        def http(url, payload):
            self.assertEqual(url, OPENTARGETS_GQL)
            self.assertIn('queryString:$name', payload['query'])
            self.assertEqual(payload['variables']['name'], 'non-small-cell lung carcinoma')
            return self.response([
                {'id': 'MONDO_0008903', 'name': 'lung cancer'},
                {'id': 'MONDO_0005233', 'name': 'non-small cell lung carcinoma'},
            ])
        with patch('galaxy.ai.target_id.data_channels.offline_mode', return_value=False):
            result = resolve_disease_name(' non-small-cell lung carcinoma ', http=http)
        self.assertEqual(result['disease_id'], 'MONDO_0005233')

    def test_no_match_ambiguous_match_and_invalid_identifier_require_clarification(self):
        for hits in ([], [{'id':'MONDO_1','name':'lung cancer'}],
                     [{'id':'EFO_1','name':'melanoma'},{'id':'MONDO_2','name':'melanoma'}],
                     [{'id':'guessed-id','name':'melanoma'}]):
            with self.subTest(hits=hits), patch('galaxy.ai.target_id.data_channels.offline_mode', return_value=False):
                with self.assertRaisesRegex(ValueError, 'unique exact match'):
                    resolve_disease_name('melanoma', http=lambda *args: self.response(hits))

    def test_offline_mode_never_calls_external_source(self):
        with patch('galaxy.ai.target_id.data_channels.offline_mode', return_value=True):
            with self.assertRaisesRegex(ValueError, 'offline'):
                resolve_disease_name('melanoma', http=lambda *args: self.fail('network called offline'))

    def test_invalid_input_and_graphql_failure_cannot_create_an_identifier(self):
        with patch('galaxy.ai.target_id.data_channels.offline_mode', return_value=False):
            for name in ('', ' ', 'x' * 301, 42):
                with self.subTest(name=name), self.assertRaises(ValueError):
                    resolve_disease_name(name, http=lambda *args: self.fail('invalid input sent'))
            for response in ({'errors':[{'message':'bad schema'}]}, {}, {'data':{'search':{'hits':None}}}):
                with self.subTest(response=response), self.assertRaises(RuntimeError):
                    resolve_disease_name('melanoma', http=lambda *args: response)

    def test_transport_failure_is_not_a_negative_disease_finding(self):
        def down(*args):
            raise TimeoutError('source unavailable')
        with patch('galaxy.ai.target_id.data_channels.offline_mode', return_value=False):
            with self.assertRaises(TimeoutError):
                resolve_disease_name('melanoma', http=down)

    def test_accepts_only_source_verified_exact_synonyms(self):
        for relation, passes in (('hasExactSynonym', True), ('hasRelatedSynonym', False),
                                 ('hasBroadSynonym', False), ('hasNarrowSynonym', False)):
            def http(url, payload):
                if 'search(queryString:' in payload['query']:
                    return self.response([{'id':'MONDO_0005233','name':'non-small cell lung carcinoma'}])
                self.assertEqual(payload['variables'], {'d0':'MONDO_0005233'})
                return {'data':{'d0':{'name':'non-small cell lung carcinoma','synonyms':[
                    {'relation':relation,'terms':['non-small cell lung cancer']}]}}}
            with self.subTest(relation=relation), patch('galaxy.ai.target_id.data_channels.offline_mode', return_value=False):
                if passes:
                    self.assertEqual(resolve_disease_name('non-small cell lung cancer', http=http)['disease_id'], 'MONDO_0005233')
                else:
                    with self.assertRaises(ValueError):
                        resolve_disease_name('non-small cell lung cancer', http=http)

    def test_ambiguous_synonyms_and_partial_graphql_failure_do_not_pick_first_hit(self):
        def http(url, payload):
            if 'search(queryString:' in payload['query']:
                return self.response([{'id':'MONDO_1','name':'disease one'},{'id':'MONDO_2','name':'disease two'}])
            return {'data':{key:{'name':'disease '+key,'synonyms':[{'relation':'hasExactSynonym','terms':['ambiguous']}]} for key in ('d0','d1')}}
        with patch('galaxy.ai.target_id.data_channels.offline_mode', return_value=False):
            with self.assertRaises(ValueError):
                resolve_disease_name('ambiguous', http=http)
            def partial(url, payload):
                return self.response([{'id':'MONDO_1','name':'other'}]) if 'search(queryString:' in payload['query'] else {'data':{},'errors':[{'message':'unavailable'}]}
            with self.assertRaises(RuntimeError):
                resolve_disease_name('ambiguous', http=partial)


if __name__ == '__main__':
    unittest.main()
