terraform {
  backend "s3" {
    bucket = "dev-terraform-123412-state"
    key    = "profile-staticweb/terraform.tfstate"
    region = "us-east-1"
    encrypt = true
  }
}   