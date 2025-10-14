"""
Email service for sending verification and notification emails.

Supports multiple email providers:
- SendGrid (recommended for ease of use)
- AWS SES (recommended for scale)
- Generic SMTP

Configuration is loaded from auth_payment_config.yml
"""

import logging
import smtplib
from abc import ABC, abstractmethod
from dataclasses import dataclass
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from typing import Dict, Any, Optional

try:
    from sendgrid import SendGridAPIClient
    from sendgrid.helpers.mail import Mail, Email, To, Content
    SENDGRID_AVAILABLE = True
except ImportError:
    SENDGRID_AVAILABLE = False

try:
    import boto3
    from botocore.exceptions import BotoCoreError, ClientError
    AWS_SES_AVAILABLE = True
except ImportError:
    AWS_SES_AVAILABLE = False

log = logging.getLogger(__name__)


# ============================================================================
# EMAIL TEMPLATES
# ============================================================================

@dataclass
class EmailTemplate:
    """Email template with subject and body"""
    subject: str
    html_body: str
    text_body: str


class EmailTemplates:
    """Pre-defined email templates"""

    @staticmethod
    def verification_email(
        username: str,
        verification_url: str,
        base_url: str,
        trial_days: int = 10
    ) -> EmailTemplate:
        """Email verification template"""
        subject = "Verify Your BioMate Account"

        html_body = f"""
        <html>
        <head>
            <style>
                body {{ font-family: Arial, sans-serif; line-height: 1.6; color: #333; }}
                .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
                .header {{ background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                          color: white; padding: 30px; text-align: center; border-radius: 5px 5px 0 0; }}
                .content {{ background: #f9f9f9; padding: 30px; border-radius: 0 0 5px 5px; }}
                .button {{ display: inline-block; padding: 12px 30px; background: #667eea;
                          color: white; text-decoration: none; border-radius: 5px;
                          font-weight: bold; margin: 20px 0; }}
                .footer {{ text-align: center; color: #666; font-size: 12px; margin-top: 30px; }}
                .highlight {{ color: #667eea; font-weight: bold; }}
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1>Welcome to BioMate!</h1>
                </div>
                <div class="content">
                    <p>Hi {username},</p>

                    <p>Thank you for signing up for BioMate! We're excited to have you join our
                    community of bioinformatics researchers.</p>

                    <p>To complete your registration, please verify your email address by clicking
                    the button below:</p>

                    <div style="text-align: center;">
                        <a href="{verification_url}" class="button">Verify Email Address</a>
                    </div>

                    <p>Or copy and paste this link into your browser:</p>
                    <p style="word-break: break-all; color: #666;">
                        <a href="{verification_url}">{verification_url}</a>
                    </p>

                    <p><strong>Your {trial_days}-day free trial has started!</strong></p>

                    <p>During your trial, you'll have full access to:</p>
                    <ul>
                        <li>9,000+ bioinformatics tools</li>
                        <li>122 curated datasets</li>
                        <li>AI-powered workflow generation</li>
                        <li>Unlimited workflow execution</li>
                        <li>Cloud storage (10GB)</li>
                    </ul>

                    <p>This verification link will expire in 24 hours.</p>

                    <p>If you didn't create a BioMate account, you can safely ignore this email.</p>

                    <p>Happy analyzing!</p>
                    <p>The BioMate Team</p>
                </div>
                <div class="footer">
                    <p>BioMate - AI-Powered Bioinformatics Platform</p>
                    <p><a href="{base_url}">{base_url}</a></p>
                </div>
            </div>
        </body>
        </html>
        """

        text_body = f"""
        Welcome to BioMate!

        Hi {username},

        Thank you for signing up for BioMate! We're excited to have you join our community.

        To complete your registration, please verify your email address by visiting:
        {verification_url}

        Your {trial_days}-day free trial has started!

        During your trial, you'll have full access to:
        - 9,000+ bioinformatics tools
        - 122 curated datasets
        - AI-powered workflow generation
        - Unlimited workflow execution
        - Cloud storage (10GB)

        This verification link will expire in 24 hours.

        If you didn't create a BioMate account, you can safely ignore this email.

        Happy analyzing!
        The BioMate Team

        ---
        BioMate - AI-Powered Bioinformatics Platform
        {base_url}
        """

        return EmailTemplate(subject, html_body, text_body)

    @staticmethod
    def trial_expiry_warning(
        username: str,
        days_remaining: int,
        subscription_url: str,
        base_url: str
    ) -> EmailTemplate:
        """Trial expiry warning template"""
        subject = f"Your BioMate Trial Expires in {days_remaining} Day{'s' if days_remaining != 1 else ''}"

        html_body = f"""
        <html>
        <head>
            <style>
                body {{ font-family: Arial, sans-serif; line-height: 1.6; color: #333; }}
                .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
                .header {{ background: #f59e0b; color: white; padding: 30px; text-align: center; border-radius: 5px 5px 0 0; }}
                .content {{ background: #f9f9f9; padding: 30px; border-radius: 0 0 5px 5px; }}
                .button {{ display: inline-block; padding: 12px 30px; background: #667eea;
                          color: white; text-decoration: none; border-radius: 5px;
                          font-weight: bold; margin: 20px 0; }}
                .pricing {{ display: flex; gap: 20px; margin: 20px 0; }}
                .plan {{ flex: 1; background: white; padding: 20px; border-radius: 5px; text-align: center; }}
                .price {{ font-size: 32px; font-weight: bold; color: #667eea; }}
                .footer {{ text-align: center; color: #666; font-size: 12px; margin-top: 30px; }}
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1>⏰ Your Trial is Ending Soon</h1>
                </div>
                <div class="content">
                    <p>Hi {username},</p>

                    <p>Your BioMate free trial will expire in <strong>{days_remaining} day{'s' if days_remaining != 1 else ''}</strong>.</p>

                    <p>We hope you've enjoyed exploring BioMate's powerful features! To continue
                    your research without interruption, subscribe now:</p>

                    <div style="text-align: center;">
                        <a href="{subscription_url}" class="button">Subscribe Now</a>
                    </div>

                    <div class="pricing">
                        <div class="plan">
                            <h3>Monthly</h3>
                            <div class="price">$20</div>
                            <p>per month</p>
                        </div>
                        <div class="plan">
                            <h3>Annual</h3>
                            <div class="price">$200</div>
                            <p>per year</p>
                            <p style="color: #10b981; font-weight: bold;">Save $40!</p>
                        </div>
                    </div>

                    <p>Both plans include:</p>
                    <ul>
                        <li>9,000+ bioinformatics tools</li>
                        <li>122 curated datasets</li>
                        <li>AI workflow generation</li>
                        <li>Priority support</li>
                        <li>100GB cloud storage</li>
                    </ul>

                    <p>Questions? Reply to this email - we're here to help!</p>

                    <p>Best regards,<br>The BioMate Team</p>
                </div>
                <div class="footer">
                    <p>BioMate - AI-Powered Bioinformatics Platform</p>
                    <p><a href="{base_url}">{base_url}</a></p>
                </div>
            </div>
        </body>
        </html>
        """

        text_body = f"""
        Your BioMate Trial is Ending Soon

        Hi {username},

        Your BioMate free trial will expire in {days_remaining} day{'s' if days_remaining != 1 else ''}.

        We hope you've enjoyed exploring BioMate's powerful features! To continue your
        research without interruption, subscribe now:

        {subscription_url}

        PRICING:
        Monthly: $20/month
        Annual: $200/year (Save $40!)

        Both plans include:
        - 9,000+ bioinformatics tools
        - 122 curated datasets
        - AI workflow generation
        - Priority support
        - 100GB cloud storage

        Questions? Reply to this email - we're here to help!

        Best regards,
        The BioMate Team

        ---
        BioMate - AI-Powered Bioinformatics Platform
        {base_url}
        """

        return EmailTemplate(subject, html_body, text_body)


