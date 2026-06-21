#!/usr/bin/env bash
# ===================================================================
#  Psalm — OSCP AD Toolkit Installer (v2 — battle-tested)
#  Installs every tool referenced in 05-active-directory.html
#  Target: Kali Linux 2024.4+ / Kali on WSL2 / Ubuntu 22.04+
#  Usage:  chmod +x install-ad-tools.sh && ./install-ad-tools.sh
#
#  Changes from v1:
#  - Removed dead apt packages (crackmapexec, kerbrute, rpcclient, ntpdate)
#  - rpcclient is in samba-common-bin (added)
#  - kerbrute via GitHub release binary (apt has no kerbrute pkg)
#  - BloodHound CE is the apt 'bloodhound' package (Legacy URL stayed broken)
#  - Verification function uses correct binary names per current Kali
#  - PoCL install attempted for hashcat on WSL/headless
#  - Added 'nxc-clean' helper function + engagement variable helpers
# ===================================================================

set -e
export DEBIAN_FRONTEND=noninteractive

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[*]${NC} $1"; }
ok()   { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[-]${NC} $1"; }

if [[ $EUID -eq 0 ]]; then
   err "Do NOT run as root. Run as normal user — sudo is called when needed."
   exit 1
fi

log "Starting OSCP AD toolkit installation (v2)..."
log "Estimated time: 10-15 minutes."

# ===================================================================
# 1. SYSTEM PACKAGES (apt)
# ===================================================================
log "Updating apt and installing base system packages..."
sudo apt update
sudo apt install -y \
    pipx git curl wget \
    python3 python3-pip python3-venv \
    build-essential libssl-dev libffi-dev python3-dev \
    libkrb5-dev krb5-user \
    ldap-utils \
    smbclient cifs-utils samba-common-bin \
    nmap \
    dnsutils whois \
    bsdmainutils \
    libxml2-dev libxslt-dev \
    libsasl2-dev \
    netcat-traditional \
    proxychains4 \
    seclists wordlists \
    hashcat john \
    hash-identifier \
    rdate \
    jq \
    golang-go \
    dos2unix \
    unzip
    # NOTE: NO ntpdate (removed from Debian 12)
    # NOTE: NO crackmapexec (project archived, removed from repos)
    # NOTE: NO kerbrute (never was in apt — installed via release below)
    # NOTE: rpcclient is in samba-common-bin

ok "Base system packages installed"

# Try installing ntpdate separately
sudo apt install -y ntpdate 2>/dev/null && ok "ntpdate available (bonus)" || warn "ntpdate not available (use ntpdig or 'dc-sync' alias instead)"

# Try PoCL for headless hashcat
sudo apt install -y pocl-opencl-icd 2>/dev/null && ok "PoCL OpenCL runtime installed (hashcat will work on CPU)" \
    || warn "PoCL not available — use 'john' as fallback for CPU cracking"

# ===================================================================
# 2. KALI-NATIVE TOOLS
# ===================================================================
log "Installing Kali-native security tools..."
sudo apt install -y \
    netexec \
    impacket-scripts \
    bloodhound \
    bloodhound.py \
    responder \
    evil-winrm \
    enum4linux-ng \
    enum4linux \
    smbmap \
    ligolo-ng \
    chisel \
    gobuster \
    ffuf \
    feroxbuster \
    wfuzz \
    sqlmap \
    sslscan \
    masscan \
    onesixtyone \
    snmp \
    snmpcheck \
    || warn "Some Kali packages failed — non-Kali system? Will install via pipx/git instead."

ok "Kali-native tools installed"
log "Note: bloodhound (apt) installs BloodHound CE; nxc replaces crackmapexec"

# ===================================================================
# 3. PIPX SETUP
# ===================================================================
log "Configuring pipx PATH..."
pipx ensurepath
export PATH="$HOME/.local/bin:$PATH"
ok "pipx PATH configured"

# ===================================================================
# 4. PIPX PYTHON TOOLS
# ===================================================================
log "Installing Python tools via pipx (isolated venvs)..."

pipx_install() {
    local pkg=$1
    if pipx list 2>/dev/null | grep -q "package $pkg "; then
        log "  $pkg already installed — upgrading..."
        pipx upgrade "$pkg" || true
    else
        pipx install "$pkg" || warn "    Failed to install $pkg"
    fi
}

pipx_install impacket
pipx install --force git+https://github.com/ly4k/Certipy.git || warn "Certipy install failed"
pipx install --force git+https://github.com/Pennyw0rth/NetExec || warn "NetExec source install failed — apt version works fine"
pipx_install bloodhound
pipx_install mitm6
pipx install --force git+https://github.com/login-securite/DonPAPI.git || warn "DonPAPI install failed"
pipx install --force git+https://github.com/p0dalirius/Coercer.git || warn "Coercer install failed"
pipx_install ldapdomaindump
pipx_install pypykatz
pipx install --force git+https://github.com/dirkjanm/adidnsdump.git || warn "adidnsdump install failed"
pipx install --force git+https://github.com/garrettfoster13/pre2k.git || warn "pre2k install failed"
pipx_install bloodyAD
pipx install --force git+https://github.com/blacklanternsecurity/MANSPIDER.git || warn "manspider install failed"

ok "pipx tools installed"

# ===================================================================
# 5. KERBRUTE — GitHub release binary
# ===================================================================
log "Installing kerbrute..."
mkdir -p ~/.local/bin

if ! command -v kerbrute &> /dev/null; then
    KERBRUTE_URL=$(curl -s https://api.github.com/repos/ropnop/kerbrute/releases/latest \
        | grep "browser_download_url.*kerbrute_linux_amd64" \
        | head -1 | cut -d '"' -f 4)

    if [[ -n "$KERBRUTE_URL" ]]; then
        log "  Downloading: $KERBRUTE_URL"
        curl -sL "$KERBRUTE_URL" -o ~/.local/bin/kerbrute
        chmod +x ~/.local/bin/kerbrute
        ok "  kerbrute installed → ~/.local/bin/kerbrute"
    else
        warn "  GitHub API didn't return URL — trying go install"
        go install github.com/ropnop/kerbrute@latest 2>/dev/null || \
            err "  Manual install: https://github.com/ropnop/kerbrute/releases"
    fi
else
    ok "  kerbrute already installed"
fi

# ===================================================================
# 6. STANDALONE GIT REPOS — clone to ~/tools/
# ===================================================================
log "Cloning standalone git repos to ~/tools/ ..."
mkdir -p "$HOME/tools"
cd "$HOME/tools"

export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/bin/echo

clone_or_pull() {
    local repo=$1
    local dir=$(basename "$repo" .git)
    if [[ -d "$dir" ]]; then
        log "  $dir exists — pulling latest..."
        cd "$dir" && git pull --quiet && cd ..
    else
        log "  Cloning $dir..."
        git clone --quiet "$repo" || warn "  Failed to clone $dir (404? renamed?)"
    fi
}

# Coercion tools
clone_or_pull https://github.com/topotam/PetitPotam.git
clone_or_pull https://github.com/dirkjanm/krbrelayx.git
clone_or_pull https://github.com/ShutdownRepo/ShadowCoerce.git
clone_or_pull https://github.com/Wh04m1001/DFSCoerce.git
clone_or_pull https://github.com/leechristensen/SpoolSample.git

# PowerShell offensive toolkits
clone_or_pull https://github.com/PowerShellMafia/PowerSploit.git
clone_or_pull https://github.com/samratashok/nishang.git
clone_or_pull https://github.com/SpecterOps/BloodHound-Legacy.git
clone_or_pull https://github.com/SpecterOps/SharpHound.git
clone_or_pull https://github.com/PowerShellEmpire/PowerTools.git

# AD enum / abuse
clone_or_pull https://github.com/dirkjanm/PKINITtools.git
clone_or_pull https://github.com/Hackndo/lsassy.git
clone_or_pull https://github.com/skelsec/pypykatz.git
clone_or_pull https://github.com/cube0x0/KrbRelay.git

# Privesc tools
clone_or_pull https://github.com/carlospolop/PEASS-ng.git
clone_or_pull https://github.com/rebootuser/LinEnum.git
clone_or_pull https://github.com/diego-treitos/linux-smart-enumeration.git

# Windows tools
clone_or_pull https://github.com/SecureAuthCorp/impacket.git
clone_or_pull https://github.com/itm4n/PrintSpoofer.git
clone_or_pull https://github.com/ohpe/juicy-potato.git
clone_or_pull https://github.com/antonioCoco/RoguePotato.git
clone_or_pull https://github.com/CCob/SweetPotato.git

# Pivoting — CORRECT URLs
clone_or_pull https://github.com/nicocha30/ligolo-ng.git
clone_or_pull https://github.com/jpillora/chisel.git

# Payloads
clone_or_pull https://github.com/swisskyrepo/PayloadsAllTheThings.git

cd "$HOME"
ok "Standalone repos cloned to ~/tools/"

# ===================================================================
# 7. WORDLISTS
# ===================================================================
log "Setting up wordlists..."
if [[ -f /usr/share/wordlists/rockyou.txt.gz ]]; then
    sudo gunzip -k /usr/share/wordlists/rockyou.txt.gz || true
    ok "  rockyou.txt decompressed"
fi
if [[ ! -d /usr/share/seclists ]]; then
    sudo git clone --quiet https://github.com/danielmiessler/SecLists.git /usr/share/seclists
fi
ok "Wordlists ready"

# ===================================================================
# 8. KRB5 CONFIG TEMPLATE
# ===================================================================
log "Setting up /etc/krb5.conf.template..."
if [[ ! -f /etc/krb5.conf.template ]]; then
    sudo tee /etc/krb5.conf.template > /dev/null << 'EOF'
# Pentester per-engagement template. Copy to /etc/krb5.conf and edit for current target.
# Replace CORP.LOCAL with the target domain (UPPERCASE) and dc01.corp.local with the DC FQDN.

[libdefaults]
    default_realm = CORP.LOCAL
    dns_lookup_realm = false
    dns_lookup_kdc = false
    default_tkt_enctypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96 rc4-hmac
    default_tgs_enctypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96 rc4-hmac
    permitted_enctypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96 rc4-hmac

[realms]
    CORP.LOCAL = {
        kdc = dc01.corp.local
        admin_server = dc01.corp.local
    }

[domain_realm]
    .corp.local = CORP.LOCAL
    corp.local = CORP.LOCAL
EOF
    ok "krb5 template saved"
fi

# ===================================================================
# 9. SHELL ALIASES + HELPERS
# ===================================================================
log "Adding aliases + helper functions to shell rc files..."

ADD_HELPERS=$(cat << 'EOF'

# ============================================================
# === OSCP AD aliases + functions (install-ad-tools.sh v2) ===
# ============================================================

# Standalone tool aliases
alias petitpotam='python3 ~/tools/PetitPotam/PetitPotam.py'
alias printerbug='python3 ~/tools/krbrelayx/printerbug.py'
alias shadowcoerce='python3 ~/tools/ShadowCoerce/shadowcoerce.py'
alias dfscoerce='python3 ~/tools/DFSCoerce/dfscoerce.py'
alias pkinit-gettgt='python3 ~/tools/PKINITtools/gettgtpkinit.py'
alias winpeas-cmd='cp ~/tools/PEASS-ng/winPEAS/winPEASexe/binaries/Obfuscated\ Releases/winPEASany.exe .'
alias linpeas='cp ~/tools/PEASS-ng/linPEAS/linpeas.sh .'
alias sharphound='cp ~/tools/SharpHound/SharpHound.exe . 2>/dev/null || cp ~/tools/BloodHound-Legacy/Collectors/SharpHound.exe .'

# Clock sync to DC (uses ntpdate if available, falls back to ntpdig)
dc-sync() {
    if command -v ntpdate &>/dev/null; then
        sudo ntpdate "$1"
    elif command -v rdate &>/dev/null; then
        sudo rdate -n "$1" 2>/dev/null || sudo ntpdig -S "$1"
    else
        sudo ntpdig -S "$1"
    fi
}

# Add DC + domain + short alias to /etc/hosts in one line
dc-host() {
    if [[ -z "$1" || -z "$2" ]]; then
        echo "Usage: dc-host <IP> <FQDN>  (e.g., dc-host 10.0.0.10 dc01.corp.local)"
        return 1
    fi
    local short_name=$(echo "$2" | cut -d. -f1)
    local domain=$(echo "$2" | cut -d. -f2-)
    echo "$1 $2 $domain $short_name" | sudo tee -a /etc/hosts
}

# Krb5 setup — copy template and open in nano
alias krb-template='sudo cp /etc/krb5.conf.template /etc/krb5.conf && sudo nano /etc/krb5.conf'

# Quick Responder start
alias respond='sudo responder -I tun0'

# nxc output cleanup — strips prefix garbage and status lines
nxc-clean() {
    nxc "$@" 2>/dev/null | sed -E 's/^[A-Z]+\s+[0-9.]+\s+[0-9]+\s+\S+\s+//' | grep -vE '^$|^\['
}

# Extract clean username list from nxc --users
nxc-users() {
    nxc smb "$@" --users 2>/dev/null \
        | awk '/-Username-/{flag=1; next} flag{print $5}' \
        | grep -vE '^$|^\['
}

# Base64 / hex quick decode helpers
b64d() { echo "$1" | base64 -d; echo; }
hexd() { echo "$1" | xxd -r -p; echo; }

# Show engagement variables
engage-show() {
    echo "IP        = $IP"
    echo "DC_IP     = $DC_IP"
    echo "DOMAIN    = $DOMAIN"
    echo "REALM     = $REALM"
    echo "DC_HOST   = $DC_HOST"
    echo "USER      = $USER"
    echo "PASS      = $(echo "$PASS" | sed 's/./*/g')"
    echo "HASH      = $HASH"
    echo "KALI      = $KALI"
}

# Set engagement variables and persist to ~/engage.env
engage-set() {
    cat > ~/engage.env << SHEOF
export IP="${1:-$IP}"
export DC_IP="${2:-${1:-$DC_IP}}"
export DOMAIN="${3:-$DOMAIN}"
export REALM="$(echo "${3:-$DOMAIN}" | tr '[:lower:]' '[:upper:]')"
export DC_HOST="${4:-$DC_HOST}"
export USER="${5:-$USER}"
export PASS="${6:-$PASS}"
export KALI=\$(ip -4 addr show tun0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
SHEOF
    source ~/engage.env
    echo "Engagement vars saved to ~/engage.env — source ~/engage.env in any new shell"
    engage-show
}

# === end OSCP AD aliases ===
EOF
)

for rcfile in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [[ -f "$rcfile" ]] && ! grep -q "OSCP AD aliases" "$rcfile"; then
        echo "$ADD_HELPERS" >> "$rcfile"
        ok "Helpers added to $rcfile"
    fi
done

# ===================================================================
# 10. VERIFICATION (correct binary names)
# ===================================================================
log "Verifying installations..."

check_tool() {
    local tool=$1
    local cmd=$2
    if command -v "$cmd" &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} $tool"
    else
        echo -e "  ${RED}✗${NC} $tool (try: source ~/.bashrc)"
    fi
}

echo ""
echo "================================"
echo " Tool Verification"
echo "================================"

check_tool "NetExec (nxc)"          "nxc"
check_tool "Impacket-secretsdump"   "impacket-secretsdump"
check_tool "Impacket-GetUserSPNs"   "impacket-GetUserSPNs"
check_tool "Impacket-GetNPUsers"    "impacket-GetNPUsers"
check_tool "Impacket-psexec"        "impacket-psexec"
check_tool "Impacket-wmiexec"       "impacket-wmiexec"
check_tool "Impacket-ntlmrelayx"    "impacket-ntlmrelayx"
check_tool "Impacket-mssqlclient"   "impacket-mssqlclient"
check_tool "Impacket-ticketer"      "impacket-ticketer"
check_tool "Impacket-getTGT"        "impacket-getTGT"
check_tool "Certipy"                "certipy"
check_tool "BloodHound.py"          "bloodhound-python"

if command -v bloodhound &> /dev/null || command -v bloodhound-ce &> /dev/null || command -v bloodhound-start &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} BloodHound CE"
else
    echo -e "  ${RED}✗${NC} BloodHound CE (sudo apt install bloodhound)"
