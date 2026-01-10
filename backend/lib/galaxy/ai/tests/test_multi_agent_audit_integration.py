"""
Comprehensive Test Suite for Multi-Agent System Upgrade

Tests the complete data flow through:
1. EnhancedDomainRouter - Hybrid routing
2. WorkflowAuditService - Audit trail
3. WorkflowLearningService - Learning from corrections
4. AgentOrchestrator - Integration

Test Categories:
- Unit tests for each component
- Integration tests for data flow
- Edge case and error handling tests
"""

import unittest
import json
import sqlite3
import tempfile
import os
from unittest.mock import Mock, MagicMock, patch
from datetime import datetime


class TestEnhancedDomainRouter(unittest.TestCase):
    """Test EnhancedDomainRouter functionality."""

    def setUp(self):
        """Set up test fixtures."""
        from galaxy.ai.agents.enhanced_domain_router import EnhancedDomainRouter, EnhancedRoutingDecision
        self.router = EnhancedDomainRouter()

    def test_keyword_routing_high_confidence(self):
        """Test that clear queries get high-confidence keyword routing."""
        result = self.router.route("Analyze RNA-seq data for differential gene expression")
        self.assertEqual(result.primary_domain, "transcriptomics")
        self.assertGreaterEqual(result.confidence, 0.7)
        self.assertEqual(result.routing_method, "keyword")
        self.assertIn("rna-seq", result.matched_keywords)

    def test_keyword_routing_low_confidence(self):
        """Test that ambiguous queries get low confidence."""
        result = self.router.route("analyze my data")
        self.assertLess(result.confidence, 0.7)
        # Without LLM client, should still use keyword
        self.assertEqual(result.routing_method, "keyword")

    def test_keyword_routing_multiple_domains(self):
        """Test secondary domain detection."""
        result = self.router.route("I want to analyze protein structure and run molecular docking")
        self.assertEqual(result.primary_domain, "structural_biology")
        # Should detect secondary domains

    def test_complexity_assessment_simple(self):
        """Test simple query complexity detection."""
        result = self.router.route("What is RNA-seq?")
        self.assertEqual(result.complexity, "simple")

    def test_complexity_assessment_complex(self):
        """Test complex query complexity detection."""
        result = self.router.route("Perform multi-omics integration combining RNA-seq and proteomics data end-to-end")
        self.assertEqual(result.complexity, "complex")

    def test_user_context_boost(self):
        """Test user preference boosting."""
        user_context = {
            'domain_preference': 'proteomics',
            'domain_confidence': 0.8,
            'expertise_level': 'expert'
        }
        # Query with ambiguous domain
        result = self.router.route("analyze this sample", user_context=user_context)
        # User preferred domain should be considered
        self.assertIn('proteomics', [result.primary_domain] + result.secondary_domains)

    def test_llm_routing_with_mock_client(self):
        """Test LLM routing path with mock client."""
        from galaxy.ai.agents.enhanced_domain_router import EnhancedDomainRouter

        mock_llm = Mock()
        mock_llm.generate.return_value = json.dumps({
            "primary_domain": "proteomics",
            "secondary_domains": ["metabolomics"],
            "confidence": 0.9,
            "complexity": "standard",
            "reasoning": "Query about protein analysis"
        })

        router = EnhancedDomainRouter(llm_client=mock_llm)
        result = router.route("analyze these samples")  # Ambiguous query

        # Should use LLM for low-confidence query
        if result.confidence < 0.7:
            mock_llm.generate.assert_called()

    def test_cache_functionality(self):
        """Test LRU cache works correctly."""
        from galaxy.ai.agents.enhanced_domain_router import LRUCache

        cache = LRUCache(max_size=3, ttl_seconds=3600)
        cache.put("key1", "value1")
        cache.put("key2", "value2")
        cache.put("key3", "value3")

        # All items should be present
        self.assertEqual(cache.get("key1"), "value1")
        self.assertEqual(cache.get("key2"), "value2")
        self.assertEqual(cache.get("key3"), "value3")

        # Add 4th item, oldest should be evicted
        cache.put("key4", "value4")
        self.assertIsNone(cache.get("key1"))
        self.assertEqual(cache.get("key4"), "value4")

    def test_learned_keywords_loading(self):
        """Test learned keywords are loaded from database."""
        # Should not crash if database doesn't have learned keywords
        from galaxy.ai.agents.enhanced_domain_router import EnhancedDomainRouter
        router = EnhancedDomainRouter()
        self.assertIsInstance(router._learned_keywords, dict)

    def test_add_learned_keywords(self):
        """Test adding learned keywords."""
        # Create mock patterns adapter
        mock_patterns = Mock()
        from galaxy.ai.agents.enhanced_domain_router import EnhancedDomainRouter
        router = EnhancedDomainRouter(user_patterns_adapter=mock_patterns)

        router.add_learned_keywords(
            domain="transcriptomics",
            keywords=["deseq2", "limma"],
            source='test',
            user_id='test_user'
        )

        self.assertIn("deseq2", router._learned_keywords.get("transcriptomics", set()))
        self.assertIn("limma", router._learned_keywords.get("transcriptomics", set()))

    def test_invalid_domain_rejected(self):
        """Test that invalid domains are rejected."""
        from galaxy.ai.agents.enhanced_domain_router import EnhancedDomainRouter
        router = EnhancedDomainRouter()

        # Try to add keywords for non-existent domain
        router.add_learned_keywords(
            domain="invalid_domain",
            keywords=["test"],
            source='test'
        )
        # Should not add - domain doesn't exist
        self.assertNotIn("invalid_domain", router._learned_keywords)


