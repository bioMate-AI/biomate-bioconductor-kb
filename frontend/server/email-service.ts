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
          .logo-bar { background-color: #ffffff; padding: 16px 20px; text-align: center; border-radius: 5px 5px 0 0; border: 1px solid #e5e7eb; border-bottom: none; }
          .logo-bar img { height: 36px; width: auto; }
          .header { background-color: #4F46E5; color: white; padding: 20px; text-align: center; }
          .content { background-color: #f9fafb; padding: 30px; border-radius: 0 0 5px 5px; }
          .button { display: inline-block; padding: 12px 30px; background-color: #4F46E5; color: white !important; text-decoration: none; border-radius: 5px; margin: 20px 0; font-family: Arial, sans-serif; font-size: 14px; font-weight: 600; }
          .footer { margin-top: 20px; font-size: 12px; color: #666; text-align: center; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="logo-bar">
            <img src="${this.appUrl}/biomate-logo.png" alt="BioMate" />
          </div>
          <div class="header">
            <h1>Welcome to BioMate!</h1>
          </div>
          <div class="content">
            <h2>Hi ${userName},</h2>
            <p>Thank you for registering with BioMate. Please verify your email address to activate your account.</p>
            <p>
              <a href="${verificationUrl}" class="button" style="display:inline-block;padding:12px 30px;background-color:#4F46E5;color:white;text-decoration:none;border-radius:5px;margin:20px 0;font-family:Arial,sans-serif;font-size:14px;font-weight:600;">Verify Email Address</a>
            </p>
            <p>Or copy and paste this link into your browser:</p>
            <p style="word-break: break-all; color: #4F46E5;">${verificationUrl}</p>
            <p><strong>This link will expire in 24 hours.</strong></p>
            <p>If you didn't create this account, you can safely ignore this email.</p>
          </div>
          <div class="footer">
            <p>© 2026 BioMate. All rights reserved.</p>
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

      © 2026 BioMate. All rights reserved.
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
          .logo-bar { background-color: #ffffff; padding: 16px 20px; text-align: center; border-radius: 5px 5px 0 0; border: 1px solid #e5e7eb; border-bottom: none; }
          .logo-bar img { height: 36px; width: auto; }
          .header { background-color: #DC2626; color: white; padding: 20px; text-align: center; }
          .content { background-color: #f9fafb; padding: 30px; border-radius: 0 0 5px 5px; }
          .button { display: inline-block; padding: 12px 30px; background-color: #DC2626; color: white !important; text-decoration: none; border-radius: 5px; margin: 20px 0; font-family: Arial, sans-serif; font-size: 14px; font-weight: 600; }
          .footer { margin-top: 20px; font-size: 12px; color: #666; text-align: center; }
          .warning { background-color: #FEF3C7; padding: 15px; border-left: 4px solid #F59E0B; margin: 15px 0; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="logo-bar">
            <img src="${this.appUrl}/biomate-logo.png" alt="BioMate" />
          </div>
          <div class="header">
            <h1>Password Reset Request</h1>
          </div>
          <div class="content">
            <h2>Hi ${userName},</h2>
            <p>We received a request to reset your BioMate account password.</p>
            <p>
              <a href="${resetUrl}" class="button" style="display:inline-block;padding:12px 30px;background-color:#DC2626;color:white;text-decoration:none;border-radius:5px;margin:20px 0;font-family:Arial,sans-serif;font-size:14px;font-weight:600;">Reset Password</a>
            </p>
            <p>Or copy and paste this link into your browser:</p>
            <p style="word-break: break-all; color: #DC2626;">${resetUrl}</p>
            <p><strong>This link will expire in 1 hour.</strong></p>
            <div class="warning">
              <strong>⚠️ Security Notice:</strong> If you didn't request a password reset, please ignore this email and your password will remain unchanged. Your account is still secure.
            </div>
          </div>
          <div class="footer">
            <p>© 2026 BioMate. All rights reserved.</p>
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

      © 2026 BioMate. All rights reserved.
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
          .logo-bar { background-color: #ffffff; padding: 16px 20px; text-align: center; border-radius: 5px 5px 0 0; border: 1px solid #e5e7eb; border-bottom: none; }
          .logo-bar img { height: 36px; width: auto; }
          .header { background-color: #10B981; color: white; padding: 20px; text-align: center; }
          .content { background-color: #f9fafb; padding: 30px; border-radius: 0 0 5px 5px; }
          .button { display: inline-block; padding: 12px 30px; background-color: #10B981; color: white !important; text-decoration: none; border-radius: 5px; margin: 20px 0; font-family: Arial, sans-serif; font-size: 14px; font-weight: 600; }
          .footer { margin-top: 20px; font-size: 12px; color: #666; text-align: center; }
          .feature { margin: 15px 0; padding-left: 25px; position: relative; }
          .feature:before { content: "✓"; position: absolute; left: 0; color: #10B981; font-weight: bold; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="logo-bar">
            <img src="${this.appUrl}/biomate-logo.png" alt="BioMate" />
          </div>
          <div class="header">
            <h1>Welcome to BioMate!</h1>
          </div>
          <div class="content">
            <h2>Hi ${userName},</h2>
            <p>Your email has been verified successfully! You now have full access to BioMate.</p>
            <h3>Your 14-Day Trial Includes:</h3>
            <div class="feature">AI-powered workflow generation</div>
            <div class="feature">Access to 1000+ bioinformatics tools</div>
            <div class="feature">Cloud data storage and processing</div>
            <div class="feature">Workflow execution and monitoring</div>
            <div class="feature">Result visualization and export</div>
            <p>
              <a href="${this.appUrl}/" class="button" style="display:inline-block;padding:12px 30px;background-color:#10B981;color:white;text-decoration:none;border-radius:5px;margin:20px 0;font-family:Arial,sans-serif;font-size:14px;font-weight:600;">Get Started</a>
            </p>
            <p>Need help? Check out our <a href="${this.appUrl}/docs">documentation</a> or contact support at support@biomate.dev</p>
          </div>
          <div class="footer">
            <p>© 2026 BioMate. All rights reserved.</p>
          </div>
        </div>
      </body>
      </html>
    `;

    const text = `
      Welcome to BioMate!

      Hi ${userName},

      Your email has been verified successfully! You now have full access to BioMate.

      Your 14-Day Trial Includes:
      ✓ AI-powered workflow generation
      ✓ Access to 1000+ bioinformatics tools
      ✓ Cloud data storage and processing
      ✓ Workflow execution and monitoring
      ✓ Result visualization and export

      Get started: ${this.appUrl}/

      Need help? Check out our documentation at ${this.appUrl}/docs or contact support at support@biomate.dev

      © 2026 BioMate. All rights reserved.
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
          .logo-bar { background-color: #ffffff; padding: 16px 20px; text-align: center; border-radius: 5px 5px 0 0; border: 1px solid #e5e7eb; border-bottom: none; }
          .logo-bar img { height: 36px; width: auto; }
          .header { background-color: #10B981; color: white; padding: 20px; text-align: center; }
          .content { background-color: #f9fafb; padding: 30px; border-radius: 0 0 5px 5px; }
          .button { display: inline-block; padding: 12px 30px; background-color: #10B981; color: white !important; text-decoration: none; border-radius: 5px; margin: 20px 0; font-family: Arial, sans-serif; font-size: 14px; font-weight: 600; }
          .footer { margin-top: 20px; font-size: 12px; color: #666; text-align: center; }
          .stats { background-color: #E5E7EB; padding: 15px; border-radius: 5px; margin: 15px 0; }
          .stat-row { display: flex; justify-content: space-between; margin: 5px 0; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="logo-bar">
            <img src="${this.appUrl}/biomate-logo.png" alt="BioMate" />
          </div>
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
            <p>© 2026 BioMate. All rights reserved.</p>
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

      © 2026 BioMate. All rights reserved.
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
          .logo-bar { background-color: #ffffff; padding: 16px 20px; text-align: center; border-radius: 5px 5px 0 0; border: 1px solid #e5e7eb; border-bottom: none; }
          .logo-bar img { height: 36px; width: auto; }
          .header { background-color: #DC2626; color: white; padding: 20px; text-align: center; }
          .content { background-color: #f9fafb; padding: 30px; border-radius: 0 0 5px 5px; }
          .button { display: inline-block; padding: 12px 30px; background-color: #DC2626; color: white !important; text-decoration: none; border-radius: 5px; margin: 20px 0; font-family: Arial, sans-serif; font-size: 14px; font-weight: 600; }
          .footer { margin-top: 20px; font-size: 12px; color: #666; text-align: center; }
          .error-box { background-color: #FEE2E2; border-left: 4px solid #DC2626; padding: 15px; margin: 15px 0; font-family: monospace; font-size: 12px; overflow-x: auto; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="logo-bar">
            <img src="${this.appUrl}/biomate-logo.png" alt="BioMate" />
          </div>
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
            <p>© 2026 BioMate. All rights reserved.</p>
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

      © 2026 BioMate. All rights reserved.
    `;

    return this.sendEmail({
      to: email,
      subject: `⚠️ Workflow Error: ${workflowName}`,
      html,
      text,
    });
  }


  async sendPaymentFailedEmail(
    email: string,
    userName: string,
    amountDue: string,     // e.g. "$20.00"
    nextAttemptDate: string, // e.g. "March 5, 2026"
    updateUrl: string,
  ): Promise<boolean> {
    const html = `
      <!DOCTYPE html>
      <html>
      <head>
        <style>
          body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
          .container { max-width: 600px; margin: 0 auto; padding: 20px; }
          .logo-bar { background-color: #ffffff; padding: 16px 20px; text-align: center; border-radius: 5px 5px 0 0; border: 1px solid #e5e7eb; border-bottom: none; }
          .logo-bar img { height: 36px; width: auto; }
          .header { background-color: #DC2626; color: white; padding: 20px; text-align: center; }
          .content { background-color: #f9fafb; padding: 30px; border-radius: 0 0 5px 5px; }
          .button { display: inline-block; padding: 12px 30px; background-color: #DC2626; color: white !important; text-decoration: none; border-radius: 5px; margin: 20px 0; font-family: Arial, sans-serif; font-size: 14px; font-weight: 600; }
          .footer { margin-top: 20px; font-size: 12px; color: #666; text-align: center; }
          .warning { background-color: #FEF3C7; padding: 15px; border-left: 4px solid #F59E0B; margin: 15px 0; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="logo-bar">
            <img src="${this.appUrl}/biomate-logo.png" alt="BioMate" />
          </div>
          <div class="header"><h1>Payment Failed</h1></div>
          <div class="content">
            <h2>Hi ${userName},</h2>
            <p>We were unable to process your BioMate subscription payment of <strong>${amountDue}</strong>.</p>
            <div class="warning">
              <strong>Action required:</strong> Please update your payment method to keep your account active.
              We will retry on <strong>${nextAttemptDate}</strong>.
            </div>
            <p><a href="${updateUrl}" class="button">Update Payment Method</a></p>
            <p>Or copy and paste this link: <span style="color:#DC2626;">${updateUrl}</span></p>
            <p>If you continue to experience issues, contact support at support@biomate.dev</p>
          </div>
          <div class="footer"><p>© 2026 BioMate. All rights reserved.</p></div>
        </div>
      </body>
      </html>
    `;
    return this.sendEmail({
      to: email,
      subject: 'Action Required: BioMate Payment Failed',
      html,
      text: `Payment Failed\n\nHi ${userName},\n\nWe could not process your payment of ${amountDue}.\nUpdate your payment method: ${updateUrl}\nWe will retry on ${nextAttemptDate}.\n\nContact support@biomate.dev if you need help.`,
    });
  }

  async sendQuotaWarningEmail(
    email: string,
    userName: string,
    pct: number,           // e.g. 80 or 100
    usedUsd: string,       // e.g. "$24.00"
    quotaUsd: string,      // e.g. "$30.00"
    addCreditsUrl: string,
  ): Promise<boolean> {
    const exceeded = pct >= 100;
    const color = exceeded ? '#DC2626' : '#F59E0B';
    const subject = exceeded
      ? 'Your BioMate quota is exhausted — jobs paused'
      : `BioMate: you've used ${pct}% of your monthly quota`;
    const html = `
      <!DOCTYPE html>
      <html>
      <head>
        <style>
          body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
          .container { max-width: 600px; margin: 0 auto; padding: 20px; }
          .logo-bar { background-color: #ffffff; padding: 16px 20px; text-align: center; border-radius: 5px 5px 0 0; border: 1px solid #e5e7eb; border-bottom: none; }
          .logo-bar img { height: 36px; width: auto; }
          .header { background-color: ${color}; color: white; padding: 20px; text-align: center; }
          .content { background-color: #f9fafb; padding: 30px; border-radius: 0 0 5px 5px; }
          .button { display: inline-block; padding: 12px 30px; background-color: ${color}; color: white !important; text-decoration: none; border-radius: 5px; margin: 20px 0; font-family: Arial, sans-serif; font-size: 14px; font-weight: 600; }
          .footer { margin-top: 20px; font-size: 12px; color: #666; text-align: center; }
          .meter { background: #E5E7EB; border-radius: 999px; height: 12px; margin: 10px 0; }
          .fill { background: ${color}; border-radius: 999px; height: 12px; width: ${Math.min(pct, 100)}%; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="logo-bar">
            <img src="${this.appUrl}/biomate-logo.png" alt="BioMate" />
          </div>
          <div class="header">
            <h1>${exceeded ? 'Quota Exhausted' : `${pct}% Quota Used`}</h1>
          </div>
          <div class="content">
            <h2>Hi ${userName},</h2>
            <p>${exceeded
              ? 'You have used all of your BioMate monthly compute quota. <strong>New workflow jobs are currently paused.</strong>'
              : `You have used <strong>${pct}%</strong> (${usedUsd}) of your <strong>${quotaUsd}</strong> monthly BioMate quota.`
            }</p>
            <div class="meter"><div class="fill"></div></div>
            <p style="font-size:13px;color:#666;">${usedUsd} used of ${quotaUsd} limit</p>
            <p>Add more credits to ${exceeded ? 'resume' : 'continue running'} your workflows without interruption.</p>
            <p><a href="${addCreditsUrl}" class="button">Add Credits Now</a></p>
            <p style="font-size:13px;color:#666;">You can also upgrade your plan for a higher monthly quota.</p>
          </div>
          <div class="footer">
            <p>© 2026 BioMate. All rights reserved.</p>
            <p><a href="${this.appUrl}/billing">Manage billing</a></p>
          </div>
        </div>
      </body>
      </html>
    `;
    return this.sendEmail({
      to: email,
      subject,
      html,
      text: `${subject}\n\nHi ${userName},\n\n${usedUsd} used of ${quotaUsd} quota (${pct}%).\nAdd credits: ${addCreditsUrl}\n\n© 2026 BioMate.`,
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

  async sendAdminAlert(subject: string, details: Record<string, unknown>, extraRecipient?: string): Promise<boolean> {
    const ADMIN_EMAIL = 'yaoyun.zhang@biomate.ai';
    const to = extraRecipient ? `${ADMIN_EMAIL}, ${extraRecipient}` : ADMIN_EMAIL;
    const ts = new Date().toISOString();
    const rows = Object.entries(details)
      .map(([k, v]) => `<tr><td style="padding:4px 8px;font-weight:bold;color:#555">${k}</td><td style="padding:4px 8px;font-family:monospace;word-break:break-all">${String(v)}</td></tr>`)
      .join('');
    const html = `
      <!DOCTYPE html><html><body style="font-family:Arial,sans-serif;color:#333">
      <div style="max-width:700px;margin:0 auto;padding:20px">
        <div style="background:#dc2626;color:white;padding:16px;border-radius:6px 6px 0 0">
          <h2 style="margin:0">BioMate System Alert</h2>
          <p style="margin:4px 0 0;font-size:13px">${ts}</p>
        </div>
        <div style="background:#fef2f2;border:1px solid #fecaca;padding:20px;border-radius:0 0 6px 6px">
          <h3 style="color:#dc2626">${subject}</h3>
          <table style="width:100%;border-collapse:collapse;background:white;border-radius:4px;overflow:hidden">
            ${rows}
          </table>
        </div>
        <p style="font-size:12px;color:#888;margin-top:12px">Sent by BioMate ops alerting — reply to investigate.</p>
      </div>
      </body></html>
    `;
    return this.sendEmail({ to, subject: `[BioMate Alert] ${subject}`, html });
  }
}

// Export singleton instance
export const emailService = new EmailService();
