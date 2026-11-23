resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

locals {
  appgw_name  = "${var.prefix}-appgw"
  be_pool     = "default-pool"
  be_settings = "default-http-settings"
  listener    = "default-listener"
  fe_port     = "port-80"
  fe_ip       = "public-frontend"
  rule        = "default-rule"
}

# 1. Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}-rg"
  location = var.location
  tags     = var.tags
}

# 2. VNET
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = var.vnet_address_space
  tags                = var.tags
}

resource "azurerm_subnet" "aks" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.aks_subnet_prefix]
}

resource "azurerm_subnet" "appgw" {
  name                 = "appgw-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.appgw_subnet_prefix]
}

# 4. Application Gateway
resource "azurerm_public_ip" "appgw" {
  name                = "${var.prefix}-appgw-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_application_gateway" "appgw" {
  name                = local.appgw_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags

  sku {
    name = "Standard_v2"
    tier = "Standard_v2"
  }

  autoscale_configuration {
    min_capacity = 1
    max_capacity = 3
  }

  gateway_ip_configuration {
    name      = "gateway-ip-config"
    subnet_id = azurerm_subnet.appgw.id
  }

  frontend_port {
    name = local.fe_port
    port = 80
  }

  frontend_ip_configuration {
    name                 = local.fe_ip
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  backend_address_pool {
    name = local.be_pool
  }

  backend_http_settings {
    name                  = local.be_settings
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = local.listener
    frontend_ip_configuration_name = local.fe_ip
    frontend_port_name             = local.fe_port
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.rule
    rule_type                  = "Basic"
    priority                   = 100
    http_listener_name         = local.listener
    backend_address_pool_name  = local.be_pool
    backend_http_settings_name = local.be_settings
  }

  lifecycle {
    ignore_changes = [
      tags,
      backend_address_pool,
      backend_http_settings,
      frontend_port,
      http_listener,
      probe,
      request_routing_rule,
      url_path_map,
      redirect_configuration,
      ssl_certificate,
    ]
  }
}

resource "azurerm_container_registry" "acr" {
  name                = "${replace(var.prefix, "-", "")}acr${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = var.tags
}

# 3. Private AKS with OIDC
resource "azurerm_user_assigned_identity" "aks" {
  name                = "${var.prefix}-aks-identity"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

resource "azurerm_role_assignment" "aks_network" {
  scope                = azurerm_virtual_network.vnet.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.prefix}-aks"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "${var.prefix}-aks"
  sku_tier            = "Free"
  tags                = var.tags

  private_cluster_enabled = true
  private_dns_zone_id     = "System"

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  default_node_pool {
    name                        = "system"
    vm_size                     = var.node_vm_size
    vnet_subnet_id              = azurerm_subnet.aks.id
    auto_scaling_enabled        = true
    min_count                   = var.node_min_count
    max_count                   = var.node_max_count
    temporary_name_for_rotation = "tmpsystem"
    os_disk_size_gb             = 64
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"
    service_cidr      = "10.200.0.0/16"
    dns_service_ip    = "10.200.0.10"
  }

  ingress_application_gateway {
    gateway_id = azurerm_application_gateway.appgw.id
  }

  depends_on = [azurerm_role_assignment.aks_network]
}

locals {
  agic_object_id = azurerm_kubernetes_cluster.aks.ingress_application_gateway[0].ingress_application_gateway_identity[0].object_id
}

resource "azurerm_role_assignment" "agic_appgw" {
  scope                = azurerm_application_gateway.appgw.id
  role_definition_name = "Contributor"
  principal_id         = local.agic_object_id
}

resource "azurerm_role_assignment" "agic_rg" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Reader"
  principal_id         = local.agic_object_id
}

resource "azurerm_role_assignment" "agic_subnet" {
  scope                = azurerm_subnet.appgw.id
  role_definition_name = "Network Contributor"
  principal_id         = local.agic_object_id
}

resource "azurerm_role_assignment" "kubelet_acr_pull" {
  scope                            = azurerm_container_registry.acr.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}