class TestWorkflowAuditService(unittest.TestCase):
    """Test WorkflowAuditService functionality."""

    def setUp(self):
        """Set up test with temporary database."""
        self.temp_db = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
        self.temp_db.close()
        self.db_path = self.temp_db.name

        # Create tables
        conn = sqlite3.connect(self.db_path)
        conn.executescript("""
            CREATE TABLE IF NOT EXISTS workflow_generation_audit (
                audit_id INTEGER PRIMARY KEY AUTOINCREMENT,
                request_id TEXT UNIQUE NOT NULL,
                user_id TEXT NOT NULL,
                session_id TEXT,
                query_text TEXT NOT NULL,
                query_hash TEXT,
                user_context TEXT,
                routing_decision TEXT,
                routing_method TEXT,
                routing_latency_ms INTEGER,
                domains_consulted TEXT,
                specialist_recommendations TEXT,
                specialist_latency_ms INTEGER,
                assembly_result TEXT,
                assembly_latency_ms INTEGER,
                success INTEGER NOT NULL DEFAULT 0,
                workflow_id TEXT,
                workflow_steps_count INTEGER,
                confidence REAL,
                generation_source TEXT,
                primary_domain TEXT,
                error_type TEXT,
                error_message TEXT,
                error_traceback TEXT,
                total_latency_ms INTEGER,
                llm_calls_count INTEGER,
                llm_tokens_used INTEGER,
                created_at TEXT DEFAULT (datetime('now'))
            );

            CREATE TABLE IF NOT EXISTS workflow_user_corrections (
                correction_id INTEGER PRIMARY KEY AUTOINCREMENT,
                audit_id INTEGER NOT NULL,
                user_id TEXT NOT NULL,
                correction_type TEXT NOT NULL,
                original_value TEXT,
                corrected_value TEXT,
                correction_reason TEXT,
                timestamp TEXT DEFAULT (datetime('now'))
            );

            CREATE TABLE IF NOT EXISTS learned_domain_keywords (
                keyword_id INTEGER PRIMARY KEY AUTOINCREMENT,
                domain TEXT NOT NULL,
                keyword TEXT NOT NULL,
                weight REAL DEFAULT 1.0,
                source TEXT,
                user_id TEXT,
                evidence_count INTEGER DEFAULT 1,
                created_at TEXT DEFAULT (datetime('now')),
                updated_at TEXT DEFAULT (datetime('now')),
                UNIQUE(domain, keyword)
            );
        """)
        conn.commit()
        conn.close()

        from galaxy.ai.services.workflow_audit_service import WorkflowAuditService
        self.audit = WorkflowAuditService(db_path=self.db_path)

    def tearDown(self):
        """Clean up temporary database."""
        os.unlink(self.db_path)

    def test_start_audit(self):
        """Test starting an audit creates request_id."""
        request_id = self.audit.start_audit(
            user_id='test_user',
            query='Test query',
            session_id='session123'
        )
        self.assertIsNotNone(request_id)
        self.assertIn(request_id, self.audit._active_audits)

    def test_record_routing(self):
        """Test recording routing decision."""
        request_id = self.audit.start_audit(
            user_id='test_user',
            query='RNA-seq analysis'
        )

        from galaxy.ai.agents.enhanced_domain_router import EnhancedRoutingDecision
        routing = EnhancedRoutingDecision(
            primary_domain='transcriptomics',
            confidence=0.9,
            routing_method='keyword'
        )

        self.audit.record_routing(request_id, routing, 'keyword', 15)

        record = self.audit._active_audits[request_id]
        self.assertEqual(record.routing_decision['primary_domain'], 'transcriptomics')
        self.assertEqual(record.routing_method, 'keyword')

    def test_complete_audit_success(self):
        """Test completing audit on success."""
        request_id = self.audit.start_audit(
            user_id='test_user',
            query='Test query'
        )

        audit_id = self.audit.complete_audit(
            request_id=request_id,
            success=True,
            workflow_id='wf123',
            workflow_steps_count=5,
            confidence=0.85,
            total_latency_ms=1500
        )

        # Should be persisted to database
        record = self.audit.get_audit_by_request_id(request_id)
        self.assertIsNotNone(record)
        self.assertEqual(record['success'], 1)
        self.assertEqual(record['workflow_steps_count'], 5)

    def test_complete_audit_failure(self):
        """Test completing audit on failure."""
        request_id = self.audit.start_audit(
            user_id='test_user',
            query='Test query'
        )

        self.audit.complete_audit(
            request_id=request_id,
            success=False,
            error_type='ValueError',
            error_message='Test error',
            total_latency_ms=500
        )

        record = self.audit.get_audit_by_request_id(request_id)
        self.assertIsNotNone(record)
        self.assertEqual(record['success'], 0)
        self.assertEqual(record['error_type'], 'ValueError')

    def test_record_correction(self):
        """Test recording user correction."""
        request_id = self.audit.start_audit(
            user_id='test_user',
            query='Test query'
        )
        self.audit.complete_audit(request_id=request_id, success=True, total_latency_ms=100)

        correction_id = self.audit.record_correction(
            request_id=request_id,
            user_id='test_user',
            correction_type='domain',
            original_value='genomics',
            corrected_value='transcriptomics',
            reason='Was RNA-seq analysis'
        )

        self.assertIsNotNone(correction_id)

    def test_get_audit_history(self):
        """Test getting user audit history."""
        # Create several audit records
        for i in range(3):
            request_id = self.audit.start_audit(
                user_id='test_user',
                query=f'Query {i}'
            )
            self.audit.complete_audit(request_id=request_id, success=True, total_latency_ms=100)

        history = self.audit.get_user_audit_history('test_user', limit=10)
        self.assertEqual(len(history), 3)

    def test_get_failure_patterns(self):
        """Test analyzing failure patterns."""
        # Create some failure records
        for i in range(3):
            request_id = self.audit.start_audit(
                user_id='test_user',
                query=f'Query {i}'
            )
            self.audit.complete_audit(
                request_id=request_id,
                success=False,
                error_type='ToolNotFoundError',
                error_message='Tool not found',
                total_latency_ms=100
            )

        patterns = self.audit.get_failure_patterns(limit=10)
        self.assertGreater(len(patterns), 0)

    def test_get_audit_statistics(self):
        """Test getting audit statistics."""
        # Create mixed results
        for i in range(5):
            request_id = self.audit.start_audit(user_id='test_user', query=f'Query {i}')
            self.audit.complete_audit(
                request_id=request_id,
                success=(i % 2 == 0),
                total_latency_ms=100
            )

        stats = self.audit.get_audit_statistics()
        self.assertIn('total_attempts', stats)
        self.assertIn('successful', stats)
        self.assertIn('success_rate', stats)