# ============================================================================
# EMAIL PROVIDERS
# ============================================================================

class EmailProvider(ABC):
    """Abstract base class for email providers"""

    @abstractmethod
    def send_email(
        self,
        to_email: str,
        subject: str,
        html_body: str,
        text_body: str,
        from_email: str = None,
        from_name: str = None
    ) -> bool:
        """Send email. Returns True if successful."""
        pass


class SendGridProvider(EmailProvider):
    """SendGrid email provider"""

    def __init__(self, api_key: str, default_from_email: str, default_from_name: str):
        if not SENDGRID_AVAILABLE:
            raise ImportError("SendGrid library not installed. Run: pip install sendgrid")

        self.api_key = api_key
        self.default_from_email = default_from_email
        self.default_from_name = default_from_name
        self.client = SendGridAPIClient(api_key)

    def send_email(
        self,
        to_email: str,
        subject: str,
        html_body: str,
        text_body: str,
        from_email: str = None,
        from_name: str = None
    ) -> bool:
        """Send email via SendGrid"""
        try:
            from_email = from_email or self.default_from_email
            from_name = from_name or self.default_from_name

            message = Mail(
                from_email=Email(from_email, from_name),
                to_emails=To(to_email),
                subject=subject,
                plain_text_content=Content("text/plain", text_body),
                html_content=Content("text/html", html_body)
            )

            response = self.client.send(message)

            if response.status_code in (200, 202):
                log.info(f"Email sent successfully to {to_email} via SendGrid")
                return True
            else:
                log.error(f"SendGrid returned status {response.status_code}")
                return False

        except Exception as e:
            log.error(f"Failed to send email via SendGrid: {e}")
            return False


