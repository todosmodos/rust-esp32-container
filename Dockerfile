ARG CARGO_HOME=/usr/local
ARG CC=clang
ARG CXX=clang++
ARG RUSTUP_HOME=/usr/local


###############################################################################
# https://hub.docker.com/_/debian?tab=tags&page=1&name=buster-slim&ordering=last_updated
FROM debian:buster-slim AS base

ARG  DEBIAN_FRONTEND=noninteractive

COPY etc/ /etc/

RUN  apt update -y \
     && apt upgrade -y \
     && apt install -y  $(cat /etc/apt/install)


###############################################################################
# http://quickhack.net/nom/blog/2019-05-14-build-rust-environment-for-esp32.html
FROM    base AS llvm-project

WORKDIR /tmp/llvm_build

RUN     git clone --depth=1 https://github.com/espressif/llvm-project.git  \
            /tmp/llvm_project

RUN     cmake ../llvm_project/llvm \
              -DCMAKE_BUILD_TYPE=Release \
              -DCMAKE_INSTALL_PREFIX=/usr/local \
              -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD="Xtensa" \
              -DLLVM_INSTALL_UTILS=ON \
              -DLLVM_TARGETS_TO_BUILD="X86" \
              -DLLVM_USE_RELATIVE_PATHS_IN_FILES=ON \
              -DLLVM_USE_RELATIVE_PATHS_IN_DEBUG_INFO=ON \
              -G "Unix Makefiles"

RUN     cmake --build . -- --jobs=$(nproc)

RUN     cmake --build . --target install


###############################################################################
# https://rustc-dev-guide.rust-lang.org/building/how-to-build-and-run.html
FROM    base AS rust-xtensa
COPY    --from=llvm-project  /usr/local/ /usr/local/
ENV     CARGO_HOME=/usr/local
ENV     RUSTUP_HOME=/usr/local
RUN     curl   --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | bash -s --   --default-toolchain nightly \
                       --profile default \
                       -y \
                       --no-modify-path


###############################################################################
WORKDIR /tmp/rust_xtensa

RUN     git clone --depth=1 https://github.com/MabezDev/rust-xtensa.git .

RUN     git submodule status \
        |   awk '{ print $2 }' \
        |   xargs -L1 -i git config -f .gitmodules submodule.{}.shallow true

RUN     ./configure --enable-parallel-compiler \
                    --disable-docs \
                    --disable-compiler-docs \
                    --disable-ninja \
                    --disable-optimize-tests \
                    --disable-codegen-tests \
                    --disable-verbose-tests \
                    --llvm-root="/usr/local" \
                    --prefix="/usr/local/toolchains/xtensa"

RUN     make rustc-stage2 --jobs=$(nproc --ignore=1)

RUN     make install --jobs=$(nproc)
# test xtensa toolchain
RUN     rustup run xtensa rustc --print target-list | grep xtensa

###############################################################################
# https://gitlab.com/lars-thrane-as/ttynvt
# The major/minor number of the device, the address (name/IP) and the port
# number of the serial server must be specified when the application
# is started (command-line options).
# Usage: ttynvt -E -D1  --maj=199 --min=6 --server=172.24.128.1:9991
FROM    base AS ttynvt

ARG     DEBIAN_FRONTEND=noninteractive

WORKDIR /tmp/ttynvt

RUN     apt -y install automake gcc

RUN     git clone --depth=1 https://gitlab.com/lars-thrane-as/ttynvt.git .

RUN     autoreconf -vif && ./configure

RUN     make --jobs=$(nproc) && make install


###############################################################################
FROM    base
COPY    --from=rust-xtensa    /usr/local/ /usr/local/
COPY    --from=ttynvt         /usr/local/ /usr/local/
# https://docs.espressif.com/projects/esp-idf/en/latest/esp32s2/get-started/linux-setup.html
COPY    --from=espressif/idf  /opt/esp/ /opt/esp/

ENV     CARGO_HOME=/usr/local
ENV     RUSTUP_HOME=/usr/local
ENV     IDF_PATH=/opt/esp/idf
ENV     IDF_TOOLS_PATH=/opt/esp
# Use /etc/bash.bashrc
RUN     rm -f /root/.bashrc /home/*/.basrc /etc/skel/.bashrc

RUN     find /usr/local/ \
                -regex '.*bash_completion\.d\/.*' \
                -exec ln --symbolic --force {} /etc/bash_completion.d/ \;
        # && rustup default xtensa \

RUN     for _f in espefuse espsecure esptool; \
        do  update-alternatives --install \
                                /usr/local/bin/$_f \
                                $_f /usr/local/bin/$_f.py 1; \
        done

VOLUME  /build

WORKDIR /build

CMD     [ "cargo", "build", "--release" ]
