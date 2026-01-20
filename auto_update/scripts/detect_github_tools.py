#!/usr/bin/env python3
"""
GitHub Tool Detector - Auto-Update System Prototype

Detects cutting-edge bioinformatics tools from GitHub based on quality signals.

Usage:
    python detect_github_tools.py --days 90 --min-stars 50
    python detect_github_tools.py --topics bioinformatics,genomics
    python detect_github_tools.py --output data/discoveries/
"""

import argparse
import json
import logging
import os
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta
from pathlib import Path
from typing import List, Dict, Optional

import requests
import yaml
from github import Github, GithubException
from colorama import init, Fore, Style

# Initialize colorama
init(autoreset=True)

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class QualityScorer:
    """
    Scores repositories based on multiple quality signals.
    """

    def __init__(self, config: Dict):
        self.weights = config.get('scoring_weights', {})
        self.popularity_tiers = config.get('popularity_tiers', {})
        self.recency_tiers = config.get('recency_tiers', {})

    def score(self, repo_data: Dict) -> float:
        """Calculate quality score (0.0 - 1.0)"""
        score = 0.0

        # Popularity removed - not fair for new cutting-edge tools

        # Code quality (max 0.35)
        if repo_data.get('has_ci_cd'):
            score += 0.15
        if repo_data.get('has_tests'):
            score += 0.15
        if repo_data.get('has_linter'):
            score += 0.05

        # Documentation (max 0.2)
        if repo_data.get('has_docs'):
            score += 0.1
        if repo_data.get('has_readme'):
            score += 0.05
        if repo_data.get('has_examples'):
            score += 0.05

        # Containerization (max 0.1)
        if repo_data.get('has_container'):
            score += 0.1

        # Recency (max 0.1)
        days_since_update = repo_data.get('days_since_update', 999)
        if days_since_update <= self.recency_tiers.get('fresh', 7):
            score += 0.1
        elif days_since_update <= self.recency_tiers.get('recent', 30):
            score += 0.05

        # Scientific validation (max 0.35)
        if repo_data.get('has_paper'):
            score += 0.2
        if repo_data.get('citation_count', 0) > 10:
            score += 0.15

        # Releases (max 0.05)
        if repo_data.get('has_releases'):
            score += 0.05

        return min(score, 1.0)

    def classify(self, score: float, thresholds: Dict) -> str:
        """Classify score into quality tier"""
        if score >= thresholds.get('auto_approve', 0.8):
            return 'high'
        elif score >= thresholds.get('review_queue', 0.5):
            return 'medium'
        else:
            return 'low'


