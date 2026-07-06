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

variable "aks_node_count"{
    type = number
}

variable "minimum_node_count" {
  type = number
}

variable "maximum_node_count" {
  type = number
}

variable "aks_node_vm_size"{
    type = string
}
variable "aks_subnet_id"{
    type = string
}

variable "log_analytics_workspace_id"{
    type = string
}