class TestWorkflowLearningService(unittest.TestCase):
    """Test WorkflowLearningService functionality."""

    def setUp(self):
        """Set up test with mock dependencies."""
        self.mock_patterns = Mock()
        self.mock_router = Mock()
        self.mock_router.DOMAIN_KEYWORDS = {
            'transcriptomics': {'rna-seq', 'gene expression'},
            'genomics': {'dna', 'variant'}
        }

        from galaxy.ai.services.workflow_learning_service import WorkflowLearningService
        self.learning = WorkflowLearningService(
            user_patterns_adapter=self.mock_patterns,
            domain_router=self.mock_router
        )

    def test_learn_from_domain_correction(self):
        """Test learning from domain correction."""
        result = self.learning.learn_from_correction(
            user_id='test_user',
            audit_id=1,
            correction_type='domain',
            original_value='genomics',
            corrected_value='transcriptomics',
            query_text='RNA-seq differential expression analysis'
        )

        self.assertTrue(result['learned'])
        self.assertGreater(len(result['actions']), 0)
        self.mock_patterns.update_domain_preference.assert_called_once()

    def test_learn_from_tool_correction(self):
        """Test learning from tool correction."""
        result = self.learning.learn_from_correction(
            user_id='test_user',
            audit_id=1,
            correction_type='tool_selection',
            original_value={'tool_id': 'tool_a'},
            corrected_value={'tool_id': 'tool_b'}
        )

        self.assertTrue(result['learned'])
        self.mock_patterns.record_tool_preference.assert_called_once()

    def test_keyword_extraction(self):
        """Test keyword extraction from query."""
        keywords = self.learning._extract_domain_keywords(
            "I want to analyze my ATAC-seq chromatin accessibility data",
            "genomics"
        )

        # Should not include common words or existing keywords
        for kw in keywords:
            self.assertNotIn(kw, ['i', 'want', 'to', 'analyze', 'my', 'data'])

    def test_learn_from_outcome_positive(self):
        """Test learning from positive workflow outcome."""
        # Mock database connection
        with patch.object(self.learning, '_get_db') as mock_db:
            mock_conn = MagicMock()
            mock_cursor = MagicMock()
            mock_cursor.fetchone.return_value = {
                'query_text': 'Test query',
                'routing_decision': '{"primary_domain": "genomics"}',
                'routing_method': 'keyword',
                'primary_domain': 'genomics',
                'workflow_id': 'wf123'
            }
            mock_conn.execute.return_value = mock_cursor
            mock_db.return_value = mock_conn

            result = self.learning.learn_from_workflow_outcome(
                user_id='test_user',
                audit_id=1,
                success=True,
                user_kept=True,
                rating=5
            )

            self.assertTrue(result['learned'])


