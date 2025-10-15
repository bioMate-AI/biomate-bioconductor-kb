import type { RecentTool } from '@shared/schema';

// Recent tools tracking service
class RecentToolsService {
  private storageKey = 'biomate-recent-tools';
  private maxRecentTools = 20; // Keep only the 20 most recent tools
  
  // Get all recent tools
  getAllRecent(): RecentTool[] {
    try {
      const stored = localStorage.getItem(this.storageKey);
      if (!stored) return this.getDefaultRecent();
      return JSON.parse(stored).sort((a: RecentTool, b: RecentTool) => 
        new Date(b.lastUsed).getTime() - new Date(a.lastUsed).getTime()
      );
    } catch (error) {
      console.error('Error loading recent tools:', error);
      return this.getDefaultRecent();
    }
  }
  
  // Add a tool to recent tools (or update if already exists)
  addRecentTool(tool: Omit<RecentTool, 'id' | 'lastUsed' | 'usageCount'>): RecentTool {
    const recent = this.getAllRecent();
    const existingIndex = recent.findIndex(t => t.toolId === tool.toolId);
    
    if (existingIndex !== -1) {
      // Update existing tool
      recent[existingIndex] = {
        ...recent[existingIndex],
        lastUsed: new Date(),
        usageCount: recent[existingIndex].usageCount + 1
      };
      this.saveRecent(recent);
      return recent[existingIndex];
    } else {
      // Add new tool
      const recentTool: RecentTool = {
        ...tool,
        id: `recent-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
        lastUsed: new Date(),
        usageCount: 1
      };
      
      recent.unshift(recentTool);
      
      // Keep only the most recent tools
      if (recent.length > this.maxRecentTools) {
        recent.splice(this.maxRecentTools);
      }
      
      this.saveRecent(recent);
      return recentTool;
    }
  }
  
  // Remove a tool from recent tools
  removeRecentTool(toolId: string): boolean {
    const recent = this.getAllRecent();
    const filteredRecent = recent.filter(t => t.toolId !== toolId);
    
    if (filteredRecent.length === recent.length) {
      return false; // Not found
    }
    
    this.saveRecent(filteredRecent);
    return true;
  }
  
  // Get recent tools by category
  getByCategory(category: string): RecentTool[] {
    return this.getAllRecent().filter(tool => tool.category === category);
  }
  
  // Get most used tools
  getMostUsed(limit: number = 10): RecentTool[] {
    return this.getAllRecent()
      .sort((a, b) => b.usageCount - a.usageCount)
      .slice(0, limit);
  }
  
  // Clear all recent tools
  clearAll(): void {
    localStorage.removeItem(this.storageKey);
  }
  
  // Clear old tools (older than specified days)
  clearOldTools(daysOld: number = 30): void {
    const cutoffDate = new Date(Date.now() - (daysOld * 24 * 60 * 60 * 1000));
    const recent = this.getAllRecent();
    const filteredRecent = recent.filter(tool => new Date(tool.lastUsed) > cutoffDate);
    this.saveRecent(filteredRecent);
  }
  
  // Private helper methods
  private saveRecent(recent: RecentTool[]): void {
    try {
      localStorage.setItem(this.storageKey, JSON.stringify(recent));
    } catch (error) {
      console.error('Error saving recent tools:', error);
    }
  }
  
  private getDefaultRecent(): RecentTool[] {
    return [
      {
        id: 'recent-default-1',
        toolId: 'fastqc',
        name: 'FastQC',
        description: 'Quality control tool for high throughput sequence data',
        category: 'quality-control',
        complexity: 'simple',
        lastUsed: new Date(Date.now() - 3600000), // 1 hour ago
        usageCount: 5
      },
      {
        id: 'recent-default-2',
        toolId: 'hisat2',
        name: 'HISAT2',
        description: 'Graph-based alignment of next generation sequencing reads',
        category: 'alignment',
        complexity: 'intermediate',
        lastUsed: new Date(Date.now() - 7200000), // 2 hours ago
        usageCount: 3
      },
      {
        id: 'recent-default-3',
        toolId: 'samtools',
        name: 'SAMtools',
        description: 'Tools for manipulating alignments in SAM/BAM format',
        category: 'data-sources',
        complexity: 'simple',
        lastUsed: new Date(Date.now() - 10800000), // 3 hours ago
        usageCount: 8
      },
      {
        id: 'recent-default-4',
        toolId: 'deseq2',
        name: 'DESeq2',
        description: 'Differential gene expression analysis',
        category: 'statistics',
        complexity: 'complex',
        lastUsed: new Date(Date.now() - 14400000), // 4 hours ago
        usageCount: 2
      },
      {
        id: 'recent-default-5',
        toolId: 'trimmomatic',
        name: 'Trimmomatic',
        description: 'Flexible read trimming tool for Illumina NGS data',
        category: 'quality-control',
        complexity: 'simple',
        lastUsed: new Date(Date.now() - 18000000), // 5 hours ago
        usageCount: 4
      }
    ];
  }
}

export const recentToolsService = new RecentToolsService();