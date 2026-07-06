terraform {
  backend "azurerm" {
    resource_group_name  = "CredPay"
    storage_account_name = "credpaystorageaccount"
    container_name       = "credpaysacontainer"
    key                  = "terraform.tfstate"
  }
}