class TestAgentOrchestratorIntegration(unittest.TestCase):
    """Test AgentOrchestrator integration with all services."""

    def setUp(self):
        """Set up with mock services."""
        self.mock_tool_search = Mock()
        self.mock_llm_client = Mock()
        self.mock_patterns = Mock()
        self.mock_audit = Mock()
        self.mock_learning = Mock()

        # Configure mocks
        self.mock_audit.start_audit.return_value = 'test-request-id'
        self.mock_audit.get_audit_by_request_id.return_value = {
            'audit_id': 1,
            'query_text': 'Test query'
        }
        self.mock_audit.complete_audit.return_value = 1
        self.mock_patterns.get_routing_context.return_value = {}

    def test_generate_workflow_with_audit(self):
        """Test workflow generation records audit trail."""
        from galaxy.ai.agents.agent_orchestrator import AgentOrchestrator
        from galaxy.ai.agents.domain_specialist import DomainRecommendation
        from galaxy.ai.agents.workflow_assembler import AssembledWorkflow

        # Mock specialist pool
        mock_specialist_pool = Mock()
        mock_specialist_pool.consult_specialists.return_value = {
            'genomics': DomainRecommendation(
                domain='genomics',
                recommended_tools=[],
                workflow_steps=[],
                domain_notes='',
                confidence=0.8
            )
        }

        # Mock assembler
        mock_assembler = Mock()
        mock_assembler.assemble.return_value = AssembledWorkflow(
            workflow_steps=[],
            recommended_tools=[],
            validation=None,
            citations=[],
            domain_sources=['genomics'],
            confidence=0.85
        )

        orchestrator = AgentOrchestrator(
            tool_search=self.mock_tool_search,
            llm_client=self.mock_llm_client,
            user_patterns_adapter=self.mock_patterns,
            audit_service=self.mock_audit,
            learning_service=self.mock_learning,
            use_enhanced_routing=False  # Use basic router for testing
        )
        orchestrator.specialist_pool = mock_specialist_pool
        orchestrator.workflow_assembler = mock_assembler

        result = orchestrator.generate_workflow(
            query="Analyze my genomic data",
            user_id="test_user",
            session_id="session123"
        )

        # Verify audit was started and completed
        self.mock_audit.start_audit.assert_called_once()
        self.mock_audit.complete_audit.assert_called_once()
        self.assertEqual(result.request_id, 'test-request-id')

    def test_record_correction_triggers_learning(self):
        """Test that corrections trigger learning."""
        from galaxy.ai.agents.agent_orchestrator import AgentOrchestrator

        self.mock_learning.learn_from_correction.return_value = {
            'learned': True,
            'actions': ['Updated domain preference']
        }

        orchestrator = AgentOrchestrator(
            tool_search=self.mock_tool_search,
            llm_client=self.mock_llm_client,
            user_patterns_adapter=self.mock_patterns,
            audit_service=self.mock_audit,
            learning_service=self.mock_learning,
            use_enhanced_routing=False
        )

        result = orchestrator.record_correction(
            request_id='test-request-id',
            user_id='test_user',
            correction_type='domain',
            original_value='genomics',
            corrected_value='transcriptomics'
        )

        self.assertTrue(result['learned'])
        self.mock_learning.learn_from_correction.assert_called_once()


