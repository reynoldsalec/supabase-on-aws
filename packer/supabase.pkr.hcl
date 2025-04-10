packer {
  required_version = "~> 1.12.0"

  required_plugins {
    amazon = {
      version = ">= 1.2.6"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

# Set the variable value in the supabase.auto.pkvars.hcl file
# or use -var "aws_access_key=..." CLI option
variable "aws_access_key" {
  description = "AWS Access Key ID."
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS Secret Access Key."
  type        = string
  sensitive   = true
}

variable "region" {
  description = "The AWS region where the AMI will be created."
  type        = string
}

variable "instance_type" {
  description = "The EC2 instance type to use for building the AMI."
  type        = string
  default     = "t3.small"
}

variable "ami_name_prefix" {
  description = "The prefix for the AMI name."
  type        = string
  default     = "supabase"
}

locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")

  ami_name = "${var.ami_name_prefix}-${local.timestamp}"

  tags = {
    Name        = local.ami_name
    Project     = "supabase"
    Environment = "production"
    Builder     = "packer"
  }
}

source "amazon-ebs" "supabase" {
  access_key      = var.aws_access_key
  secret_key      = var.aws_secret_key
  region          = var.region
  instance_type   = var.instance_type
  ssh_username    = "ubuntu"
  ami_name        = local.ami_name
  tags            = local.tags
  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"] # Canonical
  }
}

build {
  sources = ["source.amazon-ebs.supabase"]

  provisioner "file" {
    source      = "./supabase"
    destination = "/tmp"
  }

  provisioner "shell" {
    inline = [
      "sudo mkdir -p /root/supabase",
      "sudo cp -R /tmp/supabase/* /root/supabase/",
      "sudo chmod -R 755 /root/supabase"
    ]
  }

  provisioner "shell" {
    script = "./scripts/setup.sh"
  }
}
