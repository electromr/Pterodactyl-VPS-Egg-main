#!/bin/sh

# Source common functions and variables
. /common.sh

# Configuration
HOSTNAME="MyVPS"
HISTORY_FILE="${HOME}/.custom_shell_history"
MAX_HISTORY=1000

# Check if not installed
if [ ! -e "/.installed" ]; then
    # Check if rootfs.tar.xz or rootfs.tar.gz exists and remove them if they do
    if [ -f "/rootfs.tar.xz" ]; then
        rm -f "/rootfs.tar.xz"
    fi
    
    if [ -f "/rootfs.tar.gz" ]; then
        rm -f "/rootfs.tar.gz"
    fi
    
    # Wipe the files we downloaded into /tmp previously
    rm -rf /tmp/sbin

    # Add DNS Resolver nameservers to resolv.conf
    printf "nameserver 1.1.1.1\nnameserver 1.0.0.1\n" > /etc/resolv.conf
    
    # Mark as installed.
    touch "/.installed"
fi

# Check if the autorun script exists
if [ ! -e "/autorun.sh" ]; then
    touch /autorun.sh
    chmod +x /autorun.sh
fi

printf "\033c"
printf "${GREEN}Starting..${NC}\n"
sleep 1
printf "\033c"

# Function to handle cleanup on exit
cleanup() {
    log "INFO" "Session ended. Goodbye!" "$GREEN"
    exit 0
}

# Function to get formatted directory
get_formatted_dir() {
    current_dir="$PWD"
    case "$current_dir" in
        "$HOME"*)
            printf "~${current_dir#$HOME}"
        ;;
        *)
            printf "$current_dir"
        ;;
    esac
}

