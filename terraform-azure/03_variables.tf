variable "subscription_id" {
  description = "The Azure subscription ID"
  type        = string
}

variable "source_zip" {
  description = "The path to the source zip file"
  type        = string
  default     = "../back/function_app.zip"
}

variable "deploy_registry" {
  type    = bool
  default = false
}

variable "environment" {
  type        = string
  description = "Environnement de déploiement"
  default     = "staging"
}
