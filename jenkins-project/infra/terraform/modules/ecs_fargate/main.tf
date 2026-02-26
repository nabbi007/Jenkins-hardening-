data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  count = var.execution_role_arn == null ? 1 : 0

  name               = "${var.project_name}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = {
    Project = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "execution" {
  count = var.execution_role_arn == null ? 1 : 0

  role       = aws_iam_role.execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  count = var.task_role_arn == null ? 1 : 0

  name               = "${var.project_name}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = {
    Project = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = var.backend_log_group_name
  retention_in_days = 30

  tags = {
    Project = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "frontend" {
  name              = var.frontend_log_group_name
  retention_in_days = 30

  tags = {
    Project = var.project_name
  }
}

resource "aws_ecs_cluster" "this" {
  name = var.cluster_name

  tags = {
    Project = var.project_name
  }
}

resource "aws_security_group" "ecs_service" {
  name        = "${var.project_name}-ecs-service-sg"
  description = "Security group for ECS service"
  vpc_id      = var.vpc_id

  tags = {
    Name    = "${var.project_name}-ecs-service-sg"
    Project = var.project_name
  }
}

resource "aws_vpc_security_group_egress_rule" "all_egress" {
  security_group_id = aws_security_group.ecs_service.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

locals {
  execution_role_arn = var.execution_role_arn != null ? var.execution_role_arn : aws_iam_role.execution[0].arn
  task_role_arn      = var.task_role_arn != null ? var.task_role_arn : aws_iam_role.task[0].arn
  ingress_rules = {
    for pair in setproduct(toset(var.allowed_ingress_cidrs), toset(var.public_ingress_ports)) :
    "${pair[0]}:${pair[1]}" => {
      cidr = pair[0]
      port = pair[1]
    }
  }

  container_definitions = [
    {
      name      = var.backend_container_name
      image     = var.backend_image_uri
      essential = true
      cpu       = var.backend_container_cpu
      memory    = var.backend_container_memory
      portMappings = [
        {
          containerPort = var.backend_container_port
          hostPort      = var.backend_container_port
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "NODE_ENV"
          value = "production"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = var.backend_log_group_name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "wget -qO- http://127.0.0.1:3000/api/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 20
      }
    },
    {
      name      = var.frontend_container_name
      image     = var.frontend_image_uri
      essential = true
      cpu       = var.frontend_container_cpu
      memory    = var.frontend_container_memory
      portMappings = [
        {
          containerPort = var.frontend_container_port
          hostPort      = var.frontend_container_port
          protocol      = "tcp"
        }
      ]
      dependsOn = [
        {
          containerName = var.backend_container_name
          condition     = "HEALTHY"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = var.frontend_log_group_name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "wget -qO- http://127.0.0.1/nginx-health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 15
      }
    }
  ]
}

resource "aws_vpc_security_group_ingress_rule" "public_ingress" {
  for_each = local.ingress_rules

  security_group_id = aws_security_group.ecs_service.id
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.port
  ip_protocol       = "tcp"
  to_port           = each.value.port
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.task_family
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.task_cpu)
  memory                   = tostring(var.task_memory)
  execution_role_arn       = local.execution_role_arn
  task_role_arn            = local.task_role_arn
  container_definitions    = jsonencode(local.container_definitions)
}

resource "aws_ecs_service" "this" {
  name                   = var.service_name
  cluster                = aws_ecs_cluster.this.id
  task_definition        = aws_ecs_task_definition.this.arn
  desired_count          = var.desired_count
  launch_type            = "FARGATE"
  platform_version       = "LATEST"
  enable_execute_command = true

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.ecs_service.id]
    assign_public_ip = var.assign_public_ip
  }

  lifecycle {
    ignore_changes = [task_definition]
  }

  depends_on = [
    aws_cloudwatch_log_group.backend,
    aws_cloudwatch_log_group.frontend
  ]
}