class GitHubDetector:
    """
    Detects bioinformatics tools from GitHub.
    """

    def __init__(self, token: str, config: Dict):
        from github import Auth
        auth = Auth.Token(token)
        self.github = Github(auth=auth)
        self.config = config
        self.scorer = QualityScorer(config.get('filters', {}))

    def _search_single_topic(
        self,
        topic: str,
        cutoff_str: str,
        min_stars: int,
        languages: Optional[List[str]] = None
    ) -> tuple:
        """
        Search GitHub for a single topic (for parallel execution).

        Args:
            topic: Topic to search
            cutoff_str: Cutoff date string (YYYY-MM-DD)
            min_stars: Minimum stars threshold
            languages: Optional language filters

        Returns:
            Tuple of (topic_discoveries, high_quality_count)
        """
        topic_discoveries = []
        topic_high_quality = 0

        try:
            # Build query
            query_parts = [
                f"topic:{topic}",
                f"stars:>={min_stars}",
                f"pushed:>={cutoff_str}"
            ]

            if languages:
                lang_query = ' '.join([f"language:{lang}" for lang in languages])
                query_parts.append(f"({lang_query})")

            query = ' '.join(query_parts)

            logger.info(f"Query: {query}")

            # Execute search
            repos = self.github.search_repositories(
                query=query,
                sort='stars',
                order='desc'
            )

            # Process results
            count = 0
            for repo in repos:
                if count >= 100:  # Limit to top 100 per topic
                    break

                try:
                    repo_data = self._extract_repo_data(repo)
                    topic_discoveries.append(repo_data)
                    count += 1

                    # Count high-quality repos
                    if repo_data.get('classification') == 'high':
                        topic_high_quality += 1

                except Exception as e:
                    logger.warning(f"Error processing {repo.full_name}: {e}")
                    continue

            logger.info(f"Processed {count} repositories for topic '{topic}' ({topic_high_quality} high-quality)")

        except GithubException as e:
            logger.error(f"GitHub API error for topic '{topic}': {e}")

        return topic_discoveries, topic_high_quality

    def search_repos(
        self,
        topics: List[str],
        min_stars: int = 50,
        days_back: int = 90,
        languages: Optional[List[str]] = None,
        max_high_quality: Optional[int] = None,
        parallel: bool = True,
        max_workers: int = 5
    ) -> List[Dict]:
        """
        Search GitHub for bioinformatics repositories (with parallel search).

        Args:
            topics: List of topics to search
            min_stars: Minimum stars threshold
            days_back: How many days to look back
            languages: Optional language filters
            max_high_quality: Stop searching once we have this many high-quality tools (optimization)
            parallel: Whether to search topics in parallel (default: True)
            max_workers: Maximum number of parallel workers (default: 5)
        """
        logger.info(f"Searching GitHub for repos with topics: {topics}")
        logger.info(f"Filters: min_stars={min_stars}, days_back={days_back}")
        if max_high_quality:
            logger.info(f"Early termination enabled: will stop at {max_high_quality} high-quality tools")
        if parallel:
            logger.info(f"Parallel search enabled with {max_workers} workers")

        cutoff_date = datetime.now() - timedelta(days=days_back)
        cutoff_str = cutoff_date.strftime('%Y-%m-%d')

        discoveries = []
        high_quality_count = 0

        if parallel and len(topics) > 1:
            # Parallel search using ThreadPoolExecutor
            with ThreadPoolExecutor(max_workers=max_workers) as executor:
                # Submit all topic searches
                future_to_topic = {
                    executor.submit(
                        self._search_single_topic,
                        topic,
                        cutoff_str,
                        min_stars,
                        languages
                    ): topic
                    for topic in topics
                }

                # Collect results as they complete
                for future in as_completed(future_to_topic):
                    topic = future_to_topic[future]
                    try:
                        topic_discoveries, topic_high_quality = future.result()
                        discoveries.extend(topic_discoveries)
                        high_quality_count += topic_high_quality

                        # Check for early termination
                        if max_high_quality and high_quality_count >= max_high_quality:
                            logger.info(f"Early termination: found {high_quality_count} high-quality tools")
                            # Cancel remaining futures
                            for f in future_to_topic:
                                f.cancel()
                            break

                    except Exception as e:
                        logger.error(f"Error searching topic '{topic}': {e}")

        else:
            # Sequential search (fallback)
            for topic in topics:
                topic_discoveries, topic_high_quality = self._search_single_topic(
                    topic, cutoff_str, min_stars, languages
                )
                discoveries.extend(topic_discoveries)
                high_quality_count += topic_high_quality

                # Check for early termination
                if max_high_quality and high_quality_count >= max_high_quality:
                    logger.info(f"Early termination: found {high_quality_count} high-quality tools")
                    break

        # Deduplicate
        unique_discoveries = self._deduplicate(discoveries)

        logger.info(f"Found {len(unique_discoveries)} unique repositories")

        return unique_discoveries

    def _extract_repo_data(self, repo) -> Dict:
        """Extract metadata from repository"""
        logger.debug(f"Processing: {repo.full_name}")

        # Check for quality signals
        has_ci_cd = self._has_ci_cd(repo)
        has_tests = self._has_tests(repo)
        has_docs = self._has_documentation(repo)
        has_container = self._has_container(repo)
        has_linter = self._has_linter(repo)
        has_examples = self._has_examples(repo)

        # Calculate days since last update
        last_update = repo.updated_at
        if last_update.tzinfo is not None:
            # Make datetime timezone-aware if repo datetime has timezone
            from datetime import timezone
            now = datetime.now(timezone.utc)
            days_since_update = (now - last_update).days
        else:
            days_since_update = (datetime.now() - last_update).days

        # Extract description
        description = repo.description or "No description"

        # Check for paper/citations (simple heuristic)
        has_paper = self._check_for_paper(repo)

        repo_data = {
            'id': f"github/{repo.full_name}",
            'source': 'github',
            'name': repo.name,
            'full_name': repo.full_name,
            'description': description,
            'url': repo.html_url,
            'stars': repo.stargazers_count,
            'forks': repo.forks_count,
            'language': repo.language,
            'topics': repo.topics,
            'created_at': repo.created_at.isoformat(),
            'updated_at': repo.updated_at.isoformat(),
            'days_since_update': days_since_update,
            'has_readme': bool(repo.get_readme() if not repo.archived else None),
            'has_license': bool(repo.license),
            'has_ci_cd': has_ci_cd,
            'has_tests': has_tests,
            'has_docs': has_docs,
            'has_container': has_container,
            'has_linter': has_linter,
            'has_examples': has_examples,
            'has_releases': repo.get_releases().totalCount > 0,
            'has_paper': has_paper,
            'citation_count': 0,  # Would need external service
            'detected_at': datetime.now().isoformat()
        }

        # Calculate quality score
        score = self.scorer.score(repo_data)
        classification = self.scorer.classify(
            score,
            self.config.get('quality_thresholds', {})
        )

        repo_data['quality_score'] = score
        repo_data['classification'] = classification

        return repo_data

    def _has_ci_cd(self, repo) -> bool:
        """Check for CI/CD configuration"""
        try:
            contents = repo.get_contents("")
            paths = [c.path for c in contents]
            return any([
                '.github/workflows' in paths,
                '.gitlab-ci.yml' in paths,
                '.travis.yml' in paths,
                '.circleci' in paths
            ])
        except:
            return False

    def _has_tests(self, repo) -> bool:
        """Check for test files"""
        try:
            contents = repo.get_contents("")
            paths = [c.path for c in contents]
            return any([
                'tests' in paths,
                'test' in paths,
                'spec' in paths
            ])
        except:
            return False

    def _has_documentation(self, repo) -> bool:
        """Check for documentation"""
        try:
            contents = repo.get_contents("")
            paths = [c.path for c in contents]
            return any([
                'docs' in paths,
                'documentation' in paths,
                'readthedocs.yml' in paths,
                'mkdocs.yml' in paths
            ])
        except:
            return False

    def _has_container(self, repo) -> bool:
        """Check for container files"""
        try:
            contents = repo.get_contents("")
            paths = [c.path for c in contents]
            return any([
                'Dockerfile' in paths,
                'docker-compose.yml' in paths,
                'Singularity' in paths
            ])
        except:
            return False

    def _has_linter(self, repo) -> bool:
        """Check for linter configuration"""
        try:
            contents = repo.get_contents("")
            paths = [c.path for c in contents]
            return any([
                '.pylintrc' in paths,
                '.flake8' in paths,
                '.eslintrc' in paths,
                '.ruffrc.toml' in paths
            ])
        except:
            return False

    def _has_examples(self, repo) -> bool:
        """Check for examples"""
        try:
            contents = repo.get_contents("")
            paths = [c.path for c in contents]
            return any([
                'examples' in paths,
                'example' in paths,
                'demos' in paths
            ])
        except:
            return False

    def _check_for_paper(self, repo) -> bool:
        """Check for associated paper (simple heuristic)"""
        try:
            # Check for CITATION.cff
            try:
                repo.get_contents("CITATION.cff")
                return True
            except:
                pass

            # Check README for DOI or paper keywords
            try:
                readme = repo.get_readme()
                content = readme.decoded_content.decode('utf-8').lower()
                return any([
                    'doi:' in content,
                    'paper' in content,
                    'publication' in content,
                    'cite' in content
                ])
            except:
                pass

        except:
            pass

        return False

    def _deduplicate(self, discoveries: List[Dict]) -> List[Dict]:
        """Remove duplicate repositories"""
        seen = set()
        unique = []

        for disc in discoveries:
            repo_id = disc['full_name']
            if repo_id not in seen:
                seen.add(repo_id)
                unique.append(disc)

        return unique


