#!/bin/bash

# Prompt for the sudo password securely
read -s -p "Enter your system password: " user_pass
echo

# Validate the password immediately
echo "$user_pass" | sudo -S -v >/dev/null 2>&1

# Exit if the password is incorrect
if [ $? -ne 0 ]; then
  echo "Incorrect password. Exiting."
  exit 1
fi

# Keep-alive sudo session
( while true; do echo "$user_pass" | sudo -S -v; sleep 60; done ) &
KEEP_ALIVE_PID=$!
trap 'kill $KEEP_ALIVE_PID 2>/dev/null' EXIT

# Script password protection
read -sp "Enter script password: " input_pass
echo
SCRIPT_PASSWORD="adarsh@123"

if [ "$input_pass" != "$SCRIPT_PASSWORD" ]; then
  echo "Incorrect password. Exiting..."
  exit 1
fi

LOG_FILE="/tmp/adarsh_setup.log"
echo "Starting Adarsh Ubuntu Setup..." | tee "$LOG_FILE"

success_log=()
failure_log=()

log_success() {
  echo "[SUCCESS] $1" | tee -a "$LOG_FILE"
  success_log+=("$1")
}

log_failure() {
  echo "[FAILED] $1" | tee -a "$LOG_FILE"
  failure_log+=("$1")
}

header() {
  echo -e "\n===== $1 =====" | tee -a "$LOG_FILE"
}

check_and_log() {
  if command -v "$1" &>/dev/null; then
    log_success "$2"
  else
    log_failure "$2"
  fi
}

# Pin to Ubuntu Dock
pin_to_dock() {
  local app="$1"
  local desktop_file

  desktop_file=$(find /usr/share/applications/ ~/.local/share/applications/ -name "$app.desktop" 2>/dev/null | head -n 1)

  if [[ -n "$desktop_file" ]]; then
    echo "[INFO] Pinning $app to Dock..."
    current_favorites=$(gsettings get org.gnome.shell favorite-apps)
    if [[ "$current_favorites" != *"$app.desktop"* ]]; then
      new_favorites=$(echo "$current_favorites" | sed "s/]$/, '$app.desktop']/")
      gsettings set org.gnome.shell favorite-apps "$new_favorites"
      echo "[SUCCESS] $app pinned to Dock."
    else
      echo "[INFO] $app is already pinned to Dock."
    fi
  else
    echo "[WARNING] $app.desktop file not found, skipping pinning."
  fi
}

# Disabling sleep settings
header "Disabling Sleep Settings"
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'
gsettings set org.gnome.desktop.session idle-delay 0
log_success "Sleep settings set to never sleep"

# System update & upgrade
header "System Update"
sudo apt-get clean
sudo apt-get update --fix-missing
sudo apt-get upgrade -y
sudo apt-get dist-upgrade -y
sudo apt-get autoremove -y
if [ $? -eq 0 ]; then
  log_success "System update and upgrade"
else
  log_failure "System update and upgrade"
fi

# Install basic dependencies
header "Installing Basic Dependencies"
sudo apt-get install -y curl wget git software-properties-common apt-transport-https ca-certificates gnupg lsb-release expect cups rar unrar cups-pdf
check_and_log curl "Curl Installed"
check_and_log wget "Wget Installed"

# Google Chrome
header "Installing Google Chrome"
sudo wget -q -O /tmp/google-chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo dpkg -i /tmp/google-chrome.deb || sudo apt-get install -f -y
check_and_log google-chrome "Google Chrome Installed"
command -v google-chrome &>/dev/null && pin_to_dock "google-chrome"

# LibreOffice
header "Installing LibreOffice"
sudo apt-get install -y libreoffice
check_and_log libreoffice "LibreOffice Installed"

# AnyDesk
header "Installing AnyDesk"
wget -qO - https://keys.anydesk.com/repos/DEB-GPG-KEY | sudo gpg --dearmor -o /usr/share/keyrings/anydesk.gpg
echo "deb [signed-by=/usr/share/keyrings/anydesk.gpg] http://deb.anydesk.com/ all main" | sudo tee /etc/apt/sources.list.d/anydesk.list
sudo apt-get update && sudo apt-get install -y anydesk
check_and_log anydesk "AnyDesk Installed"
command -v anydesk &>/dev/null && pin_to_dock "anydesk"

# RustDesk
header "Installing RustDesk"
sudo wget https://github.com/rustdesk/rustdesk/releases/download/1.2.6/rustdesk-1.2.6-x86_64.deb -O /tmp/rustdesk.deb
sudo apt install -fy /tmp/rustdesk.deb
check_and_log rustdesk "RustDesk Installed"
command -v rustdesk &>/dev/null && pin_to_dock "rustdesk"

