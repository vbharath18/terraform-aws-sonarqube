region             = "us-east-1"
vpc_id             = "vpc-00000000000000000"
subnet_ids         = ["subnet-11111111111111111", "subnet-22222222222222222"]
availability_zones = ["us-east-1a", "us-east-1b"]
lb_cert_domain     = "*.example.com" # must be existing acm cert
lb_domain_name     = "example.com."  # must be public hosted zone
