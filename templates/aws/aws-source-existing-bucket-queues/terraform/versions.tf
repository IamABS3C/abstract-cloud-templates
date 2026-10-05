terraform {
  # 1.10 is the floor where BOTH Terraform and OpenTofu have native S3
  # conditional-write state locking and the built-in test framework, so a
  # module written here runs unmodified on either engine.
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.0+ exposes data.aws_region.region; .name is deprecated.
      version = ">= 6.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }
  }
}
