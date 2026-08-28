terraform {
  backend "s3" {
    bucket       = "8byte-tfstate-srihari-2026"
    key          = "part1/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true
  }
}
