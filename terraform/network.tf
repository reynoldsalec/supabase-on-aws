# Create VPC if not provided
resource "aws_vpc" "this" {
  count = var.vpc_id == "" ? 1 : 0

  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    var.tags,
    {
      Name = "supabase-vpc"
    }
  )
}

# Use existing VPC if provided
data "aws_vpc" "existing" {
  count = var.vpc_id != "" ? 1 : 0
  id    = var.vpc_id
}

locals {
  vpc_id = var.vpc_id != "" ? var.vpc_id : aws_vpc.this[0].id
}

# Create subnet if not provided
resource "aws_subnet" "this" {
  count = var.subnet_id == "" ? 1 : 0

  vpc_id                  = local.vpc_id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}a"

  tags = merge(
    var.tags,
    {
      Name = "supabase-subnet"
    }
  )
}

# Use existing subnet if provided
data "aws_subnet" "existing" {
  count = var.subnet_id != "" ? 1 : 0
  id    = var.subnet_id
}

locals {
  subnet_id = var.subnet_id != "" ? var.subnet_id : aws_subnet.this[0].id
}

# Create Internet Gateway
resource "aws_internet_gateway" "this" {
  count = var.vpc_id == "" ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "supabase-igw"
    }
  )
}

# Create Route Table
resource "aws_route_table" "this" {
  count = var.vpc_id == "" ? 1 : 0

  vpc_id = local.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this[0].id
  }

  tags = merge(
    var.tags,
    {
      Name = "supabase-route-table"
    }
  )
}

# Associate Route Table with Subnet
resource "aws_route_table_association" "this" {
  count = var.vpc_id == "" && var.subnet_id == "" ? 1 : 0

  subnet_id      = local.subnet_id
  route_table_id = aws_route_table.this[0].id
}

# Security Group for Supabase
resource "aws_security_group" "this" {
  name        = "supabase-sg"
  description = "Security group for Supabase"
  vpc_id      = local.vpc_id

  # Allow HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP access"
  }

  # Allow HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS access"
  }

  # Conditionally allow SSH
  dynamic "ingress" {
    for_each = var.enable_ssh ? [1] : []
    content {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.ssh_cidr_blocks
      description = "SSH access"
    }
  }

  # Conditionally allow PostgreSQL
  dynamic "ingress" {
    for_each = var.enable_db_con ? [1] : []
    content {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = var.db_cidr_blocks
      description = "PostgreSQL access"
    }
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(
    var.tags,
    {
      Name = "supabase-security-group"
    }
  )
}

# Get the Route53 hosted zone (only if use_route53 is true)
data "aws_route53_zone" "this" {
  count = var.use_route53 ? 1 : 0
  name  = var.domain
}

# Create DNS A record for Supabase (only if use_route53 is true)
resource "aws_route53_record" "a_record" {
  count   = var.use_route53 ? 1 : 0
  zone_id = data.aws_route53_zone.this[0].zone_id
  name    = "supabase.${var.domain}"
  type    = "A"
  ttl     = 300
  records = [aws_eip.this.public_ip]
}

# Elastic IP for the EC2 instance
resource "aws_eip" "this" {
  domain = "vpc"

  tags = merge(
    var.tags,
    {
      Name = "supabase-eip"
    }
  )

  # Explicitly set dependency on the internet gateway
  depends_on = [aws_internet_gateway.this]
}

# Associate Elastic IP with EC2 instance
resource "aws_eip_association" "this" {
  instance_id   = aws_instance.this.id
  allocation_id = aws_eip.this.id

  # Add explicit dependency to enforce destroy order
  depends_on = [aws_instance.this, aws_eip.this]

  # Ensure this is destroyed before the instance
  lifecycle {
    create_before_destroy = true
  }
}

# We'll use a placeholder for non-Route53 domains during instance creation
# The actual DNS will be available after instance creation via the output
locals {
  domain_name = var.use_route53 ? "supabase.${var.domain}" : "supabase-instance"
}

# Create ACM certificate if not provided and using Route53
resource "aws_acm_certificate" "this" {
  count = var.certificate_arn == "" && var.use_route53 ? 1 : 0

  domain_name       = "supabase.${var.domain}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.tags,
    {
      Name = "supabase-certificate"
    }
  )
}

# Extract DNS validation records as a local variable to avoid the "known after apply" error
locals {
  certificate_validation_records = var.certificate_arn == "" && var.use_route53 && length(aws_acm_certificate.this) > 0 ? {
    for dvo in tolist(aws_acm_certificate.this[0].domain_validation_options) :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}
}

# Create DNS records for ACM certificate validation (only if using Route53)
resource "aws_route53_record" "certificate_validation" {
  for_each = local.certificate_validation_records

  zone_id = data.aws_route53_zone.this[0].zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
  allow_overwrite = true
}

# Validate the certificate (only if using Route53)
resource "aws_acm_certificate_validation" "this" {
  count = var.certificate_arn == "" && var.use_route53 && length(aws_acm_certificate.this) > 0 ? 1 : 0

  certificate_arn         = aws_acm_certificate.this[0].arn
  validation_record_fqdns = [for record in aws_route53_record.certificate_validation : record.fqdn]
}

locals {
  certificate_arn = var.certificate_arn != "" ? var.certificate_arn : var.use_route53 ? aws_acm_certificate.this[0].arn : null
}
