/**
 * Tool Blog Post Component
 *
 * Displays blog posts for newly added tools with:
 * - Introduction and significance
 * - Input/output specifications
 * - Workflow integration suggestions
 * - "Try Now" button with auth check
 */

import React, { useState, useEffect } from 'react';
import ReactMarkdown from 'react-markdown';
import { useNavigate } from 'react-router-dom';
import './tool-blog-post.css';

interface ToolBlogPostProps {
  toolId?: string;
  showNewTools?: boolean;
  limit?: number;
}

interface BlogPost {
  tool_id: string;
  content: string;
  format: string;
  generated_at: string;
  tool_data?: {
    name: string;
    category: string;
    description: string;
    quality_score?: number;
    stars?: number;
    github_url?: string;
  };
}

interface WorkflowLinkData {
  tool_id: string;
  tool_name: string;
  workflow_url: string;
  requires_auth: boolean;
  login_url?: string;
  user_logged_in: boolean;
}

export const ToolBlogPost: React.FC<ToolBlogPostProps> = ({
  toolId,
  showNewTools = false,
  limit = 10
}) => {
  const [blogPost, setBlogPost] = useState<BlogPost | null>(null);
  const [blogPosts, setBlogPosts] = useState<BlogPost[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [workflowLink, setWorkflowLink] = useState<WorkflowLinkData | null>(null);
  const navigate = useNavigate();

  useEffect(() => {
    if (toolId) {
      fetchBlogPost(toolId);
    } else if (showNewTools) {
      fetchNewBlogPosts(limit);
    }
  }, [toolId, showNewTools, limit]);

  const fetchBlogPost = async (id: string) => {
    try {
      setLoading(true);
      const response = await fetch(`/api/tool-blog/${id}`);
      const data = await response.json();

      if (data.success) {
        setBlogPost(data.post);
      } else {
        setError(data.error || 'Failed to load blog post');
      }
    } catch (err) {
      setError('Network error loading blog post');
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  const fetchNewBlogPosts = async (lim: number) => {
    try {
      setLoading(true);
      const response = await fetch(`/api/tool-blog/new?limit=${lim}`);
      const data = await response.json();

      if (data.success) {
        setBlogPosts(data.posts);
      } else {
        setError(data.error || 'Failed to load blog posts');
      }
    } catch (err) {
      setError('Network error loading blog posts');
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  const handleTryNow = async (id: string) => {
    try {
      // Fetch workflow link with auth check
      const response = await fetch(`/api/tool-blog/workflow-link/${id}`);
      const data: WorkflowLinkData = await response.json();

      if (data.success === false) {
        alert('Error generating workflow link');
        return;
      }

      setWorkflowLink(data);

      if (data.requires_auth && data.login_url) {
        // Redirect to login with return URL
        window.location.href = data.login_url;
      } else {
        // User is logged in, navigate to workflow
        navigate(data.workflow_url);
      }
    } catch (err) {
      console.error('Error loading workflow:', err);
      alert('Failed to load workflow');
    }
  };

  const TryNowButton: React.FC<{ toolId: string; toolName: string }> = ({ toolId: id, toolName }) => (
    <button
      className="try-now-button"
      onClick={() => handleTryNow(id)}
      title={`Try ${toolName} in an interactive workflow`}
    >
      🚀 Try {toolName} Now
    </button>
  );

  const BlogPostCard: React.FC<{ post: BlogPost }> = ({ post }) => (
    <div className="blog-post-card">
      <div className="blog-post-header">
        <h2>{post.tool_data?.name || post.tool_id}</h2>
        {post.tool_data?.category && (
          <span className="category-badge">{post.tool_data.category}</span>
        )}
        {post.tool_data?.quality_score && (
          <span className="quality-badge">
            ⭐ {(post.tool_data.quality_score * 100).toFixed(0)}%
          </span>
        )}
      </div>

      <div className="blog-post-content">
        <ReactMarkdown>{post.content}</ReactMarkdown>
      </div>

      <div className="blog-post-footer">
        <TryNowButton
          toolId={post.tool_id}
          toolName={post.tool_data?.name || post.tool_id}
        />

        {post.tool_data?.github_url && (
          <a
            href={post.tool_data.github_url}
            target="_blank"
            rel="noopener noreferrer"
            className="github-link"
          >
            <svg viewBox="0 0 16 16" width="16" height="16">
              <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"></path>
            </svg>
            View on GitHub
          </a>
        )}

        <span className="generated-date">
          Added {new Date(post.generated_at).toLocaleDateString()}
        </span>
      </div>
    </div>
  );

  if (loading) {
    return (
      <div className="blog-post-loading">
        <div className="spinner"></div>
        <p>Loading blog post...</p>
      </div>
    );
  }

  if (error) {
    return (
      <div className="blog-post-error">
        <p>❌ {error}</p>
      </div>
    );
  }

  if (showNewTools) {
    return (
      <div className="blog-posts-container">
        <h1>Recently Added Tools</h1>
        <p className="subtitle">
          Discover our latest bioinformatics tools with interactive workflows
        </p>

        {blogPosts.length === 0 ? (
          <p>No new tools available</p>
        ) : (
          <div className="blog-posts-grid">
            {blogPosts.map(post => (
              <BlogPostCard key={post.tool_id} post={post} />
            ))}
          </div>
        )}
      </div>
    );
  }

  if (blogPost) {
    return (
      <div className="blog-posts-container">
        <BlogPostCard post={blogPost} />
      </div>
    );
  }

  return <div>No blog post found</div>;
};

export default ToolBlogPost;
