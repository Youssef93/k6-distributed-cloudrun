variable "region" {
  type        = string
  description = "The region in which all resources are deployed"
}

variable "project" {
  type        = string
  description = "Project name on GCP"
}

variable "num-of-tasks" {
  type        = number
  description = "The number of parallel tasks for cloudrun"
}

variable "grafana-port" {
  type        = number
  description = "The port number for grafana"
  default     = 3000
}

variable "DATABASE_USER" {
  type        = string
  description = "Database user"
  default     = "postgres"
}

variable "DATABASE_PASSWORD" {
  type        = string
  description = "Database pw"
}

variable "DATABASE_NAME" {
  type        = string
  description = "Database name"
}

variable "database-disk-size" {
  type        = number
  description = "The disk size (in GB) for the VM instances that will hold the PG database. Minimum valus is 10"
}

variable "add-firewall-rule" {
  type        = bool
  description = "Flag on whether to deployan allow all traffic rule in the vpc"
  default     = true
}

variable "vpc-name" {
  type        = string
  description = "The name of the VPC in which the compute engine instance will be deployed"
  default     = "default"
}

variable "docker-platform" {
  type        = string
  description = "The platform value used to build docker images. Benefitial for whoever is using MacOS with the apple chip"
  default     = null
}