# Function to setup resource masking
setup_resource_masking() {
    # Create /usr/local/bin if it doesn't exist
    mkdir -p /usr/local/bin

    # 1. Mask 'free' command (RAM)
    cat > /usr/local/bin/free <<'EOF'
#!/bin/sh
if [ -z "$SERVER_MEMORY" ] || [ "$SERVER_MEMORY" = "0" ]; then
    /usr/bin/free "$@"
    exit $?
fi

# Convert MB to GB/KiB for display logic if needed, but 'free -h' is standard
# Helper to pretty print memory
MEM_MB=$SERVER_MEMORY
SWAP_MB=$((MEM_MB / 2)) # Assume 50% swap or similar if not defined
MEM_TOTAL=$((MEM_MB * 1024 * 1024))
SWAP_TOTAL=$((SWAP_MB * 1024 * 1024))

# Simplified specific output for 'free -h' matching standard Linux output
# We can't perfectly mock every flag, but we'll cover the default and -h
if echo "$@" | grep -q "\-h"; then
    echo "              total        used        free      shared  buff/cache   available"
    # Pretty print with 'G' or 'M'
    # Simplified approximation using numfmt is ideal but might not be installed.
    # We will just print in GiB if > 1024MB
    
    # Calculate usage (mock random usage)
    USED_MEM=$((MEM_MB / 8))
    FREE_MEM=$((MEM_MB - USED_MEM))
    
    # Use awk/math for simple display is simplest if we want exact formatting
    # For now, just delegating to a simple static formatting based on SERVER_MEMORY
    
    # Let's simple format:
    M_TOT="${MEM_MB}Mi"
    M_USED="${USED_MEM}Mi"
    M_FREE="${FREE_MEM}Mi"
    
    echo "Mem:        $M_TOT       $M_USED       $M_FREE       0.0Ki       0.0Ki       $M_FREE"
    echo "Swap:            0B          0B          0B"
else
    # Default bytes display
    USED=$((MEM_TOTAL / 8))
    FREE=$((MEM_TOTAL - USED))
    echo "              total        used        free      shared  buff/cache   available"
    echo "Mem:     $MEM_TOTAL   $USED   $FREE           0           0   $FREE"
    echo "Swap:             0           0           0"
fi
EOF
    chmod +x /usr/local/bin/free

    # 2. Mask 'nproc' (CPU Cores)
    cat > /usr/local/bin/nproc <<'EOF'
#!/bin/sh
if [ -z "$SERVER_CPU" ] || [ "$SERVER_CPU" = "0" ]; then
    /usr/bin/nproc "$@"
    exit $?
fi
# 100 CPU = 1 Core
CORES=$(( (SERVER_CPU + 99) / 100 ))
echo "$CORES"
EOF
    chmod +x /usr/local/bin/nproc

    # 3. Mask 'lscpu' (CPU Info)
    cat > /usr/local/bin/lscpu <<'EOF'
#!/bin/sh
if [ -z "$SERVER_CPU" ] || [ "$SERVER_CPU" = "0" ]; then
    /usr/bin/lscpu "$@"
    exit $?
fi
CORES=$(( (SERVER_CPU + 99) / 100 ))
echo "Architecture:            x86_64"
echo "CPU op-mode(s):          32-bit, 64-bit"
echo "Address sizes:           46 bits physical, 48 bits virtual"
echo "Byte Order:              Little Endian"
echo "CPU(s):                  $CORES"
echo "On-line CPU(s) list:     0-$((CORES - 1))"
echo "Vendor ID:               AuthenticAMD"
echo "Model name:              Virtual CPU"
echo "CPU MHz:                 2500.000"
echo "Virtualization:          KVM"
echo "Hypervisor vendor:       KVM"
echo "Virtualization type:     full"
EOF
    chmod +x /usr/local/bin/lscpu

    # 4. Mask 'neofetch'
    # We will write a simple neofetch wrapper that calls the real one but filters output or just manually prints
    # Since neofetch is complex, writing a custom "fastfetch/neofetch" style script is often cleaner for these eggs.
    # But let's try to wrap it if installed, or provide our own if not.
    cat > /usr/local/bin/neofetch <<'EOF'
#!/bin/bash
# Check if real neofetch exists elsewhere (e.g. /usr/bin/neofetch)
REAL_NEO=$(command -v neofetch | grep -v "/usr/local/bin/neofetch" | head -n 1)
if [ -z "$REAL_NEO" ] && [ -f "/usr/bin/neofetch" ]; then REAL_NEO="/usr/bin/neofetch"; fi

# Calculate Resources
MEM_TOT_MB="${SERVER_MEMORY:-1024}"
MEM_USED_MB=$((MEM_TOT_MB / 8))
CORES=$(( (${SERVER_CPU:-100} + 99) / 100 ))

# Disk (Try to guess from user quota or just 10GB default if not valid)
# Pterodactyl doesn't strictly give SERVER_DISK env var usually, unless added.
# But we can try to look at df .
DISK_INFO=$(df -hP /home/container | tail -n 1 | awk '{print $2 " / " $4 " (" $5 ")"}')

# Source common for colors if available
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
PURPLE="\033[0;35m"
CYAN="\033[0;36m"
NC="\033[0m"

# Ascii Art
echo -e "${CYAN}            .-/+oossssoo+/-.               ${RED}${USER}@${HOSTNAME}${NC}"
echo -e "${CYAN}        \`:+ssssssssssssssssss+:\`           ${NC}-----------------${NC}"
echo -e "${CYAN}      -+ssssssssssssssssssyyssss+-         ${YELLOW}OS${NC}: Pterodactyl OS Linux x86_64"
echo -e "${CYAN}    .ossssssssssssssssssdMMMNysssso.       ${YELLOW}Host${NC}: VIZORA Node"
echo -e "${CYAN}   /ssssssssssshdmmNNmmyNMMMMhssssss/      ${YELLOW}Kernel${NC}: $(uname -r)"
echo -e "${CYAN}  +ssssssssshmydMMMMMMMNddddyssssssss+     ${YELLOW}Uptime${NC}: $(uptime -p | sed 's/up //')"
echo -e "${CYAN} /sssssssshNMMMyhhyyyyhmNMMMNhssssssss/    ${YELLOW}Packages${NC}: Unknown"
echo -e "${CYAN}.ssssssssdMMMNhsssssssssshNMMMdssssssss.   ${YELLOW}Shell${NC}: bash"
echo -e "${CYAN}+sssshhhyNMMNyssssssssssssyNMMMysssssss+   ${YELLOW}CPU${NC}: Virtual CPU ($CORES) @ 2.50GHz"
echo -e "${CYAN}ossyNMMMNyMMhsssssssssssssshmmmhssssssso   ${YELLOW}Memory${NC}: ${MEM_USED_MB}MiB / ${MEM_TOT_MB}MiB"
echo -e "${CYAN}ossyNMMMNyMMhsssssssssssssshmmmhssssssso   ${YELLOW}Disk${NC}: ${DISK_INFO}"
echo -e "${CYAN}+sssshhhyNMMNyssssssssssssyNMMMysssssss+   ${NC}"
echo -e "${CYAN}.ssssssssdMMMNhsssssssssshNMMMdssssssss.   ${NC}"
echo -e "${CYAN} /sssssssshNMMMyhhyyyyhmNMMMNhssssssss/    ${NC}"
echo ""
EOF
    chmod +x /usr/local/bin/neofetch

}

