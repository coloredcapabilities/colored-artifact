
# Simulation Test 

To facilitate artifact evaluation, we provide instructions for running the experiments using our Docker images:

```bash
./utils_script/docker_install.sh

# Note: if this is the first installation of Docker, logout from the current shell
#        and login again to enable the "docker" group in the current user
```

After installation, verify that Docker is working correctly by running:
`docker run --rm hello-world` command succeeds. If you get a permission error, make sure [your user is in the "docker" group](https://docs.docker.com/engine/install/linux-postinstall/#manage-docker-as-a-non-root-user)


Our Dockerfile automatically builds all dependencies, including clang, newlib,
and the Bluespec simulation mode of the Toooba core, for both the PICASSO and
baseline configurations. The image requires approximately 14 GB of disk space.

```sh
docker build --network=host  -t picasso .

docker run -i -t picasso
```

## Running MiBench Benchmarks (Simulation)

After starting the Docker container, you can run the MiBench benchmark suite to compare the baseline and PICASSO simulators.

### Quick Start

```sh
# Inside the Docker container
cd /home/ubuntu/cheri/Toooba/builds/RV64ACDFIMSUxCHERI_Toooba_bluesim

# Run benchmarks for baseline
make benchmarks SIM=./exe_HW_sim_baseline
# Results will be in Logs/*.bin.log

# Run benchmarks for PICASSO (PICASSO)
make benchmarks SIM=./exe_HW_sim
```

### Using the Benchmark Scripts

We provide convenient scripts to run and compare benchmarks:

```sh
# Navigate to the artifact directory
cd /home/ubuntu/bench

# Run all MiBench benchmarks for both simulators
./run_mibench.sh
```

### Comparing Results

After running benchmarks, compare the results:

```sh
./compare_benchmarks.sh
```

This generates:
- `bench_log/mibench_comparison.txt` 
- `bench_log/mibench_comparison.tex` 
