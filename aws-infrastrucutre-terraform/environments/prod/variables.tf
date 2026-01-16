variable "region" {
  type        = string
  description = "AWS region"
}

variable "account_id" {
  type        = string
  description = "AWS account ID"
}

variable "aws_access_key" {
  type        = string
  description = "AWS Access Key ID"
  sensitive   = true
}

variable "aws_secret_key" {
  type        = string
  description = "AWS Secret Access Key"
  sensitive   = true
}

variable "environment" {
  type = string
}

variable "project" {
  type = string
}

variable "dynamodb_table_name" {
  type = string
}

variable "vpc_cidr_block" {
  type = string
}

variable "subnet_cidr_blocks" {
  type = list(string)
}

variable "availability_zones" {
  type = list(string)
}

variable "ami" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "instance_name" {
  type = string
}

variable "key_name" {
  type = string
}

variable "algorithm" {
  type = string
}

variable "rsa" {
  type = string
}

variable "private_filename" {
  type = string
}

variable "public_filename" {
  type = string
}

variable "security_groups" {
  description = "A list of security group configurations"
  type = list(object({
    name = string,
    ingress_rules = list(object({
      from_port   = number,
      to_port     = number,
      protocol    = string,
      cidr_blocks = list(string),
    })),
    egress_rules = list(object({
      from_port   = number,
      to_port     = number,
      protocol    = string,
      cidr_blocks = list(string),
    })),
  }))
}

variable "db_instance_id" {
  type = string
}

variable "db_name" {
  type = string
}

variable "allocated_storage" {
  type = number
}

variable "storage_type" {
  type = string
}

variable "engine" {
  type = string
}

variable "engine_version" {
  type = string
}

variable "instance_class" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_password" {
  type = string
}

variable "multi_az" {
  type = bool
}

variable "publicly_accessible" {
  type = bool
}

variable "deletion_protection" {
  type = bool
}

variable "backup_retention_period" {
  type = number
}

variable "skip_final_snapshot" {
  type = bool
}

variable "snapshots" {
  type = string
}

variable "storage_encrypted" {
  type = bool
}

variable "db_subnet_group_name" {
  type = string
}

variable "repositories" {
  type = any
}

variable "secrets" {
  type = any
}

variable "iam_secret_name" {
  type = any
}

variable "usernames" {
  type = any
}

variable "iam_user_secrets" {
  type = any
}

variable "iam_policy_statements" {
  type = any
}

variable "role_name1" {
  type = any
}

variable "assume_role_principals1" {
  type = any
}

variable "policy_arns1" {
  type = any
}

variable "role_name2" {
  type = any
}

variable "assume_role_principals2" {
  type = any
}

variable "policy_arns2" {
  type = any
}

variable "role_name3" {
  type = any
}

variable "assume_role_principals3" {
  type = any
}

variable "policy_arns3" {
  type = any
}

variable "role_name4" {
  type = any
}

variable "assume_role_principals4" {
  type = any
}

variable "policy_arns4" {
  type = any
}

variable "role_name5" {
  type = any
}

variable "assume_role_principals5" {
  type = any
}

variable "policy_arns5" {
  type = any
}

variable "role_name6" {
  type = any
}

variable "assume_role_principals6" {
  type = any
}

variable "policy_arns6" {
  type = any
}

variable "role_name7" {
  type = any
}

variable "assume_role_principals7" {
  type = any
}

variable "policy_arns7" {
  type = any
}

variable "role_name17" {
  type = any
}

variable "assume_role_principals17" {
  type = any
}

variable "policy_arns17" {
  type = any
}

variable "role_name18" {
  type = any
}

variable "assume_role_principals18" {
  type = any
}

variable "policy_arns18" {
  type = any
}

variable "role_name19" {
  type = any
}

variable "assume_role_principals19" {
  type = any
}

variable "policy_arns19" {
  type = any
}

variable "role_name20" {
  type = any
}

variable "assume_role_principals20" {
  type = any
}

variable "policy_arns20" {
  type = any
}

variable "role_name21" {
  type = any
}

variable "assume_role_principals21" {
  type = any
}

