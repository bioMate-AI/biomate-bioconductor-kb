import * as nodemailer from 'nodemailer';
import type { Transporter } from 'nodemailer';

interface EmailConfig {
  host: string;
  port: number;
  secure: boolean;
  auth: {
    user: string;
    pass: string;
  };
}

interface SendEmailOptions {
  to: string;
  subject: string;
  html: string;
  text?: string;
}

class EmailService {
  private transporter: Transporter | null = null;
  private fromEmail: string;
  private appUrl: string;

  constructor() {
    this.fromEmail = process.env.EMAIL_FROM || 'noreply@biomate.dev';
    this.appUrl = process.env.APP_URL || 'http://localhost:5000';

    // Only initialize if email configuration is provided
    if (this.isConfigured()) {
      try {
        this.initializeTransporter();
      } catch (error) {
        console.error('[EmailService] Failed to initialize transporter:', error);
        console.warn('[EmailService] Email service will not be available');
      }
    } else {
      console.warn('[EmailService] Email not configured. Set EMAIL_HOST, EMAIL_PORT, EMAIL_USER, EMAIL_PASS in .env');
    }
  }

  private isConfigured(): boolean {
    return !!(
      process.env.EMAIL_HOST &&
      process.env.EMAIL_USER &&
      process.env.EMAIL_PASS
    );
  }

  private initializeTransporter(): void {
    const config: EmailConfig = {
      host: process.env.EMAIL_HOST!,
      port: parseInt(process.env.EMAIL_PORT || '587'),
      secure: process.env.EMAIL_SECURE === 'true', // true for 465, false for other ports
      auth: {
        user: process.env.EMAIL_USER!,
        pass: process.env.EMAIL_PASS!,
      },
    };

    this.transporter = nodemailer.createTransport(config);
    console.log('[EmailService] Email transporter initialized');
  }

  async sendEmail(options: SendEmailOptions): Promise<boolean> {
    if (!this.transporter) {
      console.error('[EmailService] Cannot send email - not configured');
      return false;
    }

    try {
      await this.transporter.sendMail({
        from: this.fromEmail,
        to: options.to,
        subject: options.subject,
        html: options.html,
        text: options.text || this.stripHtml(options.html),
      });

      console.log(`[EmailService] Email sent to ${options.to}: ${options.subject}`);
      return true;
    } catch (error) {
      console.error('[EmailService] Failed to send email:', error);
      return false;
    }
  }

  async sendVerificationEmail(email: string, token: string, userName: string): Promise<boolean> {
    const verificationUrl = `${this.appUrl}/verify-email?token=${token}`;

    const html = `
      <!DOCTYPE html>
      <html>
      <head>
        <style>
          body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
          .container { max-width: 600px; margin: 0 auto; padding: 20px; }
          .header { background-color: #4F46E5; color: white; padding: 20px; text-align: center; border-radius: 5px 5px 0 0; }
          .content { background-color: #f9fafb; padding: 30px; border-radius: 0 0 5px 5px; }
          .button { display: inline-block; padding: 12px 30px; background-color: #4F46E5; color: white; text-decoration: none; border-radius: 5px; margin: 20px 0; }
          .footer { margin-top: 20px; font-size: 12px; color: #666; text-align: center; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <h1>Welcome to BioMate!</h1>
          </div>
          <div class="content">
            <h2>Hi ${userName},</h2>
            <p>Thank you for registering with BioMate. Please verify your email address to activate your account.</p>
            <p>
              <a href="${verificationUrl}" class="button">Verify Email Address</a>
            </p>
            <p>Or copy and paste this link into your browser:</p>
            <p style="word-break: break-all; color: #4F46E5;">${verificationUrl}</p>
            <p><strong>This link will expire in 24 hours.</strong></p>
            <p>If you didn't create this account, you can safely ignore this email.</p>
          </div>
          <div class="footer">
            <p>© 2025 BioMate. All rights reserved.</p>
          </div>
        </div>
      </body>
      </html>
    `;

    const text = `
      Welcome to BioMate!

      Hi ${userName},

      Thank you for registering with BioMate. Please verify your email address to activate your account.

      Verify your email: ${verificationUrl}

      This link will expire in 24 hours.

      If you didn't create this account, you can safely ignore this email.

      © 2025 BioMate. All rights reserved.
    `;

    return this.sendEmail({
      to: email,
      subject: 'Verify Your BioMate Account',
      html,
      text,
    });
  }