print_instructions() {
    log "INFO" "Type 'help' to view a list of available custom commands." "$YELLOW"
}

# Function to print prompt
print_prompt() {
    user="$1"
    printf "\n${GREEN}${user}@${HOSTNAME}${NC}:${RED}$(get_formatted_dir)${NC}# "
}

# Function to save command to history
save_to_history() {
    cmd="$1"
    if [ -n "$cmd" ] && [ "$cmd" != "exit" ]; then
        printf "$cmd\n" >> "$HISTORY_FILE"
        # Keep only last MAX_HISTORY lines
        if [ -f "$HISTORY_FILE" ]; then
            tail -n "$MAX_HISTORY" "$HISTORY_FILE" > "$HISTORY_FILE.tmp"
            mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"
        fi
    fi
}

# Function reinstall the OS
reinstall() {    
    log "INFO" "Reinstalling the OS..." "$YELLOW"
    
    find / -mindepth 1 -xdev -delete > /dev/null 2>&1
}

# Function to install wget
install_wget() {
    distro=$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
    
    case "$distro" in
        "debian"|"ubuntu"|"devuan"|"linuxmint"|"kali")
            apt-get update -qq && apt-get install -y -qq wget > /dev/null 2>&1
        ;;
        "void")
            xbps-install -Syu wget > /dev/null 2>&1
        ;;
        "centos"|"fedora"|"rocky"|"almalinux"|"openEuler"|"amzn"|"ol")
            yum install -y -q wget > /dev/null 2>&1
        ;;
        "opensuse"|"opensuse-tumbleweed"|"opensuse-leap")
            zypper install -y -q wget > /dev/null 2>&1
        ;;
        "alpine"|"chimera")
            apk add -q --no-interactive --no-scripts wget > /dev/null 2>&1
        ;;
        "gentoo")
            emerge --sync -q && emerge -q wget > /dev/null 2>&1
        ;;
        "arch")
            pacman -Syu --noconfirm --quiet wget > /dev/null 2>&1
        ;;
        "slackware")
            yes | slackpkg install wget > /dev/null 2>&1
        ;;
        *)
            log "ERROR" "Unsupported distribution: $distro" "$RED"
            return 1
        ;;
    esac
}

# Function to install SSH from the repository
install_ssh() {
    # Check if SSH is already installed
    if [ -f "/usr/local/bin/ssh" ]; then
        log "ERROR" "SSH is already installed." "$RED"
        return 1
    fi

    # Install wget if not found
    if ! command -v wget &> /dev/null; then
        log "INFO" "Installing wget." "$YELLOW"
        install_wget
    fi
    
    log "INFO" "Installing SSH." "$YELLOW"
    
    # Determine the architecture
    arch=$(detect_architecture)
    
    # URL to download the SSH binary
    url="https://github.com/ysdragon/ssh/releases/latest/download/ssh-$arch"
    
    # Download the SSH binary
    wget -q -O /usr/local/bin/ssh "$url" || {
        log "ERROR" "Failed to download SSH." "$RED"
        return 1
    }
    
    # Make the binary executable
    chmod +x /usr/local/bin/ssh || {
        log "ERROR" "Failed to make ssh executable." "$RED"
        return 1
    }    

    log "SUCCESS" "SSH installed successfully." "$GREEN"
}

# Function to show system status
show_system_status() {
    log "INFO" "System Status:" "$GREEN"
    uptime
    free -h
    df -h
    ps aux --sort=-%mem | head -n 10
}

