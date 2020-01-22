#---------------------------------------------------------------
# get the latest ami
#---------------------------------------------------------------
data "aws_ami" "linux" {
  most_recent = true
  filter {
    name   = "name"
    values = [var.asg_ami_pattern]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = [var.asg_ami_owner]
}

#---------------------------------------------------------------
# cloud-init components
#---------------------------------------------------------------
data "template_file" "asg_user_data" {
  template = file("${path.module}/user_data.sh.tpl")
  vars = {
    clusterName = var.cluster_name
    logDir      = var.sonarqube_logdir
  }
}

data "template_cloudinit_config" "config" {
  gzip          = true
  base64_encode = true
  part {
    filename     = "user_data.sh"
    content_type = "text/x-shellscript"
    content      = data.template_file.asg_user_data.rendered
  }
}

#---------------------------------------------------------------
# launch template
#---------------------------------------------------------------
resource "aws_launch_template" "asg_template" {
  name_prefix = var.asg_prefix
  description = "Template used to spin up Sonarqube EC2 tweaked instances"

  disable_api_termination = false

  ebs_optimized = true

  iam_instance_profile {
    arn = aws_iam_instance_profile.asg_profile.arn
  }

  image_id = data.aws_ami.linux.id

  instance_initiated_shutdown_behavior = "terminate"

  monitoring {
    enabled = true
  }

  placement {
    tenancy = "default"
  }

  vpc_security_group_ids = [aws_security_group.be_sg.id]

  tag_specifications {
    resource_type = "instance"
    tags          = var.common_tags
  }

  user_data = data.template_cloudinit_config.config.rendered
}

#---------------------------------------------------------------
# auto-scaling group
#---------------------------------------------------------------
resource "aws_autoscaling_group" "asg" {
  availability_zones  = var.availability_zones
  desired_capacity    = var.asg_desired_capacity
  max_size            = var.asg_max_instances
  min_size            = var.asg_min_instances
  vpc_zone_identifier = var.subnet_ids
  enabled_metrics     = ["GroupMinSize", "GroupMaxSize", "GroupDesiredCapacity", "GroupInServiceInstances", "GroupPendingInstances", "GroupStandbyInstances", "GroupTerminatingInstances", "GroupTotalInstances"]
  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = 0
      on_demand_percentage_above_base_capacity = 0
      spot_instance_pools                      = 1
    }
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.asg_template.id
        version            = "$Latest"
      }
      dynamic "override" {
        for_each = var.asg_instance_type
        content {
          instance_type = override.value
        }
      }
    }
  }
  tags = [
    {
      key                 = "Name"
      value               = "${var.asg_prefix}-asg"
      propagate_at_launch = false
    },
    {
      key                 = "Owner"
      value               = var.owner
      propagate_at_launch = false
    },
    {
      key                 = "Application"
      value               = var.application
      propagate_at_launch = false
    }
  ]
}

#---------------------------------------------------------------
# asg instance profile
#---------------------------------------------------------------
resource "aws_iam_instance_profile" "asg_profile" {
  name = "${var.asg_prefix}-asg-profile"
  role = aws_iam_role.asg_role.name
  path = "/"
}

#---------------------------------------------------------------
# asg instance role
#---------------------------------------------------------------
resource "aws_iam_role" "asg_role" {
  name               = "${var.asg_prefix}-asg-role"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.asg_policy.json
  tags = merge(
    var.common_tags,
    {
      "Name" = "${var.asg_prefix}-asg-role",
    }
  )
}

data "aws_iam_policy_document" "asg_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com", "ecs-tasks.amazonaws.com"]
    }
  }
}

# allow ECS to launch containers on this instance
resource "aws_iam_role_policy_attachment" "asg_container_role_policy_attach" {
  role       = aws_iam_role.asg_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# allow ECS to run tasks on this instance
resource "aws_iam_role_policy_attachment" "asg_execution_role_policy_attach" {
  role       = aws_iam_role.asg_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# allow access to RDS
resource "aws_iam_role_policy_attachment" "asg_rds_role_policy_attach" {
  role       = aws_iam_role.asg_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSDataFullAccess"
}

# allow a user to log in via SSM (plus other SSM stuff) because no ssh keys are set
resource "aws_iam_role_policy_attachment" "asg_ssm_role_policy_attach" {
  role       = aws_iam_role.asg_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
}

# allow writes to cloudwatch
resource "aws_iam_role_policy_attachment" "asg_cloudwatch_role_policy_attach" {
  role       = aws_iam_role.asg_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# allow auto-scaling
resource "aws_iam_role_policy_attachment" "asg_autoscale_role_policy_attach" {
  role       = aws_iam_role.asg_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2SpotFleetAutoscaleRole"
}

# allow decrypt password in SSM Parameter Store
# NOTE: that for this to work the password has to be stored at /${var.db_ssm_pw_loc}/
#       and the key is the default aws ssm key
resource "aws_iam_policy" "asg_ssm_access_policy" {
  name        = "${var.asg_prefix}-ssm-access"
  path        = "/"
  description = "Allow this ECS to access SSM"
  policy      = <<EOF
{
     "Version": "2012-10-17",
     "Statement": [
         {
             "Effect": "Allow",
             "Action": [
                 "ssm:DescribeParameters"
             ],
             "Resource": "*"
         },
         {
             "Sid": "Statement1",
             "Effect": "Allow",
             "Action": [
                 "ssm:GetParameters"
             ],
             "Resource": [
                 "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${var.db_ssm_pw_loc}"
             ]
         },
         {
             "Sid": "Statement2",
             "Effect": "Allow",
             "Action": [
                 "kms:Decrypt"
             ],
             "Resource": [
                 "arn:aws:kms:${var.region}:${data.aws_caller_identity.current.account_id}:key/aws/ssm"
             ]
         }
     ]
 }
EOF
}

resource "aws_iam_role_policy_attachment" "asg_ssm_access_policy_attach" {
  role       = aws_iam_role.asg_role.name
  policy_arn = aws_iam_policy.asg_ssm_access_policy.arn
}
