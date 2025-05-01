#!/usr/bin/env bash

# Development Environment Setup Script
# This script sets up a development environment with Ruby, Node.js, PostgreSQL, and Redis
# Compatible with both macOS and Linux systems

set -e # Exit immediately if a command exits with a non-zero status

# Print colorful messages
info() {
  echo -e "\033[0;34m[INFO]\033[0m $1"
}

success() {
  echo -e "\033[0;32m[SUCCESS]\033[0m $1"
}

error() {
  echo -e "\033[0;31m[ERROR]\033[0m $1"
  exit 1
}

warning() {
  echo -e "\033[0;33m[WARNING]\033[0m $1"
}

# Check what OS we're running on
if [[ "$(uname)" == "Darwin" ]]; then
  info "Detected macOS system"
  export IS_MACOS=true
  export IS_LINUX=false
elif [[ "$(uname)" == "Linux" ]]; then
  info "Detected Linux system"
  export IS_MACOS=false
  export IS_LINUX=true
else
  error "Unsupported operating system: $(uname)"
fi

# Check if a command exists
command_exists() {
  command -v "$1" &> /dev/null
}

# Function to install packages on macOS
install_mac() {
  if ! command_exists brew; then
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || error "Failed to install Homebrew"
    success "Homebrew installed successfully"
  else
    info "Homebrew already installed"
  fi
  
  info "Installing $1 with Homebrew..."
  brew install "$1" || error "Failed to install $1"
  success "$1 installed successfully"
}

# Function to install packages on Linux
install_linux() {
  info "Installing $1 with apt..."
  sudo apt update && sudo apt install -y "$1" || error "Failed to install $1"
  success "$1 installed successfully"
}

# Install language version managers and utilities
info "Setting up language version managers..."

# Ruby setup (rbenv)
if ! command_exists rbenv; then
  info "Installing rbenv..."
  if [ "$IS_MACOS" = true ]; then
    install_mac rbenv
  else
    git clone https://github.com/rbenv/rbenv.git ~/.rbenv || error "Failed to clone rbenv repository"
    cd ~/.rbenv && src/configure && make -C src || error "Failed to compile rbenv"
    echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
    echo 'eval "$(rbenv init -)"' >> ~/.bashrc
    # shellcheck source=/dev/null
    source ~/.bashrc
    git clone https://github.com/rbenv/ruby-build.git "$(rbenv root)"/plugins/ruby-build || error "Failed to install ruby-build"
  fi
  success "rbenv installed successfully"
else
  info "rbenv already installed"
fi

# Node.js setup (nvm)
if ! command_exists nvm; then
  info "Installing nvm..."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash || error "Failed to install nvm"
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  success "nvm installed successfully"
else
  info "nvm already installed"
fi

# Install the latest Node.js version
info "Installing the latest Node.js version..."
if command_exists nvm; then
  nvm install || error "Failed to install Node.js"
  nvm use || error "Failed to use the installed Node.js version"
  success "Node.js installed successfully"
fi

# Yarn setup
if ! command_exists yarn; then
  info "Installing yarn..."
  npm install -g yarn || error "Failed to install yarn"
  corepack enable || warning "Could not enable corepack"
  success "Yarn installed successfully"
else
  info "yarn already installed"
fi

# Install Ruby gems
info "Installing overmind gem..."
if command_exists gem; then
  gem install overmind || error "Failed to install overmind gem"
  success "overmind gem installed successfully"
fi

# Database setup
info "Setting up databases..."

# PostgreSQL setup
if [ "$IS_MACOS" = true ]; then
  if ! command_exists psql; then
    info "Installing PostgreSQL with Homebrew..."
    install_mac postgresql@17
    brew services start postgresql@17 || error "Failed to start PostgreSQL service"
  else
    info "PostgreSQL already installed"
  fi

  # Configure trust authentication on macOS
  info "Configuring PostgreSQL trust authentication..."
  PG_CONF_DIR="$(brew --prefix)/var/postgresql@17"
  PG_HBA_CONF="$PG_CONF_DIR/pg_hba.conf"
  
  if [ -f "$PG_HBA_CONF" ]; then
    # Backup the original configuration
    cp "$PG_HBA_CONF" "${PG_HBA_CONF}.bak" || warning "Could not backup pg_hba.conf"
    
    # Update authentication method to trust for local connections
    sed -i.bak 's/\(local.*all.*all.*\)md5/\1trust/g' "$PG_HBA_CONF" || warning "Could not update local connections"
    sed -i.bak 's/\(host.*all.*all.*127.0.0.1\/32.*\)md5/\1trust/g' "$PG_HBA_CONF" || warning "Could not update IPv4 connections"
    sed -i.bak 's/\(host.*all.*all.*::1\/128.*\)md5/\1trust/g' "$PG_HBA_CONF" || warning "Could not update IPv6 connections"
    
    # Restart PostgreSQL to apply changes
    brew services restart postgresql@17 || warning "Could not restart PostgreSQL service"
    success "PostgreSQL configured with trust authentication"
  else
    warning "Could not find pg_hba.conf at $PG_HBA_CONF"
  fi
  
  # Create PostgreSQL user that matches system user on macOS
  info "Creating PostgreSQL user to match system user..."
  CURRENT_USER="$(whoami)"
  if psql -d postgres -c "SELECT 1 FROM pg_roles WHERE rolname='$CURRENT_USER'" | grep -q 1; then
    info "PostgreSQL user '$CURRENT_USER' already exists"
  else
    psql -d postgres -c "CREATE USER $CURRENT_USER SUPERUSER;" || warning "Could not create PostgreSQL user '$CURRENT_USER'"
    psql -d postgres -c "CREATE DATABASE $CURRENT_USER OWNER $CURRENT_USER;" || warning "Could not create database for '$CURRENT_USER'"
    success "Created PostgreSQL user and database '$CURRENT_USER'"
  fi
