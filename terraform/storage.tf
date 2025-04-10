resource "random_id" "bucket" {
  byte_length = 8
  prefix      = "supabase-"
}

# S3 Bucket for storage
resource "aws_s3_bucket" "this" {
  bucket = random_id.bucket.hex

  tags = merge(
    var.tags,
    {
      Name = "supabase-bucket"
    }
  )
}

# S3 Bucket ownership controls
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# S3 Bucket access control
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket policy
resource "aws_s3_bucket_policy" "this" {
  count  = var.s3_restrict_access ? 1 : 0
  bucket = aws_s3_bucket.this.id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "IPAllow",
        "Effect" : "Deny",
        "Principal" : "*",
        "Action" : "s3:*",
        "Resource" : [
          "arn:aws:s3:::${aws_s3_bucket.this.id}",
          "arn:aws:s3:::${aws_s3_bucket.this.id}/*"
        ],
        "Condition" : {
          "NotIpAddress" : {
            "aws:SourceIp" : [
              aws_eip.this.public_ip,
              var.enable_ssh ? var.ssh_cidr_blocks : []
            ]
          }
        }
      }
    ]
  })
}

# EBS Volume for PostgreSQL data
resource "aws_ebs_volume" "this" {
  availability_zone = aws_instance.this.availability_zone
  size              = var.volume_size
  type              = "gp3"
  encrypted         = true

  tags = merge(
    var.tags,
    {
      Name = "supabase-volume"
    }
  )
}

# Attach EBS Volume to EC2 instance
resource "aws_volume_attachment" "this" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.this.id
  instance_id = aws_instance.this.id

  # Ensure the volume is detached when the instance is terminated
  skip_destroy = true
}

# Get IAM policy for EC2 to access S3
resource "aws_iam_policy" "s3_access" {
  name        = "supabase-s3-access"
  description = "Policy for EC2 to access S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.this.arn,
          "${aws_s3_bucket.this.arn}/*"
        ]
      }
    ]
  })
}

# Create IAM role for EC2 to access S3
resource "aws_iam_role" "this" {
  name = "supabase-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "supabase-ec2-role"
    }
  )
}

# Attach S3 access policy to IAM role
resource "aws_iam_role_policy_attachment" "s3_access" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.s3_access.arn
}

# Create IAM instance profile
resource "aws_iam_instance_profile" "this" {
  name = "supabase-instance-profile"
  role = aws_iam_role.this.name
}

