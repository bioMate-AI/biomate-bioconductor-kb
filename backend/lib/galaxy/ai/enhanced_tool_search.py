"""
Enhanced Tool Search System
Uses scientific_context + nfcore_metadata JSON from database to provide contextually relevant tool recommendations
Integrates with existing ToolSearchIndex for backward compatibility

Based on NFCORE_VS_SCIENTIFIC_CONTEXT_ANALYSIS.md:
- nfcore_metadata: Workflow patterns, I/O formats, community validation (20% of tools)
- scientific_context: Decision-making guidance, applicability (100% of tools)
"""

import json
import logging
from typing import Dict, List, Optional, Any
from pathlib import Path

log = logging.getLogger(__name__)


class EnhancedToolSearch:
    """
    Enhanced search that uses BOTH scientific_context + nfcore_metadata for intelligent tool discovery

    Scoring Algorithm:
    - Omics applicability: 25% weight (from scientific_context)
    - Task suitability: 20% weight (from scientific_context)
    - Data requirements: 15% weight (from scientific_context)
    - User expertise match: 10% weight (from scientific_context)
    - Workflow validation: 15% weight (from nfcore_metadata)
    - Information quality: 10% weight (from both sources)
    - Usage indicators: 5% weight (examples, citations)
    """

    def __init__(self, search_index):
        """
        Args:
            search_index: ToolSearchIndex instance from search_index.py
        """
        self.search_index = search_index

    def search_with_context(
        self,
        query: str,
        user_context: Optional[Dict] = None,
        filters: Optional[Dict] = None,
        limit: int = 20
    ) -> List[Dict[str, Any]]:
        """
        Enhanced search using scientific_context from database

        Args:
            query: User's natural language query
            user_context: {
                'research_domain': 'proteomics' | 'genomics' | 'transcriptomics' | etc,
                'data_type': 'DIA-LCMS' | 'RNA-seq' | 'WGS' | etc,
                'organism': 'human' | 'mouse' | etc,
                'expertise_level': 'beginner' | 'intermediate' | 'expert',
                'num_samples': int,
                'num_replicates': int
            }
            filters: {
                'omics_type': str,
                'suitable_for': str (e.g., 'differential expression'),
                'min_samples': int,
                'data_format': str (e.g., 'FASTQ', 'mzML')
            }
            limit: Maximum results to return

        Returns:
            List of tools with enhanced relevance scoring
        """
        log.info(f"Enhanced search: query='{query}', user_domain={user_context.get('research_domain') if user_context else 'unknown'}")

        # Step 1: Use existing FTS5 search for initial candidates
        try:
            initial_results = self.search_index.search(query, category=None, limit=min(100, limit * 5))
            log.info(f"FTS5 search returned {len(initial_results)} initial candidates")
        except Exception as e:
            log.error(f"FTS5 search failed: {e}")
            return []

        # Step 2: Enhance with scientific context + nfcore metadata scoring
        enhanced_results = []
        for tool in initial_results:
            try:
                # Parse scientific_context JSON
                context_str = tool.get('scientific_context', '{}')
                if not context_str or context_str == 'null':
                    context_str = '{}'
                scientific_context = json.loads(context_str) if isinstance(context_str, str) else context_str

                # Parse nfcore_metadata JSON
                nfcore_str = tool.get('nfcore_metadata', '{}')
                if not nfcore_str or nfcore_str == 'null':
                    nfcore_str = '{}'
                nfcore_metadata = json.loads(nfcore_str) if isinstance(nfcore_str, str) else nfcore_str

                # Calculate scientific relevance score (uses both sources)
                scientific_score = self._calculate_scientific_relevance(
                    tool, scientific_context, nfcore_metadata, user_context, filters
                )

                # Skip tools with very low scientific relevance
                if scientific_score < 0.2:
                    continue

                # Combine FTS5 rank with scientific score
                # FTS5 rank is negative (BM25), normalize to 0-1
                fts_score = min(1.0, abs(tool.get('rank', -10)) / 10) if tool.get('rank') else 0.5

                # Weighted combination: 60% scientific relevance, 40% text match
                combined_score = (scientific_score * 0.6) + (fts_score * 0.4)

                # Add enhanced fields to result
                enhanced_tool = dict(tool)
                enhanced_tool['scientific_relevance_score'] = scientific_score
                enhanced_tool['fts_score'] = fts_score
                enhanced_tool['combined_score'] = combined_score
                enhanced_tool['parsed_context'] = scientific_context
                enhanced_tool['parsed_nfcore'] = nfcore_metadata

                # Add human-readable relevance explanation
                enhanced_tool['relevance_explanation'] = self._generate_relevance_explanation(
                    tool, scientific_context, nfcore_metadata, user_context, scientific_score
                )

                enhanced_results.append(enhanced_tool)

            except json.JSONDecodeError as e:
                log.warning(f"Failed to parse scientific_context for tool {tool.get('tool_id')}: {e}")
                # Keep tool but with lower score
                enhanced_tool = dict(tool)
                enhanced_tool['combined_score'] = 0.3
                enhanced_results.append(enhanced_tool)
            except Exception as e:
                log.error(f"Error processing tool {tool.get('tool_id')}: {e}")
                continue

        # Step 3: Sort by combined score
        enhanced_results.sort(key=lambda x: x['combined_score'], reverse=True)

        # Step 4: Apply post-filters if needed
        if filters:
            enhanced_results = self._apply_filters(enhanced_results, filters)

        final_results = enhanced_results[:limit]

        log.info(f"Enhanced search complete: returning {len(final_results)} tools")
        if final_results:
            log.debug(f"Top result: {final_results[0].get('name')} (score: {final_results[0]['combined_score']:.3f})")

        return final_results

    def _calculate_scientific_relevance(
        self,
        tool: Dict,
        context: Dict,
        nfcore: Dict,
        user_context: Optional[Dict],
        filters: Optional[Dict]
    ) -> float:
        """
        Calculate relevance based on scientific_context + nfcore_metadata JSON

        Returns score between 0.0 and 1.0
        """
        score = 0.0

        # === 1. Omics Applicability (25% weight) - from scientific_context ===
        if user_context and 'research_domain' in user_context:
            omics_app = context.get('omics_applicability', {})
            primary_omics = omics_app.get('primary_omics', [])
            secondary_omics = omics_app.get('secondary_omics', [])
            not_suitable = omics_app.get('not_suitable', [])

            user_domain = user_context['research_domain'].lower()

            # Check if domain matches
            if any(user_domain in str(omics).lower() for omics in primary_omics):
                score += 0.25  # Perfect match (reduced from 0.30)
            elif any(user_domain in str(omics).lower() for omics in secondary_omics):
                score += 0.13  # Secondary match (reduced from 0.15)

            # Penalty if explicitly not suitable
            if any(user_domain in str(ns).lower() for ns in not_suitable):
                score -= 0.40  # Strong penalty

        # === 2. Task Suitability (20% weight) - from scientific_context ===
        if filters and 'suitable_for' in filters:
            tool_selection = context.get('tool_selection', {})
            best_for = tool_selection.get('best_for', [])
            not_recommended = tool_selection.get('not_recommended_for', [])

            task = filters['suitable_for'].lower()

            # Check if task matches
            if any(task in str(use).lower() for use in best_for):
                score += 0.20  # Great match (reduced from 0.25)
            elif any(task in str(use).lower() for use in not_recommended):
                score -= 0.30  # Strong penalty for wrong use

        # === 3. Data Requirements (15% weight) - from scientific_context ===
        if user_context:
            data_req = context.get('omics_applicability', {}).get('data_requirements', {})
            min_samples = data_req.get('min_samples')
            min_replicates = data_req.get('min_replicates')

            # Check sample count
            if 'num_samples' in user_context and min_samples:
                if user_context['num_samples'] >= min_samples:
                    score += 0.12  # Has enough samples (reduced from 0.15)
                else:
                    score -= 0.25  # Insufficient samples - penalize heavily

            # Check replicate count
            if 'num_replicates' in user_context and min_replicates:
                if user_context['num_replicates'] >= min_replicates:
                    score += 0.03  # Has enough replicates (reduced from 0.05)
                elif user_context['num_replicates'] < min_replicates:
                    score -= 0.05  # Warning level penalty

        # === 4. User Expertise Level (10% weight) - from scientific_context ===
        if user_context and 'expertise_level' in user_context:
            guidance = context.get('scientific_guidance', {})
            pitfalls = guidance.get('common_pitfalls', [])
            key_params = guidance.get('key_parameters', [])

            # Estimate tool complexity
            complexity = min(1.0, (len(pitfalls) + len(key_params)) / 10)

            user_level = user_context['expertise_level']

            if user_level == 'expert':
                score += 0.10  # Experts can handle any complexity (reduced from 0.15)
            elif user_level == 'beginner':
                if complexity < 0.3:
                    score += 0.10  # Simple tools for beginners (reduced from 0.15)
                elif complexity > 0.7:
                    score -= 0.08  # Complex tools - slight penalty
                else:
                    score += 0.05  # Medium complexity tools
            else:  # intermediate
                if complexity < 0.5:
                    score += 0.08  # Prefer moderate complexity
                else:
                    score += 0.05

        # === 5. Workflow Validation (15% weight) - from nfcore_metadata ===
        # Tools used in production nf-core workflows get bonus
        if nfcore and nfcore.get('modules'):
            # Tool is in nf-core - strong signal of quality and production readiness
            score += 0.10  # Base bonus for being in nf-core

            # Additional bonus if it has workflow context
            if nfcore.get('workflows'):
                score += 0.03  # Used in complete workflows

            # Check I/O format validation if user specified data format
            if filters and 'data_format' in filters:
                typical_inputs = nfcore.get('typical_inputs', [])
                user_format = filters['data_format'].lower()

                # Check if user's format matches typical inputs
                if any(user_format in str(fmt).lower() for fmt in typical_inputs):
                    score += 0.02  # Format validated by nf-core usage

        # === 6. Information Quality (10% weight) - from both sources ===
        info_sources = context.get('information_sources', {})

        quality_indicators = 0
        if info_sources.get('paper_references'):
            quality_indicators += 1
        if info_sources.get('official_manual'):
            quality_indicators += 1
        if info_sources.get('toolshed_metadata'):
            quality_indicators += 1
        if info_sources.get('galaxy_tool_xml'):
            quality_indicators += 1

        # nfcore_metadata counts as quality indicator
        if nfcore and nfcore.get('modules'):
            quality_indicators += 1

        # Normalize to 0.10 max (5 possible sources now)
        score += (quality_indicators / 5) * 0.10

        # === 7. Usage Indicators (5% weight) ===

        # Boost if tool has usage examples
        examples_str = tool.get('examples', '[]')
        if examples_str and examples_str != '[]':
            try:
                examples = json.loads(examples_str) if isinstance(examples_str, str) else examples_str
                if examples and len(examples) > 0:
                    score += 0.03  # Bonus for having examples (reduced from 0.05)
            except:
                pass

        # Boost if tool has citations
        citations_str = tool.get('citations', '[]')
        if citations_str and citations_str != '[]':
            try:
                citations = json.loads(citations_str) if isinstance(citations_str, str) else citations_str
                if citations and len(citations) > 0:
                    score += 0.02  # Small bonus for citations (reduced from 0.03)
            except:
                pass

        # Clamp score to [0, 1]
        return max(0.0, min(1.0, score))

    def _generate_relevance_explanation(
        self,
        tool: Dict,
        context: Dict,
        nfcore: Dict,
        user_context: Optional[Dict],
        score: float
    ) -> str:
        """Generate human-readable explanation of why tool is relevant"""

        reasons = []

        # Check nf-core validation FIRST (strong signal)
        if nfcore and nfcore.get('modules'):
            reasons.append("✓ Used in nf-core production workflows")

        # Check omics match
        if user_context and 'research_domain' in user_context:
            omics_app = context.get('omics_applicability', {})
            primary_omics = omics_app.get('primary_omics', [])

            user_domain = user_context['research_domain']
            if any(user_domain.lower() in str(omics).lower() for omics in primary_omics):
                reasons.append(f"Designed for {user_domain}")

        # Check task suitability
        tool_selection = context.get('tool_selection', {})
        best_for = tool_selection.get('best_for', [])
        if best_for:
            reasons.append(f"Best for: {', '.join(best_for[:2])}")

        # Check data requirements
        data_req = context.get('omics_applicability', {}).get('data_requirements', {})
        if data_req.get('min_samples'):
            reasons.append(f"Requires ≥{data_req['min_samples']} samples")

        # Check workflow I/O patterns from nfcore
        if nfcore and nfcore.get('typical_inputs'):
            typical_inputs = nfcore.get('typical_inputs', [])[:2]  # Show first 2
            if typical_inputs:
                reasons.append(f"Accepts: {', '.join(typical_inputs)}")

        # Check quality indicators
        info_sources = context.get('information_sources', {})
        if info_sources.get('paper_references'):
            reasons.append("Well-documented with citations")

        if not reasons:
            return "General bioinformatics tool"

        return " • ".join(reasons)

    def _apply_filters(self, results: List[Dict], filters: Dict) -> List[Dict]:
        """Apply additional hard filters"""

        filtered = []

        for tool in results:
            context = tool.get('parsed_context', {})

            # Filter by data format if specified
            if 'data_format' in filters:
                inputs = tool.get('inputs', '[]')
                try:
                    inputs_list = json.loads(inputs) if isinstance(inputs, str) else inputs

                    # Check if any input accepts this format
                    has_format = any(
                        filters['data_format'].lower() in str(inp.get('format', '')).lower()
                        for inp in inputs_list
                    )

                    if not has_format:
                        continue  # Skip this tool

                except:
                    pass  # Include tool if we can't parse inputs

            filtered.append(tool)

        return filtered

    def get_scientific_context(self, tool_id: str) -> Dict[str, Any]:
        """
        Get parsed scientific_context for a specific tool

        Args:
            tool_id: Tool identifier

        Returns:
            Parsed scientific_context dictionary
        """
        tool = self.search_index.get_by_id(tool_id)

        if not tool:
            return {}

        context_str = tool.get('scientific_context', '{}')
        if not context_str or context_str == 'null':
            return {}

        try:
            return json.loads(context_str) if isinstance(context_str, str) else context_str
        except json.JSONDecodeError:
            log.warning(f"Failed to parse scientific_context for tool {tool_id}")
            return {}

    def get_suitable_tools_for_domain(
        self,
        domain: str,
        task: Optional[str] = None,
        limit: int = 20
    ) -> List[Dict[str, Any]]:
        """
        Get tools suitable for a specific research domain

        Args:
            domain: Research domain (e.g., 'proteomics', 'genomics')
            task: Optional specific task (e.g., 'differential expression')
            limit: Maximum results

        Returns:
            List of suitable tools
        """
        user_context = {'research_domain': domain}
        filters = {'suitable_for': task} if task else None

        # Use broad query for domain
        query = domain
        if task:
            query += f" {task}"

        return self.search_with_context(
            query=query,
            user_context=user_context,
            filters=filters,
            limit=limit
        )

    def validate_tool_for_context(
        self,
        tool_id: str,
        user_context: Dict
    ) -> Dict[str, Any]:
        """
        Validate if a tool is appropriate for given context

        Args:
            tool_id: Tool to validate
            user_context: User's research context

        Returns:
            {
                'suitable': bool,
                'confidence': float,
                'warnings': List[str],
                'recommendations': List[str]
            }
        """
        tool = self.search_index.get_by_id(tool_id)

        if not tool:
            return {
                'suitable': False,
                'confidence': 0.0,
                'warnings': ['Tool not found'],
                'recommendations': []
            }

        context = self.get_scientific_context(tool_id)

        # Get nfcore_metadata
        nfcore_str = tool.get('nfcore_metadata', '{}')
        if not nfcore_str or nfcore_str == 'null':
            nfcore_str = '{}'
        try:
            nfcore = json.loads(nfcore_str) if isinstance(nfcore_str, str) else nfcore_str
        except:
            nfcore = {}

        warnings = []
        recommendations = []

        # Check omics suitability
        if 'research_domain' in user_context:
            omics_app = context.get('omics_applicability', {})
            primary_omics = omics_app.get('primary_omics', [])
            not_suitable = omics_app.get('not_suitable', [])

            domain = user_context['research_domain'].lower()

            if any(domain in str(ns).lower() for ns in not_suitable):
                warnings.append(f"Tool is explicitly NOT suitable for {user_context['research_domain']}")
            elif not any(domain in str(omics).lower() for omics in primary_omics):
                warnings.append(f"Tool not primarily designed for {user_context['research_domain']}")

        # Check data requirements
        if 'num_samples' in user_context:
            data_req = context.get('omics_applicability', {}).get('data_requirements', {})
            min_samples = data_req.get('min_samples')

            if min_samples and user_context['num_samples'] < min_samples:
                warnings.append(f"Tool requires at least {min_samples} samples, but only {user_context['num_samples']} provided")

        # Check expertise level
        if 'expertise_level' in user_context:
            guidance = context.get('scientific_guidance', {})
            pitfalls = guidance.get('common_pitfalls', [])

            if user_context['expertise_level'] == 'beginner' and len(pitfalls) > 5:
                recommendations.append("This tool has many common pitfalls. Consider seeking expert guidance.")

        # Add recommendation if tool is in nf-core
        if nfcore and nfcore.get('modules'):
            recommendations.append("✓ This tool is validated by nf-core community and used in production workflows")

        # Calculate suitability
        score = self._calculate_scientific_relevance(tool, context, nfcore, user_context, None)
        suitable = score > 0.5 and len([w for w in warnings if 'NOT suitable' in w]) == 0

        return {
            'suitable': suitable,
            'confidence': score,
            'warnings': warnings,
            'recommendations': recommendations,
            'scientific_context': context,
            'nfcore_metadata': nfcore
        }
