provider "aws" {
  region = "us-east-1"
}

# VPC
resource "aws_vpc" "instance_control" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

# Public Subnet
resource "aws_subnet" "public_1" {
  vpc_id            = aws_vpc.instance_control.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true
}

# Internet Gateway
resource "aws_internet_gateway" "ig" {
  vpc_id = aws_vpc.instance_control.id
}

# Route Table for Public Subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.instance_control.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ig.id
  }
}

# Route Table Association for Public Subnet
resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

# Create a Security Group
resource "aws_security_group" "my_security_group" {
  vpc_id = aws_vpc.instance_control.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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
}

# Create an EC2 Instance
resource "aws_instance" "my_instance" {
  ami           = "ami-0b72821e2f351e396"  # Amazon Linux 2023
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.my_security_group.id]

  tags = {
    Name = "MyInstance"
  }
}

output "instance_id" {
  value = aws_instance.my_instance.id
}

data "archive_file" "zip_start_function" {
  type        = "zip"
  source_file = "${path.module}/aws_lambda/start_func.py"
  output_path = "${path.module}/aws_lambda/start_func.zip"
}

data "archive_file" "zip_stop_function" {
  type        = "zip"
  source_file = "${path.module}/aws_lambda/stop_func.py"
  output_path = "${path.module}/aws_lambda/stop_func.zip"
}

resource "aws_lambda_function" "start_instance_function" {
  filename         = data.archive_file.zip_start_function.output_path
  source_code_hash = data.archive_file.zip_start_function.output_base64sha256
  function_name    = "start_instance_function"
  handler          = "start_func.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_role.arn

  environment {
    variables = {
      INSTANCE_ID = aws_instance.my_instance.id
    }
  }
}

resource "aws_lambda_function" "stop_instance_function" {
  filename         = data.archive_file.zip_stop_function.output_path
  source_code_hash = data.archive_file.zip_stop_function.output_base64sha256
  function_name    = "stop_instance_function"
  handler          = "stop_func.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_role.arn

  environment {
    variables = {
      INSTANCE_ID = aws_instance.my_instance.id
    }
  }
}
# IAM Role for Lambda Functions
resource "aws_iam_role" "lambda_role" {
  name = "lambda_ec2_control_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

data "aws_caller_identity" "current" {}

# IAM Policy for Lambda to start/stop EC2 instances
resource "aws_iam_role_policy" "lambda_policy" {
  name   = "lambda_policy"
  role   = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ec2:StartInstances",
          "ec2:StopInstances"
        ],
        Resource = "arn:aws:ec2:${data.aws_caller_identity.current.account_id}:instance/${aws_instance.my_instance.id}"
      }
    ]
  })
}

# CloudWatch Event Rule to trigger the start instance Lambda function
resource "aws_cloudwatch_event_rule" "start_instance_rule" {
  name                = "start_instance_rule"
  schedule_expression = "cron(0 8 * * ? *)"  # 8 AM UTC daily
}

resource "aws_cloudwatch_event_target" "start_instance_target" {
  rule      = aws_cloudwatch_event_rule.start_instance_rule.name
  target_id = "startLambda"
  arn       = aws_lambda_function.start_instance_function.arn
}

resource "aws_lambda_permission" "allow_start_instance" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.start_instance_function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.start_instance_rule.arn
}

# CloudWatch Event Rule to trigger the stop instance Lambda function
resource "aws_cloudwatch_event_rule" "stop_instance_rule" {
  name                = "stop_instance_rule"
  schedule_expression = "cron(0 20 * * ? *)"  # 8 PM UTC daily
}

resource "aws_cloudwatch_event_target" "stop_instance_target" {
  rule      = aws_cloudwatch_event_rule.stop_instance_rule.name
  target_id = "stopLambda"
  arn       = aws_lambda_function.stop_instance_function.arn
}

resource "aws_lambda_permission" "allow_stop_instance" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stop_instance_function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.stop_instance_rule.arn
}
