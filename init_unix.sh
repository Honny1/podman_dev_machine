#!/bin/bash
# init_unix.sh - Initialize a podman machine for containers development
#
# Requires: podman 5.x or 6.x
#
# Usage:
#   ./init_unix.sh [options] [machine-name]
#
# Options:
#   -z, --zsh            Install and configure zsh + oh-my-zsh
#   -p, --project-dir    Host directory to bind-mount as ~/projects in the guest
#   -g, --git-config     Copy local ~/.gitconfig (and ~/.gitignore_global) into the guest
#   -h, --help           Show this help message
#
# Examples:
#   ./init_unix.sh                                          # creates "dev" machine, no zsh
#   ./init_unix.sh -z dev                                   # with zsh
#   ./init_unix.sh -z -p ~/projects/containers dev          # zsh + project symlink
#   ./init_unix.sh -g dev                                    # git config
#   ./init_unix.sh -z -g -p ~/projects dev                   # everything
#
# Environment variables:
#   DISK  - disk size in GB (default: 100)
#
# The machine will have:
#   - rhcontainerbot/podman-next Copr repo (latest container stack builds)
#   - All build deps for podman, buildah, netavark, container-libs
#   - Go, Rust, gcc, make, protobuf, -devel libraries
#   - zsh + oh-my-zsh (agnoster theme) auto-launched on SSH (with -z)
#   - Host git config copied into guest (with -g)
#   - SELINUXOPT="" set (needed for builds on virtio-fs mounts)
#   - ~/projects bind-mount of host dir (with -p)
#
# Building podman inside the machine:
#   podman machine ssh dev
#   cd ~/projects/podman   # or wherever your clone is
#   make binaries
#
set -euo pipefail

usage() {
    sed -n '2,/^$/{ s/^# \{0,1\}//; p; }' "$0"
    exit 0
}

if ! command -v podman &>/dev/null; then
    echo "Error: podman is not installed." >&2
    exit 1
fi

PODMAN_VERSION=$(podman --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
PODMAN_MAJOR=${PODMAN_VERSION%%.*}
if [[ "${PODMAN_MAJOR}" -lt 5 || "${PODMAN_MAJOR}" -gt 6 ]]; then
    echo "Error: podman 5.x or 6.x is required (found ${PODMAN_VERSION})." >&2
    exit 1
fi

INSTALL_ZSH=false
COPY_GIT_CONFIG=false
PROJECT_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -z|--zsh)
            INSTALL_ZSH=true
            shift
            ;;
        -g|--git-config)
            COPY_GIT_CONFIG=true
            shift
            ;;
        -p|--project-dir)
            PROJECT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        -*)
            echo "Unknown option: $1" >&2
            echo "Run with --help for usage." >&2
            exit 1
            ;;
        *)
            MACHINE_NAME="$1"
            shift
            ;;
    esac
done

MACHINE_NAME="${MACHINE_NAME:-dev}"

case "$(uname -s)" in
    Darwin)
        CPUS=$(sysctl -n hw.ncpu)
        MEMORY=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 2 ))
        ;;
    Linux)
        CPUS=$(nproc)
        MEMORY=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 / 2 ))
        ;;
    *)
        echo "Error: unsupported OS '$(uname -s)'." >&2
        exit 1
        ;;
esac

DISK="${DISK:-100}"

echo "==> Creating podman dev machine '${MACHINE_NAME}' (cpus=${CPUS}, mem=${MEMORY}MB, disk=${DISK}GB)"

INIT_EXTRA_FLAGS=""
if [[ "${PODMAN_MAJOR}" -ge 6 ]]; then
    INIT_EXTRA_FLAGS="--update-connection=false"
fi

podman machine init "${MACHINE_NAME}" \
    --cpus "${CPUS}" \
    --memory "${MEMORY}" \
    --disk-size "${DISK}" \
    --rootful \
    --now \
    ${INIT_EXTRA_FLAGS}

echo "==> Waiting for machine to be ready..."
until podman machine ssh "${MACHINE_NAME}" "echo ready" 2>/dev/null; do
    sleep 2
done

ZSH_PKGS=""
if $INSTALL_ZSH; then
    ZSH_PKGS="zsh powerline-fonts"
fi

echo "==> Enabling podman-next Copr repo..."
podman machine ssh "${MACHINE_NAME}" "sudo curl -fsSL -o /etc/yum.repos.d/rhcontainerbot-podman-next.repo https://copr.fedorainfracloud.org/coprs/rhcontainerbot/podman-next/repo/fedora-\$(rpm -E %fedora)/rhcontainerbot-podman-next-fedora-\$(rpm -E %fedora).repo"

echo "==> Upgrading base container stack from podman-next..."
podman machine ssh "${MACHINE_NAME}" "sudo rpm-ostree override replace --experimental --from repo=copr:copr.fedorainfracloud.org:rhcontainerbot:podman-next netavark aardvark-dns conmon"

echo "==> Installing developer dependencies..."
podman machine ssh "${MACHINE_NAME}" "sudo rpm-ostree install --allow-inactive \
    golang gcc make automake autoconf libtool pkgconfig redhat-rpm-config \
    rust cargo clippy rustfmt protobuf-compiler protobuf-c protobuf-devel \
    systemd systemd-devel \
    gpgme-devel libassuan-devel libgpg-error-devel libseccomp-devel \
    device-mapper-devel btrfs-progs-devel \
    glib2-devel libselinux-devel ostree-devel libcap-devel libnet-devel glibc-devel \
    glibc-static libblkid-devel shadow-utils-subid-devel \
    fuse3 fuse3-devel fuse-overlayfs composefs sqlite-devel openssl-devel libxml2-devel \
    selinux-policy-devel container-selinux policycoreutils \
    passt bind-utils net-tools iproute-tc nftables \
    git-core go-md2man man-db \
    perl perl-Clone perl-FindBin perl-File-Find \
    pre-commit \
    bats ShellCheck python3-pip codespell \
    attr httpd-tools openssl gnupg2 xfsprogs \
    dbus-daemon dnsmasq firewalld \
    vim-enhanced tmux htop jq curl wget rsync unzip tar xz zip fzf ripgrep bat \
    findutils lsof socat nmap-ncat \
    skopeo buildah runc bzip2 git-daemon \
    ${ZSH_PKGS}"

