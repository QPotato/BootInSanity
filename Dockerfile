FROM debian:bullseye-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        bash coreutils \
        mmdebstrap debootstrap dpkg-dev \
        xorriso isolinux syslinux-common \
        grub-pc-bin grub-efi-amd64-bin grub-common \
        mtools dosfstools \
        squashfs-tools \
        parted \
        partclone \
        zstd xz-utils \
        ca-certificates \
        file kmod \
        rsync \
        sudo \
        procps \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
