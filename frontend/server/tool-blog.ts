/**
 * Tool Blog API - Serves blog posts for newly added tools
 *
 * Endpoints:
 * - GET /api/tool-blog/new - Get recent blog posts
 * - GET /api/tool-blog/:toolId - Get blog post for specific tool
 * - POST /api/tool-blog/generate - Generate blog posts for new tools
 */

import { Router } from 'express';
import sqlite3 from 'sqlite3';
import { promisify } from 'util';
import path from 'path';
import fs from 'fs/promises';
import { exec } from 'child_process';

const router = Router();

// Database connection
const DB_PATH = path.join(process.env.HOME || '', 'biomate/backend/database/galaxy_ai_tools.db');
const BLOG_OUTPUT_DIR = path.join(process.env.HOME || '', 'biomate/auto_update/blog_posts');
const BLOG_GENERATOR_SCRIPT = path.join(process.env.HOME || '', 'biomate/auto_update/scripts/blog_post_generator.py');

const db = new sqlite3.Database(DB_PATH);
const dbAll = promisify(db.all.bind(db));
const dbGet = promisify(db.get.bind(db)) as (sql: string, params?: any[]) => Promise<any>;
const execPromise = promisify(exec);

interface ToolBlogPost {
  tool_id: string;
  tool_name: string;
  content: string;
  format: string;
  generated_at: string;
  tool_data?: any;
}

/**
 * GET /api/tool-blog/new
 * Get recent blog posts for newly added tools
 */
router.get('/new', async (req, res) => {
  try {
    const limit = parseInt(req.query.limit as string) || 10;
    const since = req.query.since as string || null;

    let query = `
      SELECT
        tool_id, name, description, category, discovery_date,
        quality_score, github_url, stars
      FROM tools
      WHERE auto_discovered = 1
    `;

    if (since) {
      query += ` AND discovery_date >= '${since}'`;
    }

    query += ` ORDER BY discovery_date DESC LIMIT ${limit}`;

    const tools = await dbAll(query) as any[];

    // Load blog posts for these tools
    const blogPosts = await Promise.all(
      tools.map(async (tool) => {
        const blogPath = path.join(BLOG_OUTPUT_DIR, `${tool.tool_id}_blog.json`);

        try {
          const blogData = await fs.readFile(blogPath, 'utf-8');
          const blog = JSON.parse(blogData);
          return {
            ...blog,
            tool_data: tool
          };
        } catch (error) {
          // Blog post not generated yet
          return null;
        }
      })
    );

    const validBlogPosts = blogPosts.filter(post => post !== null);

    res.json({
      success: true,
      count: validBlogPosts.length,
      posts: validBlogPosts
    });

  } catch (error) {
    console.error('Error fetching blog posts:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch blog posts'
    });
  }
});

/**
 * GET /api/tool-blog/:toolId
 * Get blog post for a specific tool
 */
router.get('/:toolId', async (req, res) => {
  try {
    const { toolId } = req.params;

    // Get tool data
    const tool = await dbGet(
      'SELECT * FROM tools WHERE tool_id = ?',
      [toolId]
    ) as any;

    if (!tool) {
      return res.status(404).json({
        success: false,
        error: 'Tool not found'
      });
    }

    // Try to load existing blog post
    const blogPath = path.join(BLOG_OUTPUT_DIR, `${toolId}_blog.json`);

    try {
      const blogData = await fs.readFile(blogPath, 'utf-8');
      const blog = JSON.parse(blogData);

      res.json({
        success: true,
        post: {
          ...blog,
          tool_data: tool
        }
      });
    } catch (error) {
      // Blog post doesn't exist, generate it
      console.log(`Generating blog post for ${toolId}...`);

      await execPromise(
        `python3 ${BLOG_GENERATOR_SCRIPT} --tool-id ${toolId} --output ${BLOG_OUTPUT_DIR}`
      );

      // Load newly generated blog post
      const blogData = await fs.readFile(blogPath, 'utf-8');
      const blog = JSON.parse(blogData);

      res.json({
        success: true,
        post: {
          ...blog,
          tool_data: tool
        },
        generated: true
      });
    }

  } catch (error) {
    console.error('Error fetching blog post:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch blog post'
    });
  }
});

/**
 * POST /api/tool-blog/generate
 * Generate blog posts for all new tools
 */
router.post('/generate', async (req, res) => {
  try {
    const { since, toolIds } = req.body;

    let command = `python3 ${BLOG_GENERATOR_SCRIPT} --output ${BLOG_OUTPUT_DIR}`;

    if (toolIds && Array.isArray(toolIds)) {
      // Generate for specific tools
      for (const toolId of toolIds) {
        await execPromise(`${command} --tool-id ${toolId}`);
      }

      res.json({
        success: true,
        message: `Generated ${toolIds.length} blog posts`,
        count: toolIds.length
      });
    } else {
      // Generate for all new tools
      if (since) {
        command += ` --all-new --since ${since}`;
      } else {
        command += ` --all-new`;
      }

      await execPromise(command);

      res.json({
        success: true,
        message: 'Blog posts generated for all new tools'
      });
    }

  } catch (error) {
    console.error('Error generating blog posts:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to generate blog posts'
    });
  }
});

/**
 * GET /api/tool-blog/workflow-link/:toolId
 * Generate workflow link for a tool (with auth check)
 */
router.get('/workflow-link/:toolId', async (req, res) => {
  try {
    const { toolId } = req.params;
    const user = (req as any).user; // Assumes auth middleware sets req.user

    // Get tool data
    const tool = await dbGet(
      'SELECT tool_id, name FROM tools WHERE tool_id = ?',
      [toolId]
    ) as any;

    if (!tool) {
      return res.status(404).json({
        success: false,
        error: 'Tool not found'
      });
    }

    // Generate workflow URL
    const workflowUrl = `/workflow/builder?tool=${toolId}&mode=try`;

    res.json({
      success: true,
      tool_id: toolId,
      tool_name: tool.name,
      workflow_url: workflowUrl,
      requires_auth: !user,
      login_url: user ? null : `/login?redirect=${encodeURIComponent(workflowUrl)}`,
      user_logged_in: !!user
    });

  } catch (error) {
    console.error('Error generating workflow link:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to generate workflow link'
    });
  }
});

export default router;
