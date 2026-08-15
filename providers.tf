terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region
  profile = "ha-project"
}

terraform {
  backend "s3" {
    bucket         = "ha-project-tfstate-ahsinmemon"
    key            = "ha-project/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "ha-project-tf-locks"
    encrypt        = true
  }
}
