<#
.SYNOPSIS
    Initialize a podman machine for containers development.

.DESCRIPTION
    Requires: podman 5.x or 6.x

.PARAMETER MachineName
    Name of the podman machine (default: dev)

.PARAMETER Zsh
    Install and configure zsh + oh-my-zsh

.PARAMETER ProjectDir
    Host directory to symlink as ~/projects in the guest

.PARAMETER GitConfig
    Copy local ~/.gitconfig (and ~/.gitignore_global) into the guest

.PARAMETER Disk
    Disk size in GB (default: 100)

.EXAMPLE
    .\init_windows.ps1
.EXAMPLE
    .\init_windows.ps1 -Zsh -MachineName dev
.EXAMPLE
    .\init_windows.ps1 -Zsh -ProjectDir C:\Users\me\projects -MachineName dev
#>

[CmdletBinding()]
param(
    [string]$MachineName = "dev",
    [switch]$Zsh,
    [string]$ProjectDir,
    [switch]$GitConfig,
    [int]$Disk = 100
)

$ErrorActionPreference = "Stop"

# Check podman is installed
$podmanCmd = Get-Command podman -ErrorAction SilentlyContinue
if (-not $podmanCmd) {
    Write-Error "podman is not installed."
}

# Check podman version
$versionOutput = & podman --version
if ($versionOutput -match '(\d+)\.\d+\.\d+') {
    $podmanMajor = [int]$Matches[1]
    $podmanVersion = $Matches[0]
    if ($podmanMajor -lt 5 -or $podmanMajor -gt 6) {
        Write-Error "podman 5.x or 6.x is required (found $podmanVersion)."
    }
} else {
    Write-Error "Could not determine podman version."
}

