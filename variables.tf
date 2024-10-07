variable "os_username" {
  description = "OpenStack username"
  type        = string
}

variable "os_password" {
  description = "OpenStack password"
  type        = string
}

variable "os_region" {
  description = "OpenStack region"
  type        = string
}

variable "key_pair_name" {
  description = "Name of the key pair in Virtuozzo"
  type        = string
}

variable "rhcos_image" {
  description = "Name of the RHCOS image to use for instances"
  type        = string
}

variable "control_plane_flavor" {
  description = "Flavor to use for control plane nodes"
  type        = string
}

variable "worker_flavor" {
  description = "Flavor to use for worker nodes"
  type        = string
}

variable "external_network_id" {
  description = "ID of the external network"
  type        = string
}

variable "bootstrap_flavor" {
  description = "Flavor to use for bootstrap node"
  type        = string
}

variable "floating_ip_pool" {
  description = "Name of the floating IP pool to use"
  type        = string
}