# Function to create a backup
create_backup() {
    # Check if tar is installed
    if ! command -v tar > /dev/null 2>&1; then
        log "ERROR" "tar is not installed. Please install tar first." "$RED"
        return 1
    fi

    backup_file="/backup_$(date +%Y%m%d%H%M%S).tar.gz"
    exclude_file="/tmp/exclude-list.txt"

    # Create a file with a list of patterns to exclude. This is more
    # compatible with different versions of tar, including busybox tar.
    # We use relative paths for exclusion as we'll be running tar from /.
    cat > "$exclude_file" <<EOF
./${backup_file#/}
./proc
./tmp
./dev
./sys
./run
./vps.config
${exclude_file#/}
EOF

    log "INFO" "Starting backup process..." "$YELLOW"
    (cd / && tar --numeric-owner -czf "$backup_file" -X "$exclude_file" .) > /dev/null 2>&1
    log "SUCCESS" "Backup created at $backup_file" "$GREEN"

    # Clean up the exclude file
    rm -f "$exclude_file"
}

# Function to restore a backup
restore_backup() {
    backup_file="$1"

    # Check if tar is installed
    if ! command -v tar > /dev/null 2>&1; then
        log "ERROR" "tar is not installed. Please install tar first." "$RED"
        return 1
    fi

    if [ -z "$backup_file" ]; then
        log "INFO" "Usage: restore <backup_file>" "$YELLOW"
        log "INFO" "Example: restore backup_20250620024221.tar.gz" "$YELLOW"
        return 1
    fi

    if [ -f "/$backup_file" ]; then
        log "INFO" "Starting restore process..." "$YELLOW"
        tar --numeric-owner -xzf "/$backup_file" -C / --exclude="$backup_file" > /dev/null 2>&1
        log "SUCCESS" "Backup restored from $backup_file" "$GREEN"
    else
        log "ERROR" "Backup file not found: $backup_file" "$RED"
    fi
}

# Function to print initial banner
print_banner() {
    print_main_banner
}

# Function to print a beautiful help message
print_help_message() {
    print_help_banner
}

# Function to handle command execution
execute_command() {
    cmd="$1"
    user="$2"
    
    # Save command to history
    save_to_history "$cmd"
    
    # Handle special commands
    case "$cmd" in
        "clear"|"cls")
            printf "\033c"
            print_prompt "$user"
            return 0
        ;;
        "exit")
            cleanup
        ;;
        "history")
            if [ -f "$HISTORY_FILE" ]; then
                cat "$HISTORY_FILE"
            fi
            print_prompt "$user"
            return 0
        ;;
        "reinstall")
            reinstall
            exit 2
        ;;
        "sudo"*|"su"*)
            log "ERROR" "You are already running as root." "$RED"
            print_prompt "$user"
            return 0
        ;;
        "install-ssh")
            install_ssh
            print_prompt "$user"
            return 0
        ;;
        "status")
            show_system_status
            print_prompt "$user"
            return 0
        ;;
        "backup")
            create_backup
            print_prompt "$user"
            return 0
        ;;
        "restore")
            log "ERROR" "No backup file specified. Usage: restore <backup_file>" "$RED"
            print_prompt "$user"
            return 0
        ;;
        "restore "*)
            backup_file=$(echo "$cmd" | cut -d' ' -f2-)
            restore_backup "$backup_file"
            print_prompt "$user"
            return 0
        ;;
        "help")
            print_help_message
            print_prompt "$user"
            return 0
        ;;
        *)
            eval "$cmd"
            print_prompt "$user"
            return 0
        ;;
    esac
}

# Function to run command prompt for a specific user
run_prompt() {
    user="$1"
    read -r cmd
    
    execute_command "$cmd" "$user"
    print_prompt "$user"
}

# Create history file if it doesn't exist
touch "$HISTORY_FILE"

# Set up trap for clean exit
trap cleanup INT TERM

# Setup resource masking
setup_resource_masking

# Print the initial banner
print_banner

# Print the initial instructions
print_instructions

# Print initial command
printf "${GREEN}root@${HOSTNAME}${NC}:${RED}$(get_formatted_dir)${NC}#\n"

# Execute autorun.sh
sh "/autorun.sh"

# Main command loop
while true; do
    run_prompt "user"
done