class TestDataFlowIntegration(unittest.TestCase):
    """Test complete data flow through all components."""

    def setUp(self):
        """Set up with temporary database and real components."""
        self.temp_db = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
        self.temp_db.close()
        self.db_path = self.temp_db.name

        # Create all required tables
        conn = sqlite3.connect(self.db_path)
        conn.executescript("""
            CREATE TABLE IF NOT EXISTS workflow_generation_audit (
                audit_id INTEGER PRIMARY KEY AUTOINCREMENT,
                request_id TEXT UNIQUE NOT NULL,
                user_id TEXT NOT NULL,
                session_id TEXT,
                query_text TEXT NOT NULL,
                query_hash TEXT,
                user_context TEXT,
                routing_decision TEXT,
                routing_method TEXT,
                routing_latency_ms INTEGER,
                domains_consulted TEXT,
                specialist_recommendations TEXT,
                specialist_latency_ms INTEGER,
                assembly_result TEXT,
                assembly_latency_ms INTEGER,
                success INTEGER NOT NULL DEFAULT 0,
                workflow_id TEXT,
                workflow_steps_count INTEGER,
                confidence REAL,
                generation_source TEXT,
                primary_domain TEXT,
                error_type TEXT,
                error_message TEXT,
                error_traceback TEXT,
                total_latency_ms INTEGER,
                llm_calls_count INTEGER,
                llm_tokens_used INTEGER,
                created_at TEXT DEFAULT (datetime('now'))
            );

            CREATE TABLE IF NOT EXISTS workflow_user_corrections (
                correction_id INTEGER PRIMARY KEY AUTOINCREMENT,
                audit_id INTEGER NOT NULL,
                user_id TEXT NOT NULL,
                correction_type TEXT NOT NULL,
                original_value TEXT,
                corrected_value TEXT,
                correction_reason TEXT,
                timestamp TEXT DEFAULT (datetime('now'))
            );

            CREATE TABLE IF NOT EXISTS learned_domain_keywords (
                keyword_id INTEGER PRIMARY KEY AUTOINCREMENT,
                domain TEXT NOT NULL,
                keyword TEXT NOT NULL,
                weight REAL DEFAULT 1.0,
                source TEXT,
                user_id TEXT,
                evidence_count INTEGER DEFAULT 1,
                created_at TEXT DEFAULT (datetime('now')),
                updated_at TEXT DEFAULT (datetime('now')),
                UNIQUE(domain, keyword)
            );

            CREATE TABLE IF NOT EXISTS user_patterns (
                pattern_id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT NOT NULL,
                pattern_type TEXT NOT NULL,
                pattern_data TEXT,
                confidence REAL DEFAULT 0.5,
                evidence_count INTEGER DEFAULT 1,
                first_observed TEXT,
                last_observed TEXT,
                last_updated TEXT
            );

            CREATE TABLE IF NOT EXISTS user_interactions (
                interaction_id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT NOT NULL,
                interaction_type TEXT NOT NULL,
                query TEXT,
                selected_tool_id TEXT,
                workflow_id TEXT,
                workflow_success INTEGER,
                detected_context TEXT,
                user_feedback_rating INTEGER,
                timestamp TEXT DEFAULT (datetime('now'))
            );

            CREATE TABLE IF NOT EXISTS context_inferences (
                inference_id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT NOT NULL,
                query_text TEXT,
                inferred_domain TEXT,
                domain_confidence REAL,
                inferred_data_type TEXT,
                inference_method TEXT,
                timestamp TEXT DEFAULT (datetime('now'))
            );
        """)
        conn.commit()
        conn.close()

    def tearDown(self):
        """Clean up."""
        os.unlink(self.db_path)

    def test_full_audit_learning_flow(self):
        """Test complete flow: audit → correction → learning → keyword storage."""
        from galaxy.ai.services.workflow_audit_service import WorkflowAuditService
        from galaxy.ai.services.workflow_learning_service import WorkflowLearningService
        from galaxy.ai.agents.user_patterns_adapter import UserPatternsAdapter
        from galaxy.ai.agents.enhanced_domain_router import EnhancedDomainRouter

        # Initialize services with same database
        audit = WorkflowAuditService(db_path=self.db_path)
        patterns = UserPatternsAdapter(db_path=self.db_path)
        router = EnhancedDomainRouter(user_patterns_adapter=patterns, db_path=self.db_path)
        learning = WorkflowLearningService(
            user_patterns_adapter=patterns,
            domain_router=router,
            db_path=self.db_path
        )

        # Step 1: Route a query
        routing_result = router.route("Analyze my ATAC-seq chromatin data")

        # Step 2: Start audit
        request_id = audit.start_audit(
            user_id='integration_test_user',
            query='Analyze my ATAC-seq chromatin data',
            session_id='test_session'
        )

        # Step 3: Record routing
        audit.record_routing(request_id, routing_result, routing_result.routing_method, 25)

        # Step 4: Complete audit
        audit_id = audit.complete_audit(
            request_id=request_id,
            success=True,
            workflow_id='test_wf',
            workflow_steps_count=3,
            confidence=0.85,
            total_latency_ms=1500
        )

        # Verify audit was persisted
        record = audit.get_audit_by_request_id(request_id)
        self.assertIsNotNone(record)
        self.assertEqual(record['success'], 1)

        # Step 5: Submit correction
        correction_id = audit.record_correction(
            request_id=request_id,
            user_id='integration_test_user',
            correction_type='domain',
            original_value='genomics',
            corrected_value='transcriptomics',
            reason='Was RNA-seq'
        )
        self.assertIsNotNone(correction_id)

        # Step 6: Trigger learning
        learning_result = learning.learn_from_correction(
            user_id='integration_test_user',
            audit_id=record['audit_id'],
            correction_type='domain',
            original_value='genomics',
            corrected_value='transcriptomics',
            query_text='Analyze my ATAC-seq chromatin data'
        )

        self.assertTrue(learning_result['learned'])

        # Step 7: Verify user pattern was updated
        context = patterns.get_routing_context('integration_test_user')
        # Should have recorded domain preference
        self.assertIsNotNone(context)


