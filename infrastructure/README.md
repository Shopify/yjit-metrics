# YJIT Continuous Benchmarking Infrastructure


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

This volume has 2 directories that are not needed by the benchmarking instances:
- The yjit-raw/yjit-reports repo where the pages are published
- A cache dir of previous reports so that the report generator knows what it can skip

This only needs to be created once.

When we need to create a new one we should run this command to create it:

    ./with-op.sh packer build -only reporting-ebs.amazon-ebsvolume.yjit-reporting ./packer

Then we should attach the new volume to the existing reporting instance
and copy the built-yjit-reports cache data to it.