class AWSSESProvider(EmailProvider):
    """AWS SES email provider"""

    def __init__(
        self,
        region: str,
        access_key_id: str,
        secret_access_key: str,
        default_from_email: str,
        default_from_name: str
    ):
        if not AWS_SES_AVAILABLE:
            raise ImportError("AWS boto3 library not installed. Run: pip install boto3")

        self.default_from_email = default_from_email
        self.default_from_name = default_from_name

        self.client = boto3.client(
            'ses',
            region_name=region,
            aws_access_key_id=access_key_id,
            aws_secret_access_key=secret_access_key
        )

    def send_email(
        self,
        to_email: str,
        subject: str,
        html_body: str,
        text_body: str,
        from_email: str = None,
        from_name: str = None
    ) -> bool:
        """Send email via AWS SES"""
        try:
            from_email = from_email or self.default_from_email
            from_name = from_name or self.default_from_name
            from_address = f"{from_name} <{from_email}>"

            response = self.client.send_email(
                Source=from_address,
                Destination={'ToAddresses': [to_email]},
                Message={
                    'Subject': {'Data': subject, 'Charset': 'UTF-8'},
                    'Body': {
                        'Text': {'Data': text_body, 'Charset': 'UTF-8'},
                        'Html': {'Data': html_body, 'Charset': 'UTF-8'}
                    }
                }
            )

            log.info(f"Email sent successfully to {to_email} via AWS SES "
                    f"(MessageId: {response['MessageId']})")
            return True

        except (BotoCoreError, ClientError) as e:
            log.error(f"Failed to send email via AWS SES: {e}")
            return False


class SMTPProvider(EmailProvider):
    """Generic SMTP email provider"""

    def __init__(
        self,
        host: str,
        port: int,
        username: str,
        password: str,
        use_tls: bool,
        default_from_email: str,
        default_from_name: str
    ):
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.use_tls = use_tls
        self.default_from_email = default_from_email
        self.default_from_name = default_from_name

    def send_email(
        self,
        to_email: str,
        subject: str,
        html_body: str,
        text_body: str,
        from_email: str = None,
        from_name: str = None
    ) -> bool:
        """Send email via SMTP"""
        try:
            from_email = from_email or self.default_from_email
            from_name = from_name or self.default_from_name
            from_address = f"{from_name} <{from_email}>"

            # Create message
            msg = MIMEMultipart('alternative')
            msg['Subject'] = subject
            msg['From'] = from_address
            msg['To'] = to_email

            # Attach text and HTML parts
            part1 = MIMEText(text_body, 'plain')
            part2 = MIMEText(html_body, 'html')
            msg.attach(part1)
            msg.attach(part2)

            # Connect and send
            if self.use_tls:
                server = smtplib.SMTP(self.host, self.port)
                server.starttls()
            else:
                server = smtplib.SMTP_SSL(self.host, self.port)

            server.login(self.username, self.password)
            server.sendmail(from_email, to_email, msg.as_string())
            server.quit()

            log.info(f"Email sent successfully to {to_email} via SMTP")
            return True

        except Exception as e:
            log.error(f"Failed to send email via SMTP: {e}")
            return False