fi

check_tool "Kerbrute"               "kerbrute"
check_tool "evil-winrm"             "evil-winrm"
check_tool "Responder"              "responder"
check_tool "mitm6"                  "mitm6"

if command -v Coercer &> /dev/null || command -v coercer &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} Coercer"
else
    echo -e "  ${RED}✗${NC} Coercer"
fi

check_tool "ldapsearch"             "ldapsearch"
check_tool "smbclient"              "smbclient"
check_tool "smbmap"                 "smbmap"
check_tool "rpcclient"              "rpcclient"

if command -v enum4linux-ng &> /dev/null || command -v enum4linux &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} enum4linux / enum4linux-ng"
else
    echo -e "  ${RED}✗${NC} enum4linux-ng"
fi

check_tool "ldapdomaindump"         "ldapdomaindump"
check_tool "adidnsdump"             "adidnsdump"
check_tool "bloodyAD"               "bloodyAD"
check_tool "pypykatz"               "pypykatz"
check_tool "Hashcat"                "hashcat"
check_tool "John the Ripper"        "john"

if command -v ligolo-ng-proxy &> /dev/null || command -v ligolo-ng &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} Ligolo-ng (proxy)"
else
    echo -e "  ${RED}✗${NC} Ligolo-ng"
fi

if command -v chisel &> /dev/null || [[ -f $HOME/go/bin/chisel ]]; then
    echo -e "  ${GREEN}✓${NC} Chisel"
