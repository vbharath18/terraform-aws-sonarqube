#---------------------------------------------------------------
# cluster
#---------------------------------------------------------------
resource "aws_ecs_cluster" "ecs_cluster" {
  name = var.cluster_name
}

#---------------------------------------------------------------
# task definition
#---------------------------------------------------------------
resource "aws_ecs_task_definition" "task_definition" {
  family             = "${var.asg_prefix}-family"
  execution_role_arn = aws_iam_role.asg_role.arn
  container_definitions = templatefile("${path.module}/task_definition.json.tpl",
    {
      awsAccount     = data.aws_caller_identity.current.account_id,
      awsRegion      = var.region,
      clusterName    = var.cluster_name,
      appOwner       = var.owner,
      appName        = var.application,
      dbName         = var.db_name,
      dbUser         = var.db_user,
      dbPassword     = var.db_ssm_pw_loc,
      dbEndpoint     = aws_db_instance.dbinstance.endpoint,
      taskRoleArn    = aws_iam_role.asg_role.arn,
      taskFamily     = "${var.asg_prefix}-family"
      containerImage = var.container_image
    }
  )
  volume {
    name      = "sonarqube_logs"
    host_path = var.sonarqube_logdir
  }
}

#---------------------------------------------------------------
#service definition
#---------------------------------------------------------------
resource "aws_ecs_service" "service_definition" {
  name            = "${var.asg_prefix}-service"
  iam_role        = aws_iam_role.ecs_service_role.arn
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.task_definition.arn
  desired_count   = 1
  depends_on      = [aws_iam_role.ecs_service_role, aws_lb.load_balancer]

  load_balancer {
    target_group_arn = aws_lb_target_group.target_group.arn
    container_name   = var.cluster_name
    container_port   = 9000
  }
}

#---------------------------------------------------------------
# ecs service role
#---------------------------------------------------------------
resource "aws_iam_role" "ecs_service_role" {
  name               = "ecs-service-role"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.ecs_service_policy.json
  tags = merge(
    var.common_tags,
    {
      "Name" = "${var.asg_prefix}-service-role",
    },
  )
}

data "aws_iam_policy_document" "ecs_service_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecs_container_role_policy_attach" {
  role       = aws_iam_role.ecs_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole"
}

#---------------------------------------------------------------
# ecs log group
#---------------------------------------------------------------
resource "aws_cloudwatch_log_group" "log_group" {
  name              = "sonarqube-ecs-logs"
  retention_in_days = 90
  tags = merge(
    var.common_tags,
    {
      "Name" = "sonarqube-ecs-logs",
    },
  )
}