# HP Plugin Installation
header "Installing HP Plugin"
expect <<'EOF'
log_user 1
set timeout 300
spawn hp-plugin -i --required --force

expect {
  -re "Do you accept the license.*" { send "y\r"; exp_continue }
  -re "Enter option.*" { send "d\r"; exp_continue }
  -re "Download the plugin from HP.*" { send "d\r"; exp_continue }
  -re "Is this OK.*" { send "y\r"; exp_continue }
  -re "Press 'q' to quit.*" { send "q\r"; exp_continue }
  eof
}
EOF
[ $? -eq 0 ] && log_success "HP Plugin Installed" || log_failure "HP Plugin Installation Failed"

# Detect HP USB Printer
header "Waiting for USB Printer Detection"
echo "Please connect the USB printer..."

printer_detected=false
for i in {1..12}; do
  if lsusb | grep -i 'hp\|hewlett' >/dev/null; then
    echo "HP USB Printer detected. Proceeding with setup..."
    printer_detected=true
    break
  fi
  sleep 5
  echo "Waiting for printer to be connected... ($i/12)"
done

if [ "$printer_detected" = true ]; then
  header "Running HP Setup"
  expect <<EOF
set timeout 300
log_user 1
spawn sudo -S hp-setup -i
expect {
  "*password*" { send "$user_pass\r"; exp_continue }
  "*Found USB printers*" { exp_continue }
  "*Enter number*" { send "0\r"; exp_continue }
  "*Enter option*" { send "d\r"; exp_continue }
  "*Do you accept the license*" { send "y\r"; exp_continue }
  "*Please enter a name for this print queue*" { send "m\r"; exp_continue }
  "*Does this PPD file appear to be the correct one*" { send "y\r"; exp_continue }
  "*Enter a location description for this printer*" { send "Office Printer\r"; exp_continue }
  "*Enter additonal information or notes for this printer*" { send "\r"; exp_continue }
  "*Would you like to print a test page*" { send "n\r"; exp_continue }
  "*Would you like to install another print queue for this device*" { send "n\r"; exp_continue }
  eof
}
EOF
  [ $? -eq 0 ] && log_success "HP Setup Completed" || log_failure "HP Setup Failed"

# Test print
header "Printing Test Page"

# Get the most recently added HP printer
PRINTER_ID=$(lpstat -v | grep -i 'hp\|hewlett' | awk '{print $3}' | sed 's/:$//' | tail -n 1)

# Choose test page source
TEST_PAGE="/usr/share/cups/data/default-testpage.pdf"
  if [ ! -f "$TEST_PAGE" ]; then
    echo "Test print from Adarsh setup script" > /tmp/testprint.txt
    TEST_PAGE="/tmp/testprint.txt"
  fi

  if [ -n "$PRINTER_ID" ]; then
    echo "[INFO] Sending test print to: $PRINTER_ID"
    lp -d "$PRINTER_ID" "$TEST_PAGE" && log_success "Test page sent to printer: $PRINTER_ID" || log_failure "Test page printing failed"
  else
    log_failure "Could not determine HP printer ID"
  fi
fi

# Create user "Depo"
header "Creating User"
if ! id "Depo" &>/dev/null; then
  sudo useradd -m -s /bin/bash Depo && echo "Depo:depo" | sudo chpasswd
  sudo usermod -aG sudo Depo && log_success "User 'Depo' Created and Added to Sudo" || log_failure "User Modification Failed"
else
  log_failure "User 'Depo' already exists"
fi

# Setup Summary
header "Setup Summary"
echo -e "\n===== SUCCESSFULLY INSTALLED ====="
for item in "${success_log[@]}"; do echo "- $item"; done

echo -e "\n===== FAILED INSTALLATIONS ====="
for item in "${failure_log[@]}"; do echo "- $item"; done

echo -e "\nAdarsh Setup Completed! Log available at $LOG_FILE"

# Copy log file to Desktop
header "Copying Log File to Desktop"
DESKTOP_PATH_CURRENT="$HOME/Desktop"
FINAL_LOG_NAME="adarsh_setup-log.txt"
if [ -d "$DESKTOP_PATH_CURRENT" ]; then
  cp "$LOG_FILE" "$DESKTOP_PATH_CURRENT/$FINAL_LOG_NAME" && log_success "Log copied to Desktop" || log_failure "Failed to copy log to Desktop"
else
  log_failure "Desktop directory not found"
fi

# Cleanup
unset user_pass
echo -e "\nRebooting in 30 seconds... Press Ctrl+C to cancel."
sleep 30
sudo reboot