class TestEdgeCases(unittest.TestCase):
    """Test edge cases and error handling."""

    def test_audit_with_null_user(self):
        """Test audit handles null user gracefully."""
        from galaxy.ai.services.workflow_audit_service import WorkflowAuditService

        # Create temp db
        temp_db = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
        temp_db.close()

        conn = sqlite3.connect(temp_db.name)
        conn.execute("""CREATE TABLE workflow_generation_audit (
            audit_id INTEGER PRIMARY KEY, request_id TEXT, user_id TEXT NOT NULL,
            session_id TEXT, query_text TEXT, query_hash TEXT, user_context TEXT,
            routing_decision TEXT, routing_method TEXT, routing_latency_ms INTEGER,
            domains_consulted TEXT, specialist_recommendations TEXT, specialist_latency_ms INTEGER,
            assembly_result TEXT, assembly_latency_ms INTEGER, success INTEGER DEFAULT 0,
            workflow_id TEXT, workflow_steps_count INTEGER, confidence REAL,
            generation_source TEXT, primary_domain TEXT, error_type TEXT, error_message TEXT,
            error_traceback TEXT, total_latency_ms INTEGER, llm_calls_count INTEGER,
            llm_tokens_used INTEGER, created_at TEXT
        )""")
        conn.commit()
        conn.close()

        audit = WorkflowAuditService(db_path=temp_db.name)
        request_id = audit.start_audit(
            user_id=None,  # Null user
            query='Test query'
        )
        # Should handle gracefully with 'anonymous'
        self.assertIsNotNone(request_id)

        os.unlink(temp_db.name)

    def test_router_empty_query(self):
        """Test router handles empty query."""
        from galaxy.ai.agents.enhanced_domain_router import EnhancedDomainRouter
        router = EnhancedDomainRouter()

        result = router.route("")
        # Should return default with low confidence
        self.assertIsNotNone(result.primary_domain)
        self.assertLess(result.confidence, 0.3)

    def test_learning_with_missing_audit(self):
        """Test learning handles missing audit record."""
        from galaxy.ai.services.workflow_learning_service import WorkflowLearningService

        learning = WorkflowLearningService()

        result = learning.learn_from_workflow_outcome(
            user_id='test_user',
            audit_id=99999,  # Non-existent
            success=True,
            user_kept=True
        )

        # Should not crash, just not learn
        self.assertFalse(result['learned'])


def run_tests():
    """Run all tests and print summary."""
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()

    # Add all test classes
    suite.addTests(loader.loadTestsFromTestCase(TestEnhancedDomainRouter))
    suite.addTests(loader.loadTestsFromTestCase(TestWorkflowAuditService))
    suite.addTests(loader.loadTestsFromTestCase(TestWorkflowLearningService))
    suite.addTests(loader.loadTestsFromTestCase(TestAgentOrchestratorIntegration))
    suite.addTests(loader.loadTestsFromTestCase(TestDataFlowIntegration))
    suite.addTests(loader.loadTestsFromTestCase(TestEdgeCases))

    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)

    return result


if __name__ == '__main__':
    run_tests()
