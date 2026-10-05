# State is held by runner01 only. The path is supplied at init by
# scripts/tf-ci.sh (-backend-config=path=...), outside the job workspace that
# every job wipes. See design D7 of golden-template-and-runner-terraform.
terraform {
  backend "local" {}
}
