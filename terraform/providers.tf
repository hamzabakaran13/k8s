provider "aws" {
  region              = var.aws_region

  default_tags {
    tags = {
      Terraform   = "True"
      Environment = "k8s-learning"
    }
  }
}