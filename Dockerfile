FROM debian
RUN  printf ' \n\
APT::Install-Recommends "0"; \n\
APT::Install-Suggests "0"; \n\
APT::Get::Install-Recommends "0"; \n\
APT::Get::Install-Suggests "0"; \
'     >/etc/apt/apt.conf.d/99norecommend

RUN apt update -y && apt upgrade -y

## Various dependencies
## ESP-IDF dependencies
## https://docs.espressif.com/projects/esp-idf/en/latest/get-started/linux-setup.html
RUN apt install -y  acl             gperf           pv \
                    bash-completion htop            python3-pip \
                    bison           iotop           python3-wheel \
                    bmon            iptraf          rsync \
                    ca-certificates iputils-ping    screen \
                    ccache          less            sudo \
                    clang           lsof            tree \
                    cmake           make            vim \
                    curl            most            wget \
                    dnsutils        mtr-tiny        zlib1g \
                    flex            net-tools \
                    git             psmisc 

## Build LLVM
## based on these build instructions
## http://quickhack.net/nom/blog/2019-05-14-build-rust-environment-for-esp32.html
ENV BUILD_ROOT $(mktemp --directory)
RUN git clone https://github.com/espressif/llvm-project.git --depth 1 ${BUILD_ROOT}/llvm-project
ENV LLVM_BUILD ${BUILD_ROOT}/llvm_build
RUN mkdir -p "${LLVM_BUILD}"
WORKDIR ${LLVM_BUILD}
ENV CC clang
ENV CXX clang++
RUN cmake ../llvm-project/llvm -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD="Xtensa" -DLLVM_TARGETS_TO_BUILD="X86" -DCMAKE_BUILD_TYPE=Release -G "Unix Makefiles"
RUN cmake --build . 

## Build Rust
ENV RUSTUP_HOME=/usr/local
ENV CARGO_HOME=/usr/local
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | bash -s --  --default-toolchain nightly \
                  --profile default \
                  -y \
                  --no-modify-path \ 
                  --component 'rust-src'
## Build LLVM
# WORKDIR ${BUILD_ROOT}
RUN git clone https://github.com/MabezDev/rust-xtensa.git --depth 1
WORKDIR ${BUILD_ROOT}/rust-xtensa
ENV RUST_BUILD ${BUILD_ROOT}/rust_build
RUN mkdir -p ${RUST_BUILD}
RUN ./configure --llvm-root="${LLVM_BUILD}" \
                --enable-parallel-compiler
                --prefix="/usr/local" \ 
                --disable-docs \
                --disable-compiler-docs \
                --disable-ninja \
                --disable-optimize-tests \
                --disable-verbose-tests
                
RUN make --jobs=$(nproc)
RUN make install
# ## Build the compiler
# RUN python ./x.py build
# RUN python ./x.py install
RUN $HOME/.cargo/bin/rustup toolchain link xtensa ${RUST_BUILD}
RUN $HOME/.cargo/bin/rustup run xtensa rustc --print target-list | grep xtensa

# Setup ESP-IDF & esptool
ENV ESP32_IDF /xtensa-esp32-elf
ENV ESP8266_IDF /xtensa-lx106-elf
WORKDIR /
RUN curl --fail --retry 5 https://dl.espressif.com/dl/xtensa-esp32-elf-linux64-1.22.0-80-g6c4433a-5.2.0.tar.gz \
    | tar --extract --gunzip
RUN curl --fail --retry 5 https://dl.espressif.com/dl/xtensa-lx106-elf-linux64-1.22.0-100-ge567ec7-5.2.0.tar.gz \
    | tar --extract --gunzip
RUN pip3 install esptool
	
## Setup Xargo
RUN /usr/local/bin/cargo install xargo
# ENV XARGO_RUST_SRC ${BUILD_ROOT}/rust-xtensa/src
ENV RUSTC /usr/local/bin/rustc

## Setup path
#ENV HOME /root
ENV PATH ${ESP8266_IDF}/bin:${ESP32_IDF}/bin:$PATH

## test build sample project
WORKDIR $(mktemp --directory)
RUN git clone https://github.com/mtnmts/xtensa-rust-quickstart --depth 1 .
RUN xargo build --release
WORKDIR /
# RUN rm -rf /xtensa-rust-quickstart

# Use /etc/bash.bashrc          
RUN rm -f /root/.bashrc /home/*/.basrc /etc/skel/.bashrc

## Build project from /source
WORKDIR $(mktemp --directory)
CMD [ "xargo", "build", "--release" ]
