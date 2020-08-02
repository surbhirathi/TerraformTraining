provider "azurerm"{
    version = "=2.20.0"
    features{}
}

resource "azurerm_resource_group" "web_server_rg" {
    name = var.web_server_rg
    location = var.web_server_location
} 