  async sendPasswordResetEmail(email: string, token: string, userName: string): Promise<boolean> {
    const resetUrl = `${this.appUrl}/reset-password?token=${token}`;

    const html = `
      <!DOCTYPE html>
      <html>
      <head>
        <style>
          body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
          .container { max-width: 600px; margin: 0 auto; padding: 20px; }
          .header { background-color: #DC2626; color: white; padding: 20px; text-align: center; border-radius: 5px 5px 0 0; }
          .content { background-color: #f9fafb; padding: 30px; border-radius: 0 0 5px 5px; }
          .button { display: inline-block; padding: 12px 30px; background-color: #DC2626; color: white; text-decoration: none; border-radius: 5px; margin: 20px 0; }
          .footer { margin-top: 20px; font-size: 12px; color: #666; text-align: center; }
          .warning { background-color: #FEF3C7; padding: 15px; border-left: 4px solid #F59E0B; margin: 15px 0; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <h1>Password Reset Request</h1>
          </div>
          <div class="content">
            <h2>Hi ${userName},</h2>
            <p>We received a request to reset your BioMate account password.</p>
            <p>
              <a href="${resetUrl}" class="button">Reset Password</a>
            </p>
            <p>Or copy and paste this link into your browser:</p>
            <p style="word-break: break-all; color: #DC2626;">${resetUrl}</p>
            <p><strong>This link will expire in 1 hour.</strong></p>
            <div class="warning">
              <strong>⚠️ Security Notice:</strong> If you didn't request a password reset, please ignore this email and your password will remain unchanged. Your account is still secure.
            </div>
          </div>
          <div class="footer">
            <p>© 2025 BioMate. All rights reserved.</p>
          </div>
        </div>
      </body>
      </html>
    `;

    const text = `
      Password Reset Request

      Hi ${userName},

      We received a request to reset your BioMate account password.

      Reset your password: ${resetUrl}

      This link will expire in 1 hour.

      ⚠️ Security Notice: If you didn't request a password reset, please ignore this email and your password will remain unchanged. Your account is still secure.

      © 2025 BioMate. All rights reserved.
    `;

    return this.sendEmail({
      to: email,
      subject: 'Reset Your BioMate Password',
      html,
      text,
    });
  }

  async sendWelcomeEmail(email: string, userName: string): Promise<boolean> {
    const html = `
      <!DOCTYPE html>
      <html>
      <head>
        <style>
          body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
          .container { max-width: 600px; margin: 0 auto; padding: 20px; }
          .header { background-color: #10B981; color: white; padding: 20px; text-align: center; border-radius: 5px 5px 0 0; }
          .content { background-color: #f9fafb; padding: 30px; border-radius: 0 0 5px 5px; }
          .button { display: inline-block; padding: 12px 30px; background-color: #10B981; color: white; text-decoration: none; border-radius: 5px; margin: 20px 0; }
          .footer { margin-top: 20px; font-size: 12px; color: #666; text-align: center; }
          .feature { margin: 15px 0; padding-left: 25px; position: relative; }
          .feature:before { content: "✓"; position: absolute; left: 0; color: #10B981; font-weight: bold; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <h1>Welcome to BioMate!</h1>
          </div>
          <div class="content">
            <h2>Hi ${userName},</h2>
            <p>Your email has been verified successfully! You now have full access to BioMate.</p>
            <h3>Your 7-Day Trial Includes:</h3>
            <div class="feature">AI-powered workflow generation</div>
            <div class="feature">Access to 1000+ bioinformatics tools</div>
            <div class="feature">Cloud data storage and processing</div>
            <div class="feature">Workflow execution and monitoring</div>
            <div class="feature">Result visualization and export</div>
            <p>
              <a href="${this.appUrl}/dashboard" class="button">Get Started</a>
            </p>
            <p>Need help? Check out our <a href="${this.appUrl}/docs">documentation</a> or contact support at support@biomate.dev</p>
          </div>
          <div class="footer">
            <p>© 2025 BioMate. All rights reserved.</p>
          </div>
        </div>
      </body>
      </html>
    `;

    const text = `
      Welcome to BioMate!

      Hi ${userName},

      Your email has been verified successfully! You now have full access to BioMate.

      Your 7-Day Trial Includes:
      ✓ AI-powered workflow generation
      ✓ Access to 1000+ bioinformatics tools
      ✓ Cloud data storage and processing
      ✓ Workflow execution and monitoring
      ✓ Result visualization and export

      Get started: ${this.appUrl}/dashboard

      Need help? Check out our documentation at ${this.appUrl}/docs or contact support at support@biomate.dev

      © 2025 BioMate. All rights reserved.
    `;

    return this.sendEmail({
      to: email,
      subject: 'Welcome to BioMate - Your Account is Active!',
      html,
      text,
    });
  }

  private stripHtml(html: string): string {
    return html
      .replace(/<[^>]*>/g, '')
      .replace(/\s+/g, ' ')
      .trim();
  }

  // ============================================================================
  // WORKFLOW NOTIFICATION EMAILS
  // ============================================================================