# Detect system resources
$cpus = (Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
$totalMemMB = [math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB / 2)

Write-Host "==> Creating podman dev machine '$MachineName' (cpus=$cpus, mem=${totalMemMB}MB, disk=${Disk}GB)"

$initArgs = @("machine", "init", $MachineName, "--cpus", $cpus, "--memory", $totalMemMB, "--disk-size", $Disk, "--rootful", "--now")
if ($podmanMajor -ge 6) {
    $initArgs += "--update-connection=false"
}

& podman @initArgs

if ($LASTEXITCODE -ne 0) { Write-Error "podman machine init failed." }

Write-Host "==> Waiting for machine to be ready..."
do {
    $result = & podman machine ssh $MachineName "echo ready" 2>$null
    if ($LASTEXITCODE -ne 0) { Start-Sleep -Seconds 2 }
} until ($LASTEXITCODE -eq 0)

$zshPkgs = ""
if ($Zsh) {
    $zshPkgs = "zsh powerline-fonts"
}

Write-Host "==> Enabling podman-next Copr repo..."
& podman machine ssh $MachineName "sudo curl -fsSL -o /etc/yum.repos.d/rhcontainerbot-podman-next.repo https://copr.fedorainfracloud.org/coprs/rhcontainerbot/podman-next/repo/fedora-`$(rpm -E %fedora)/rhcontainerbot-podman-next-fedora-`$(rpm -E %fedora).repo"

Write-Host "==> Upgrading base container stack from podman-next..."
& podman machine ssh $MachineName "sudo rpm-ostree override replace --experimental --from repo=copr:copr.fedorainfracloud.org:rhcontainerbot:podman-next netavark aardvark-dns conmon"

Write-Host "==> Installing developer dependencies..."
& podman machine ssh $MachineName "sudo rpm-ostree install --allow-inactive golang gcc make automake autoconf libtool pkgconfig redhat-rpm-config rust cargo clippy rustfmt protobuf-compiler protobuf-c protobuf-devel systemd systemd-devel gpgme-devel libassuan-devel libgpg-error-devel libseccomp-devel device-mapper-devel btrfs-progs-devel glib2-devel libselinux-devel ostree-devel libcap-devel libnet-devel glibc-devel glibc-static libblkid-devel shadow-utils-subid-devel fuse3 fuse3-devel fuse-overlayfs composefs sqlite-devel openssl-devel libxml2-devel selinux-policy-devel container-selinux policycoreutils passt bind-utils net-tools iproute-tc nftables git-core go-md2man man-db perl perl-Clone perl-FindBin perl-File-Find pre-commit bats ShellCheck python3-pip codespell attr httpd-tools openssl gnupg2 xfsprogs dbus-daemon dnsmasq firewalld vim-enhanced tmux htop jq curl wget rsync unzip tar xz zip fzf ripgrep bat findutils lsof socat nmap-ncat skopeo buildah runc bzip2 git-daemon $zshPkgs"

if ($LASTEXITCODE -ne 0) { Write-Error "Package installation failed." }

Write-Host "==> Rebooting machine to apply all changes..."
& podman machine stop $MachineName
$startArgs = @("machine", "start", $MachineName)
if ($podmanMajor -ge 6) {
    $startArgs += "--update-connection=false"
}
& podman @startArgs

Write-Host "==> Waiting for machine to be ready..."
do {
    $result = & podman machine ssh $MachineName "echo ready" 2>$null
    if ($LASTEXITCODE -ne 0) { Start-Sleep -Seconds 2 }
} until ($LASTEXITCODE -eq 0)

& podman machine ssh $MachineName "sudo ldconfig"

Write-Host "==> Installing golangci-lint..."
& podman machine ssh $MachineName "curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/HEAD/install.sh | sudo sh -s -- -b /usr/local/bin"

if ($Zsh) {
    Write-Host "==> Installing oh-my-zsh..."
    & podman machine ssh $MachineName "git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh && rm -rf ~/.oh-my-zsh/.git && git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions && rm -rf ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions/.git && git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting && rm -rf ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting/.git"
}

$guestHome = (& podman machine ssh $MachineName "echo `$HOME") -replace "`r",""

if ($GitConfig) {
    Write-Host "==> Copying git configuration into guest..."
    $gitconfigPath = Join-Path $env:USERPROFILE ".gitconfig"
    if (Test-Path $gitconfigPath) {
        & podman machine cp $gitconfigPath "${MachineName}:${guestHome}/.gitconfig"
    } else {
        Write-Host "    (no ~/.gitconfig found on host, skipping)"
    }
    $gitignorePath = Join-Path $env:USERPROFILE ".gitignore_global"
    if (Test-Path $gitignorePath) {
        & podman machine cp $gitignorePath "${MachineName}:${guestHome}/.gitignore_global"
    }
    $gitcredsPath = Join-Path $env:USERPROFILE ".git-credentials"
    if (Test-Path $gitcredsPath) {
        & podman machine cp $gitcredsPath "${MachineName}:${guestHome}/.git-credentials"
        & podman machine ssh $MachineName "chmod 600 ~/.git-credentials"
    }
}

$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("podman-init-" + [System.Guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

try {
    if ($Zsh) {
        Write-Host "==> Configuring zsh..."
        $zshrc = @'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="agnoster"
plugins=(git golang podman docker zsh-autosuggestions zsh-syntax-highlighting)
source $ZSH/oh-my-zsh.sh

export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"
export EDITOR=vim
export SELINUXOPT=""
'@
        $zshrcPath = Join-Path $tmpDir ".zshrc"
        [System.IO.File]::WriteAllText($zshrcPath, $zshrc.Replace("`r`n", "`n"))
        & podman machine cp $zshrcPath "${MachineName}:${guestHome}/.zshrc"
    } else {
        Write-Host "==> Configuring bash environment..."
        $bashExtra = @'

export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"
export EDITOR=vim
export SELINUXOPT=""
'@
        $bashExtraPath = Join-Path $tmpDir ".bashrc_extra"
        [System.IO.File]::WriteAllText($bashExtraPath, $bashExtra.Replace("`r`n", "`n"))
        & podman machine cp $bashExtraPath "${MachineName}:${guestHome}/.bashrc_extra"
        & podman machine ssh $MachineName "cat ~/.bashrc_extra >> ~/.bashrc && rm ~/.bashrc_extra"
    }

    if ($ProjectDir) {
        Write-Host "==> Creating symlink ~/projects -> $ProjectDir on guest..."
        & podman machine ssh $MachineName "ln -sfn '$ProjectDir' ~/projects"
    }

    if ($Zsh) {
        & podman machine ssh $MachineName "echo '[ -x /bin/zsh ] && exec /bin/zsh' >> ~/.bashrc"
    }
} finally {
    Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "==> Dev machine '$MachineName' is ready!"
Write-Host ""
Write-Host "  SSH into it:   podman machine ssh $MachineName"
if ($ProjectDir) {
    Write-Host "  Projects at:   ~/projects (-> $ProjectDir)"
}
if ($GitConfig) {
    Write-Host "  Git config:    copied from host"
}
if ($Zsh) {
    Write-Host "  Shell:         zsh (oh-my-zsh, auto-launched)"
} else {
    Write-Host "  Shell:         bash (use -Zsh to add zsh next time)"
}
Write-Host "  Start it (it is already started): podman machine start $MachineName -u=false"
Write-Host "  Stop it:       podman machine stop $MachineName"
Write-Host "  Remove it:     podman machine rm -f $MachineName"
