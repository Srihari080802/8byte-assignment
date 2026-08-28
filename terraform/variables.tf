variable "aws_region" {
  type        = string
  description = "AWS region where all resources are provisioned"
  default     = "ap-south-1"
}


variable "environment" {
  type        = string
  description = "Deployment environment name"
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  type        = string
  description = "Project name used for resource naming"
  default     = "8byte"
}

variable "vpc_cidr" {
  type        = string
  description = "Describes the CIDR range of the VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Describes the CIDR range of the Public Subnets"
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_app_subnet_cidrs" {
  type        = list(string)
  description = "Describes the CIDR range of the Private App Subnets"
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "private_data_subnet_cidrs" {
  type        = list(string)
  description = "Describes the CIDR range of the Private Data Subnets"
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

variable "container_port" {
  type        = number
  description = "Describes the Container port of ECS"
  default     = 8080
}

variable "db_instance_class" {
  type        = string
  description = "Describes the instance class of rds db"
  default     = "db.t4g.micro"
}

variable "db_username" {
  type        = string
  description = "Describes the username of rds db"
  default     = "appuser"
}

variable "db_name" {
  type        = string
  description = "Describes the name of rds db"
  default     = "appdb"
}

variable "db_allocated_storage" {
  type        = number
  description = "Describes the no of allocated storage of rds db"
  default     = 20
}