def load_config(config_dir: Path) -> Dict:
    """Load configuration files"""
    config = {}

    # Load sources.yaml
    sources_path = config_dir / 'sources.yaml'
    if sources_path.exists():
        with open(sources_path) as f:
            config['sources'] = yaml.safe_load(f)

    # Load filters.yaml
    filters_path = config_dir / 'filters.yaml'
    if filters_path.exists():
        with open(filters_path) as f:
            config['filters'] = yaml.safe_load(f)

    # Load credentials.yaml
    creds_path = config_dir / 'credentials.yaml'
    if creds_path.exists():
        with open(creds_path) as f:
            config['credentials'] = yaml.safe_load(f)

    return config


def save_discoveries(discoveries: List[Dict], output_dir: Path):
    """Save discoveries to JSON file"""
    output_dir.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    filename = f"github_tools_{timestamp}.json"
    output_path = output_dir / filename

    with open(output_path, 'w') as f:
        json.dump(discoveries, f, indent=2)

    logger.info(f"Saved discoveries to: {output_path}")

    return output_path


def print_summary(discoveries: List[Dict]):
    """Print discovery summary"""
    print(f"\n{Fore.CYAN}{'='*80}{Style.RESET_ALL}")
    print(f"{Fore.CYAN}Discovery Summary{Style.RESET_ALL}")
    print(f"{Fore.CYAN}{'='*80}{Style.RESET_ALL}\n")

    print(f"Total repositories found: {Fore.GREEN}{len(discoveries)}{Style.RESET_ALL}\n")

    # Count by classification
    high = sum(1 for d in discoveries if d['classification'] == 'high')
    medium = sum(1 for d in discoveries if d['classification'] == 'medium')
    low = sum(1 for d in discoveries if d['classification'] == 'low')

    print("Quality Distribution:")
    print(f"  {Fore.GREEN}High quality (>0.8):{Style.RESET_ALL} {high} (auto-add)")
    print(f"  {Fore.YELLOW}Medium quality (0.5-0.8):{Style.RESET_ALL} {medium} (review queue)")
    print(f"  {Fore.RED}Low quality (<0.5):{Style.RESET_ALL} {low} (reject)\n")

    # Top 10 by score
    sorted_discoveries = sorted(
        discoveries,
        key=lambda x: x['quality_score'],
        reverse=True
    )

    print(f"{Fore.CYAN}Top 10 Tools by Quality Score:{Style.RESET_ALL}\n")
    for i, disc in enumerate(sorted_discoveries[:10], 1):
        color = Fore.GREEN if disc['classification'] == 'high' else Fore.YELLOW
        print(f"{i:2d}. {color}{disc['name']}{Style.RESET_ALL} "
              f"({disc['stars']} ⭐) - Score: {disc['quality_score']:.2f}")
        print(f"    {disc['description'][:80]}...")
        print(f"    {disc['url']}\n")


