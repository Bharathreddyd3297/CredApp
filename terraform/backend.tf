
terraform {
  backend "azurerm" {
    resource_group_name  = "CredProj"
    storage_account_name = "credprojstate"
    container_name       = "statefile"
    key                  = "credpay.terraform.tfstate"
  }
}
