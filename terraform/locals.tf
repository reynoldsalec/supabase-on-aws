resource "random_password" "psql" {
  length           = 32
  special          = true
  override_special = "-_"
}

resource "random_password" "htpasswd" {
  length           = 32
  special          = true
  override_special = "-_"
}

resource "htpasswd_password" "hash" {
  password = random_password.htpasswd.result

  lifecycle {
    ignore_changes = [password]
  }
}

resource "time_static" "jwt_iat" {}

resource "time_static" "jwt_exp" {
  rfc3339 = timeadd(time_static.jwt_iat.rfc3339, "43829h") # Add 5 Years
}

resource "random_password" "jwt" {
  length           = 40
  special          = true
  override_special = "-_"
}

resource "jwt_hashed_token" "anon" {
  secret    = random_password.jwt.result
  algorithm = "HS256"
  claims_json = jsonencode(
    {
      role = "anon"
      iss  = "supabase"
      iat  = time_static.jwt_iat.unix
      exp  = time_static.jwt_exp.unix
    }
  )
}

resource "jwt_hashed_token" "service_role" {
  secret    = random_password.jwt.result
  algorithm = "HS256"
  claims_json = jsonencode(
    {
      role = "service_role"
      iss  = "supabase"
      iat  = time_static.jwt_iat.unix
      exp  = time_static.jwt_exp.unix
    }
  )
}

locals {
  default_tags = {
    Project     = "supabase"
    Environment = "production"
    Terraform   = "true"
  }

  smtp_sender_name   = var.smtp_sender_name != "" ? var.smtp_sender_name : var.smtp_admin_user
  smtp_nickname      = var.smtp_nickname != "" ? var.smtp_nickname : var.smtp_sender_name != "" ? var.smtp_sender_name : var.smtp_admin_user
  smtp_reply_to      = var.smtp_reply_to != "" ? var.smtp_reply_to : var.smtp_admin_user
  smtp_reply_to_name = var.smtp_reply_to_name != "" ? var.smtp_reply_to_name : var.smtp_sender_name != "" ? var.smtp_sender_name : var.smtp_admin_user

  # Determine the SMTP settings based on which provider is enabled
  effective_smtp = {
    # Use smtp_settings from ses.tf when SES is enabled, fall back to SendGrid or disabled
    host     = var.enable_ses ? local.smtp_settings.host : (var.enable_sendgrid ? var.smtp_host : "disabled")
    port     = var.enable_ses ? local.smtp_settings.port : (var.enable_sendgrid ? var.smtp_port : 25)
    user     = var.enable_ses ? local.smtp_settings.user : (var.enable_sendgrid ? var.smtp_user : "")
    password = var.enable_ses ? local.smtp_settings.password : (var.enable_sendgrid ? (var.sendgrid_api != "" ? sendgrid_api_key.this[0].api_key : var.sendgrid_api) : "")
    enabled  = var.enable_ses || var.enable_sendgrid ? "true" : "false"
  }

  env_file = templatefile("${path.module}/files/.env.tftpl",
    {
      TF_PSQL_PASS                = "${random_password.psql.result}",
      TF_JWT_SECRET               = "${random_password.jwt.result}",
      TF_ANON_KEY                 = "${jwt_hashed_token.anon.token}",
      TF_SERVICE_ROLE_KEY         = "${jwt_hashed_token.service_role.token}",
      TF_DOMAIN                   = var.use_route53 ? "${var.domain}" : "${local.domain_name}",
      TF_SITE_URL                 = "${var.site_url}",
      TF_TIMEZONE                 = "${var.timezone}",
      TF_REGION                   = "${var.region}",
      TF_SPACES_BUCKET            = "${aws_s3_bucket.this.id}",
      TF_SPACES_ACCESS_KEY_ID     = "${var.aws_access_key}",
      TF_SPACES_SECRET_ACCESS_KEY = "${var.aws_secret_key}",
      TF_SPACES_ENDPOINT          = "https://s3.${var.region}.amazonaws.com",
      TF_SMTP_ADMIN_EMAIL         = "${var.smtp_admin_user}",
      TF_SMTP_HOST                = local.effective_smtp.host,
      TF_SMTP_PORT                = local.effective_smtp.port,
      TF_SMTP_USER                = local.effective_smtp.user,
      TF_SMTP_PASS                = local.effective_smtp.password,
      TF_SMTP_SENDER_NAME         = "${local.smtp_sender_name}",
      TF_DEFAULT_ORGANIZATION     = "${var.studio_org}",
      TF_DEFAULT_PROJECT          = "${var.studio_project}",
      TF_EMAIL_ENABLED            = local.effective_smtp.enabled,
      TF_USE_HTTPS                = var.use_route53 ? "true" : "false",
    }
  )

  route53_ini = templatefile("${path.module}/files/route53.ini.tftpl", {
    TF_AWS_ACCESS_KEY = "${var.aws_access_key}",
    TF_AWS_SECRET_KEY = "${var.aws_secret_key}",
    TF_AWS_REGION = "${var.region}"
  })

  htpasswd = templatefile("${path.module}/files/.htpasswd.tftpl",
    {
      AUTH_USER = "${var.auth_user}",
      AUTH_PASS = "${htpasswd_password.hash.apr1}"
    }
  )

  kong_file = templatefile("${path.module}/files/kong.yml.tftpl",
    {
      TF_ANON_KEY         = "${jwt_hashed_token.anon.token}",
      TF_SERVICE_ROLE_KEY = "${jwt_hashed_token.service_role.token}",
    }
  )

  cloud_config = <<-END
    #cloud-config
    ${jsonencode({
  write_files = [
    {
      path        = "/root/supabase/.env"
      permissions = "0644"
      owner       = "root:root"
      encoding    = "b64"
      content     = base64encode("${local.env_file}")
    },
    {
      path        = "/root/supabase/route53.ini"
      permissions = "0600"
      owner       = "root:root"
      encoding    = "b64"
      content     = base64encode("${local.route53_ini}")
    },
    {
      path        = "/root/supabase/.htpasswd"
      permissions = "0644"
      owner       = "root:root"
      encoding    = "b64"
      content     = base64encode("${local.htpasswd}")
    },
    {
      path        = "/root/supabase/volumes/api/kong.yml"
      permissions = "0644"
      owner       = "root:root"
      encoding    = "b64"
      content     = base64encode("${local.kong_file}")
    },
    # Add a post-startup script to fix configuration with the real domain
    {
      path        = "/root/supabase/update-domain.sh"
      permissions = "0755"
      owner       = "root:root"
      content     = var.use_route53 ? "#!/bin/bash\necho 'Using Route53, no domain update needed.'" : "#!/bin/bash\nPUBLIC_DNS=$(curl -s http://169.254.169.254/latest/meta-data/public-hostname)\nsed -i \"s/supabase-instance/$PUBLIC_DNS/g\" /root/supabase/.env\nsed -i \"s/supabase-instance/$PUBLIC_DNS/g\" /home/ubuntu/supabase/.env\necho \"Domain updated to $PUBLIC_DNS\"\n"
    },
  ]
})}
  END
}
