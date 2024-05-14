# main.tf
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  region     = "af-south-1"
  access_key = local.envs["AWS_ACCESS_KEY"]
  secret_key = local.envs["AWS_SECRET_KEY"]
}

# create an ECR repository
resource "aws_ecr_repository" "app-repo" {
  name = "app-repo"
}

# creeate an ecs cluster
resource "aws_ecs_cluster" "app-cluster" {
  name = "app-cluster"
}

# create an IMA role for the task defination
resource "aws_iam_role" "ecsTaskExecutionRole" {
  name               = "ecsTaskExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_policy" {
  role       = aws_iam_role.ecsTaskExecutionRole.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# configuire an ecs task definition
# main.tf
resource "aws_ecs_task_definition" "app_task" {
  family                   = "app_task" # Name your task
  container_definitions    = <<DEFINITION
  [
    {
      "name": "app_task",
      "image": "${aws_ecr_repository.app-repo.repository_url}",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 3000,
          "hostPort": 3000
        }
      ],
       "logConfiguration": {
          "logDriver": "awslogs",
          "options": {
              "awslogs-create-group": "true",
              "awslogs-group": "${aws_ecr_repository.app-repo.registry_id}",
              "awslogs-region": "af-south-1",
              "awslogs-stream-prefix": "aws-docker-logs",
              "mode": "non-blocking",
              "max-buffer-size": "25m"
          }
      },
      "memory": 512,
      "cpu": 256
    }
  ]
  DEFINITION
  requires_compatibilities = ["FARGATE"] # use Fargate as the launch type
  network_mode             = "awsvpc"    # add the AWS VPN network mode as this is required for Fargate
  memory                   = 512         # Specify the memory the container requires
  cpu                      = 256         # Specify the CPU the container requires
  execution_role_arn       = aws_iam_role.ecsTaskExecutionRole.arn


}

# provide a referance to the default vpc
resource "aws_default_vpc" "default_vpc" {
}

# provide a referance to the default subnet
resource "aws_default_subnet" "default_subnet_a" {
  availability_zone = "af-south-1a"
}

# provide a referance to the default subnet
resource "aws_default_subnet" "default_subnet_b" {
  availability_zone = "af-south-1b"
}

# create a load balancer
resource "aws_alb" "application_load_balancer" {
  name               = "test-lb-tf"
  load_balancer_type = "application"
  subnets = [
    aws_default_subnet.default_subnet_a.id,
    aws_default_subnet.default_subnet_b.id
  ]
  security_groups = [aws_security_group.load_balancer_security_group.id]
}

# creating SG for the load balancer
resource "aws_security_group" "load_balancer_security_group" {
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "load-balancer-sg"
  }
}

# configure the load balancer with the VPC networking
resource "aws_lb_target_group" "target_group" {
  name        = "target-group"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_default_vpc.default_vpc.id
}

# configure the load balancer with the VPC networking
resource "aws_lb_listener" "load_balancer_listener" {
  load_balancer_arn = aws_alb.application_load_balancer.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn
  }
}

# create an ecs service
resource "aws_ecs_service" "app_service" {
  name            = "app-first-service"
  cluster         = aws_ecs_cluster.app-cluster.id
  task_definition = aws_ecs_task_definition.app_task.arn
  launch_type     = "FARGATE"
  desired_count   = 3

  load_balancer {
    target_group_arn = aws_lb_target_group.target_group.arn
    container_name   = aws_ecs_task_definition.app_task.family
    container_port   = 3000
  }

  network_configuration {
    subnets = [
      "${aws_default_subnet.default_subnet_a.id}",
      "${aws_default_subnet.default_subnet_b.id}"
    ]
    assign_public_ip = true
    security_groups  = [aws_security_group.service_security_group.id]
  }
}

# access the ecs services iver http while ensuring the vpc is more secure, create a security group that will allow traffic created from the load balancer
resource "aws_security_group" "service_security_group" {
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    # Only allowing traffic in from the load balancer security group
    security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#Log the load balancer app URL
output "app_url" {
  value = aws_alb.application_load_balancer.dns_name
}

locals {
  envs = { for tuple in regexall("(.*)=(.*)", file(".env")) : tuple[0] => sensitive(tuple[1]) }
}
