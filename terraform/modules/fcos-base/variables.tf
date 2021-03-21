variable "fcos_version" {
    type = string
    description = "The FCOS version to deploy. Version strings are located on https://getfedora.org/coreos/download/"
}

variable "pool" {
    type = string
    description = "Pool to download files to."
    default = "default"
}
