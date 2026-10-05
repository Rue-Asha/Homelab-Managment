## ADDED Requirements

### Requirement: Infrastructure applies before services deploy

`.github/workflows/deploy.yml` SHALL order its jobs `plan`, `apply`, `deploy`
within one workflow and one concurrency group, so an infrastructure change and a
service change in the same push never run concurrently, and `deploy` starts only
after `apply` succeeded or was skipped. A failed or rejected `apply` SHALL stop
`deploy`.

#### Scenario: A push changes only a service
- **WHEN** a merge touches no file under `terraform/`
- **THEN** `plan` and `apply` are skipped and `deploy` runs
- **proof:** manual (needs a real run)

#### Scenario: A push changes a host and its service
- **WHEN** a merge adds a guest in `hosts.auto.tfvars` and its service playbook inputs
- **THEN** `deploy` starts only after the `apply` job is approved and succeeds
- **proof:** manual (needs a real run)

#### Scenario: The apply is rejected
- **WHEN** the `infrastructure` approval is rejected
- **THEN** no `deploy` job runs for that push
- **proof:** manual (needs a real run)
