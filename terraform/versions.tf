terraform {
  required_version = ">= 1.16.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.113.1"
    }
  }

  backend "s3" {
    bucket = "rafa-home-server-backups"
    key    = "terraform/proxmox.tfstate"
    region = "us-west-004"

    endpoints = {
      s3 = "https://s3.us-west-004.backblazeb2.com"
    }
    use_path_style               = true
    skip_credentials_validation  = true
    skip_region_validation       = true
    skip_requesting_account_id   = true
    skip_metadata_api_check      = true
    skip_s3_checksum             = true

    # Credentials come from AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY env
    # vars at `terraform init` time - the same B2 application key used
    # elsewhere, not stored here.
  }
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true # self-signed cert on the Proxmox host - flip to false if you've since set up a real one
}
