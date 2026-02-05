# CheriBSD Tips

## Compiling for FPGA

```sh
./cheribuild.py cheribsd-mfs-root-kernel-riscv64-purecap \
    --cheribsd-mfs-root-kernel/build-fpga-kernels \
    --cheribsd-mfs-root-kernel/build-bench-kernels \
    -d
```

## Disabling Cornucopia

To disable runtime revocation (Cornucopia):

```sh
sysctl security.cheri.runtime_revocation_default=0
sysctl security.cheri.runtime_revocation_async=0
```

## Enabling Revoke-on-Free

To enable revocation on every free:

```sh
export _RUNTIME_REVOCATION_EVERY_FREE_ENABLE=""
```