else
    echo -e "  ${RED}✗${NC} Chisel"
fi

check_tool "Proxychains"            "proxychains4"
check_tool "Nmap"                   "nmap"
check_tool "Gobuster"               "gobuster"
check_tool "Feroxbuster"            "feroxbuster"
check_tool "Ffuf"                   "ffuf"

if command -v ntpdate &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} ntpdate (clock sync)"
elif command -v rdate &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} rdate (clock sync — works if port 37 open)"
fi

echo ""
echo "================================"
echo ""
ok "Installation complete!"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Reload shell:        source ~/.bashrc"
echo "  2. Set engagement vars: engage-set 10.0.0.10 10.0.0.10 corp.local DC01.corp.local user pass"
echo "  3. Verify:              engage-show"
echo ""
echo -e "${YELLOW}BloodHound CE — first-time setup:${NC}"
echo "  1. sudo bloodhound-start  (prompts for first-time setup)"
echo "  2. Browser → http://localhost:7474, login neo4j:neo4j, set new password"
echo "  3. sudo nano /etc/bhapi/bhapi.json  (update neo4j password)"
echo "  4. sudo bloodhound-start  (real start)"
echo "  5. Browser → http://localhost:8080, admin login shown in terminal"
echo ""
echo -e "${GREEN}Toolkit ready. Go grind labs.${NC}"
