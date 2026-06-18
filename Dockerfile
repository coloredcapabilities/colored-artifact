FROM ubuntu:focal

ENV TZ=UTC

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    locales

RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

RUN apt update && apt install -y \
    curl \
    wget \
    git \
    vim \
    build-essential \
    unzip \
    pkg-config \
    tzdata \
    python3 \
    autoconf \
    automake \
    cmake \
    ninja-build \
    zlib1g-dev \
    python3-pip \
    libtcl8.6 \
    libelf-dev \
    bc \
    sudo

RUN  pip3 install pyyaml
ARG USERNAME=ubuntu
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN adduser --uid $USER_UID --disabled-password $USERNAME

USER $USERNAME
WORKDIR /home/$USERNAME


# Install BlueSpec compiler (bsc)
ADD --chown=$USERNAME:$USERNAME https://github.com/B-Lang-org/bsc/releases/download/2024.07/bsc-2024.07-ubuntu-20.04.tar.gz ./
RUN tar xzf bsc-2024.07-ubuntu-20.04.tar.gz
RUN ls bsc-2024.07-ubuntu-20.04
ENV PATH="$PATH:/home/$USERNAME/bsc-2024.07-ubuntu-20.04/bin/"
RUN echo $PATH

# Install BlueSpec libraries
RUN git clone https://github.com/B-Lang-org/bsc-contrib.git
RUN cd bsc-contrib && git checkout 17e029843cefb3421913d630b2984a1591d2cb8c && make PREFIX=~/bsc-2024.07-ubuntu-20.04/

WORKDIR /home/$USERNAME/
COPY --chown=$USERNAME:$USERNAME ./patches ./patches

### Let's build Toooba core for baseline
RUN mkdir -p /home/$USERNAME/cheri
WORKDIR /home/$USERNAME/cheri
RUN git clone https://github.com/CTSRD-CHERI/Toooba.git &&  cd Toooba && git checkout a8299cfc01896 && git submodule update --init --recursive
ENV TOOOBA_ROOT=/home/$USERNAME/cheri/Toooba/
RUN sed -i 's/if len (argv \[j:\]) != 0 and isdecimal (argv \[j\]):/if len (argv [j:]) != 0 and argv[j].isdecimal():/; s/if len(argv\[j:\]) != 0 and isdecimal (argv\[j\]):/if len(argv[j:]) != 0 and argv[j].isdecimal():/' ${TOOOBA_ROOT}/Tests/Run_benchmarks.py

WORKDIR ${TOOOBA_ROOT}/builds/RV64ACDFIMSUxCHERI_Toooba_bluesim
RUN make compile && make simulator
RUN cp exe_HW_sim exe_HW_sim_baseline
RUN cp exe_HW_sim.so exe_HW_sim_baseline.so
ENV SIM_BASELINE=/home/$USERNAME/cheri/Toooba/builds/RV64ACDFIMSUxCHERI_Toooba_bluesim/exe_HW_sim_baseline

### Let's build Toooba core for picasso
RUN cd ${TOOOBA_ROOT} && \
    git apply --exclude='Tests/isa/coremark.elf' /home/$USERNAME/patches/toooba_colored.patch && \
    cd ${TOOOBA_ROOT}/libs/cheri-cap-lib/ && \
    git apply /home/$USERNAME/patches/cheri-cap-lib_colored.patch
RUN sed -i 's/Bool verbose = True;/Bool verbose = False;/' ../../src_Core/RISCY_OOO/procs/RV64G_OOO/MemExePipeline.bsv
RUN sed -i 's/Bool verbose = True;/Bool verbose = False;/' ../../src_Core/RISCY_OOO/procs/lib/DTlb.bsv
RUN sed -i 's/Bool verbose = True;/Bool verbose = False;/' ../../src_Core/RISCY_OOO/procs/lib/SplitLSQ.bsv
RUN make compile && make simulator
RUN make -C ${TOOOBA_ROOT}/Tests/elf_to_hex
ENV SIM_PICASSO=/home/$USERNAME/cheri/Toooba/builds/RV64ACDFIMSUxCHERI_Toooba_bluesim/exe_HW_sim

### Setup benchmark scripts and artifact utilities
WORKDIR /home/$USERNAME/
RUN mkdir -p bench/bench_log
COPY --chown=$USERNAME:$USERNAME ./utils_script/mibench/run_mibench.sh ./bench/
COPY --chown=$USERNAME:$USERNAME ./utils_script/mibench/compare_benchmarks.sh ./bench/
RUN chmod +x ./bench/run_mibench.sh ./bench/compare_benchmarks.sh

COPY --chown=$USERNAME:$USERNAME ./utils_script ./utils_script

# Clone blinded-cheri-sw for coremark run/build scripts
WORKDIR /home/$USERNAME/cheri
RUN git clone https://github.com/blindedcapabilities/blinded-cheri-sw.git
ENV BLINDED_SW_ROOT=/home/$USERNAME/cheri/blinded-cheri-sw
# SIM_BLACKOUT is blinded-cheri-sw's name for the patched simulator (= PICASSO)
ENV SIM_BLACKOUT=/home/$USERNAME/cheri/Toooba/builds/RV64ACDFIMSUxCHERI_Toooba_bluesim/exe_HW_sim

# Copy pre-built coremark ELFs into the location blinded-cheri-sw's run script expects
RUN mkdir -p ${BLINDED_SW_ROOT}/benchmarks/coremark
COPY --chown=$USERNAME:$USERNAME ./utils_script/coremark/benchmarks/coremark/coremark_baseline.elf ${BLINDED_SW_ROOT}/benchmarks/coremark/
COPY --chown=$USERNAME:$USERNAME ./utils_script/coremark/benchmarks/coremark/coremark_purecap.elf  ${BLINDED_SW_ROOT}/benchmarks/coremark/

# Wrapper scripts in bench/coremark/ that cd to blinded-cheri-sw root first
# (the build/run scripts use relative paths so must run from the repo root)
WORKDIR /home/$USERNAME/
RUN mkdir -p bench/coremark && \
    printf '#!/bin/sh\ncd %s && sh build_scripts/build_coremark_for_sim.sh "$@"\n' \
        "${BLINDED_SW_ROOT}" > bench/coremark/build_coremark_for_sim.sh && \
    printf '#!/bin/sh\ncd %s && sh build_scripts/run_coremark_for_sim.sh "$@"\n' \
        "${BLINDED_SW_ROOT}" > bench/coremark/run_coremark_for_sim.sh && \
    chmod +x bench/coremark/build_coremark_for_sim.sh \
             bench/coremark/run_coremark_for_sim.sh

USER root
RUN echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/no-passwd && \
    chmod 0440 /etc/sudoers.d/no-passwd
USER $USERNAME

WORKDIR /home/$USERNAME/

CMD ["/bin/bash"]
