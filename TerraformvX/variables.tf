#region variable
variable "location" {
  type    = string
  default = "canadacentral"
}

variable "resource_group_name" {
  type    = string
  default = "credpay-rg"
}
#Network Variables
variable "address_space" {
  type    = string
  default = "10.0.0.0/16"
}

variable "aks_subnet_prefix" {
  type    = string
  default = "10.0.1.0/20"
}

variable "postgres_subnet_prefix" {
  type    = string
  default = "10.0.2.0/24"
}

#AKS
variable "aks_node_count" {
  type    = number
  default = 3
}

variable "minimum_node_count" {
  type    = number
  default = 2
}

variable "maximum_node_count" {
  type    = number
  default = 5
}

variable "aks_node_vm_size" {
  type    = string
  default = "Standard_D2alds_v6"
}

#Postgres variables
variable "postgres_version" {
  type    = number
  default = 18
}

variable "post_admin_username" {
  type    = string
  default = "credpayadmin"
}

variable "database_name" {
  type    = string
  default = "credpay"
}

variable "log_rentention_days" {
  type    = number
  default = 30
}
