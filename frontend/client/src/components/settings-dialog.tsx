import { useState, useEffect } from "react"
import { useLocation } from "wouter"
import { useAuth } from "@/contexts/auth-context"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import { Input } from "@/components/ui/input"
import { Switch } from "@/components/ui/switch"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Separator } from "@/components/ui/separator"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { ScrollArea } from "@/components/ui/scroll-area"
import { userSettingsService } from "@/lib/user-settings"
import type { UserSettings } from "@shared/schema"
import { 
  User, 
  Settings, 
  Palette, 
  MessageSquare, 
  Database, 
  Bell, 
  Shield, 
  Code, 
  Download, 
  Upload, 
  RotateCcw,
  HelpCircle,
  ExternalLink,
  LogOut,
  Languages
} from "lucide-react"

interface SettingsDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
}

export function SettingsDialog({ open, onOpenChange }: SettingsDialogProps) {
  const { logout } = useAuth()
  const [, setLocation] = useLocation()
  const [settings, setSettings] = useState<UserSettings>(userSettingsService.getSettings())
  const [activeTab, setActiveTab] = useState("profile")

  const handleLogout = async () => {
    onOpenChange(false)
    await logout()
    setLocation('/login')
  }

  useEffect(() => {
    if (open) {
      setSettings(userSettingsService.getSettings())
    }
  }, [open])

  const updateSetting = <K extends keyof UserSettings>(key: K, value: UserSettings[K]) => {
    const updatedSettings = userSettingsService.updateSetting(key, value)
    setSettings(updatedSettings)
  }

  const resetToDefaults = () => {
    const defaultSettings = userSettingsService.resetToDefaults()
    setSettings(defaultSettings)
  }

  const exportSettings = () => {
    const settingsJson = userSettingsService.exportSettings()
    const blob = new Blob([settingsJson], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = 'biomate-settings.json'
    a.click()
    URL.revokeObjectURL(url)
  }

  const importSettings = (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0]
    if (file) {
      const reader = new FileReader()
      reader.onload = (e) => {
        try {
          const settingsJson = e.target?.result as string
          const importedSettings = userSettingsService.importSettings(settingsJson)
          setSettings(importedSettings)
        } catch (error) {
          console.error('Error importing settings:', error)
        }
      }
      reader.readAsText(file)
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-4xl max-h-[90vh] p-0">
        <DialogHeader className="p-6 pb-0">
          <DialogTitle className="flex items-center gap-2">
            <Settings className="w-5 h-5" />
            Settings
          </DialogTitle>
        </DialogHeader>

        <div className="flex flex-1 overflow-hidden">
          <Tabs value={activeTab} onValueChange={setActiveTab} className="flex flex-1" orientation="vertical">
            {/* Settings Navigation */}
            <div className="w-64 border-r bg-muted/50 p-4">
              <TabsList className="grid w-full grid-cols-1 h-auto gap-1 bg-transparent">
                <TabsTrigger value="profile" className="justify-start gap-2 p-3" data-testid="tab-profile">
                  <User className="w-4 h-4" />
                  Profile
                </TabsTrigger>
                <TabsTrigger value="general" className="justify-start gap-2 p-3" data-testid="tab-general">
                  <Settings className="w-4 h-4" />
                  General
                </TabsTrigger>
                <TabsTrigger value="appearance" className="justify-start gap-2 p-3" data-testid="tab-appearance">
                  <Palette className="w-4 h-4" />
                  Appearance
                </TabsTrigger>
                <TabsTrigger value="chat" className="justify-start gap-2 p-3" data-testid="tab-chat">
                  <MessageSquare className="w-4 h-4" />
                  Chat
                </TabsTrigger>
                <TabsTrigger value="data" className="justify-start gap-2 p-3" data-testid="tab-data">
                  <Database className="w-4 h-4" />
                  Data
                </TabsTrigger>
                <TabsTrigger value="notifications" className="justify-start gap-2 p-3" data-testid="tab-notifications">
                  <Bell className="w-4 h-4" />
                  Notifications
                </TabsTrigger>
                <TabsTrigger value="privacy" className="justify-start gap-2 p-3" data-testid="tab-privacy">
                  <Shield className="w-4 h-4" />
                  Privacy
                </TabsTrigger>
                <TabsTrigger value="advanced" className="justify-start gap-2 p-3" data-testid="tab-advanced">
                  <Code className="w-4 h-4" />
                  Advanced
                </TabsTrigger>
              </TabsList>

              <Separator className="my-4" />

              {/* Quick Actions */}
              <div className="space-y-2">
                <Button variant="outline" size="sm" onClick={exportSettings} className="w-full justify-start gap-2" data-testid="button-export-settings">
                  <Download className="w-4 h-4" />
                  Export Settings
                </Button>
                <Button variant="outline" size="sm" className="w-full justify-start gap-2" data-testid="button-import-settings">
                  <Upload className="w-4 h-4" />
                  <label htmlFor="import-settings" className="cursor-pointer">
                    Import Settings
                  </label>
                </Button>
                <input
                  id="import-settings"
                  type="file"
                  accept=".json"
                  className="hidden"
                  onChange={importSettings}
                />
                <Button variant="outline" size="sm" onClick={resetToDefaults} className="w-full justify-start gap-2" data-testid="button-reset-settings">
                  <RotateCcw className="w-4 h-4" />
                  Reset to Defaults
                </Button>
              </div>

              <Separator className="my-4" />

              {/* Help & Support */}
              <div className="space-y-2">
                <Button variant="ghost" size="sm" className="w-full justify-start gap-2" data-testid="button-help">
                  <HelpCircle className="w-4 h-4" />
                  Get Help
                </Button>
                <Button variant="ghost" size="sm" className="w-full justify-start gap-2" data-testid="button-documentation">
                  <ExternalLink className="w-4 h-4" />
                  Documentation
                </Button>
                <Button variant="ghost" size="sm" className="w-full justify-start gap-2 text-destructive hover:text-destructive" data-testid="button-logout" onClick={handleLogout}>
                  <LogOut className="w-4 h-4" />
                  Log Out
                </Button>
              </div>
            </div>

            {/* Settings Content */}
            <ScrollArea className="flex-1 p-6">
              {/* Profile Tab */}
              <TabsContent value="profile" className="space-y-6 m-0">
                <div>
                  <h3 className="text-lg font-semibold mb-4">Profile Information</h3>
                  
                  <Card>
                    <CardHeader>
                      <CardTitle className="flex items-center gap-2">
                        <Avatar className="w-12 h-12">
                          <AvatarImage src={settings.avatar} alt="Profile" />
                          <AvatarFallback>{settings.displayName?.charAt(0) || 'U'}</AvatarFallback>
                        </Avatar>
                        <div>
                          <div className="flex items-center gap-2">
                            <span>{settings.displayName}</span>
                            <Badge variant="secondary">Pro Plan</Badge>
                          </div>
                          <p className="text-sm text-muted-foreground">{settings.email}</p>
                        </div>
                      </CardTitle>
                    </CardHeader>
                    <CardContent className="space-y-4">
                      <div className="grid grid-cols-2 gap-4">
                        <div className="space-y-2">
                          <Label htmlFor="display-name">Display Name</Label>
                          <Input
                            id="display-name"
                            value={settings.displayName || ''}
                            onChange={(e) => updateSetting('displayName', e.target.value)}
                            data-testid="input-display-name"
                          />
                        </div>
                        <div className="space-y-2">
                          <Label htmlFor="email">Email</Label>
                          <Input
                            id="email"
                            type="email"
                            value={settings.email || ''}
                            onChange={(e) => updateSetting('email', e.target.value)}
                            data-testid="input-email"
                          />
                        </div>
                      </div>
                      <div className="space-y-2">
                        <Label htmlFor="role">Role</Label>
                        <Input
                          id="role"
                          value={settings.role}
                          onChange={(e) => updateSetting('role', e.target.value)}
                          data-testid="input-role"
                        />
                      </div>
                    </CardContent>
                  </Card>
                </div>
              </TabsContent>

              {/* General Tab */}
              <TabsContent value="general" className="space-y-6 m-0">
                <div>
                  <h3 className="text-lg font-semibold mb-4">General Settings</h3>
                  
                  <Card>
                    <CardHeader>
                      <CardTitle className="flex items-center gap-2">
                        <Languages className="w-5 h-5" />
                        Language & Region
                      </CardTitle>
                      <CardDescription>
                        Configure your language preferences
                      </CardDescription>
                    </CardHeader>
                    <CardContent>
                      <div className="space-y-2">
                        <Label htmlFor="language">Language</Label>
                        <Select value={settings.language} onValueChange={(value: any) => updateSetting('language', value)}>
                          <SelectTrigger data-testid="select-language">
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            <SelectItem value="english">English</SelectItem>
                            <SelectItem value="spanish">Español</SelectItem>
                            <SelectItem value="french">Français</SelectItem>
                            <SelectItem value="german">Deutsch</SelectItem>
                            <SelectItem value="chinese">中文</SelectItem>
                          </SelectContent>
                        </Select>
                      </div>
                    </CardContent>
                  </Card>
                </div>
              </TabsContent>

              {/* Appearance Tab */}
              <TabsContent value="appearance" className="space-y-6 m-0">
                <div>
                  <h3 className="text-lg font-semibold mb-4">Appearance</h3>
                  
                  <Card>
                    <CardHeader>
                      <CardTitle>Theme</CardTitle>
                      <CardDescription>
                        Choose your preferred appearance
                      </CardDescription>
                    </CardHeader>
                    <CardContent>
                      <div className="space-y-2">
                        <Label htmlFor="theme">Theme</Label>
                        <Select value={settings.theme} onValueChange={(value: any) => updateSetting('theme', value)}>
                          <SelectTrigger data-testid="select-theme">
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            <SelectItem value="system">System</SelectItem>
                            <SelectItem value="light">Light</SelectItem>
                            <SelectItem value="dark">Dark</SelectItem>
                          </SelectContent>
                        </Select>
                      </div>
                    </CardContent>
                  </Card>
                </div>
              </TabsContent>

              {/* Chat Tab */}
              <TabsContent value="chat" className="space-y-6 m-0">
                <div>
                  <h3 className="text-lg font-semibold mb-4">Chat Preferences</h3>
                  
                  <Card>
                    <CardContent className="space-y-6 pt-6">
                      <div className="flex items-center justify-between">
                        <div className="space-y-0.5">
                          <Label>Chat Suggestions</Label>
                          <p className="text-sm text-muted-foreground">
                            Show suggestion chips after assistant responses
                          </p>
                        </div>
                        <Switch
                          checked={settings.chatSuggestions}
                          onCheckedChange={(checked) => updateSetting('chatSuggestions', checked)}
                          data-testid="switch-chat-suggestions"
                        />
                      </div>
                      
                      <Separator />
                      
                      <div className="flex items-center justify-between">
                        <div className="space-y-0.5">
                          <Label>Typing Indicator</Label>
                          <p className="text-sm text-muted-foreground">
                            Show typing indicator when assistant is responding
                          </p>
                        </div>
                        <Switch
                          checked={settings.typingIndicator}
                          onCheckedChange={(checked) => updateSetting('typingIndicator', checked)}
                          data-testid="switch-typing-indicator"
                        />
                      </div>
                      
                      <Separator />
                      
                      <div className="flex items-center justify-between">
                        <div className="space-y-0.5">
                          <Label>Message Timestamps</Label>
                          <p className="text-sm text-muted-foreground">
                            Show timestamps on chat messages
                          </p>
                        </div>
                        <Switch
                          checked={settings.messageTimestamps}
                          onCheckedChange={(checked) => updateSetting('messageTimestamps', checked)}
                          data-testid="switch-message-timestamps"
                        />
                      </div>
                    </CardContent>
                  </Card>
                </div>
              </TabsContent>

              {/* Data Tab */}
              <TabsContent value="data" className="space-y-6 m-0">
                <div>
                  <h3 className="text-lg font-semibold mb-4">Data Management</h3>
                  
                  <Card>
                    <CardContent className="space-y-6 pt-6">
                      <div className="space-y-2">
                        <Label htmlFor="default-storage">Default Storage Type</Label>
                        <Select value={settings.defaultStorageType} onValueChange={(value: any) => updateSetting('defaultStorageType', value)}>
                          <SelectTrigger data-testid="select-default-storage">
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            <SelectItem value="replit_storage">Replit Storage</SelectItem>
                            <SelectItem value="local">Local Storage</SelectItem>
                            <SelectItem value="s3">Amazon S3</SelectItem>
                          </SelectContent>
                        </Select>
                      </div>
                      
                      <Separator />
                      
                      <div className="flex items-center justify-between">
                        <div className="space-y-0.5">
                          <Label>Auto-delete Temporary Files</Label>
                          <p className="text-sm text-muted-foreground">
                            Automatically clean up temporary workflow files
                          </p>
                        </div>
                        <Switch
                          checked={settings.autoDeleteTempFiles}
                          onCheckedChange={(checked) => updateSetting('autoDeleteTempFiles', checked)}
                          data-testid="switch-auto-delete-temp"
                        />
                      </div>
                      
                      <div className="space-y-2">
                        <Label htmlFor="retention-days">Data Retention (Days)</Label>
                        <Input
                          id="retention-days"
                          type="number"
                          value={settings.dataRetentionDays}
                          onChange={(e) => updateSetting('dataRetentionDays', parseInt(e.target.value) || 30)}
                          data-testid="input-retention-days"
                        />
                      </div>
                    </CardContent>
                  </Card>
                </div>
              </TabsContent>

              {/* Notifications Tab */}
              <TabsContent value="notifications" className="space-y-6 m-0">
                <div>
                  <h3 className="text-lg font-semibold mb-4">Notification Preferences</h3>
                  
                  <Card>
                    <CardContent className="space-y-6 pt-6">
                      <div className="flex items-center justify-between">
                        <div className="space-y-0.5">
                          <Label>Workflow Completion Notifications</Label>
                          <p className="text-sm text-muted-foreground">
                            Get notified when workflows complete
                          </p>
                        </div>
                        <Switch
                          checked={settings.workflowCompletionNotifications}
                          onCheckedChange={(checked) => updateSetting('workflowCompletionNotifications', checked)}
                          data-testid="switch-workflow-notifications"
                        />
                      </div>
                      
                      <Separator />
                      
                      <div className="flex items-center justify-between">
                        <div className="space-y-0.5">
                          <Label>Error Notifications</Label>
                          <p className="text-sm text-muted-foreground">
                            Get notified when errors occur
                          </p>
                        </div>
                        <Switch
                          checked={settings.errorNotifications}
                          onCheckedChange={(checked) => updateSetting('errorNotifications', checked)}
                          data-testid="switch-error-notifications"
                        />
                      </div>
                    </CardContent>
                  </Card>
                </div>
              </TabsContent>

              {/* Privacy Tab */}
              <TabsContent value="privacy" className="space-y-6 m-0">
                <div>
                  <h3 className="text-lg font-semibold mb-4">Privacy Settings</h3>
                  
                  <Card>
                    <CardContent className="space-y-6 pt-6">
                      <div className="flex items-center justify-between">
                        <div className="space-y-0.5">
                          <Label>Share Usage Data</Label>
                          <p className="text-sm text-muted-foreground">
                            Help improve BioMate by sharing anonymous usage data
                          </p>
                        </div>
                        <Switch
                          checked={settings.shareUsageData}
                          onCheckedChange={(checked) => updateSetting('shareUsageData', checked)}
                          data-testid="switch-share-usage"
                        />
                      </div>
                      
                      <Separator />
                      
                      <div className="flex items-center justify-between">
                        <div className="space-y-0.5">
                          <Label>Share Error Reports</Label>
                          <p className="text-sm text-muted-foreground">
                            Automatically send error reports to help us fix issues
                          </p>
                        </div>
                        <Switch
                          checked={settings.shareErrorReports}
                          onCheckedChange={(checked) => updateSetting('shareErrorReports', checked)}
                          data-testid="switch-share-errors"
                        />
                      </div>
                    </CardContent>
                  </Card>
                </div>
              </TabsContent>

              {/* Advanced Tab */}
              <TabsContent value="advanced" className="space-y-6 m-0">
                <div>
                  <h3 className="text-lg font-semibold mb-4">Advanced Settings</h3>
                  
                  <Card>
                    <CardContent className="space-y-6 pt-6">
                      <div className="flex items-center justify-between">
                        <div className="space-y-0.5">
                          <Label>Debug Mode</Label>
                          <p className="text-sm text-muted-foreground">
                            Enable detailed logging for troubleshooting
                          </p>
                        </div>
                        <Switch
                          checked={settings.debugMode}
                          onCheckedChange={(checked) => updateSetting('debugMode', checked)}
                          data-testid="switch-debug-mode"
                        />
                      </div>
                      
                      <Separator />
                      
                      <div className="flex items-center justify-between">
                        <div className="space-y-0.5">
                          <Label>Experimental Features</Label>
                          <p className="text-sm text-muted-foreground">
                            Access beta features and new functionality
                          </p>
                        </div>
                        <Switch
                          checked={settings.experimentalFeatures}
                          onCheckedChange={(checked) => updateSetting('experimentalFeatures', checked)}
                          data-testid="switch-experimental"
                        />
                      </div>
                    </CardContent>
                  </Card>
                </div>
              </TabsContent>
            </ScrollArea>
          </Tabs>
        </div>
      </DialogContent>
    </Dialog>
  )
}