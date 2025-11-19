#!/usr/bin/env python3
"""
API Availability Detector - Detect if tools have REST/web APIs

Checks for:
- REST API endpoints
- Web service interfaces
- GraphQL/gRPC APIs
- Documented API usage

Usage:
    from api_detector import APIDetector
    detector = APIDetector()
    has_api, api_info = detector.check(tool_metadata)
"""

import re
import logging
from typing import Dict, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class APIDetector:
    """
    Detects if a tool has a REST/web API that could be used instead of local installation.
    """

    API_INDICATORS = [
        # REST API
        'rest api', 'restful api', 'api endpoint', 'web api',
        'http api', 'https api', '/api/', 'api documentation',

        # Web services
        'web service', 'web server', 'api server',

        # Specific protocols
        'graphql', 'grpc', 'soap api', 'json api', 'xml api',

        # API tools/frameworks
        'swagger', 'openapi', 'postman', 'api gateway',

        # Cloud/hosted services
        'cloud api', 'hosted api', 'saas', 'online tool',

        # Documentation patterns
        'api reference', 'api guide', 'curl', 'api key',
        'api token', 'authentication', 'rate limit',
    ]

    API_URL_PATTERNS = [
        r'https?://[^\s]+/api[/\s]',
        r'api\.[^\s]+\.com',
        r'/v\d+/api',
        r'graphql endpoint',
    ]

    def check(self, tool: Dict) -> Tuple[bool, Optional[Dict]]:
        """
        Check if tool has an API.

        Args:
            tool: Dictionary with 'readme', 'description', 'homepage' keys

        Returns:
            Tuple of (has_api, api_info_dict)
        """
        readme = tool.get('readme', '').lower()
        description = tool.get('description', '').lower()
        homepage = tool.get('homepage', '').lower()

        combined_text = f"{readme} {description} {homepage}"

        # Check for API indicators
        api_indicators_found = []
        for indicator in self.API_INDICATORS:
            if indicator in combined_text:
                api_indicators_found.append(indicator)

        # Check for API URL patterns
        api_urls_found = []
        for pattern in self.API_URL_PATTERNS:
            matches = re.findall(pattern, combined_text, re.IGNORECASE)
            api_urls_found.extend(matches)

        has_api = len(api_indicators_found) >= 2 or len(api_urls_found) >= 1

        if has_api:
            api_info = {
                'has_api': True,
                'indicators': api_indicators_found[:5],  # Top 5
                'urls': api_urls_found[:3],  # Top 3
                'confidence': self._calculate_confidence(
                    len(api_indicators_found),
                    len(api_urls_found)
                )
            }
            return True, api_info
        else:
            return False, None

    def _calculate_confidence(self, num_indicators: int, num_urls: int) -> float:
        """
        Calculate confidence score for API availability.

        Returns:
            Confidence between 0.0 and 1.0
        """
        # URLs are stronger signals
        url_score = min(num_urls * 0.3, 0.6)
        indicator_score = min(num_indicators * 0.1, 0.4)

        return min(url_score + indicator_score, 0.95)


if __name__ == '__main__':
    # Test
    detector = APIDetector()

    test_tool = {
        'readme': 'This tool provides a REST API at https://example.com/api/v1',
        'description': 'Web service for data analysis',
        'homepage': 'https://api.example.com'
    }

    has_api, api_info = detector.check(test_tool)
    print(f"Has API: {has_api}")
    if api_info:
        print(f"API Info: {api_info}")
