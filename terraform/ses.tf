############
# Amazon SES Configuration
############

# Variable to control if SES should be enabled
variable "enable_ses" {
  description = "Whether to enable Amazon SES for email functionality. If false, email functionality will be disabled."
  type        = bool
  default     = true
}

# SES Domain Identity
resource "aws_ses_domain_identity" "this" {
  count  = var.enable_ses && var.use_route53 ? 1 : 0
  domain = var.domain
}

# SES DKIM Configuration
resource "aws_ses_domain_dkim" "this" {
  count  = var.enable_ses && var.use_route53 ? 1 : 0
  domain = aws_ses_domain_identity.this[0].domain
}

# Route53 TXT record for SES domain verification
resource "aws_route53_record" "ses_verification" {
  count   = var.enable_ses && var.use_route53 ? 1 : 0
  zone_id = data.aws_route53_zone.this[0].zone_id
  name    = "_amazonses.${var.domain}"
  type    = "TXT"
  ttl     = "600"
  records = [aws_ses_domain_identity.this[0].verification_token]
}

# Route53 CNAME records for DKIM
resource "aws_route53_record" "ses_dkim" {
  count   = var.enable_ses && var.use_route53 ? 3 : 0
  zone_id = data.aws_route53_zone.this[0].zone_id
  name    = "${aws_ses_domain_dkim.this[0].dkim_tokens[count.index]}._domainkey.${var.domain}"
  type    = "CNAME"
  ttl     = "600"
  records = ["${aws_ses_domain_dkim.this[0].dkim_tokens[count.index]}.dkim.amazonses.com"]
  allow_overwrite = true
}

# Verify the SES domain
resource "aws_ses_domain_identity_verification" "this" {
  count      = var.enable_ses && var.use_route53 ? 1 : 0
  domain     = aws_ses_domain_identity.this[0].id
  depends_on = [aws_route53_record.ses_verification]
}

# IAM policy for sending emails via SES
resource "aws_iam_policy" "ses_send_email" {
  count       = var.enable_ses ? 1 : 0
  name        = "supabase-ses-send-email"
  description = "Policy to allow sending emails via SES"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["ses:SendEmail", "ses:SendRawEmail"]
        Effect   = "Allow"
        Resource = var.use_route53 ? "arn:aws:ses:${var.region}:${data.aws_caller_identity.current.account_id}:identity/${var.domain}" : "*"
      },
    ]
  })
}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# IAM role policy attachment for SES
resource "aws_iam_role_policy_attachment" "ses_send_email" {
  count      = var.enable_ses ? 1 : 0
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.ses_send_email[0].arn
}

# SES SMTP user for programmatic email sending
resource "aws_iam_user" "ses_smtp_user" {
  count = var.enable_ses ? 1 : 0
  name  = "supabase-ses-smtp-user"
}

resource "aws_iam_access_key" "ses_smtp_user" {
  count = var.enable_ses ? 1 : 0
  user  = aws_iam_user.ses_smtp_user[0].name
}

resource "aws_iam_user_policy" "ses_smtp_policy" {
  count = var.enable_ses ? 1 : 0
  name  = "ses-smtp-policy"
  user  = aws_iam_user.ses_smtp_user[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["ses:SendRawEmail"]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# Helper function to convert IAM access key to SES SMTP password
# This is necessary because SES SMTP password is different from IAM secret key
locals {
  # These will override the SendGrid values when SES is enabled
  smtp_settings = var.enable_ses ? {
    host     = "email-smtp.${var.region}.amazonaws.com"
    port     = 587
    user     = var.enable_ses ? aws_iam_access_key.ses_smtp_user[0].id : ""
    password = var.enable_ses ? aws_iam_access_key.ses_smtp_user[0].ses_smtp_password_v4 : ""
  } : {}
}