def main():
    parser = argparse.ArgumentParser(
        description='Detect cutting-edge bioinformatics tools from GitHub'
    )
    parser.add_argument(
        '--days',
        type=int,
        default=90,
        help='Look back N days (default: 90)'
    )
    parser.add_argument(
        '--min-stars',
        type=int,
        default=50,
        help='Minimum stars (default: 50)'
    )
    parser.add_argument(
        '--topics',
        type=str,
        help='Comma-separated topics (default: from config)'
    )
    parser.add_argument(
        '--output',
        type=str,
        default='data/discoveries',
        help='Output directory (default: data/discoveries)'
    )
    parser.add_argument(
        '--verbose',
        action='store_true',
        help='Enable verbose logging'
    )

    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    # Load configuration
    script_dir = Path(__file__).parent.parent
    config_dir = script_dir / 'config'
    config = load_config(config_dir)

    # Get GitHub token
    github_token = config.get('credentials', {}).get('github', {}).get('token')
    if not github_token:
        logger.error("GitHub token not found in config/credentials.yaml")
        logger.error("Please copy credentials.yaml.example and add your token")
        sys.exit(1)

    # Get topics
    if args.topics:
        topics = [t.strip() for t in args.topics.split(',')]
    else:
        topics = config.get('sources', {}).get('github', {}).get('topics', [])

    if not topics:
        logger.error("No topics specified")
        sys.exit(1)

    # Initialize detector
    detector = GitHubDetector(
        token=github_token,
        config={
            'filters': config.get('filters', {}),
            'quality_thresholds': config.get('sources', {}).get('quality_thresholds', {})
        }
    )

    # Run detection
    logger.info("Starting GitHub tool detection...")
    discoveries = detector.search_repos(
        topics=topics,
        min_stars=args.min_stars,
        days_back=args.days
    )

    # Save results
    output_dir = Path(args.output)
    output_path = save_discoveries(discoveries, output_dir)

    # Print summary
    print_summary(discoveries)

    print(f"\n{Fore.GREEN}✓ Detection complete!{Style.RESET_ALL}")
    print(f"Results saved to: {output_path}\n")


if __name__ == '__main__':
    main()
