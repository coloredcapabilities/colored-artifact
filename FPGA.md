# FPGA Evaluation

# Pre-built Binaries

We provide pre-built bitstreams and binaries under the [`prebuilt`](./prebuilt/bitstreams/) directory.
If you prefer not to build everything manually, skip to [Flashing FPGA and Running Benchmark on CheriBSD](#flashing-fpga-and-running-benchmark-on-cheribsd).

### Manual Building

Set the artifact directory (this repository) so patch paths resolve correctly:

```sh
export ARTIFACT_DIR=~/cheri/Colored_Usenix
```

#### Generate the Bitstreams

##### Baseline Toooba

Clone the CHERI BESSPIN-GFE repository into a new `$GFE_REPO` directory, and replace the Toooba directory with the baseline version:

```sh
git clone https://github.com/CTSRD-CHERI/BESSPIN-GFE.git $GFE_REPO
cd $GFE_REPO
./init_submodules.sh

cd $GFE_REPO/bluespec-processors/P3/Toooba/
git checkout a8299cfc01896
git submodule update --init --recursive
```

Build the Toooba RTL and BESSPIN-GFE bitstream:

```sh
cd $GFE_REPO/bluespec-processors/P3/Toooba/src_SSITH_P3
make compile    # takes a while
cp Verilog_RTL/* xilinx_ip/hdl/
cd $GFE_REPO
./setup_soc_project.sh bluespec_p3
./build.sh bluespec_p3
```

Copy the generated bitstream to the prebuilt directory:

```sh
cp $GFE_REPO/vivado/soc_bluespec_p3/soc_bluespec_p3.runs/impl_1/design_1.bit \
   prebuilt/bitstreams/cheri_baseline/design_1.bit

cp $GFE_REPO/vivado/soc_bluespec_p3/soc_bluespec_p3.runs/impl_1/design_1.ltx \
   prebuilt/bitstreams/cheri_baseline/design_1.ltx
```

##### Colored Toooba

For the Colored Toooba, apply the necessary patches:

```sh
cd $GFE_REPO/bluespec-processors/P3/Toooba/
git apply $ARTIFACT_DIR/patches/toooba_colored.patch
cd $GFE_REPO/bluespec-processors/P3/Toooba/libs/cheri-cap-lib
git apply $ARTIFACT_DIR/patches/cheri-cap-lib_colored.patch
```

Build Toooba RTL and BESSPIN-GFE bitstream:

```sh
cd $GFE_REPO/bluespec-processors/P3/Toooba/src_SSITH_P3
make compile    # takes a while
cp Verilog_RTL/* xilinx_ip/hdl/
cd $GFE_REPO
./setup_soc_project.sh bluespec_p3
./build.sh bluespec_p3
```

Copy the generated bitstream to the prebuilt directory:

```sh
cp $GFE_REPO/vivado/soc_bluespec_p3/soc_bluespec_p3.runs/impl_1/design_1.bit \
   prebuilt/bitstreams/colored_paper/design_1.bit

cp $GFE_REPO/vivado/soc_bluespec_p3/soc_bluespec_p3.runs/impl_1/design_1.ltx \
   prebuilt/bitstreams/colored_paper/design_1.ltx
```

#### Building CheriBSD Kernel and LLVM

[Cheribuild](https://github.com/CTSRD-CHERI/cheribuild) provides a convenient
way to build the CheriBSD kernel, LLVM, and related components.

```sh
git clone https://github.com/CTSRD-CHERI/cheribuild $CHERIBUILD
git apply $ARTIFACT_DIR/patches/cheribuild_colored.diff
```

By default, cheribuild expects the source folder to be at: `~/cheri/`

##### Baseline Kernel 
Clone and build LLVM:

```sh
cd ~/cheri/
git clone git@github.com:CTSRD-CHERI/llvm-project.git
cd $CHERIBUILD
./cheribuild.py llvm-native
```

Build the kernel:

```sh
cd ~/cheri/
git clone git@github.com:CTSRD-CHERI/cheribsd.git
cd ~/cheri/cheribsd
git apply $ARTIFACT_DIR/patches/mrs_base_revoke_count.patch
cd $CHERIBUILD
./cheribuild.py cheribsd-mfs-root-kernel-riscv64-purecap --cheribsd-mfs-root-kernel/build-fpga-kernels --cheribsd-mfs-root-kernel/build-bench-kernels -d
```

The kernel will be output to `~/cheri/output/`.


##### Colored Kernel 
Clone and build LLVM:

```sh
cd ~/cheri/llvm-project
git apply $ARTIFACT_DIR/patches/llvm_colored.diff
cd $CHERIBUILD
./cheribuild.py llvm-native
```

Build the kernel:

```sh
cd ~/cheri/cheribsd
git apply $ARTIFACT_DIR/patches/cheribsd_fpga.diff
cd $CHERIBUILD
./cheribuild.py cheribsd-mfs-root-kernel-riscv64-purecap --cheribsd-mfs-root-kernel/build-fpga-kernels --cheribsd-mfs-root-kernel/build-bench-kernels -d
```

The kernel will be output to `~/cheri/output/`.



### Flashing FPGA and Running Benchmark on CheriBSD

The cheribuild system provides an easy-to-use `vcu118-run.py` script that allows
you to flash the FPGA and run the CheriBSD kernel.

```sh
cd $CHERIBUILD
./vcu118-run.py \
    --bios $HOME/cheri/output/sdk/bbl-gfe/riscv64-purecap/bbl \
    --kernel $HOME/cheri/output/kernel-riscv64-purecap.CHERI-PURECAP-GFE-NODEBUG \
    --gdb $HOME/opt/riscv/bin/riscv64-unknown-elf-gdb \
    --openocd $HOME/opt/bin/openocd
```

Once the system boots into CheriBSD, you can evaluate the benchmark.

### Running Benchmark on Baremetal

#### Loading ELF File to FPGA

Start OpenOCD:

```sh
openocd -f testing/targets/ssith_gfe.cfg
```

Build baremetal benchmark:

```sh
./colored-cheri-sw/baremetal_elf.sh
```

To get the output from terminal:

```sh
socat stdin,raw,echo=0 /dev/ttyUSB2,raw,echo=0
```

Connect to FPGA via GDB:

```sh
riscv64-unknown-elf-gdb some.elf
target remote localhost:3333
load
```

### Setting Up VCU118 and Host SSH Connection

On FPGA:

```sh
ifconfig xae0 inet <FPGA_IP> netmask 255.255.0.0
```

On host:

```sh
sudo ifconfig <DEVICE> <HOST_IP>
```

#### How to increase the disk space on FPGA

```sh
mount -t tmpfs -o size=1000m  tmpfs /bench
```

#### How to transfer file to FPGA
```sh
scp -r -v -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null @SOMEFOLDER root@<FPGA_IP>:/bench/
```