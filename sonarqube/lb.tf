#--------------------------------------------------------------------
# Get the Route53 domain information so we have the Hosted Zone ID
#--------------------------------------------------------------------
# data "aws_route53_zone" "rt53domain" {
#   name = var.lb_domain_name
# }

#--------------------------------------------------------------------
# Find a certificate issued by (not imported into) ACM
#--------------------------------------------------------------------
# data "aws_acm_certificate" "cert_name" {
#   domain      = var.lb_cert_domain
#   types       = ["AMAZON_ISSUED"]
#   most_recent = true
# }

#--------------------------------------------------------------------
# Route53 Record Set
#--------------------------------------------------------------------
# resource "aws_route53_record" "www" {
#   zone_id = data.aws_route53_zone.rt53domain.zone_id
#   name    = "${var.asg_prefix}.${var.lb_domain_name}"
#   type    = "A"

#   alias {
#     name                   = aws_lb.load_balancer.dns_name
#     zone_id                = aws_lb.load_balancer.zone_id
#     evaluate_target_health = false
#   }
# }

#--------------------------------------------------------------------
# load balancer
#--------------------------------------------------------------------
resource "aws_lb_target_group" "target_group" {
  name     = "${var.asg_prefix}-tg"
  port     = 9000
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  health_check {
    healthy_threshold   = 5
    unhealthy_threshold = 2
    interval            = 30
    matcher             = 200
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
  }
  tags = merge(
    var.common_tags,
    {
      "Name" = "${var.asg_prefix}-tg",
    },
  )
}

resource "aws_lb" "load_balancer" {
  name               = "${var.asg_prefix}-lb"
  internal           = var.lb_internal
  load_balancer_type = "application"
  security_groups    = [aws_security_group.fe_sg.id, aws_security_group.be_sg.id]
  subnets            = var.subnet_ids

  enable_deletion_protection = false

  tags = merge(
    var.common_tags,
    {
      "Name" = "${var.asg_prefix}-lb"
    }
  )
}

resource "aws_lb_listener" "lb_listener" {
  load_balancer_arn = aws_lb.load_balancer.arn
  port              = "80"
  protocol          = "HTTP"
  # ssl_policy        = "ELBSecurityPolicy-2016-08"
  # certificate_arn   = data.aws_acm_certificate.cert_name.arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn
  }
}

#--------------------------------------------------------------------
# security group between load balancer and ec2 instance (backend)
#--------------------------------------------------------------------
resource "aws_security_group" "be_sg" {
  name        = "${var.asg_prefix}-be-sg"
  description = "Allow connections from the load balancer to the container or EC2 instance"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  tags = merge(
    var.common_tags,
    {
      "Name" = "${var.asg_prefix}-be-sg"
    },
  )
}

#--------------------------------------------------------------------
# security group in front of load balancer (frontend)
#--------------------------------------------------------------------
resource "aws_security_group" "fe_sg" {
  name        = "${var.asg_prefix}-fe-sg"
  description = "Allow access to the load balancer"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.common_tags,
    {
      "Name" = "${var.asg_prefix}-fe-sg"
    }
  )
}

resource "aws_security_group_rule" "allow_fe" {
  type        = "ingress"
  from_port   = 80
  to_port     = 80
  protocol    = "tcp"
  cidr_blocks = var.lb_fe_cidrs
  description = "Allow into front door"

  security_group_id = aws_security_group.fe_sg.id
}
