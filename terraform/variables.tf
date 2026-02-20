variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "name" {
  type    = string
  default = "kthw-aws"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  type    = string
  default = "10.0.2.0/24"
}

variable "instance_type_cp" {
  type    = string
  default = "t3.medium"
}

variable "instance_type_wk" {
  type    = string
  default = "t3.medium"
}

# Ko smije pristupiti Kubernetes API (NLB:6443) izvana.
# Stavi svoj public IP /32 (preporuka), npr: "203.0.113.10/32"
variable "allowed_api_cidr" {
  type    = string
  default = "104.30.134.142/32"
}

variable "enable_vpc_endpoints" {
  type    = bool
  default = false
}
