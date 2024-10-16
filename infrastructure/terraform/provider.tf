terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket  = "yjit-automation"
    key     = "yjit-benchmarking.tfstate"
    region  = "us-east-2"
    encrypt = true
  }
}

provider "aws" {
  region = var.region

  # Use default_tags so that we don't have to put `tags = var.tags` on every resource.
  default_tags {
    tags = var.tags
  }
}
