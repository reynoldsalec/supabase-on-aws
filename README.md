# Supabase on AWS

A version of [timothymamo's](https://github.com/timothymamo) project [supabase-on-do](https://github.com/digitalocean/supabase-on-do), but configured for AWS.

Note that this is a work in progress!

## Running Supabase on AWS

@todo: Add a diagram of the architecture

### Docker Compose

The components that make up Supabase will be running via a [docker-compose.yml](./packer/supabase/docker-compose.yml) file. The following is taken directly from the Supabase [self-hosting documentation](https://supabase.com/docs/guides/self-hosting) page and provides a description of each of its components:

> - [Kong](https://github.com/Kong/kong) is a cloud-native API gateway.
> - [GoTrue](https://github.com/netlify/gotrue) is an SWT based API for managing users and issuing SWT tokens.
> - [PostgREST](http://postgrest.org/) is a web server that turns your PostgreSQL database directly into a RESTful API
> - [Realtime](https://github.com/supabase/realtime) is an Elixir server that allows you to listen to PostgreSQL inserts, updates, and deletes using websockets. Realtime polls Postgres' built-in replication functionality for database changes, converts changes to JSON, then broadcasts the JSON over websockets to authorized clients.
> - [Storage](https://github.com/supabase/storage-api) provides a RESTful interface for managing Files stored in S3, using Postgres to manage permissions.
> - [postgres-meta](https://github.com/supabase/postgres-meta) is a RESTful API for managing your Postgres, allowing you to fetch tables, add roles, and run queries, etc.
> - [PostgreSQL](https://www.postgresql.org/) is an object-relational database system with over 30 years of active development that has earned it a strong reputation for reliability, feature robustness, and performance.

In addition to the above components, the docker-compose file also runs [swag](https://docs.linuxserver.io/general/swag). SWAG (Secure Web Application Gateway) provides an Nginx webserver and reverse proxy with a built-in certbot client that automates free SSL certificate generation and renewal. It also contains [fail2ban](https://www.fail2ban.org/wiki/index.php/Main_Page) for added intrusion prevention. As swag deploys Nginx we will also use it to setup basic authentication to protect access to `studio` (the dashboard component of Supabase).

### AWS Components

All of the above will be running on an AWS [EC2 instance](https://aws.amazon.com/ec2/). Persistent storage for the database is provided via an [EBS volume](https://aws.amazon.com/ebs/) attached to the EC2 instance, and object storage for artifacts like profile pics and more is achieved using [S3](https://aws.amazon.com/s3/). A domain, Elastic IP and Security Group are also set up to ensure we can securely access our Supabase instance from the web.

### SendGrid (Optional)

Supabase's auth component, `GoTrue`, requires the ability to send emails for authentication workflows like password resets. As with most cloud providers, AWS has restrictions on outbound port 25 for new accounts (to prevent spam).

You have two options for email delivery:

#### Option 1: SendGrid
We support using [SendGrid](https://sendgrid.com/), which offers a generous free plan of 100 emails/day that should suffice for most use cases.

To use SendGrid, set `enable_sendgrid = true` and provide a SendGrid API key.

#### Option 2: Amazon SES (Recommended for AWS deployments)
For a fully AWS-integrated solution, you can use [Amazon SES](https://aws.amazon.com/ses/) (Simple Email Service) which provides reliable and cost-effective email sending.

To use SES:
1. Set `enable_ses = true` and `enable_sendgrid = false`
2. Ensure your domain is verified in SES (the module will attempt to set this up if using Route53)
3. If your account is in the SES sandbox, you'll need to verify recipient email addresses

SES advantages:
- Tighter integration with AWS
- Potentially lower costs for high volume
- Better deliverability for AWS-hosted applications

### Packer and Terraform

Infrastructure as Code practices recommend automating as much as possible of our processes. In this regard we will use [Packer](https://www.packer.io/) and [Terraform](https://www.terraform.io/) to automate the build and provision the resources.

## Pre-requisites

- [AWS](https://aws.amazon.com/) account
- [SendGrid](https://app.sendgrid.com/login/) account (Only if you need email functionality)
- [packer cli](https://developer.hashicorp.com/packer/tutorials/docker-get-started/get-started-install-cli)
- [terraform cli](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
- curl installed on your machine
- A Domain you own [added to AWS Route53](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/domain-register.html)

## The Manual Part

- Create an AWS IAM user with the necessary permissions to create resources
- Create a Domain in Route 53 (or use an existing one)
- Create an admin (full access) SendGrid API token ([docs](https://docs.sendgrid.com/for-developers/sending-email/brite-verify#creating-a-new-api-key)) (Only if you need email functionality)
- (_Optional_) If using Terraform Cloud to manage your state file, create a [user API token](https://app.terraform.io/app/settings/tokens)

## The (Semi-)Automated Part
_We're going to run some cli commands within our terminal which can be automated within a CI/CD process._

Once we've setup and created all of the above, clone the repository:
```bash
git clone https://github.com/SprintReviewAI/supabase-on-aws.git
cd supabase-on-aws
```

1. After cloning the repo, our next step is to build an AMI of the EC2 instance we will be running, by following the documentation in the [packer directory](./packer).
2. Finally we will deploy our resources using terraform as specified [here](./terraform).

## _TLDR_
_Or the - I didn't want to read the next sections, just give me the commands to run, I trust you - version_

### Run Packer to create the AMI

```bash
## From the root of the repository change directory to the packer directory
cd packer

## Copy the example file to supabase.auto.pkrvars.hcl, modify it with your own variables and save
cp supabase.auto.pkrvars.hcl.example supabase.auto.pkrvars.hcl
```

```bash
## Initialise packer to download any plugin binaries needed
packer init .

## Build the AMI
packer build .
```

### Run Terraform to create the resources

```bash
## From the root of the repository change directory to the terraform directory
## (from the packer directory  use ../terraform)
cd terraform

## Copy the example file to terraform.tfvars, modify it with your own variables and save
cp terraform.tfvars.example terraform.tfvars
```

```bash
## Initialise terraform to download any plugin binaries needed
terraform init

## Create and show a plan of what will be created
## (skip if you want to apply immediately)
terraform plan

## Apply the changes specified by confirming at the prompt
## (--auto-approve if you're feeling adventures)
terraform apply
```

The apply will create all resources including the ACM certificate with DNS validation; however this can take a while to complete.

```bash
## If you enabled SendGrid, you might need to apply again to verify the SendGrid components
terraform apply
```

### Show generated passwords and tokens for later use

```bash
## Show the generated auth password
terraform output htpasswd

## Show the generated psql password
terraform output psql_pass

## Show the generated jwt secret and tokens
terraform output jwt
terraform output jwt_anon
terraform output jwt_service_role
```

Take a **5-10 min** break and after that point your browser to `supabase.${your-domain}`. When the pop-up asking for your auth details appears enter your provided username and the generated htpasswd.

Enjoy and Happy creating :)

### AWS Authentication

This project uses IAM instance profiles for authentication, which is the AWS recommended practice. This means:

1. No AWS access keys or secret keys are needed in your configuration
2. Terraform will use your environment's AWS credentials (from environment variables or ~/.aws/credentials) to create resources
3. The EC2 instance will use its attached instance profile to authenticate with AWS services (S3, Route53, SES, etc.)

Using instance profiles enhances security by:
- Eliminating the need for long-lived credentials
- Removing the risk of credential exposure in configuration files
- Eliminating credential management and rotation
- Following AWS best practices for service-to-service authentication

When deploying this project:
1. Ensure your AWS CLI is configured with appropriate credentials
2. The terraform commands will use these credentials to create resources
3. The deployed EC2 instance will use its IAM role for all AWS API calls
