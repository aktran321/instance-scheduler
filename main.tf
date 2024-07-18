provider "aws" {
  region = "us-east-1"
}

# VPC
resource "aws_vpc" "instance_control" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostanmes = true
}

# Public Subnet
resource "aws_subnet" "public_1" {
  vpc_id = aws_vpc.instance_control.vpc_id
  cidr_block = "10.0.1.0/24"
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
  subnet_id = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}