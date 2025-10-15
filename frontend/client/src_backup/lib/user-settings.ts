import type { UserSettings } from '@shared/schema';

// User settings management service
class UserSettingsService {
  private storageKey = 'biomate-user-settings';
  
  // Get user settings
  getSettings(): UserSettings {
    try {
      const stored = localStorage.getItem(this.storageKey);
      if (!stored) return this.getDefaultSettings();
      return JSON.parse(stored);
    } catch (error) {
      console.error('Error loading user settings:', error);
      return this.getDefaultSettings();
    }
  }
  
  // Update user settings
  updateSettings(updates: Partial<UserSettings>): UserSettings {
    const currentSettings = this.getSettings();
    const updatedSettings: UserSettings = {
      ...currentSettings,
      ...updates,
      updatedAt: new Date()
    };
    
    this.saveSettings(updatedSettings);
    return updatedSettings;
  }
  
  // Update a specific setting
  updateSetting<K extends keyof UserSettings>(key: K, value: UserSettings[K]): UserSettings {
    return this.updateSettings({ [key]: value });
  }
  
  // Reset to default settings
  resetToDefaults(): UserSettings {
    const defaultSettings = this.getDefaultSettings();
    this.saveSettings(defaultSettings);
    return defaultSettings;
  }
  
  // Export settings as JSON
  exportSettings(): string {
    return JSON.stringify(this.getSettings(), null, 2);
  }
  
  // Import settings from JSON
  importSettings(settingsJson: string): UserSettings {
    try {
      const importedSettings = JSON.parse(settingsJson);
      const validatedSettings = this.validateSettings(importedSettings);
      this.saveSettings(validatedSettings);
      return validatedSettings;
    } catch (error) {
      console.error('Error importing settings:', error);
      throw new Error('Invalid settings format');
    }
  }
  
  // Get settings for a specific category
  getProfileSettings() {
    const settings = this.getSettings();
    return {
      displayName: settings.displayName,
      email: settings.email,
      role: settings.role,
      avatar: settings.avatar
    };
  }
  
  getApplicationSettings() {
    const settings = this.getSettings();
    return {
      language: settings.language,
      theme: settings.theme
    };
  }
  
  getWorkflowSettings() {
    const settings = this.getSettings();
    return {
      defaultWorkflowComplexity: settings.defaultWorkflowComplexity,
      autoSaveWorkflows: settings.autoSaveWorkflows,
      showWorkflowEstimates: settings.showWorkflowEstimates
    };
  }
  
  getChatSettings() {
    const settings = this.getSettings();
    return {
      chatSuggestions: settings.chatSuggestions,
      typingIndicator: settings.typingIndicator,
      messageTimestamps: settings.messageTimestamps
    };
  }
  
  getDataSettings() {
    const settings = this.getSettings();
    return {
      defaultStorageType: settings.defaultStorageType,
      autoDeleteTempFiles: settings.autoDeleteTempFiles,
      dataRetentionDays: settings.dataRetentionDays
    };
  }
  
  getNotificationSettings() {
    const settings = this.getSettings();
    return {
      workflowCompletionNotifications: settings.workflowCompletionNotifications,
      errorNotifications: settings.errorNotifications
    };
  }
  
  getPrivacySettings() {
    const settings = this.getSettings();
    return {
      shareUsageData: settings.shareUsageData,
      shareErrorReports: settings.shareErrorReports
    };
  }
  
  getAdvancedSettings() {
    const settings = this.getSettings();
    return {
      debugMode: settings.debugMode,
      experimentalFeatures: settings.experimentalFeatures
    };
  }
  
  // Private helper methods
  private saveSettings(settings: UserSettings): void {
    try {
      localStorage.setItem(this.storageKey, JSON.stringify(settings));
    } catch (error) {
      console.error('Error saving user settings:', error);
    }
  }
  
  private validateSettings(settings: any): UserSettings {
    // Basic validation - in a real app, you'd use the Zod schema
    const defaultSettings = this.getDefaultSettings();
    return {
      ...defaultSettings,
      ...settings,
      updatedAt: new Date()
    };
  }
  
  private getDefaultSettings(): UserSettings {
    return {
      id: 'settings-default',
      userId: 'user-default',
      // Profile settings
      displayName: 'John Doe',
      email: 'john.doe@biomate.com',
      role: 'Researcher',
      avatar: undefined,
      // Application preferences
      language: 'english',
      theme: 'system',
      // Workflow preferences
      defaultWorkflowComplexity: 'intermediate',
      autoSaveWorkflows: true,
      showWorkflowEstimates: true,
      // Chat preferences
      chatSuggestions: true,
      typingIndicator: true,
      messageTimestamps: true,
      // Data preferences
      defaultStorageType: 'replit_storage',
      autoDeleteTempFiles: true,
      dataRetentionDays: 30,
      // Notification preferences
      workflowCompletionNotifications: true,
      errorNotifications: true,
      // Privacy settings
      shareUsageData: false,
      shareErrorReports: true,
      // Advanced settings
      debugMode: false,
      experimentalFeatures: false,
      updatedAt: new Date()
    };
  }
}

export const userSettingsService = new UserSettingsService();