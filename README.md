# Podman Dev Machine

A script to spin up a Fedora CoreOS podman machine pre-loaded with everything
needed to build and test podman, buildah, netavark, and other container projects.

## Requirements

- **Podman 5.x** installed on the host

## Quick start

**Linux / macOS:**

```bash
./init_unix.sh -z -p /path/to/your/projects dev
```

**Windows (PowerShell):**

```powershell
.\init_windows.ps1 -Zsh -ProjectDir C:\Users\me\projects -MachineName dev
```

This creates a machine named `dev` with zsh and a `~/projects` symlink pointing
to your host directory.

## Usage

### Linux / macOS

```bash
./init_unix.sh [options] [machine-name]
```

| Flag | Description |
| ------ | ------------- |
| `-z`, `--zsh` | Install zsh + oh-my-zsh (agnoster theme, autosuggestions, syntax highlighting) |
| `-p`, `--project-dir <path>` | Any host directory to symlink as `~/projects` in the guest |
| `-g`, `--git-config` | Copy `~/.gitconfig`, `~/.gitignore_global`, and `~/.git-credentials` into the guest |
| `-h`, `--help` | Show help |

| Environment variable | Default | Description |
| ---------------------- | --------- | ------------- |
| `DISK` | `100` | Disk size in GB |

```bash
./init_unix.sh                                       # minimal, bash
./init_unix.sh -z myvm                               # named machine with zsh
./init_unix.sh -z -p /path/to/your/projects dev      # zsh + project dir
DISK=200 ./init_unix.sh dev                           # larger disk
```

### Windows (PowerShell)

```powershell
.\init_windows.ps1 [[-MachineName] <string>] [-Zsh] [-ProjectDir <path>] [-GitConfig] [-Disk <int>]
```

| Parameter | Description |
| ----------- | ------------- |
| `-MachineName` | Machine name (default: `dev`) |
| `-Zsh` | Install zsh + oh-my-zsh |
| `-ProjectDir <path>` | Host directory to symlink as `~/projects` in the guest |
| `-GitConfig` | Copy `~/.gitconfig`, `~/.gitignore_global`, and `~/.git-credentials` into the guest |
| `-Disk <int>` | Disk size in GB (default: `100`) |

```powershell
.\init_windows.ps1                                                    # minimal, bash
.\init_windows.ps1 -Zsh -MachineName myvm                            # named machine with zsh
.\init_windows.ps1 -Zsh -ProjectDir C:\Users\me\projects -MachineName dev  # zsh + project dir
.\init_windows.ps1 -Disk 200 -MachineName dev                        # larger disk
```

## Workflow

### Edit and commit on the host, build and test in the machine

The host directory mounted via `-p` is shared with the guest through virtio-fs.
Use your regular editor, IDE, and git workflow **on the host**. The machine is
only for compiling, running tests, and experimenting.

```text
┌─────────────────────────────┐        ┌─────────────────────────────┐
│            HOST             │        │     GUEST (Fedora CoreOS)   │
│                             │        │                             │
│  Edit code in your IDE      │        │  Build & test only:         │
│  git add / commit / push    │ ───►   │    cd ~/projects/myproject  │
│  Create PRs                 │        │    make binaries            │
│                             │        │    make test                │
│  /path/to/your/projects/    │ virtio │                             │
│    ├── myproject/           │  -fs   │  ~/projects/ is a symlink   │
│    ├── another-repo/        │        │  to the host directory      │
│    └── ...                  │        │                             │
└─────────────────────────────┘        └─────────────────────────────┘
```

**Do not** run `git commit` or `git push` from inside the machine. The guest
does not have your SSH keys or GPG signing setup, and changes made on the host
are immediately visible in the guest — there is no need to sync.

### Connecting to the machine

```bash
podman machine ssh dev
```

### Building inside the machine

```bash
podman machine ssh dev
cd ~/projects/myproject
make binaries
make test
```

## Machine management

```bash
# Start (after host reboot, etc.)
podman machine start dev

# Stop
podman machine stop dev

# Remove completely
podman machine rm -f dev
```

## What gets installed

The machine comes with:

- **Languages**: Go, Rust (cargo, clippy, rustfmt)
- **Build tools**: gcc, make, automake, autoconf, libtool, protobuf-compiler
- **Dev libraries**: gpgme-devel, libseccomp-devel, device-mapper-devel, btrfs-progs-devel, glib2-devel, libselinux-devel, ostree-devel, fuse3-devel, and more
- **Container tools**: skopeo, buildah, runc, slirp4netns, passt (latest from podman-next Copr)
- **Linting & testing**: golangci-lint, ShellCheck, bats, codespell, python3-pip
- **Utilities**: vim, tmux, htop, jq, fzf, ripgrep, bat, curl, wget, rsync
- **Shell (with `-z`)**: zsh, oh-my-zsh, powerline-fonts, zsh-autosuggestions, zsh-syntax-highlighting

The environment is pre-configured with `SELINUXOPT=""` (required for builds on
virtio-fs mounts).