variable "policy_arns21" {
  type = any
}

variable "role_name22" {
  type = any
}

variable "assume_role_principals22" {
  type = any
}

variable "policy_arns22" {
  type = any
}

variable "role_name23" {
  type = any
}

variable "assume_role_principals23" {
  type = any
}

variable "policy_arns23" {
  type = any
}

variable "role_name24" {
  type = any
}

variable "assume_role_principals24" {
  type = any
}

variable "policy_arns24" {
  type = any
}

variable "role_name25" {
  type = any
}

variable "assume_role_principals25" {
  type = any
}

variable "policy_arns25" {
  type = any
}

variable "role_name26" {
  type = any
}

variable "assume_role_principals26" {
  type = any
}

variable "policy_arns26" {
  type = any
}

variable "role_name27" {
  type = any
}

variable "assume_role_principals27" {
  type = any
}

variable "policy_arns27" {
  type = any
}

variable "role_name28" {
  type = any
}

variable "assume_role_principals28" {
  type = any
}

variable "policy_arns28" {
  type = any
}

variable "role_name29" {
  type = any
}

variable "assume_role_principals29" {
  type = any
}

variable "policy_arns29" {
  type = any
}

variable "role_name30" {
  type = any
}

variable "assume_role_principals30" {
  type = any
}

variable "policy_arns30" {
  type = any
}

variable "role_name32" {
  type = any
}

variable "assume_role_principals32" {
  type = any
}

variable "policy_arns32" {
  type = any
}

variable "role_name33" {
  type = any
}

variable "assume_role_principals33" {
  type = any
}

variable "policy_arns33" {
  type = any
}

variable "role_name34" {
  type = any
}

variable "assume_role_principals34" {
  type = any
}

variable "policy_arns34" {
  type = any
}

variable "role_name35" {
  type = any
}

variable "assume_role_principals35" {
  type = any
}

variable "policy_arns35" {
  type = any
}

variable "role_name36" {
  type = any
}

variable "assume_role_principals36" {
  type = any
}

variable "policy_arns36" {
  type = any
}

variable "role_name37" {
  type = any
}

variable "assume_role_principals37" {
  type = any
}

variable "policy_arns37" {
  type = any
}

variable "role_name38" {
  type = any
}

variable "assume_role_principals38" {
  type = any
}

variable "policy_arns38" {
  type = any
}

variable "role_name39" {
  type = any
}

variable "assume_role_principals39" {
  type = any
}

variable "policy_arns39" {
  type = any
}

variable "alb_name" {
  type = any
}

variable "internal" {
  type = any
}

variable "load_balancer_type" {
  type = any
}

variable "enable_http2" {
  type = any
}

variable "idle_timeout" {
  type = any
}

variable "ip_address_type" {
  type = any
}

variable "enable_cross_zone_load_balancing" {
  type = any
}

variable "port" {
  type = any
}

variable "protocol" {
  type = any
}

variable "ssl_policy" {
  type = any
}

variable "action_type" {
  type = any
}

variable "target_groups" {
  type = any
}

variable "stack_certificate_domain_name" {
  type = any
}

variable "stack_certificate_subject_alternative_names" {
  type = any
}

variable "stack_certificate_validation_method" {
  type = any
}

variable "stack_certificate_key_algorithm" {
  type = any
}

variable "stack_certificate_transparency_logging_preference" {
  type = any
}

variable "listener_rules" {
  type = any
}

variable "ecs_cluster_name" {
  type = any
}

variable "task_definitions" {
  type = any
}

variable "tags" {
  type = any
}

variable "services" {
  type = any
}

variable "desired_count_services" {
  type = any
}

variable "sqs_queues" {
  type = any
}

variable "ecs_rules" {
  type = any
}

variable "lambda_functions_1" {
  type = any
}

variable "lambda_functions" {
  type = any
}

variable "permissions" {
  type = any
}

variable "log_groups" {
  type = any
}

variable "api_name" {
  type = any
}

variable "stage_name" {
  type = any
}

variable "http_method" {
  type = any
}

variable "authorization_type" {
  type = any
}

variable "path_part" {
  type = any
}
