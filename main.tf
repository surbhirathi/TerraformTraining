provider "azurerm"{
    version = "=2.20.0"
    features{}
}
locals{
    web_server_name = var.environment == "production" ? "${var.web_server_name}-prd" : "${var.web_server_name}-dev"
    build_environment = var.environment == "production" ? "production" : "development"
}
resource "azurerm_resource_group" "web_server_rg" {
    name = var.web_server_rg
    location = var.web_server_location
    tags = {
        environment = local.build_environment
        build-version = var.terraform_script_version
    }
}

resource "azurerm_virtual_network" "web_server_vnet" {
    name = "${var.resource_prefix}-vnet"
    location = var.web_server_location
    resource_group_name = azurerm_resource_group.web_server_rg.name
    address_space = [var.web_server_address_space]
}

/* resource "azurerm_subnet" "web_server_subnet" {
    name = "${var.resource_prefix}-subnet"
    resource_group_name = azurerm_resource_group.web_server_rg.name
    virtual_network_name = azurerm_virtual_network.web_server_vnet.name
    address_prefix = var.web_server_address_prefix
} */
resource "azurerm_subnet" "web_server_subnet" {
    for_each = var.web_server_subnet
    name = each.key
    resource_group_name = azurerm_resource_group.web_server_rg.name
    virtual_network_name = azurerm_virtual_network.web_server_vnet.name
    address_prefix = each.value

}

resource "azurerm_public_ip" "web_server_ip"{
    name = "${var.resource_prefix}-public" 
    location = var.web_server_location
    resource_group_name = azurerm_resource_group.web_server_rg.name
    allocation_method = var.environment == "production" ? "Static" : "Dynamic"
}

resource "azurerm_network_security_group" "web_server_sg" {
    name = "${var.resource_prefix}-nsg"
    location = var.web_server_location
    resource_group_name = azurerm_resource_group.web_server_rg.name
}

resource "azurerm_network_security_rule" "web_server_nsg_rule_rdp"{
    name = "RDP Inbound"
    priority = 100
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range = "*" 
    destination_port_range = "3389"
    source_address_prefix = "*"
    destination_address_prefix = "*"
    resource_group_name = azurerm_resource_group.web_server_rg.name
    network_security_group_name = azurerm_network_security_group.web_server_sg.name 
}

resource "azurerm_network_security_rule" "web_server_nsg_rule_http"{
    name = "HTTP Inbound"
    priority = 110
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range = "*" 
    destination_port_range = "80"
    source_address_prefix = "*"
    destination_address_prefix = "*"
    resource_group_name = azurerm_resource_group.web_server_rg.name
    network_security_group_name = azurerm_network_security_group.web_server_sg.name 
}


resource "azurerm_subnet_network_security_group_association" "web_server_sag"{
    network_security_group_id = azurerm_network_security_group.web_server_sg.id
    subnet_id = azurerm_subnet.web_server_subnet["web-server"].id
}

resource "azurerm_virtual_machine_scale_set" "web_server" {
    name = "${var.resource_prefix}-scale-set" 
    location = var.web_server_location
    resource_group_name = azurerm_resource_group.web_server_rg.name 
    upgrade_policy_mode = "manual"
    sku {
        name = "Standard_B1s"
        tier = "Standard"
        capacity = var.web_server_count
    }
    storage_profile_image_reference {
        publisher = "MicrosoftWindowsServer"
        offer = "WindowsServer"
        sku = "2019-Datacenter"
        version = "latest"
    }
    storage_profile_os_disk{
        name                 = ""
        caching              = "ReadWrite"
        create_option     = "FromImage"
        managed_disk_type = "Standard_LRS"
      }
    os_profile{
        computer_name_prefix = local.web_server_name
        admin_username = "webserver"
        admin_password = "Password@123456"
    }
    os_profile_windows_config {
        provision_vm_agent = true
    }
    network_profile {
        name = "web_server_network_profile"
        primary = true
        ip_configuration {
            name = local.web_server_name
            primary = true
            subnet_id = azurerm_subnet.web_server_subnet["web-server"].id
            load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.web_server_lb_backend_pool.id]
        }
    }
}

resource "azurerm_lb" "web_server_lb"{
    name = "${var.resource_prefix}-lb"
    location = var.web_server_location
    resource_group_name = azurerm_resource_group.web_server_rg.name
    frontend_ip_configuration {
        name                 = "${var.resource_prefix}-lb-frontend-ip"
    public_ip_address_id = azurerm_public_ip.web_server_ip.id

    }
}

resource "azurerm_lb_backend_address_pool" "web_server_lb_backend_pool"{
    name = "${var.resource_prefix}-lb-backend-pool"
    resource_group_name = azurerm_resource_group.web_server_rg.name
    loadbalancer_id = azurerm_lb.web_server_lb.id
}

resource "azurerm_lb_probe" "web_server_lb_http_probe"{
    name = "${var.resource_prefix}-lb-http-probe"
    resource_group_name = azurerm_resource_group.web_server_rg.name
    loadbalancer_id = azurerm_lb.web_server_lb.id
    protocol = "tcp"
    port = "80"
}

resource "azurerm_lb_rule" "web_server_lb_http_rule" {
    name = "${var.resource_prefix}-lb-http-rule"
    resource_group_name = azurerm_resource_group.web_server_rg.name
    loadbalancer_id = azurerm_lb.web_server_lb.id
    protocol = "tcp"
    frontend_port = "80"
    backend_port = "80"
    frontend_ip_configuration_name = "{var.resource_prefix}-lb-frontend_ip"
    probe_id = "azurerm_lb_probe.web_server_lb_http_probe.id"
    backend_address_pool_id = "azurerm_lb_backend_address_pool.web_server_lb_backend_pool.id"
}

