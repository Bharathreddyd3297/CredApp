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
    default = {}
}

variable "address_space"{
    type = string
}

variable "aks_subnet_prefix"{
    type = string
}

variable "postgres_subnet_prefix"{
    type = string
}