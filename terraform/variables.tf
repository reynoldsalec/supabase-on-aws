# You can also set SENDGRID_API_KEY env variable
# Set the variable value in *.tfvars file or use the -var="sendgrid_api=..." CLI option
variable "sendgrid_api" {
  description = "SendGrid API Key. Required only if enable_sendgrid is true."
  type        = string
  sensitive   = true
  default     = ""
}

# # You can also set TF_TOKEN_app_terraform_io
# # Set the variable value in *.tfvars file or use the -var="_=..." CLI option
# variable "tf_token" {
#   description = "Terraform Cloud API Token."
#   type        = string
#   sensitive   = true
# }

variable "region" {
  description = "The AWS region where resources will be created."
  type        = string
}

variable "domain" {
  description = "Domain name where the Supabase instance is accessible. Required only if use_route53 is true. When use_route53 is false, the EC2's public DNS will be used instead."
  type        = string
  default     = ""
}

variable "site_url" {
  description = "Domain name of your application in the format."
  type        = string
}

variable "timezone" {
  description = "Timezone to use for Nginx (e.g. Europe/Amsterdam)."
  type        = string
}

variable "auth_user" {
  description = "The username for Nginx authentication."
  type        = string
  sensitive   = true
}

variable "smtp_admin_user" {
  description = "`From` email address for all emails sent."
  type        = string
}

variable "smtp_addr" {
  description = "Company Address of the Verified Sender. Max 100 characters. If more is needed use `smtp_addr_2`"
  type        = string
}

variable "smtp_city" {
  description = "Company city of the verified sender."
  type        = string
}

variable "smtp_country" {
  description = "Company country of the verified sender."
  type        = string
}

variable "instance_type" {
  description = "The EC2 instance type."
  type        = string
  default     = "t3.small"
}

variable "instance_backups" {
  description = "Boolean controlling if backups are made. Defaults to true."
  type        = bool
  default     = true
}

variable "ssh_pub_file" {
  description = "The path to the public key ssh file."
  type        = string
  default     = ""
}

variable "tags" {
  description = "A map of tags to be added to all resources."
  type        = map(string)
  default     = {}
}

variable "volume_size" {
  description = "The size of the EBS volume in GiB. If updated, can only be expanded."
  type        = number
  default     = 25
}

variable "enable_ssh" {
  description = "Boolean enabling connections to EC2 instance via SSH by opening port 22 on the security group."
  type        = bool
  default     = true
}

variable "ssh_cidr_blocks" {
  description = "List of CIDR blocks from which SSH connections are allowed."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_db_con" {
  description = "Boolean enabling connections to database by opening port 5432 on the security group."
  type        = bool
  default     = false
}

variable "db_cidr_blocks" {
  description = "List of CIDR blocks from which database connections are allowed."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "s3_restrict_access" {
  description = "Boolean signifying whether to restrict the S3 bucket to the EC2 instance or allow all IPs."
  type        = bool
  default     = false
}

variable "studio_org" {
  description = "Organization for Studio Configuration."
  type        = string
  default     = "Default Organization"
}

variable "studio_project" {
  description = "Project for Studio Configuration."
  type        = string
  default     = "Default Project"
}

variable "enable_smtp" {
  description = "Whether to enable SMTP for email functionality. If false, email functionality will be disabled."
  type        = bool
  default     = true
}

variable "smtp_host" {
  description = "The SMTP server hostname."
  type        = string
  default     = ""
}

variable "smtp_port" {
  description = "Port number to connect to the SMTP server on."
  type        = number
  default     = 587
}

variable "smtp_user" {
  description = "The username to use for SMTP authentication."
  type        = string
  default     = ""
}

variable "smtp_password" {
  description = "The password to use for SMTP authentication."
  type        = string
  sensitive   = true
  default     = ""
}

variable "smtp_sender_name" {
  description = "Friendly name to show recipient rather than email address. Defaults to the email address specified in the `smtp_admin_user` variable."
  type        = string
  default     = ""
}

variable "smtp_addr_2" {
  description = "Company Address Line 2. Max 100 characters."
  type        = string
  default     = ""
}

variable "smtp_state" {
  description = "Company State."
  type        = string
  default     = ""
}

variable "smtp_zip_code" {
  description = "Company Zip Code."
  type        = string
  default     = ""
}

variable "smtp_nickname" {
  description = "Nickname to show recipient. Defaults to `smtp_sender_name` or the email address specified in the `smtp_admin_user` variable if neither are specified."
  type        = string
  default     = ""
}

variable "smtp_reply_to" {
  description = "Email address to show in the `reply-to` field within an email. Defaults to the email address specified in the `smtp_admin_user` variable."
  type        = string
  default     = ""
}

variable "smtp_reply_to_name" {
  description = "Friendly name to show recipient rather than email address in the `reply-to` field within an email. Defaults to `smtp_sender_name` or `smtp_reply_to` if `smtp_sender_name` is not set, or the email address specified in the `smtp_admin_user` variable if neither are specified."
  type        = string
  default     = ""
}

# AWS specific variables
variable "vpc_id" {
  description = "ID of the VPC where resources will be created. If not provided, a new VPC will be created."
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "ID of the subnet where the EC2 instance will be launched. If not provided, a new subnet will be created."
  type        = string
  default     = ""
}

variable "ami_id" {
  description = "ID of the AMI to use for the EC2 instance. This AMI must exist in the specified region."
  type        = string
}

variable "certificate_arn" {
  description = "ARN of the ACM certificate to use for HTTPS. If not provided, a new certificate will be created."
  type        = string
  default     = ""
}

# Enable or disable SendGrid integration
variable "enable_sendgrid" {
  description = "Whether to enable SendGrid for email functionality. If false, email functionality will be disabled."
  type        = bool
  default     = true
}

# Enable or disable Route53 for domain management
variable "use_route53" {
  description = "Whether to use Route53 for domain management. If false, the EC2 public DNS will be used instead."
  type        = bool
  default     = true
}

# Enable or disable Let's Encrypt staging environment
variable "use_letsencrypt_staging" {
  description = "Whether to use Let's Encrypt staging environment for certificate generation. Useful for testing to avoid rate limits."
  type        = bool
  default     = false
}

variable "enable_email_autoconfirm" {
  description = "Whether to automatically confirm email addresses during signup. If false, users will need to confirm their email addresses."
  type        = bool
  default     = false
}

variable "enable_github_oauth" {
  description = "Whether to enable GitHub OAuth authentication."
  type        = bool
  default     = false
}

variable "github_client_id" {
  description = "GitHub OAuth client ID. Required only if enable_github_oauth is true."
  type        = string
  sensitive   = true
  default     = ""
}

variable "github_client_secret" {
  description = "GitHub OAuth client secret. Required only if enable_github_oauth is true."
  type        = string
  sensitive   = true
  default     = ""
}

# Enable or disable Google OAuth authentication
variable "enable_google_oauth" {
  description = "Whether to enable Google OAuth authentication."
  type        = bool
  default     = false
}

variable "google_client_id" {
  description = "Google OAuth client ID. Required only if enable_google_oauth is true."
  type        = string
  sensitive   = true
  default     = ""
}

variable "google_client_secret" {
  description = "Google OAuth client secret. Required only if enable_google_oauth is true."
  type        = string
  sensitive   = true
  default     = ""
}
