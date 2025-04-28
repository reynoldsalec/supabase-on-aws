locals {
  ami_id = var.ami_id
}

data "cloudinit_config" "this" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/cloud-config"
    filename     = "cloud-config.yaml"
    content      = local.cloud_config
  }

  part {
    content_type = "text/x-shellscript"
    filename     = "init.sh"
    content      = <<-EOF
      #!/bin/bash
      # Install Docker and Docker Compose
      apt-get update
      apt-get install -y apt-transport-https ca-certificates curl software-properties-common
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
      add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
      apt-get update
      apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

      # Add ubuntu user to the docker group
      usermod -aG docker ubuntu

      # Setup EBS volume
      mkdir -p /mnt/supabase_volume
      device_path="/dev/nvme1n1"
      if [ -e /dev/xvdf ]; then
        device_path="/dev/xvdf"
      fi

      # Check if the EBS volume is already formatted
      if ! blkid $device_path; then
        # Format the volume if it's not formatted
        mkfs.ext4 $device_path
      fi

      # Mount the volume
      echo "$device_path /mnt/supabase_volume ext4 defaults,nofail,discard 0 2" >> /etc/fstab
      mount -a

      # Setup Supabase directories
      mkdir -p /mnt/supabase_volume/supabase/data
      mkdir -p /mnt/supabase_volume/supabase/ssl
      mkdir -p /mnt/supabase_volume/supabase/log
      mkdir -p /root/supabase

      # Copy configuration to ubuntu user's home directory
      mkdir -p /home/ubuntu/supabase
      cp -r /root/supabase/. /home/ubuntu/supabase/
      chown -R ubuntu:ubuntu /home/ubuntu/supabase

      # Create a symlink for easier access
      ln -s /mnt/supabase_volume/supabase/data /home/ubuntu/supabase/data

      # Get Supabase configuration
      cd /root/supabase

      # Run domain update script if needed
      /root/supabase/update-domain.sh

      # Start Supabase Docker Compose
      docker compose -f /root/supabase/docker-compose.yml up -d
    EOF
  }
}

# Create EC2 key pair if SSH public key file is provided
resource "aws_key_pair" "this" {
  count = var.ssh_pub_file != "" ? 1 : 0

  key_name   = "supabase-key"
  public_key = file(var.ssh_pub_file)

  tags = merge(
    var.tags,
    {
      Name = "supabase-key"
    }
  )
}

# Create EC2 instance
resource "aws_instance" "this" {
  ami                    = local.ami_id
  instance_type          = var.instance_type
  subnet_id              = local.subnet_id
  vpc_security_group_ids = [aws_security_group.this.id]
  key_name               = var.ssh_pub_file != "" ? aws_key_pair.this[0].key_name : null
  user_data              = data.cloudinit_config.this.rendered
  iam_instance_profile   = aws_iam_instance_profile.this.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(
    var.tags,
    {
      Name = "supabase-instance"
    }
  )

  lifecycle {
    ignore_changes = [user_data]
  }
}

# Create backup of the instance if enabled
resource "aws_dlm_lifecycle_policy" "this" {
  count = var.instance_backups ? 1 : 0

  description        = "Supabase instance backup policy"
  execution_role_arn = aws_iam_role.dlm[count.index].arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["INSTANCE"]

    schedule {
      name = "Daily-Backup"

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["03:00"]
      }

      retain_rule {
        count = 7
      }

      tags_to_add = {
        SnapshotCreator = "DLM"
      }

      copy_tags = true
    }

    target_tags = {
      Name = "supabase-instance"
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "supabase-backup-policy"
    }
  )
}

# IAM role for Data Lifecycle Manager
resource "aws_iam_role" "dlm" {
  count = var.instance_backups ? 1 : 0

  name = "supabase-dlm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "dlm.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "supabase-dlm-role"
    }
  )
}

# Attach DLM policy to IAM role
resource "aws_iam_role_policy_attachment" "dlm" {
  count = var.instance_backups ? 1 : 0

  role       = aws_iam_role.dlm[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}
