variable "proxmox_endpoint" {
  description = "Proxmox API URL, e.g. https://192.168.1.x:8006/"
  type        = string
}

variable "proxmox_api_token" {
  description = "terraform-bot@pve API token, format: terraform-bot@pve!tf-token=<secret>"
  type        = string
  sensitive   = true
}
