plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "proxmox" {
  enabled = true
  version = "0.1.0"
  source  = "github.com/awlsring/tflint-ruleset-proxmox"
}

rule "terraform_naming_convention" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_module_pinned_source" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_typed_variables" {
  enabled = true
}
