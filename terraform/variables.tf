variable "prefix" {
  type    = string
  default = "tomato"
}

variable "location" {
  type    = string
  default = "eastasia"
}

variable "vnet_address_space" {
  type    = list(string)
  default = ["10.10.0.0/16"]
}

variable "aks_subnet_prefix" {
  type    = string
  default = "10.10.0.0/22"
}

variable "appgw_subnet_prefix" {
  type    = string
  default = "10.10.8.0/24"
}

variable "node_vm_size" {
  type    = string
  default = "Standard_D2s_v3"
}

variable "node_min_count" {
  type    = number
  default = 1
}

variable "node_max_count" {
  type    = number
  default = 2
}

variable "tags" {
  type = map(string)
  default = {
    project    = "tomato-food-delivery"
    managed_by = "terraform"
  }
}
