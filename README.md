# Moving FitKhel's Terraform state to S3 (one time)

State files used to live on the laptop and in git. They now go to the private,
versioned, encrypted bucket `fitkhel-tfstate-926614722408`, with the lock table
`fitkhel-tf-locks` stopping two applies at once.

Before you start: back up the folder (`cp -R ~/fitkhel ~/fitkhel-backup-$(date +%F)`).

1. Create the bucket and lock table (once):
   cd ~/fitkhel/fitkhel-tfstate
   terraform init && terraform apply

2. In each repo, move its state into S3 (answer "yes" when asked to copy existing
   state, including all workspaces):
   for d in fitkhel-terraform-vpc fitkhel-domain fitkhel-database fitkhel-route53-terraform fitkhel-ecs; do
     (cd ~/fitkhel/$d && terraform init -migrate-state)
   done

3. Check nothing changed in each repo (stay on the leaguesphere-* workspace):
   cd ~/fitkhel/<repo> && terraform workspace show && terraform plan
   The plan should show only the changes you meant to make (see below), never
   resources being recreated.

4. Stop tracking state in git (the files stay on disk as a backup):
   cd ~/fitkhel/<repo>
   git rm -r --cached --ignore-unmatch terraform.tfstate terraform.tfstate.backup terraform.tfstate.d
   git add .gitignore backend.tf && git commit -m "Move Terraform state to S3"
   (State is still in git history; the repos are private. Rotate the JWT secret
   if anyone outside the team ever had access.)

Note: fitkhel-ecs, fitkhel-domain and fitkhel-route53-terraform also have an older
"default" workspace state. It's migrated too, untouched. Always work in the
leaguesphere-* workspace; don't apply in "default".