  async sendWorkflowCompleteEmail(
    email: string,
    userName: string,
    workflowName: string,
    invocationId: string,
    completedSteps: number,
    totalSteps: number,
    elapsedTime: string
  ): Promise<boolean> {
    const resultUrl = `${this.appUrl}/workflows/results/${invocationId}`;

    const html = `
      <!DOCTYPE html>
      <html>
      <head>
        <style>
          body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
          .container { max-width: 600px; margin: 0 auto; padding: 20px; }
          .header { background-color: #10B981; color: white; padding: 20px; text-align: center; border-radius: 5px 5px 0 0; }
          .content { background-color: #f9fafb; padding: 30px; border-radius: 0 0 5px 5px; }
          .button { display: inline-block; padding: 12px 30px; background-color: #10B981; color: white; text-decoration: none; border-radius: 5px; margin: 20px 0; }
          .footer { margin-top: 20px; font-size: 12px; color: #666; text-align: center; }
          .stats { background-color: #E5E7EB; padding: 15px; border-radius: 5px; margin: 15px 0; }
          .stat-row { display: flex; justify-content: space-between; margin: 5px 0; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <h1>✓ Workflow Complete!</h1>
          </div>
          <div class="content">
            <h2>Hi ${userName},</h2>
            <p>Great news! Your workflow has finished running successfully.</p>

            <div class="stats">
              <div class="stat-row"><strong>Workflow:</strong> ${workflowName}</div>
              <div class="stat-row"><strong>Steps Completed:</strong> ${completedSteps}/${totalSteps}</div>
              <div class="stat-row"><strong>Total Time:</strong> ${elapsedTime}</div>
            </div>

            <p>
              <a href="${resultUrl}" class="button">View Results</a>
            </p>
            <p>Or copy and paste this link into your browser:</p>
            <p style="word-break: break-all; color: #10B981;">${resultUrl}</p>
          </div>
          <div class="footer">
            <p>© 2025 BioMate. All rights reserved.</p>
            <p><a href="${this.appUrl}/settings/notifications">Manage notification preferences</a></p>
          </div>
        </div>
      </body>
      </html>
    `;

    const text = `
      Workflow Complete!

      Hi ${userName},

      Great news! Your workflow has finished running successfully.

      Workflow: ${workflowName}
      Steps Completed: ${completedSteps}/${totalSteps}
      Total Time: ${elapsedTime}

      View Results: ${resultUrl}

      © 2025 BioMate. All rights reserved.
    `;

    return this.sendEmail({
      to: email,
      subject: `✓ Workflow Complete: ${workflowName}`,
      html,
      text,
    });
  }

  async sendWorkflowErrorEmail(
    email: string,
    userName: string,
    workflowName: string,
    invocationId: string,
    failedStep: string,
    errorMessage: string
  ): Promise<boolean> {
    const resultUrl = `${this.appUrl}/workflows/results/${invocationId}`;

    const html = `
      <!DOCTYPE html>
      <html>
      <head>
        <style>
          body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
          .container { max-width: 600px; margin: 0 auto; padding: 20px; }
          .header { background-color: #DC2626; color: white; padding: 20px; text-align: center; border-radius: 5px 5px 0 0; }
          .content { background-color: #f9fafb; padding: 30px; border-radius: 0 0 5px 5px; }
          .button { display: inline-block; padding: 12px 30px; background-color: #DC2626; color: white; text-decoration: none; border-radius: 5px; margin: 20px 0; }
          .footer { margin-top: 20px; font-size: 12px; color: #666; text-align: center; }
          .error-box { background-color: #FEE2E2; border-left: 4px solid #DC2626; padding: 15px; margin: 15px 0; font-family: monospace; font-size: 12px; overflow-x: auto; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <h1>⚠️ Workflow Error</h1>
          </div>
          <div class="content">
            <h2>Hi ${userName},</h2>
            <p>Unfortunately, your workflow encountered an error and could not complete.</p>

            <p><strong>Workflow:</strong> ${workflowName}</p>
            <p><strong>Failed Step:</strong> ${failedStep}</p>

            <div class="error-box">
              ${errorMessage.substring(0, 500)}${errorMessage.length > 500 ? '...' : ''}
            </div>

            <p>
              <a href="${resultUrl}" class="button">View Details</a>
            </p>
            <p>Or copy and paste this link into your browser:</p>
            <p style="word-break: break-all; color: #DC2626;">${resultUrl}</p>

            <p>Need help? Contact support at support@biomate.dev</p>
          </div>
          <div class="footer">
            <p>© 2025 BioMate. All rights reserved.</p>
            <p><a href="${this.appUrl}/settings/notifications">Manage notification preferences</a></p>
          </div>
        </div>
      </body>
      </html>
    `;

    const text = `
      Workflow Error

      Hi ${userName},

      Unfortunately, your workflow encountered an error and could not complete.

      Workflow: ${workflowName}
      Failed Step: ${failedStep}

      Error:
      ${errorMessage.substring(0, 500)}${errorMessage.length > 500 ? '...' : ''}

      View Details: ${resultUrl}

      Need help? Contact support at support@biomate.dev

      © 2025 BioMate. All rights reserved.
    `;

    return this.sendEmail({
      to: email,
      subject: `⚠️ Workflow Error: ${workflowName}`,
      html,
      text,
    });
  }

  async testConnection(): Promise<boolean> {
    if (!this.transporter) {
      return false;
    }

    try {
      await this.transporter.verify();
      console.log('[EmailService] Connection test successful');
      return true;
    } catch (error) {
      console.error('[EmailService] Connection test failed:', error);
      return false;
    }
  }
}

// Export singleton instance
export const emailService = new EmailService();
