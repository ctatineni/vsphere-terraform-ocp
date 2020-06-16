variable "dependson" {
  type    = list(string)
  default = []
}

variable "helper" {
  type = map(string)
}

variable "helper_public_ip" {
  type = string
}

variable "ssh_private_key" {
  type = string
}

variable "cluster_id" {
  type    = string
  default = null
}

variable "base_domain" {
  type    = string
  default = null
}

variable "private_registry_enabled" {
  type    = string
  default = false
}

variable "docker_username" {
  type    = string
  default = null
}

variable "docker_password" {
  type    = string
  default = null
}

variable "imageRegistry" {
  type    = string
  default = null
}

variable "mcm_hub_url" {
  type    = string
  default = null
}

variable "mcm_username" {
  type    = string
  default = null
}

variable "mcm_password" {
  type    = string
  default = null
}