echo "==> Rebooting machine to apply all changes..."
podman machine stop "${MACHINE_NAME}"
podman machine start "${MACHINE_NAME}" "${INIT_EXTRA_FLAGS}"

echo "==> Waiting for machine to be ready..."
until podman machine ssh "${MACHINE_NAME}" "echo ready" 2>/dev/null; do
    sleep 2
done

podman machine ssh "${MACHINE_NAME}" "sudo ldconfig"

# CoreOS has /root -> /var/roothome symlink which breaks Go path resolution.
# Ensure HOME=/var/roothome so bash and Go getcwd() agree on paths.
echo "==> Ensuring root HOME is /var/roothome (not /root symlink)..."
podman machine ssh "${MACHINE_NAME}" "if [ \"\$(getent passwd root | cut -d: -f6)\" != '/var/roothome' ]; then sudo sed -i 's|:/root:|:/var/roothome:|' /etc/passwd; fi"

echo "==> Installing golangci-lint..."
podman machine ssh "${MACHINE_NAME}" "curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/HEAD/install.sh | sudo sh -s -- -b /usr/local/bin"

if $INSTALL_ZSH; then
    echo "==> Installing oh-my-zsh..."
    podman machine ssh "${MACHINE_NAME}" "git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh && \
        rm -rf ~/.oh-my-zsh/.git && \
        git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions && \
        rm -rf ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions/.git && \
        git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting && \
        rm -rf ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting/.git"
fi

GUEST_HOME=$(podman machine ssh "${MACHINE_NAME}" "echo \$HOME" | tr -d '\r')

if $COPY_GIT_CONFIG; then
    echo "==> Copying git configuration into guest..."
    if [[ -f "${HOME}/.gitconfig" ]]; then
        podman machine cp "${HOME}/.gitconfig" "${MACHINE_NAME}:${GUEST_HOME}/.gitconfig"
    else
        echo "    (no ~/.gitconfig found on host, skipping)"
    fi
    if [[ -f "${HOME}/.gitignore_global" ]]; then
        podman machine cp "${HOME}/.gitignore_global" "${MACHINE_NAME}:${GUEST_HOME}/.gitignore_global"
    fi
    if [[ -f "${HOME}/.git-credentials" ]]; then
        podman machine cp "${HOME}/.git-credentials" "${MACHINE_NAME}:${GUEST_HOME}/.git-credentials"
        podman machine ssh "${MACHINE_NAME}" "chmod 600 ~/.git-credentials"
    fi
fi

TMPDIR_CONF=$(mktemp -d)
trap "rm -rf ${TMPDIR_CONF}" EXIT

if $INSTALL_ZSH; then
    echo "==> Configuring zsh..."
    cat > "${TMPDIR_CONF}/.zshrc" << 'EOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="agnoster"
plugins=(git golang podman docker zsh-autosuggestions zsh-syntax-highlighting)
source $ZSH/oh-my-zsh.sh

export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"
export EDITOR=vim
export SELINUXOPT=""
EOF
    podman machine cp "${TMPDIR_CONF}/.zshrc" "${MACHINE_NAME}:${GUEST_HOME}/.zshrc"
else
    echo "==> Configuring bash environment..."
    cat > "${TMPDIR_CONF}/.bashrc_extra" << 'EOF'

export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"
export EDITOR=vim
export SELINUXOPT=""
EOF
    podman machine cp "${TMPDIR_CONF}/.bashrc_extra" "${MACHINE_NAME}:${GUEST_HOME}/.bashrc_extra"
    podman machine ssh "${MACHINE_NAME}" "cat ~/.bashrc_extra >> ~/.bashrc && rm ~/.bashrc_extra"
fi

if [[ -n "${PROJECT_DIR}" ]]; then
    echo "==> Bind-mounting ${PROJECT_DIR} -> ~/projects on guest..."
    podman machine ssh "${MACHINE_NAME}" "sudo mkdir -p ~/projects && sudo mount --bind '${PROJECT_DIR}' ~/projects && echo '${PROJECT_DIR} ${GUEST_HOME}/projects none bind 0 0' | sudo tee -a /etc/fstab > /dev/null"
fi

if $INSTALL_ZSH; then
    podman machine ssh "${MACHINE_NAME}" "echo '[ -x /bin/zsh ] && exec /bin/zsh' >> ~/.bashrc"
fi

echo ""
echo "==> Dev machine '${MACHINE_NAME}' is ready!"
echo ""
echo "  SSH into it:   podman machine ssh ${MACHINE_NAME}"
if [[ -n "${PROJECT_DIR}" ]]; then
echo "  Projects at:   ~/projects (bind-mount of ${PROJECT_DIR})"
fi
if $COPY_GIT_CONFIG; then
echo "  Git config:    copied from host"
fi
if $INSTALL_ZSH; then
echo "  Shell:         zsh (oh-my-zsh, auto-launched)"
else
echo "  Shell:         bash (use -z to add zsh next time)"
fi
echo "  Start it (it is already started): podman machine start ${MACHINE_NAME} -u=false"
echo "  Stop it:       podman machine stop ${MACHINE_NAME}"
echo "  Remove it:     podman machine rm -f ${MACHINE_NAME}"
