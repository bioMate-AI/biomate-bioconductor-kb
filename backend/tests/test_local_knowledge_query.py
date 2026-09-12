import importlib.util
import sqlite3
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('local_knowledge_query', Path(__file__).parents[1] / 'lib/galaxy/ai/local_knowledge_query.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class KnowledgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / 'knowledge.db'
        with sqlite3.connect(self.path) as db:
            db.executescript('''CREATE TABLE tools(id INTEGER PRIMARY KEY,tool_id,name,category,description,parameters,inputs,outputs,citations,availability_status);
            CREATE TABLE workflows(id INTEGER PRIMARY KEY,name,filename,description,domain,input_types,output_types,params_schema,executable,real_exec_status);
            CREATE VIRTUAL TABLE tools_fts USING fts5(tool_id,name);
            CREATE VIRTUAL TABLE workflows_fts USING fts5(name);
            INSERT INTO tools VALUES(1,'fastqc','FastQC','qc','quality check','{}','fastq','html','[]','unknown');
            INSERT INTO tools_fts(rowid,tool_id,name) VALUES(42,'fastqc','FastQC FASTQ quality');
            INSERT INTO workflows VALUES(1,'Read quality','qc.ga','FastQC','qc','fastq','html','{}',1,NULL);
            INSERT INTO workflows_fts(rowid,name) VALUES(1,'FastQC quality');''')
    def tearDown(self):
        self.tmp.cleanup()
    def test_real_records_and_no_execution_claim(self):
        result = module.query_knowledge(self.path, 'FastQC', 1)
        self.assertEqual(result['tools'][0]['tool_id'], 'fastqc')
        self.assertEqual(result['workflows'][0]['id'], 1)
        self.assertFalse(result['execution_verified'])
    def test_query_is_data_and_database_is_unchanged(self):
        before = self.path.read_bytes()
        module.query_knowledge(self.path, 'FastQC"; DROP TABLE tools; --')
        self.assertEqual(self.path.read_bytes(), before)
        with self.assertRaises(ValueError): module.query_knowledge(self.path, 'x' * 501)
        with self.assertRaises(ValueError): module.query_knowledge(self.path, 'FastQC', 100)
    def test_missing_database_is_not_created_and_excerpts_are_marked(self):
        missing = self.path.with_name('missing.db')
        with self.assertRaises(sqlite3.Error): module.query_knowledge(missing, 'FastQC')
        self.assertFalse(missing.exists())
        with sqlite3.connect(self.path) as db: db.execute('UPDATE tools SET parameters=?', ('x' * 3500,))
        record = module.query_knowledge(self.path, 'FastQC')['tools'][0]
        self.assertEqual(record['truncated_fields'], ['parameters'])
        self.assertEqual(len(record['parameters']), 3000)

if __name__ == '__main__': unittest.main()
