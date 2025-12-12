# YJIT Continuous Benchmarking Infrastructure


## Daily jobs

These are executed daily via GitHub Actions
(see schedules in ../.github/workflow/).


## Setting up 1Password access

There is a helper script `with-op.sh` that uses secrets defined in `op.env` in
order to provide a wrapper around the tools that manipulate the underlying EC2
instances. In order for this to be used, the 1Password CLI must be configured,
and have access to a Vault that contains matching credentials.

1Password CLI can be enabled via the [method in the 1Password
documentation](https://developer.1password.com/docs/cli/get-started/) and the
SSH Agent will need to be configured with access to ssh keys in the Ruby and
Rails Infrastructure Vault.

This can be done by placing the following toml snipped inside
`~/.config/1Password/ssh/agent.toml`

```
[[ssh-keys]]
vault = "Vault Name Here"
```

## Commands

The CLI used by GitHub Actions can also be used locally:

Get info about instances:

    ./with-op.sh bin/run info
                     name     state         address last start time
    yjit-benchmarking-arm   running    <ip address> 2024-10-15 20:32:15 UTC
    yjit-benchmarking-x86   running    <ip address> 2024-10-15 20:32:15 UTC
           yjit-reporting   stopped                 2024-10-15 19:30:56 UTC

Connect (this will start a stopped instance):

    ./with-op.sh bin/run ssh yjit-benchmarking-arm


## Terraform resources

Packer resources need to be built before running any Terraform
but these only need to be built once (or when major upgrades are needed).

After that terraform can be run as often as necessary to update desired state.

To get the necessary secrets from 1password you can use the `with-op.sh` script
to load the secrets defined in `op.env` and then run any subsequent command:

Before terraform can be run, each user must initialize their terraform backends
locally. This can be done as follows:

    ./with-op.sh terraform -chdir=terraform init

This only needs done once, and will establish a connection to S3 and sync any
modules at the correct version specified by the projects lockfiles.

After that terraform can be run as often as necessary to update desired state.

    ./with-op.sh terraform -chdir=terraform apply

If you want to see what changes terraform is planning to make, you can use the
`plan` command to output a full breakdown of the changes terraform will make
when you `apply`.

    ./with-op.sh terraform -chdir=terraform plan

**NOTE** Applying the terraform will leave the instances in a "running" state.
If you don't intend to do anything with them (and you are sure benchmarks aren't
running) you should stop the instances:

    ./with-op.sh bin/run stop


If you just want to rebuild the instances
you can skip some of the other resources with something like:

    ./with-op.sh terraform -chdir=terraform destroy -target=aws_launch_template.yjit-metrics\[\"{x86,arm}\"\]
    ./with-op.sh terraform -chdir=terraform apply


## Packer resources

Packer is used to build new AMIs (and our EBS cache volume).

We can build new AMIs any time we want to upgrade the OS or install new dependencies.
In order to move to new hardware (potentially) all that is required is to build
new instances with terraform.

### x86 AMI

This will produce the AMI that can be used for the Intel x86_64 metal instance.

    ./with-op.sh packer build -only ami-bench.amazon-ebs.yjit-benchmarking.x86 ./packer

### arm AMI

This will produce the AMI that can be used for the Graviton arm64 metal instance.

    ./with-op.sh packer build -only ami-bench.amazon-ebs.yjit-benchmarking.arm ./packer

### YJIT Dev AMI

To create an AMI for less-specific utilities such as reporting aggregation or manually creating personal instances not part of the YJIT benchmarking CI infrastructure:

    ./with-op.sh packer build -only ami-dev.amazon-ebs.yjit-dev.x86 ./packer

### EBS reporting cache volume

This volume has one directory that is not needed by the benchmarking instances:
- A cache dir of previous reports so that the report generator knows what it can skip

This only needs to be created once.

When we need to create a new one we should run this command to create it:

    ./with-op.sh packer build -only reporting-ebs.amazon-ebsvolume.yjit-reporting ./packer

Then we should attach the new volume to the existing reporting instance
and copy the built-yjit-reports cache data to it.
