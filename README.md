# Supabase on AWS

[Supabase](https://supabase.com/) is a backend-as-a-service platform built around the Postgres database, and is an Open Source alternative to Firebase. It can reduce time to market by providing a ready to use backend that includes a database with real time capabilities, authentication, object storage and edge functions. You can use Supabase as a service via their [managed offerings](https://supabase.com/pricing) or self-host it on your own server or on a cloud provider.

## Running Supabase on AWS

We will self-host Supabase by deploying the following architecture on AWS.
![Supabase on AWS](./assets/Supabase-on-AWS.png "Supabase on AWS")

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

By default, we use [SendGrid](https://sendgrid.com/) to send emails, which offers a generous free plan of 100 emails/day that should suffice for most use cases. However, SendGrid integration is now optional - you can disable it if:

- You don't need email functionality for your application
- You want to use a different email service provider
- You're just testing Supabase and don't need real email delivery

To disable SendGrid, simply set `enable_sendgrid = false` in your Terraform variables. When disabled, the email functionality in Supabase will be turned off, and you won't need to provide a SendGrid API key.

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

- Create an AWS IAM user with programmatic access and the necessary permissions
- Create an AWS S3 access key and secret
- Create a Domain in Route 53 (or use an existing one)
- Create an admin (full access) SendGrid API token ([docs](https://docs.sendgrid.com/for-developers/sending-email/brite-verify#creating-a-new-api-key)) (Only if you need email functionality)
- (_Optional_) If using Terraform Cloud to manage your state file, create a [user API token](https://app.terraform.io/app/settings/tokens)

## The (Semi-)Automated Part
_We're going to run some cli commands within our terminal which can be automated within a CI/CD process._

Once we've setup and created all of the above, clone the repository:
```bash
git clone https://github.com/yourusername/supabase-on-aws.git
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

## If you enabled SendGrid, apply again to verify the SendGrid components
## (needed as they are created before the domain records in AWS)
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