else
  info "Installing PostgreSQL on Linux..."
  sudo apt install -y postgresql-common || error "Failed to install postgresql-common"
  sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh || error "Failed to run PostgreSQL repository setup"
  sudo apt update
  sudo apt install -y postgresql-17 postgresql-client-17 libpq-dev || error "Failed to install PostgreSQL 17"
  sudo systemctl enable postgresql || warning "Failed to enable PostgreSQL service"
  sudo systemctl start postgresql || warning "Failed to start PostgreSQL service"
  
  # Configure trust authentication on Linux
  info "Configuring PostgreSQL trust authentication..."
  PG_VERSION=17
  PG_HBA_CONF="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"
  
  if [ -f "$PG_HBA_CONF" ]; then
    # Backup the original configuration
    sudo cp "$PG_HBA_CONF" "${PG_HBA_CONF}.bak" || warning "Could not backup pg_hba.conf"
    
    # Update authentication method to trust for local connections
    sudo sed -i 's/\(local.*all.*all.*\)peer/\1trust/g' "$PG_HBA_CONF" || warning "Could not update local connections"
    sudo sed -i 's/\(host.*all.*all.*127.0.0.1\/32.*\)md5/\1trust/g' "$PG_HBA_CONF" || warning "Could not update IPv4 connections"
    sudo sed -i 's/\(host.*all.*all.*::1\/128.*\)md5/\1trust/g' "$PG_HBA_CONF" || warning "Could not update IPv6 connections"
    
    # Restart PostgreSQL to apply changes
    sudo systemctl restart postgresql || warning "Could not restart PostgreSQL service"
    success "PostgreSQL configured with trust authentication"
  else
    warning "Could not find pg_hba.conf at $PG_HBA_CONF"
  fi
  
  # Create PostgreSQL user that matches system user on Linux
  info "Creating PostgreSQL user to match system user..."
  CURRENT_USER="$(whoami)"
  if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$CURRENT_USER'" | grep -q 1; then
    info "PostgreSQL user '$CURRENT_USER' already exists"
  else
    sudo -u postgres psql -c "CREATE USER $CURRENT_USER SUPERUSER;" || warning "Could not create PostgreSQL user '$CURRENT_USER'"
    sudo -u postgres psql -c "CREATE DATABASE $CURRENT_USER OWNER $CURRENT_USER;" || warning "Could not create database for '$CURRENT_USER'"
    success "Created PostgreSQL user and database '$CURRENT_USER'"
  fi
  
  success "PostgreSQL installed successfully"
fi

# Install libicu-dev for Unicode support
if [ "$IS_MACOS" = true ]; then
  install_mac icu4c
else
  install_linux libicu-dev
fi

# Redis setup
if [ "$IS_MACOS" = true ]; then
  if ! command_exists redis-server; then
    info "Installing Redis with Homebrew..."
    install_mac redis
    brew services start redis || error "Failed to start Redis service"
  else
    info "Redis already installed"
  fi
else
  info "Installing Redis on Linux..."
  sudo apt install lsb-release curl gpg -y || error "Failed to install prerequisites for Redis"
  curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg || error "Failed to download Redis GPG key"
  sudo chmod 644 /usr/share/keyrings/redis-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list
  sudo apt update
  sudo apt install -y redis || error "Failed to install Redis"
  sudo systemctl enable redis-server || warning "Failed to enable Redis service"
  sudo systemctl start redis-server || warning "Failed to start Redis service"
  success "Redis installed successfully"
fi

success "All development dependencies have been installed!"
info "You may need to restart your terminal or run 'source ~/.bashrc' (or ~/.zshrc) to use rbenv and nvm"
