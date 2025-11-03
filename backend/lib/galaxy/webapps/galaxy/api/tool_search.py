"""
API for searching and installing tools on-demand
With proper validation, error handling, and HTTP status codes
"""

import logging
from typing import Optional, Dict, Any

from fastapi import (
    Body,
    Path,
    Query,
    HTTPException,
    status,
)
from pydantic import Field, constr, conint

from galaxy.managers.context import ProvidesUserContext
from galaxy.tools.search_index import ToolSearchIndex
from galaxy.ai.enhanced_tool_search import EnhancedToolSearch
from galaxy.tools.on_demand_installer import OnDemandToolInstaller
from galaxy.webapps.galaxy.api import (
    depends,
    DependsOnTrans,
    Router,
)

log = logging.getLogger(__name__)

router = Router(tags=["tool_search"])


@router.cbv
class FastAPIToolSearch:
    search_index: ToolSearchIndex = depends(ToolSearchIndex)

    def __init__(self):
        # Initialize enhanced search if available
        try:
            self.enhanced_search = EnhancedToolSearch(self.search_index)
            log.info("Enhanced tool search initialized successfully")
        except Exception as e:
            log.warning(f"Enhanced tool search not available: {e}")
            self.enhanced_search = None

    @router.get(
        "/api/tool_search",
        summary="Search for tools in ToolShed",
        response_model_exclude_unset=True,
    )
    def search_tools(
        self,
        trans: ProvidesUserContext = DependsOnTrans,
        q: constr(min_length=1, max_length=200) = Query(..., description="Search query (1-200 chars)"),
        category: Optional[str] = Query(None, description="Filter by category", max_length=100),
        limit: conint(ge=1, le=1000) = Query(50, description="Maximum results (1-1000)"),
    ):
        """
        Search for tools using full-text search

        Raises:
            400: Invalid query parameters
            500: Search error
        """
        try:
            results = self.search_index.search(q, category=category, limit=limit)
            return {
                "query": q,
                "category": category,
                "count": len(results),
                "tools": results
            }
        except ValueError as e:
            log.warning(f"Invalid search parameters: {e}")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=str(e)
            )
        except Exception as e:
            log.error(f"Tool search error: {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Search failed: {str(e)}"
            )

    @router.get(
        "/api/tool_search/categories",
        summary="Get list of tool categories",
    )
    def get_categories(
        self,
        trans: ProvidesUserContext = DependsOnTrans,
    ):
        """
        Get list of all tool categories with counts

        Raises:
            500: Database error
        """
        try:
            stats = self.search_index.get_category_stats()
            return {
                "categories": [
                    {"name": cat, "count": count}
                    for cat, count in stats.items()
                ]
            }
        except Exception as e:
            log.error(f"Error fetching categories: {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Failed to fetch categories: {str(e)}"
            )

    @router.get(
        "/api/tool_search/schema",
        summary="Get tool parameter schema for configuration UI",
    )
    def get_tool_schema(
        self,
        trans: ProvidesUserContext = DependsOnTrans,
        tool_id: constr(min_length=1, max_length=500) = Query(..., description="Tool ID"),
    ):
        """
        Get structured parameter schema for a tool (for frontend parameter editor)

        Returns:
            ToolSchema with structured inputs/outputs for dynamic form generation

        Raises:
            404: Tool not found or schema not available
            500: Database error
        """
        try:
            schema = self.search_index.get_tool_schema(tool_id)
            if schema:
                return schema
            else:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=f"Tool schema not found: {tool_id}"
                )
        except HTTPException:
            raise
        except Exception as e:
            log.error(f"Error fetching tool schema {tool_id}: {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Failed to fetch tool schema: {str(e)}"
            )

    @router.get(
        "/api/tool_search/{tool_id:path}",
        summary="Get tool details by ID",
    )
    def get_tool(
        self,
        trans: ProvidesUserContext = DependsOnTrans,
        tool_id: str = Path(..., description="Tool ID", min_length=1, max_length=500),
    ):
        """
        Get detailed information about a specific tool

        Raises:
            404: Tool not found
            500: Database error
        """
        try:
            tool = self.search_index.get_by_id(tool_id)
            if tool:
                return tool
            else:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=f"Tool not found: {tool_id}"
                )
        except HTTPException:
            raise
        except Exception as e:
            log.error(f"Error fetching tool {tool_id}: {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Failed to fetch tool: {str(e)}"
            )

    @router.post(
        "/api/tool_search/install",
        summary="Install a tool on-demand",
        status_code=status.HTTP_202_ACCEPTED,
    )
    def install_tool(
        self,
        trans: ProvidesUserContext = DependsOnTrans,
        tool_id: Optional[constr(min_length=1, max_length=500)] = Body(
            None, description="Tool ID from search index"
        ),
        owner: Optional[constr(min_length=1, max_length=100)] = Body(
            None, description="Repository owner"
        ),
        name: Optional[constr(min_length=1, max_length=100)] = Body(
            None, description="Repository name"
        ),
        changeset_revision: Optional[str] = Body(
            "latest", description="Changeset revision", max_length=40
        ),
        tool_shed_url: constr(min_length=1, max_length=200) = Body(
            "https://toolshed.g2.bx.psu.edu", description="ToolShed URL"
        ),
        tool_panel_section_id: constr(min_length=1, max_length=100) = Body(
            "lcms_metabolomics", description="Tool panel section"
        ),
    ):
        """
        Install a tool from ToolShed on-demand (admin only)

        Raises:
            400: Missing required parameters
            401: Not authenticated
            403: Not admin
            404: Tool not found in index
            500: Installation error
        """
        # Check authentication
        if not trans.user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Authentication required"
            )

        # Check admin permission
        if not trans.user_is_admin:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Admin access required for tool installation"
            )

        # Validate parameters
        if not tool_id and not (owner and name):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Must provide either tool_id or (owner, name)"
            )

        try:
            installer = OnDemandToolInstaller(trans.app, self.search_index)

            result = installer.install_tool_sync(
                tool_id=tool_id,
                owner=owner,
                name=name,
                changeset_revision=changeset_revision,
                tool_shed_url=tool_shed_url,
                tool_panel_section_id=tool_panel_section_id,
            )

            if result['success']:
                return result
            else:
                # Map error types to HTTP status codes
                error_code = result.get('error', 'Unknown')
                if error_code == 'ToolNotFound':
                    raise HTTPException(
                        status_code=status.HTTP_404_NOT_FOUND,
                        detail=result.get('message', 'Tool not found')
                    )
                elif error_code == 'MissingParameters':
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=result.get('message', 'Missing parameters')
                    )
                else:
                    raise HTTPException(
                        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                        detail=result.get('message', 'Installation failed')
                    )

        except HTTPException:
            raise
        except Exception as e:
            log.error(f"Tool installation error: {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Installation failed: {str(e)}"
            )

    @router.post(
        "/api/tool_search/check_and_install",
        summary="Check if tool is installed, install if not",
        status_code=status.HTTP_200_OK,
    )
    def check_and_install(
        self,
        trans: ProvidesUserContext = DependsOnTrans,
        tool_id: constr(min_length=1, max_length=500) = Body(
            ..., description="Tool ID to check/install"
        ),
    ):
        """
        Check if a tool is installed, install it if not (admin only)

        Raises:
            400: Invalid tool_id
            401: Not authenticated
            403: Not admin
            404: Tool not found
            500: Check/install error
        """
        # Check authentication
        if not trans.user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Authentication required"
            )

        # Check admin permission
        if not trans.user_is_admin:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Admin access required"
            )

        try:
            installer = OnDemandToolInstaller(trans.app, self.search_index)
            result = installer.check_and_install(tool_id)

            if result['success']:
                return result
            else:
                error_code = result.get('error', 'Unknown')
                if error_code == 'ToolNotFound':
                    raise HTTPException(
                        status_code=status.HTTP_404_NOT_FOUND,
                        detail=result.get('message', 'Tool not found')
                    )
                else:
                    raise HTTPException(
                        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                        detail=result.get('message', 'Check and install failed')
                    )

        except HTTPException:
            raise
        except Exception as e:
            log.error(f"Check and install error: {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Check and install failed: {str(e)}"
            )

    @router.get(
        "/api/tool_search/installed",
        summary="Get list of installed tools",
    )
    def get_installed_tools(
        self,
        trans: ProvidesUserContext = DependsOnTrans,
    ):
        """
        Get list of all installed tools from the index

        Raises:
            500: Database error
        """
        try:
            tools = self.search_index.get_installed_tools()
            return {
                "count": len(tools),
                "tools": tools
            }
        except Exception as e:
            log.error(f"Error fetching installed tools: {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Failed to fetch installed tools: {str(e)}"
            )

    @router.post(
        "/api/tool_search/enhanced",
        summary="Enhanced tool search using scientific context",
    )
    def enhanced_search(
        self,
        trans: ProvidesUserContext = DependsOnTrans,
        query: constr(min_length=1, max_length=200) = Body(..., description="Search query"),
        session_id: Optional[str] = Body(
            None,
            description="Session ID to auto-inject user context"
        ),
        user_context: Optional[Dict[str, Any]] = Body(
            None,
            description="User context: research_domain, expertise_level, data_type, etc. (overrides session context)"
        ),
        filters: Optional[Dict[str, Any]] = Body(
            None,
            description="Search filters: omics_type, suitable_for, min_samples, data_format"
        ),
        limit: conint(ge=1, le=100) = Body(20, description="Maximum results (1-100)"),
    ):
        """
        Enhanced tool search that uses scientific_context JSON for intelligent ranking

        Example request body:
        {
            "query": "differential expression proteomics",
            "user_context": {
                "research_domain": "proteomics",
                "expertise_level": "intermediate",
                "data_type": "DIA-LCMS",
                "num_samples": 6,
                "num_replicates": 3
            },
            "filters": {
                "suitable_for": "differential expression",
                "omics_type": "proteomics"
            },
            "limit": 20
        }

        Returns:
            {
                "query": str,
                "count": int,
                "tools": [
                    {
                        ...tool fields...,
                        "scientific_relevance_score": float,
                        "combined_score": float,
                        "relevance_explanation": str,
                        "parsed_context": dict
                    }
                ]
            }

        Raises:
            400: Invalid query parameters
            500: Search error
            503: Enhanced search not available
        """
        if not self.enhanced_search:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Enhanced search not available - using standard search instead"
            )

        try:
            results = self.enhanced_search.search_with_context(
                query=query,
                user_context=user_context,
                filters=filters,
                limit=limit
            )

            return {
                "query": query,
                "user_context": user_context,
                "filters": filters,
                "count": len(results),
                "tools": results
            }

        except ValueError as e:
            log.warning(f"Invalid enhanced search parameters: {e}")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=str(e)
            )
        except Exception as e:
            log.error(f"Enhanced search error: {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Enhanced search failed: {str(e)}"
            )

    @router.post(
        "/api/tool_search/validate",
        summary="Validate if a tool is suitable for given context",
    )
    def validate_tool(
        self,
        trans: ProvidesUserContext = DependsOnTrans,
        tool_id: constr(min_length=1, max_length=500) = Body(..., description="Tool ID to validate"),
        user_context: Dict[str, Any] = Body(..., description="User research context"),
    ):
        """
        Validate if a tool is appropriate for the given research context

        Example request body:
        {
            "tool_id": "toolshed.g2.bx.psu.edu/repos/...",
            "user_context": {
                "research_domain": "proteomics",
                "expertise_level": "beginner",
                "num_samples": 3,
                "num_replicates": 1
            }
        }

        Returns:
            {
                "tool_id": str,
                "suitable": bool,
                "confidence": float,
                "warnings": [str],
                "recommendations": [str],
                "scientific_context": dict
            }

        Raises:
            400: Invalid parameters
            404: Tool not found
            500: Validation error
            503: Enhanced search not available
        """
        if not self.enhanced_search:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Tool validation not available - enhanced search required"
            )

        try:
            result = self.enhanced_search.validate_tool_for_context(
                tool_id=tool_id,
                user_context=user_context
            )

            if not result.get('suitable') and result.get('confidence', 0) == 0:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=f"Tool not found: {tool_id}"
                )

            return {
                "tool_id": tool_id,
                **result
            }

        except HTTPException:
            raise
        except ValueError as e:
            log.warning(f"Invalid validation parameters: {e}")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=str(e)
            )
        except Exception as e:
            log.error(f"Tool validation error: {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Validation failed: {str(e)}"
            )
