variable "aws_region" {
    description = "AWS Region To Deploy Into"
    type = string
    default = "us-east-1"
}

variable "vpc_cidr" {
    description = "CIDR block for the VPC"
    type = string
    default = "10.0.0.0/16"
  
}

variable "azs" {
    description = "Availability zones to deploy to"
    type = list(string)
    default = [ "us-east-1a", "us-east-1b" ]
  
}

variable "public_subnet_cidrs" {
    type = list(string)
    default = [ "10.0.1.0/24", "10.0.2.0/24" ]
  
}

variable "private_subnet_cidrs" {
    type = list(string)
    default = [ "10.0.11.0/24", "10.0.12.0/24" ]
  
}

variable "my_ip" {
    description = "Your public IP in CIDR notation, for SSH access"
    type = string
  
}

variable "ami_id" {
    description = "AMI ID for EC2 Instances"
    type = string
  
}

variable "alert_email" {
    description = "Email address for Cloudwatch alarm notifications"
    type = string
  
}