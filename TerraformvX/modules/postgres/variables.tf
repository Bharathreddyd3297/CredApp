variable "name_prefix" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "tags" {
    type = map(string)
}

variable "postgres_version"{
    type = number
}

variable "post_admin_username"{
    type = string
}

variable "database_name"{
    type = string
}
