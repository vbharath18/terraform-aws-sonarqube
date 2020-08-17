#---------------------------------------------------------------
# project related
#---------------------------------------------------------------
variable "region" {
  description = "The AWS Region where the container will be deployed"
}

variable "vpc_id" {
  description = "The VPC ID where this container will run"
}

variable "availability_zones" {
  description = "The list of availability zones where the container can be deployed"
}

variable "subnet_ids" {
  description = "List of Private Subnets IDs"
}

# variable "lb_cert_domain" {
#   description = "The domain that is represented by the ACM certificate we are using"
# }

# variable "lb_domain_name" {
#   description = "The domain name to be used for the Route53 entry"
# }
