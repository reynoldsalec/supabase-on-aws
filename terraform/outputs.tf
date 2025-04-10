output "psql_pass" {
  description = "Randomly generated 32 character password for the Postgres database."
  value       = random_password.psql.result
  sensitive   = true
}

output "htpasswd" {
  description = "Randomly generated 32 character password for authentication via Nginx."
  value       = random_password.htpasswd.result
  sensitive   = true
}

output "sendgrid_generated_api" {
  description = "SendGrid API key to allow sending of emails (The api key is limited to Send Mail scope only). Only available if enable_sendgrid is true."
  value       = var.enable_sendgrid ? sendgrid_api_key.this[0].api_key : "SendGrid is disabled"
  sensitive   = true
}

output "jwt" {
  description = "Randomly generated 40 character jwt secret."
  value       = random_password.jwt.result
  sensitive   = true
}

output "jwt_iat" {
  description = "The Issued At time for the `anon` and `service_role` jwt tokens in epoch time."
  value       = time_static.jwt_iat.unix
}

output "jwt_exp" {
  description = "The Expiration time for the `anon` and `service_role` jwt tokens in epoch time."
  value       = time_static.jwt_exp.unix
}

output "jwt_anon" {
  description = "The HS256 generated jwt token for the `anon` role."
  value       = jwt_hashed_token.anon.token
  sensitive   = true
}

output "jwt_service_role" {
  description = "The HS256 generated jwt token for the `service_role` role."
  value       = jwt_hashed_token.service_role.token
  sensitive   = true
}

output "ebs_volume_id" {
  description = "The unique identifier for the EBS volume attached to the EC2 instance."
  value       = aws_ebs_volume.this.id
}

output "elastic_ip" {
  description = "The Elastic IP assigned to the EC2 instance."
  value       = aws_eip.this.public_ip
}

output "s3_bucket" {
  description = "The unique name of the S3 bucket in the format `supabase-ab12cd34ef56gh78`."
  value       = aws_s3_bucket.this.id
}

output "instance_id" {
  description = "The ID of the EC2 instance."
  value       = aws_instance.this.id
}

output "instance_public_dns" {
  description = "The public DNS of the EC2 instance."
  value       = aws_instance.this.public_dns
}

output "supabase_url" {
  description = "The URL to access Supabase."
  value       = var.use_route53 ? "https://supabase.${var.domain}" : "http://${aws_eip.this.public_dns}"
}

output "access_instructions" {
  description = "Instructions on how to access Supabase."
  value       = var.use_route53 ? "Access Supabase at: https://supabase.${var.domain}" : "Access Supabase at: http://${aws_eip.this.public_dns}\nNote: When using the AWS-assigned domain without Route53, you'll need to accept any certificate warnings in your browser."
}

output "cleanup_script" {
  description = "Script to help clean up resources if terraform destroy fails"
  value       = <<EOF
#!/bin/bash
# Run this script if terraform destroy fails due to dependency issues
# Replace these values with the actual IDs from your terraform output
INSTANCE_ID="${aws_instance.this.id}"
VOLUME_ID="${aws_ebs_volume.this.id}"
EIP_ALLOC_ID="${aws_eip.this.id}"

echo "Stopping EC2 instance..."
aws ec2 stop-instances --instance-ids $INSTANCE_ID
aws ec2 wait instance-stopped --instance-ids $INSTANCE_ID

echo "Detaching EBS volume..."
aws ec2 detach-volume --force --volume-id $VOLUME_ID

echo "Disassociating Elastic IP..."
aws ec2 disassociate-address --association-id $(aws ec2 describe-addresses --allocation-ids $EIP_ALLOC_ID --query 'Addresses[0].AssociationId' --output text)

echo "Resources cleaned up. Try running 'terraform destroy' again."
EOF
}
