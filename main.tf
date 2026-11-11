# One-time setup: the S3 bucket and lock table that hold Terraform state for
# every FitKhel repo (instead of state files on laptops and in git).
# Run once:  terraform init && terraform apply
# This folder keeps its own small local state (it only describes these two
# resources and holds no secrets); keep it, but don't commit *.tfstate.

terraform {
  required_version = ">= 1.5"
}

provider "aws" {
  region              = "ap-south-1"
  allowed_account_ids = ["926614722408"] # the state bucket lives in the prod account
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "tfstate" {
  bucket = "fitkhel-tfstate-${data.aws_caller_identity.current.account_id}"
  lifecycle {
    prevent_destroy = true # never delete the state of the whole platform by accident
  }
  tags = { App = "fitkhel", Purpose = "terraform-state" }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled" # every state change is kept; a bad apply can be rolled back
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Only HTTPS access to the state bucket.
resource "aws_s3_bucket_policy" "tfstate_tls_only" {
  bucket     = aws_s3_bucket.tfstate.id
  depends_on = [aws_s3_bucket_public_access_block.tfstate]
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.tfstate.arn, "${aws_s3_bucket.tfstate.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

# Stops two people (or two terminals) applying the same repo at once.
resource "aws_dynamodb_table" "locks" {
  name         = "fitkhel-tf-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
  tags = { App = "fitkhel", Purpose = "terraform-locks" }
}

output "state_bucket" {
  value = aws_s3_bucket.tfstate.bucket
}