class MockEmailProvider(EmailProvider):
    """Mock provider for development (logs emails instead of sending)"""

    def __init__(self):
        log.info("Using MockEmailProvider - emails will be logged but not sent")

    def send_email(
        self,
        to_email: str,
        subject: str,
        html_body: str,
        text_body: str,
        from_email: str = None,
        from_name: str = None
    ) -> bool:
        """Mock send - just log the email"""
        log.info("=" * 80)
        log.info("MOCK EMAIL (not actually sent)")
        log.info(f"To: {to_email}")
        log.info(f"From: {from_name} <{from_email}>")
        log.info(f"Subject: {subject}")
        log.info("-" * 80)
        log.info(text_body)
        log.info("=" * 80)
        return True


# ============================================================================
# EMAIL SERVICE
# ============================================================================

class EmailService:
    """Main email service that handles sending emails via configured provider"""

    def __init__(self, config: Dict[str, Any]):
        """
        Initialize email service with configuration

        Args:
            config: Configuration dict from auth_payment_config.yml
        """
        self.config = config
        self.base_url = config.get('app', {}).get('base_url', 'http://localhost:8080')
        self.frontend_url = config.get('app', {}).get('frontend_url', 'http://localhost:8081')

        # Check if we're in dev mode with mock emails
        if config.get('development', {}).get('mock_email', False):
            self.provider = MockEmailProvider()
            log.info("Email service initialized with MockEmailProvider (development mode)")
            return

        # Initialize real provider
        email_config = config.get('email', {})
        provider_type = email_config.get('provider', 'sendgrid')

        if provider_type == 'sendgrid':
            sendgrid_config = email_config.get('sendgrid', {})
            self.provider = SendGridProvider(
                api_key=sendgrid_config['api_key'],
                default_from_email=sendgrid_config['from_email'],
                default_from_name=sendgrid_config['from_name']
            )
            log.info("Email service initialized with SendGrid")

        elif provider_type == 'aws_ses':
            ses_config = email_config.get('aws_ses', {})
            self.provider = AWSSESProvider(
                region=ses_config['region'],
                access_key_id=ses_config['access_key_id'],
                secret_access_key=ses_config['secret_access_key'],
                default_from_email=ses_config['from_email'],
                default_from_name=ses_config['from_name']
            )
            log.info("Email service initialized with AWS SES")

        elif provider_type == 'smtp':
            smtp_config = email_config.get('smtp', {})
            self.provider = SMTPProvider(
                host=smtp_config['host'],
                port=smtp_config['port'],
                username=smtp_config['username'],
                password=smtp_config['password'],
                use_tls=smtp_config['use_tls'],
                default_from_email=smtp_config['from_email'],
                default_from_name=smtp_config['from_name']
            )
            log.info("Email service initialized with SMTP")

        else:
            raise ValueError(f"Unknown email provider: {provider_type}")

    def send_verification_email(self, to_email: str, username: str, token: str) -> bool:
        """
        Send email verification email

        Args:
            to_email: Recipient email
            username: User's username
            token: Verification token

        Returns:
            True if email sent successfully
        """
        verification_url = f"{self.frontend_url}/verify-email?token={token}"
        trial_days = self.config.get('subscription', {}).get('trial_duration_days', 10)

        template = EmailTemplates.verification_email(
            username=username,
            verification_url=verification_url,
            base_url=self.base_url,
            trial_days=trial_days
        )

        return self.provider.send_email(
            to_email=to_email,
            subject=template.subject,
            html_body=template.html_body,
            text_body=template.text_body
        )

    def send_trial_expiry_warning(
        self,
        to_email: str,
        username: str,
        days_remaining: int
    ) -> bool:
        """
        Send trial expiry warning email

        Args:
            to_email: Recipient email
            username: User's username
            days_remaining: Days until trial expires

        Returns:
            True if email sent successfully
        """
        subscription_url = f"{self.frontend_url}/subscription"

        template = EmailTemplates.trial_expiry_warning(
            username=username,
            days_remaining=days_remaining,
            subscription_url=subscription_url,
            base_url=self.base_url
        )

        return self.provider.send_email(
            to_email=to_email,
            subject=template.subject,
            html_body=template.html_body,
            text_body=template.text_body
        )

    def send_custom_email(
        self,
        to_email: str,
        subject: str,
        html_body: str,
        text_body: str
    ) -> bool:
        """
        Send custom email

        Args:
            to_email: Recipient email
            subject: Email subject
            html_body: HTML body
            text_body: Plain text body

        Returns:
            True if email sent successfully
        """
        return self.provider.send_email(
            to_email=to_email,
            subject=subject,
            html_body=html_body,
            text_body=text_body
        )
