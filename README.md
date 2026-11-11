# Terraform environments (prod now, dev later) and state in S3

## Day to day

In any Terraform repo, the selected **workspace** decides the environment:

| Workspace | Settings file | Used for |
| --- | --- | --- |
| `leaguesphere-vpc`, `-domain`, `-database`, `-route53`, `-ecs` | `env/prod.yaml` | production (selected today) |
| `dev` | `env/dev.yaml` | development, once you have a dev AWS account |

    cd ~/fitkhel/fitkhel-ecs
    terraform workspace show        # check which environment you're on
    terraform plan
    terraform apply

- Settings per environment live in `env/prod.yaml` and `env/dev.yaml` (like tfvars).
- Terraform refuses to run if your AWS credentials are for a different account than
  the file's `account_id`, so dev settings can't touch prod.
- Any other workspace (e.g. `default`) stops with "no file exists at
  env/unknown-workspace-...yaml" - nothing is changed.
- Secret scripts take the environment too: `./put-jwt-secret.sh prod`,
  `./put-cashfree-keys.sh prod`.

## One time: move state from the laptop/git into S3

Back up first: `cp -R ~/fitkhel ~/fitkhel-backup-$(date +%F)`

1. Create the state bucket and lock table:

       cd ~/fitkhel/fitkhel-tfstate && terraform init && terraform apply

2. In each repo (vpc, domain, database, route53-terraform, ecs):

       terraform init -migrate-state      # answer yes to copy every workspace
       terraform plan                     # only intended changes; nothing destroyed/recreated

3. Move the old local state files out of the way and stop tracking them in git:

       mkdir -p .state-backup-before-s3
       mv terraform.tfstate* terraform.tfstate.d .state-backup-before-s3/ 2>/dev/null
       git rm -r --cached --ignore-unmatch terraform.tfstate terraform.tfstate.backup terraform.tfstate.d
       git add -A && git commit -m "Env settings per workspace; state in S3"

## When you have a dev AWS account

1. `aws configure --profile fitkhel-dev`, then put the dev account id in every
   `env/dev.yaml` (`account_id`).
2. In each repo: `terraform workspace new dev`, fill the `REPLACE_` values in
   `env/dev.yaml` from the outputs of the repo before, then `terraform apply`.
   Order: vpc, domain, database, ecs (first push images to the dev ECR and run
   `./put-jwt-secret.sh dev` and `./put-cashfree-keys.sh dev`), route53.
3. Delegate dev.fitkhel.co.in: add an NS record in the prod zone with the name
   servers from `terraform output` in fitkhel-domain (dev workspace).

Dev's state is stored in the same S3 bucket (prod account) under its own key;
the backend uses your default (prod) credentials, the AWS provider uses the
dev profile from env/dev.yaml.
