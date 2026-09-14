#!/bin/sh
# ==========================================
# LINUX DMAS AUTOMATED INSTALLER (POSIX)
# ==========================================
# Chế độ: chạy lại nhiều lần an toàn (check trước khi cài, tự sửa lỗi kẹt)
# Mẹo chống treo apt: DMAS_FORCE_IPV4=1 sh linuxdmas.sh
# ==========================================

ESC=$(printf '\033')
C_CYAN="${ESC}[38;2;0;220;255m"
C_GREEN="${ESC}[38;2;50;255;120m"
C_YELLOW="${ESC}[38;2;255;200;50m"
C_MAGENTA="${ESC}[38;2;235;90;255m"
C_RED="${ESC}[38;2;255;80;80m"
C_RESET="${ESC}[0m"

SETUP_FLAG="$HOME/.dmas_setup_done"
LOG_FILE="$HOME/.dmas_install.log"
WALLPAPER_URL="https://raw.githubusercontent.com/dmasntd/DmasLinux/main/dmaslinux.png"

PKG_EDITOR="code"
PKG_BROWSER="firefox"

APT_IPV4_OPT=""
if [ "${DMAS_FORCE_IPV4:-0}" = "1" ]; then
    APT_IPV4_OPT="-o Acquire::ForceIPv4=true "
fi
APT_OPTS="-o APT::Sandbox::User=root -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 -o Acquire::Retries=3 ${APT_IPV4_OPT}"

UPDATE_MODE=0
if [ -f "$SETUP_FLAG" ]; then
    UPDATE_MODE=1
fi

LOCK_DIR="$HOME/.dmas_install.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "${C_RED}[ERROR] Một bản cài DMAS khác đang chạy (lock: $LOCK_DIR).${C_RESET}"
    printf '%s\n' "Nếu chắc chắn không còn tiến trình nào: rm -rf $LOCK_DIR"
    exit 1
fi
release_lock() {
    rmdir "$LOCK_DIR" 2>/dev/null || true
}
on_signal_exit() {
    release_lock
    exit 130
}
trap release_lock EXIT
trap on_signal_exit INT TERM

if [ ! -d "$HOME" ] || [ ! -w "$HOME" ]; then
    printf '[ERROR] $HOME không tồn tại hoặc không ghi được.\n'
    exit 1
fi

: >>"$LOG_FILE" || {
    printf '[ERROR] Không thể tạo/ghi log: %s\n' "$LOG_FILE"
    exit 1
}

printf '\n==== DMAS installer run %s ====\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo unknown)" >>"$LOG_FILE"

log() {
    printf '%s\n' "$*" >>"$LOG_FILE" 2>/dev/null || true
}

info() {
    printf '%s\n' "$*"
    log "[INFO] $*"
}

warn() {
    printf '%s[!] %s%s\n' "$C_YELLOW" "$*" "$C_RESET"
    log "[WARN] $*"
}

error() {
    printf '%s[ERROR] %s%s\n' "$C_RED" "$*" "$C_RESET"
    log "[ERROR] $*"
}

fail() {
    printf '\n'
    error "$1"
    error "Installer stopped safely. Container/data were preserved."
    error "Log: $LOG_FILE"
    exit 1
}

run() {
    r_desc=$1
    shift
    log "[RUN] $*"
    "$@" >>"$LOG_FILE" 2>&1
    r_status=$?
    if [ "$r_status" -ne 0 ]; then
        fail "$r_desc"
    fi
    return 0
}

run_warn() {
    rw_desc=$1
    shift
    log "[RUN-WARN] $*"
    if ! "$@" >>"$LOG_FILE" 2>&1; then
        warn "$rw_desc"
        return 1
    fi
    return 0
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || fail "Lệnh quan trọng '$1' không tồn tại."
}

spinner_wait() {
    sw_pid=$1
    sw_desc=$2
    while kill -0 "$sw_pid" 2>/dev/null; do
        sw_last=$(tail -n 1 "$LOG_FILE" 2>/dev/null | tr -d '\r' | cut -c1-40)
        printf '\r\033[K%s%s%s | %s%s%s' "$C_MAGENTA" "$sw_desc" "$C_RESET" "$C_CYAN" "$sw_last" "$C_RESET"
        sleep 5
    done
    wait "$sw_pid"
    SPINNER_STATUS=$?
    printf '\r\033[K'
    return 0
}

run_live() {
    rl_desc=$1
    shift
    log "[RUN-LIVE] $*"
    "$@" >>"$LOG_FILE" 2>&1 &
    spinner_wait $! "$rl_desc"
    if [ "$SPINNER_STATUS" -ne 0 ]; then
        fail "$rl_desc"
    fi
    return 0
}

show_banner() {
    if command -v clear >/dev/null 2>&1; then
        clear
    else
        printf '\033[2J\033[H'
    fi

    AND_VER=$(getprop ro.build.version.release 2>/dev/null || echo "N/A")
    KERNEL=$(uname -r 2>/dev/null || echo "N/A")
    ARCH=$(uname -m 2>/dev/null || echo "N/A")
    OS="Termux (Android)"

    printf '%s\n' "${C_CYAN}+---------------------------------------------------+${C_RESET}"
    printf '%s\n' "${C_MAGENTA}|          LINUX DMAS AUTOMATED INSTALLER           |${C_RESET}"
    printf '%s\n' "${C_CYAN}+---------------------------------------------------+${C_RESET}"
    printf '%s\n' "${C_GREEN} Android Version : ${C_RESET}$AND_VER"
    printf '%s\n' "${C_GREEN} Kernel Version  : ${C_RESET}$KERNEL"
    printf '%s\n' "${C_GREEN} OS Environment  : ${C_RESET}$OS"
    printf '%s\n' "${C_GREEN} Architecture    : ${C_RESET}$ARCH"
    printf '%s\n' "${C_CYAN}+---------------------------------------------------+${C_RESET}"
}

draw_progress() {
    pct=$1
    msg=$2
    width=20
    filled=$((pct * width / 100))
    empty=$((width - filled))
    bar=""
    i=0

    while [ "$i" -lt "$filled" ]; do
        bar="${bar}#"
        i=$((i + 1))
    done

    i=0
    while [ "$i" -lt "$empty" ]; do
        bar="${bar}-"
        i=$((i + 1))
    done

    printf "\r${C_CYAN}[${C_GREEN}%s${C_CYAN}] ${C_YELLOW}%3d%%${C_RESET} ${C_MAGENTA}- %s${C_RESET}\033[K" "$bar" "$pct" "$msg"

    if [ "$pct" -eq 100 ]; then
        printf '\n'
    fi
}

distro_exec() {
    proot-distro login "$DISTRO" -- /bin/sh -c "$1" >>"$LOG_FILE" 2>&1
}

distro_exec_live() {
    proot-distro login "$DISTRO" -- /bin/sh -c "$1" >>"$LOG_FILE" 2>&1 &
    spinner_wait $! "${LIVE_DESC:-đang xử lý trong container...}"
    return "$SPINNER_STATUS"
}

distro_cmd() {
    dc_desc=$1
    dc_cmd=$2
    log "[DISTRO-CMD] $dc_cmd"
    if ! distro_exec "$dc_cmd"; then
        fail "$dc_desc"
    fi
}

distro_cmd_live() {
    dc_desc=$1
    dc_cmd=$2
    log "[DISTRO-CMD-LIVE] $dc_cmd"
    LIVE_DESC="$dc_desc"
    if ! distro_exec_live "$dc_cmd"; then
        LIVE_DESC=""
        fail "$dc_desc"
    fi
    LIVE_DESC=""
}

try_distro() {
    td_desc=$1
    td_cmd=$2
    log "[DISTRO-TRY] $td_cmd"
    if distro_exec "$td_cmd"; then
        return 0
    fi
    warn "$td_desc"
    return 1
}

install_vscode_debian() {
    VC_STEP="Kiểm tra VS Code đã tồn tại"
    log "[VSCODE] $VC_STEP"
    if distro_exec 'command -v code >/dev/null 2>&1'; then
        return 0
    fi

    VC_STEP="Cài dependency VS Code (Debian/Ubuntu)"
    log "[VSCODE] $VC_STEP"
    distro_exec "export DEBIAN_FRONTEND=noninteractive; apt-get $APT_OPTS update -y >/dev/null 2>&1 || true; apt-get $APT_OPTS install -y wget curl ca-certificates gnupg apt-transport-https" || return 1

    VC_STEP="Tải và cài Microsoft signing key"
    log "[VSCODE] $VC_STEP"
    distro_exec 'install -m 0755 -d /etc/apt/keyrings && wget -qO /tmp/microsoft.asc https://packages.microsoft.com/keys/microsoft.asc && gpg --dearmor < /tmp/microsoft.asc > /etc/apt/keyrings/microsoft.gpg.tmp && mv /etc/apt/keyrings/microsoft.gpg.tmp /etc/apt/keyrings/microsoft.gpg && chmod a+r /etc/apt/keyrings/microsoft.gpg' || return 1

    VC_STEP="Thêm repository VS Code"
    log "[VSCODE] $VC_STEP"
    distro_exec 'ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m); case "$ARCH" in amd64|arm64) : ;; x86_64) ARCH=amd64 ;; aarch64) ARCH=arm64 ;; *) echo "Unsupported VS Code architecture: $ARCH" >&2; exit 1 ;; esac; echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list' || return 1

    VC_STEP="Cập nhật apt với repo VS Code"
    log "[VSCODE] $VC_STEP"
    if ! distro_exec "export DEBIAN_FRONTEND=noninteractive; apt-get $APT_OPTS update -y"; then
        log "[WARN] apt update sau khi thêm repo VS Code thất bại; vẫn thử cài code."
    fi

    VC_STEP="Cài gói code"
    log "[VSCODE] $VC_STEP"
    LIVE_DESC="Cài gói code (VS Code)..."
    distro_exec_live "export DEBIAN_FRONTEND=noninteractive; apt-get $APT_OPTS install -y code" || { LIVE_DESC=""; return 1; }
    LIVE_DESC=""

    VC_STEP="Xác minh VS Code"
    log "[VSCODE] $VC_STEP"
    if distro_exec 'command -v code >/dev/null 2>&1'; then
        return 0
    fi

    return 1
}

install_vscode_fedora() {
    VC_STEP="Kiểm tra VS Code đã tồn tại"
    log "[VSCODE] $VC_STEP"
    if distro_exec 'command -v code >/dev/null 2>&1'; then
        return 0
    fi

    VC_STEP="Cài dependency VS Code (Fedora)"
    log "[VSCODE] $VC_STEP"
    distro_exec 'dnf install -y curl wget gnupg || yum install -y curl wget gnupg' || return 1

    VC_STEP="Nhập Microsoft signing key"
    log "[VSCODE] $VC_STEP"
    distro_exec 'rpm --import https://packages.microsoft.com/keys/microsoft.asc || { wget -qO /tmp/microsoft.asc https://packages.microsoft.com/keys/microsoft.asc && rpm --import /tmp/microsoft.asc; }' || return 1

    VC_STEP="Thêm VS Code repository"
    log "[VSCODE] $VC_STEP"
    distro_exec 'cat > /etc/yum.repos.d/vscode.repo <<EOF
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
' || return 1

    VC_STEP="Cập nhật metadata dnf"
    log "[VSCODE] $VC_STEP"
    distro_exec 'dnf clean all --enablerepo=code >/dev/null 2>&1 || true; dnf makecache --refresh >/dev/null 2>&1 || dnf makecache >/dev/null 2>&1 || true' || return 1

    VC_STEP="Cài gói code"
    log "[VSCODE] $VC_STEP"
    LIVE_DESC="Cài gói code (VS Code)..."
    distro_exec_live 'dnf install -y code' || { LIVE_DESC=""; return 1; }
    LIVE_DESC=""

    VC_STEP="Xác minh VS Code"
    log "[VSCODE] $VC_STEP"
    if distro_exec 'command -v code >/dev/null 2>&1'; then
        return 0
    fi

    return 1
}

show_banner

if [ "$UPDATE_MODE" -eq 1 ]; then
    info "Đã setup trước đó → chạy CHẾ ĐỘ CẬP NHẬT & SỬA CHỮA (kiểm tra trước, không cài lại thứ đã có)."
fi
info "Mẹo chống 'tưởng treo': mở session Termux mới (quẹt trái → NEW SESSION) và chạy: tail -f $LOG_FILE"

draw_progress 5 "Bước 1/11 - Kiểm tra môi trường Termux..."
if [ -z "$HOME" ] || [ ! -w "$HOME" ]; then
    fail "HOME không tồn tại hoặc không ghi được."
fi

if [ -z "$PREFIX" ]; then
    warn "PREFIX chưa được đặt. Có thể môi trường không phải Termux chuẩn."
fi

need_cmd pkg
need_cmd uname

draw_progress 10 "Bước 2/11 - Cài/kiểm tra gói Termux..."
run_warn "pkg update thất bại, tiếp tục với chỉ mục gói hiện có." pkg update -y

if ! command -v termux-x11 >/dev/null 2>&1; then
    run "Cài x11-repo thất bại" pkg install -y x11-repo
fi

TERMUX_PKGS=""
command -v proot-distro >/dev/null 2>&1 || TERMUX_PKGS="$TERMUX_PKGS proot-distro"
command -v termux-x11 >/dev/null 2>&1 || TERMUX_PKGS="$TERMUX_PKGS termux-x11-nightly"
command -v wget >/dev/null 2>&1 || TERMUX_PKGS="$TERMUX_PKGS wget"
command -v curl >/dev/null 2>&1 || TERMUX_PKGS="$TERMUX_PKGS curl"

if [ -n "$TERMUX_PKGS" ]; then
    run "Cài gói Termux thiếu thất bại" pkg install -y $TERMUX_PKGS
else
    info "Gói Termux đã đủ, bỏ qua cài đặt."
fi

need_cmd proot-distro
need_cmd termux-x11

if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
    fail "Thiếu cả wget và curl trong Termux."
fi

draw_progress 15 "Bước 3/11 - Kiểm tra Termux:X11 Android app..."
if command -v pm >/dev/null 2>&1; then
    if pm list packages 2>/dev/null | grep -q "package:com.termux.x11"; then
        info "Termux:X11 Android app đã cài."
    else
        warn "Không thấy package com.termux.x11. Hãy cài APK Termux:X11 nếu GUI không mở được."
    fi
else
    warn "Không kiểm tra được Termux:X11 Android app vì pm không khả dụng."
fi

printf '\n'
draw_progress 20 "Bước 4/11 - Chọn distro"
printf '%s\n' "${C_YELLOW}[+] Chọn Hệ điều hành Linux Container:${C_RESET}"
printf '  1) Ubuntu (Khuyên dùng - Đầy đủ bộ thư viện)\n'
printf '  2) Debian (Siêu ổn định & Nhẹ)\n'
printf '  3) Fedora (Gói ứng dụng mới nhất)\n'
printf '%s' "${C_CYAN}Nhập lựa chọn [1-3] (Mặc định 1): ${C_RESET}"
read DISTRO_CHOICE || DISTRO_CHOICE=1

case "$DISTRO_CHOICE" in
    2) DISTRO="debian" ;;
    3) DISTRO="fedora" ;;
    *) DISTRO="ubuntu" ;;
esac

info "Distro được chọn: $DISTRO"

draw_progress 30 "Bước 5/11 - Kiểm tra container $DISTRO..."
CONTAINER_EXISTS=0

if [ -n "$PREFIX" ] && [ -d "$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO" ]; then
    CONTAINER_EXISTS=1
fi

if [ "$CONTAINER_EXISTS" -eq 0 ] && proot-distro login "$DISTRO" -- /bin/sh -c true >/dev/null 2>&1; then
    CONTAINER_EXISTS=1
fi

if [ "$CONTAINER_EXISTS" -eq 1 ]; then
    info "Container $DISTRO đã tồn tại. Không xóa dữ liệu; chỉ cài/sửa gói thiếu."
else
    run_live "Cài container $DISTRO" proot-distro install "$DISTRO"
fi

if ! proot-distro login "$DISTRO" -- /bin/sh -c true >>"$LOG_FILE" 2>&1; then
    fail "Container $DISTRO không thể đăng nhập sau khi cài đặt."
fi

draw_progress 45 "Bước 6/11 - Sửa lỗi kẹt lần trước + cài gói Linux..."
info "Bước này có thể tải nhiều gói; lần đầu mất 10-45 phút tuỳ mạng. Thứ đã có sẽ bị bỏ qua."
info "Theo dõi trực tiếp tại session khác: tail -f $LOG_FILE"

if [ "$DISTRO" = "fedora" ]; then
    try_distro 'Sửa transaction dnf kẹt lần trước thất bại' 'dnf -y complete-transaction || true; dnf clean all || true; dnf makecache --refresh || true'
    distro_cmd_live 'Cài gói nền Fedora thất bại' 'miss=""; for p in xfce4-session xfwm4 xfce4-panel xfdesktop xfce4-terminal Thunar dbus-x11 curl wget git gnupg glibc-langpack-en; do rpm -q "$p" >/dev/null 2>&1 || miss="$miss $p"; done; if [ -n "$miss" ]; then case "$miss" in *xfce4-session*) dnf groupinstall -y "Xfce Desktop" || dnf install -y $miss || true ;; *) dnf install -y $miss || true ;; esac; else echo "DMAS: gói nền Fedora đã đủ."; fi'
    try_distro 'Cài bộ theme mở rộng thất bại' 'miss=""; for p in arc-theme numix-gtk-theme materia-gtk-theme gnome-themes-extra greybird-gtk-theme papirus-icon-theme numix-icon-theme numix-icon-theme-circle moka-icon-theme adwaita-icon-theme ubuntu-font-family google-noto-emoji-color-fonts; do rpm -q "$p" >/dev/null 2>&1 || miss="$miss $p"; done; if [ -n "$miss" ]; then dnf install -y $miss || for p in $miss; do dnf install -y "$p" || true; done; else echo "DMAS: theme Fedora đã đủ."; fi'

    if distro_exec 'rpm -q firefox >/dev/null 2>&1'; then
        info "Firefox đã có trong container."
    else
        try_distro 'Cài Firefox thất bại' 'dnf install -y firefox' || true
    fi

    try_distro 'Thiết lập locale Fedora thất bại' 'if ! locale -a 2>/dev/null | grep -qi "^en_US.utf8"; then dnf install -y glibc-langpack-en || true; fi; printf "LANG=en_US.UTF-8\n" > /etc/locale.conf; printf "export LANG=en_US.UTF-8\nexport LC_ALL=en_US.UTF-8\n" > /etc/profile.d/99-dmas-locale.sh; chmod 644 /etc/profile.d/99-dmas-locale.sh || true'
else
    try_distro 'Sửa dpkg/apt kẹt lần trước thất bại' 'dpkg --configure -a 2>/tmp/dmas_dpkg.err || { grep -qi lock /tmp/dmas_dpkg.err && rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock; dpkg --configure -a; }; rm -f /tmp/dmas_dpkg.err; apt-get install -f -y || true'
    try_distro 'Cập nhật apt thất bại' 'export DEBIAN_FRONTEND=noninteractive; apt-get '"$APT_OPTS"' update -y'
    distro_cmd_live 'Cài gói nền Debian thất bại' 'export DEBIAN_FRONTEND=noninteractive; miss=""; for p in dbus-x11 xfce4 xfce4-terminal thunar curl wget ca-certificates gnupg apt-transport-https locales git; do dpkg -s "$p" >/dev/null 2>&1 || miss="$miss $p"; done; if [ -n "$miss" ]; then apt-get '"$APT_OPTS"' install -y --no-install-recommends $miss || for p in $miss; do apt-get '"$APT_OPTS"' install -y --no-install-recommends "$p" || true; done; else echo "DMAS: gói nền Debian đã đủ."; fi'
    try_distro 'Cài xfce4-goodies thất bại' 'export DEBIAN_FRONTEND=noninteractive; if ! dpkg -s xfce4-goodies >/dev/null 2>&1; then apt-get '"$APT_OPTS"' install -y --no-install-recommends xfce4-goodies || true; else echo "DMAS: xfce4-goodies đã có."; fi'
    try_distro 'Cài bộ theme mở rộng thất bại' 'export DEBIAN_FRONTEND=noninteractive; miss=""; for p in arc-theme numix-gtk-theme materia-gtk-theme gnome-themes-extra greybird-gtk-theme gtk2-engines-murrine gtk2-engines-pixbuf papirus-icon-theme numix-icon-theme numix-icon-theme-circle moka-icon-theme elementary-xfce-icon-theme adwaita-icon-theme fonts-ubuntu fonts-noto-color-emoji; do dpkg -s "$p" >/dev/null 2>&1 || miss="$miss $p"; done; if [ -n "$miss" ]; then apt-get '"$APT_OPTS"' install -y --no-install-recommends $miss || for p in $miss; do apt-get '"$APT_OPTS"' install -y --no-install-recommends "$p" || true; done; else echo "DMAS: theme Debian đã đủ."; fi'

    if distro_exec 'dpkg -s firefox >/dev/null 2>&1 || dpkg -s firefox-esr >/dev/null 2>&1'; then
        info "Firefox/Firefox ESR đã có trong container."
    else
        try_distro 'Cài Firefox thất bại' 'export DEBIAN_FRONTEND=noninteractive; apt-get '"$APT_OPTS"' install -y firefox' || \
        try_distro 'Cài Firefox ESR thất bại' 'export DEBIAN_FRONTEND=noninteractive; apt-get '"$APT_OPTS"' install -y firefox-esr' || true
    fi
    try_distro 'Thiết lập locale Debian/Ubuntu thất bại' 'export DEBIAN_FRONTEND=noninteractive; if ! locale -a 2>/dev/null | grep -qi "^en_US.utf8"; then apt-get '"$APT_OPTS"' install -y locales || true; if [ -f /etc/locale.gen ]; then sed -i "s/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/" /etc/locale.gen 2>/dev/null || true; grep -q "^en_US.UTF-8 UTF-8" /etc/locale.gen || echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen; fi; locale-gen en_US.UTF-8 || true; else echo "DMAS: locale en_US.UTF-8 đã có."; fi; update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 || true; printf "export LANG=en_US.UTF-8\nexport LC_ALL=en_US.UTF-8\n" > /etc/profile.d/99-dmas-locale.sh; chmod 644 /etc/profile.d/99-dmas-locale.sh || true'
fi

info "Locale UTF-8 được áp dụng qua /etc/profile.d và export trực tiếp trong startdmas.sh."

draw_progress 75 "Bước 8/11 - Cài đặt VS Code..."
VSCODE_OK=0
VS_ATTEMPT=1

while [ "$VS_ATTEMPT" -le 2 ]; do
    if [ "$DISTRO" = "fedora" ]; then
        if install_vscode_fedora; then
            VSCODE_OK=1
            break
        fi
    else
        if install_vscode_debian; then
            VSCODE_OK=1
            break
        fi
    fi

    warn "Cài VS Code thất bại ở bước: $VC_STEP."

    if [ "$VS_ATTEMPT" -lt 2 ]; then
        warn "Đang thử lại VS Code. Xem log: $LOG_FILE"
        sleep 2
    fi

    VS_ATTEMPT=$((VS_ATTEMPT + 1))
done

if [ "$VSCODE_OK" -eq 1 ]; then
    PKG_EDITOR="code"
    info "VS Code cài thành công và đã xác minh. Geany sẽ KHÔNG được cài."
else
    warn "[!] VS Code không thể cài đặt trên môi trường hiện tại."
    warn "[+] Fallback sang Geany."

    if [ "$DISTRO" = "fedora" ]; then
        if ! try_distro 'Cài Geany fallback thất bại' 'dnf install -y geany'; then
            fail "Đã thử VS Code nhưng không thành công, và Geany fallback cũng không cài được."
        fi
    else
        if ! try_distro 'Cài Geany fallback thất bại' "export DEBIAN_FRONTEND=noninteractive; apt-get $APT_OPTS install -y geany"; then
            fail "Đã thử VS Code nhưng không thành công, và Geany fallback cũng không cài được."
        fi
    fi

    PKG_EDITOR="geany"
    info "Đã cài Geany fallback. VS Code vẫn là editor chính trong thiết kế, nhưng môi trường này không hỗ trợ."
fi

draw_progress 85 "Bước 9/11 - Cấu hình wallpaper, theme, panel, autostart..."
distro_cmd 'Tạo thư mục UI thất bại' 'mkdir -p /root/.config/autostart /root/Pictures'

UI_SRC="$HOME/.dmas_ui_fix.src.$$"
UI_OUT="$HOME/.dmas_ui_fix.out.$$"
DESKTOP_SRC="$HOME/.dmas_ui_desktop.src.$$"
DESKTOP_OUT="$HOME/.dmas_ui_desktop.out.$$"

cat <<'UIEOF' > "$UI_SRC" || fail "Không ghi được UI template"
#!/bin/sh
# DMAS UI fix - generated by linuxdmas.sh
DISPLAY="${DISPLAY:-:0}"
export DISPLAY

WALLPAPER_DIR="/root/Pictures"
PRIMARY_URL="__WALLPAPER_URL__"
PRIMARY_FILE="$WALLPAPER_DIR/dmaslinux.png"
FALLBACK_URL="https://picsum.photos/1920/1080.jpg"
FALLBACK_FILE="$WALLPAPER_DIR/dmas-fallback.jpg"
UI_LOG="/root/.dmas_ui_fix.log"

ui_log() {
    printf '[DMAS-UI] %s\n' "$*" >> "$UI_LOG" 2>/dev/null || true
}

verify_image() {
    file="$1"
    ext="$2"

    [ -s "$file" ] || return 1

    if ! command -v od >/dev/null 2>&1 || ! command -v tr >/dev/null 2>&1; then
        return 0
    fi

    magic=$(od -An -N4 -tx1 "$file" 2>/dev/null | tr -d ' \n')

    case "$ext" in
        png)
            [ "$magic" = "89504e47" ] && return 0
            ;;
        jpg|jpeg)
            case "$magic" in
                ffd8ff*) return 0 ;;
            esac
            ;;
    esac

    return 1
}

download_file() {
    url="$1"
    dest="$2"
    ext="$3"
    tmp="${dest}.tmp"

    if command -v wget >/dev/null 2>&1; then
        wget -T 30 -q -O "$tmp" "$url" 2>/dev/null || return 1
    elif command -v curl >/dev/null 2>&1; then
        curl -fsSL --max-time 30 -o "$tmp" "$url" 2>/dev/null || return 1
    else
        ui_log "Không có wget/curl để tải wallpaper."
        return 1
    fi

    if ! verify_image "$tmp" "$ext"; then
        rm -f "$tmp" 2>/dev/null || true
        return 1
    fi

    mv "$tmp" "$dest" || return 1
}

mkdir -p "$WALLPAPER_DIR" 2>/dev/null || true
WALLPAPER=""

if [ -s "$PRIMARY_FILE" ] && verify_image "$PRIMARY_FILE" png; then
    WALLPAPER="$PRIMARY_FILE"
elif [ -s "$FALLBACK_FILE" ] && verify_image "$FALLBACK_FILE" jpg; then
    WALLPAPER="$FALLBACK_FILE"
else
    if download_file "$PRIMARY_URL" "$PRIMARY_FILE" png; then
        WALLPAPER="$PRIMARY_FILE"
        ui_log "Đã tải wallpaper chính."
    elif download_file "$FALLBACK_URL" "$FALLBACK_FILE" jpg; then
        WALLPAPER="$FALLBACK_FILE"
        ui_log "Wallpaper chính lỗi, dùng fallback."
    else
        ui_log "ERROR: không tải được wallpaper nào."
    fi
fi

i=0
while [ "$i" -lt 30 ]; do
    if xfconf-query -c xfce4-desktop -l >/dev/null 2>&1; then
        break
    fi
    sleep 1
    i=$((i + 1))
done

if command -v xfconf-query >/dev/null 2>&1; then
    if [ -n "$WALLPAPER" ]; then
        for prop in $(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep '/last-image$'); do
            xfconf-query -c xfce4-desktop -p "$prop" -s "$WALLPAPER" 2>/dev/null || true
        done

        MONS=$(xrandr 2>/dev/null | grep ' connected' | cut -d' ' -f1)
        for mon in $MONS monitor0; do
            xfconf-query -c xfce4-desktop -p "/backdrop/screen0/monitor$mon/workspace0/last-image" -s "$WALLPAPER" --create -t string 2>/dev/null || true
            xfconf-query -c xfce4-desktop -p "/backdrop/screen0/monitor$mon/workspace0/image-style" -s 5 --create -t int 2>/dev/null || true
            xfconf-query -c xfce4-desktop -p "/backdrop/screen0/monitor$mon/image-show" -s true --create -t bool 2>/dev/null || true
        done
        ui_log "Đã set wallpaper: $WALLPAPER"
    fi

    pick_dir() {
        pd_dir="$1"
        shift
        for t in "$@"; do
            if [ -d "$pd_dir/$t" ]; then
                printf '%s' "$t"
                return 0
            fi
        done
        printf ''
    }

    GTK_T=$(pick_dir /usr/share/themes Arc-Dark Materia-dark Numix Greybird Adwaita)
    ICO_T=$(pick_dir /usr/share/icons Papirus-Dark Numix-Circle Moka elementary-xfce-dark Adwaita)
    WM_T=$(pick_dir /usr/share/themes Arc-Dark Materia-dark Numix Greybird Adwaita)

    if [ -n "$GTK_T" ]; then
        xfconf-query -c xsettings -p /Net/ThemeName -s "$GTK_T" --create -t string 2>/dev/null || true
        xfconf-query -c xfwm4 -p /general/theme -s "$GTK_T" --create -t string 2>/dev/null || true
    fi
    if [ -n "$ICO_T" ]; then
        xfconf-query -c xsettings -p /Net/IconThemeName -s "$ICO_T" --create -t string 2>/dev/null || true
    fi
    xfconf-query -c xsettings -p /Gtk/CursorThemeName -s "Adwaita" --create -t string 2>/dev/null || true
    ui_log "Theme đã áp dụng: GTK=$GTK_T ICON=$ICO_T WM=$WM_T"

    PANEL_ID=$(xfconf-query -c xfce4-panel -l 2>/dev/null | grep '^/panels/panel-' | head -n 1 | cut -d/ -f3)
    if [ -z "$PANEL_ID" ]; then
        PANEL_ID="panel-1"
    fi
    xfconf-query -c xfce4-panel -p "/panels/$PANEL_ID/position" -s "p=10;x=0;y=0" --create -t string 2>/dev/null || true
    xfconf-query -c xfce4-panel -p "/panels/$PANEL_ID/length" -s 100 --create -t int 2>/dev/null || true
    xfconf-query -c xfce4-panel -p "/panels/$PANEL_ID/length-adjust" -s true --create -t bool 2>/dev/null || true
    xfconf-query -c xfce4-panel -p "/panels/$PANEL_ID/autohide-behavior" -s 2 --create -t int 2>/dev/null || true
    xfconf-query -c xfce4-panel -p "/panels/$PANEL_ID/position-locked" -s true --create -t bool 2>/dev/null || true
    ui_log "Đã cấu hình panel: $PANEL_ID"

    cat > /root/.dmas_theme.sh <<'SWEOF'
#!/bin/sh
echo "=== GTK themes đang có ==="
ls /usr/share/themes 2>/dev/null
echo "=== Icon themes đang có ==="
ls /usr/share/icons 2>/dev/null
printf 'Nhập tên GTK theme mới (Enter = giữ nguyên): '
read -r GT
printf 'Nhập tên icon theme mới (Enter = giữ nguyên): '
read -r IT
if [ -n "$GT" ]; then
    xfconf-query -c xsettings -p /Net/ThemeName -s "$GT" --create -t string 2>/dev/null || true
    xfconf-query -c xfwm4 -p /general/theme -s "$GT" --create -t string 2>/dev/null || true
fi
if [ -n "$IT" ]; then
    xfconf-query -c xsettings -p /Net/IconThemeName -s "$IT" --create -t string 2>/dev/null || true
fi
echo "Đã áp dụng."
SWEOF
    chmod 755 /root/.dmas_theme.sh 2>/dev/null || true
else
    ui_log "xfconf-query không tồn tại, bỏ qua cấu hình UI."
fi

exit 0
UIEOF

log "[RUN] sed thay URL wallpaper"
if ! sed "s#__WALLPAPER_URL__#$WALLPAPER_URL#" "$UI_SRC" > "$UI_OUT" 2>>"$LOG_FILE"; then
    fail "sed thay URL wallpaper thất bại"
fi

if command -v tr >/dev/null 2>&1; then
    if ! tr -d '\r' < "$UI_OUT" > "$UI_OUT.clean" 2>>"$LOG_FILE"; then
        fail "tr CRLF UI script thất bại"
    fi
    mv "$UI_OUT.clean" "$UI_OUT" || fail "mv UI script thất bại"
fi

log "[RUN] ghi /root/.dmas_ui_fix.sh vào container"
if ! proot-distro login "$DISTRO" -- /bin/sh -c 'cat > /root/.dmas_ui_fix.sh' < "$UI_OUT" >>"$LOG_FILE" 2>&1; then
    fail "Không ghi được /root/.dmas_ui_fix.sh"
fi

distro_cmd 'chmod UI script thất bại' 'chmod 755 /root/.dmas_ui_fix.sh'

cat <<'DEOF' > "$DESKTOP_SRC" || fail "Không ghi được desktop template"
[Desktop Entry]
Type=Application
Name=DMAS_UI_Fix
Exec=/root/.dmas_ui_fix.sh
OnlyShowIn=XFCE;
DEOF

if command -v tr >/dev/null 2>&1; then
    if ! tr -d '\r' < "$DESKTOP_SRC" > "$DESKTOP_OUT" 2>>"$LOG_FILE"; then
        fail "tr CRLF desktop file thất bại"
    fi
else
    if ! cat "$DESKTOP_SRC" > "$DESKTOP_OUT" 2>>"$LOG_FILE"; then
        fail "cat desktop file thất bại"
    fi
fi

log "[RUN] ghi /root/.config/autostart/dmas_ui.desktop vào container"
if ! proot-distro login "$DISTRO" -- /bin/sh -c 'cat > /root/.config/autostart/dmas_ui.desktop' < "$DESKTOP_OUT" >>"$LOG_FILE" 2>&1; then
    fail "Không ghi được /root/.config/autostart/dmas_ui.desktop"
fi

distro_cmd 'chmod desktop file thất bại' 'chmod 644 /root/.config/autostart/dmas_ui.desktop'

rm -f "$UI_SRC" "$UI_OUT" "$DESKTOP_SRC" "$DESKTOP_OUT" 2>/dev/null || true

draw_progress 92 "Bước 10/11 - Tạo startdmas.sh..."
START_SRC="$HOME/.startdmas.src.$$"
START_TMP="$HOME/.startdmas.tmp.$$"

cat <<'START_EOF' > "$START_SRC" || fail "Không ghi được startdmas.sh template"
#!/bin/sh
# Generated by linuxdmas.sh
# DO NOT EDIT THIS FILE WITH CRLF

ESC=$(printf '\033')
C_CYAN="${ESC}[38;2;0;220;255m"
C_GREEN="${ESC}[38;2;50;255;120m"
C_YELLOW="${ESC}[38;2;255;200;50m"
C_RED="${ESC}[38;2;255;80;80m"
C_RESET="${ESC}[0m"

DISTRO="__DMAS_DISTRO__"
DISPLAY_NUM=":0"
START_LOG="$HOME/.dmas_start.log"
CLEANED=0
XSERVER_PID=""

log() {
    printf '%s\n' "$*" >> "$START_LOG" 2>/dev/null || true
}

msg() {
    printf '%s\n' "$*"
    log "$*"
}

cleanup() {
    [ "$CLEANED" -eq 1 ] && return
    CLEANED=1

    log "Cleaning up Termux:X11 display ${DISPLAY_NUM}"

    if [ -n "$XSERVER_PID" ] && kill -0 "$XSERVER_PID" 2>/dev/null; then
        kill "$XSERVER_PID" 2>/dev/null || true
        sleep 1
        kill -9 "$XSERVER_PID" 2>/dev/null || true
    fi

    pkill -f "termux-x11 ${DISPLAY_NUM}" 2>/dev/null || true
    pkill -f "Xwayland ${DISPLAY_NUM}" 2>/dev/null || true

    termux-wake-unlock 2>/dev/null || true
}

on_signal() {
    cleanup
    exit 130
}

trap cleanup EXIT
trap on_signal INT TERM

if [ -z "$DISTRO" ]; then
    msg "[ERROR] DISTRO chưa được cấu hình trong startdmas.sh."
    exit 1
fi

command -v proot-distro >/dev/null 2>&1 || {
    msg "[ERROR] Thiếu proot-distro."
    exit 1
}

command -v termux-x11 >/dev/null 2>&1 || {
    msg "[ERROR] Thiếu termux-x11."
    exit 1
}

if ! proot-distro login "$DISTRO" -- /bin/sh -c true >/dev/null 2>&1; then
    msg "[ERROR] Container $DISTRO chưa tồn tại hoặc không đăng nhập được."
    exit 1
fi

termux-wake-lock 2>/dev/null || true

msg "${C_CYAN}[+] Đang dọn dẹp tiến trình X11 cũ cho display ${DISPLAY_NUM}...${C_RESET}"
pkill -f "termux-x11 ${DISPLAY_NUM}" 2>/dev/null || true
pkill -f "Xwayland ${DISPLAY_NUM}" 2>/dev/null || true
sleep 1

if [ -n "$TMPDIR" ]; then
    rm -f "$TMPDIR/.X11-unix/X0" "$TMPDIR/.X0-lock" 2>/dev/null || true
fi
rm -f /tmp/.X11-unix/X0 /tmp/.X0-lock 2>/dev/null || true

msg "${C_GREEN}[+] Mở ứng dụng Termux:X11...${C_RESET}"
if command -v am >/dev/null 2>&1; then
    am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >>"$START_LOG" 2>&1 || log "[WARN] am start failed"
else
    log "[WARN] am không khả dụng"
fi

sleep 2

msg "${C_GREEN}[+] Khởi chạy termux-x11 server ${DISPLAY_NUM}...${C_RESET}"
termux-x11 "$DISPLAY_NUM" -ac >>"$START_LOG" 2>&1 &
XSERVER_PID=$!

SOCKET=""
if [ -n "$TMPDIR" ]; then
    SOCKET="$TMPDIR/.X11-unix/X0"
else
    SOCKET="/tmp/.X11-unix/X0"
fi

i=0
while [ "$i" -lt 20 ]; do
    if [ -e "$SOCKET" ]; then
        break
    fi
    sleep 1
    i=$((i + 1))
done

if [ ! -e "$SOCKET" ]; then
    msg "[ERROR] Không tìm thấy X11 socket $SOCKET."
    exit 1
fi

msg "${C_GREEN}[+] Đang đăng nhập vào $DISTRO XFCE4...${C_RESET}"

proot-distro login "$DISTRO" --shared-tmp --env DISPLAY="$DISPLAY_NUM" -- /bin/sh -c 'export LANG=en_US.UTF-8; export LC_ALL=en_US.UTF-8; if ! command -v dbus-launch >/dev/null 2>&1; then echo "[ERROR] dbus-launch không tồn tại trong container." >&2; exit 70; fi; if ! command -v startxfce4 >/dev/null 2>&1; then echo "[ERROR] startxfce4 không tồn tại trong container." >&2; exit 71; fi; mkdir -p /tmp/xdg 2>/dev/null || true; chmod 700 /tmp/xdg 2>/dev/null || true; exec dbus-launch --exit-with-session startxfce4'
rc=$?

if [ "$rc" -eq 70 ]; then
    msg "[ERROR] DBus thiếu/không khởi động được."
fi

if [ "$rc" -eq 71 ]; then
    msg "[ERROR] XFCE4 thiếu/không khởi động được."
fi

if [ "$rc" -ne 0 ]; then
    msg "[!] XFCE thoát với mã $rc."
fi

exit "$rc"
START_EOF

log "[RUN] sed thay DISTRO vào startdmas.sh"
if ! sed "s#__DMAS_DISTRO__#$DISTRO#" "$START_SRC" > "$START_TMP" 2>>"$LOG_FILE"; then
    fail "sed thay DISTRO vào startdmas.sh thất bại"
fi

if command -v tr >/dev/null 2>&1; then
    if ! tr -d '\r' < "$START_TMP" > "$START_TMP.clean" 2>>"$LOG_FILE"; then
        fail "tr CRLF startdmas.sh thất bại"
    fi
    mv "$START_TMP.clean" "$START_TMP" || fail "mv startdmas.sh thất bại"
fi

PREV_CAND=""
for cand in "$PWD/startdmas.sh" "$HOME/startdmas.sh"; do
    if [ "$cand" = "$PREV_CAND" ]; then
        continue
    fi
    PREV_CAND=$cand
    if cp "$START_TMP" "$cand" 2>>"$LOG_FILE"; then
        chmod +x "$cand" 2>/dev/null || true
        log "[INFO] Đã ghi launcher: $cand"
    else
        warn "Không ghi được launcher vào $cand"
    fi
done

rm -f "$START_SRC" "$START_TMP" 2>/dev/null || true

START_SCRIPT=""
RUN_CMD=""
if [ -x "$PWD/startdmas.sh" ]; then
    START_SCRIPT="$PWD/startdmas.sh"
    RUN_CMD="./startdmas.sh"
elif [ -x "$HOME/startdmas.sh" ]; then
    START_SCRIPT="$HOME/startdmas.sh"
    RUN_CMD="~/startdmas.sh"
    warn "Thư mục hiện tại ($PWD) không hỗ trợ quyền thực thi (thường gặp trên /sdcard). Launcher chính: ~/startdmas.sh"
elif [ -f "$HOME/startdmas.sh" ]; then
    START_SCRIPT="$HOME/startdmas.sh"
    RUN_CMD="sh ~/startdmas.sh"
    warn "Filesystem không hỗ trợ exec. Chạy bằng: sh ~/startdmas.sh"
elif [ -f "$PWD/startdmas.sh" ]; then
    START_SCRIPT="$PWD/startdmas.sh"
    RUN_CMD="sh $PWD/startdmas.sh"
    warn "Filesystem không hỗ trợ exec. Chạy bằng: $RUN_CMD"
else
    fail "Không ghi được startdmas.sh ở cả $PWD và $HOME."
fi

log "[RUN] sh -n $START_SCRIPT"
if ! sh -n "$START_SCRIPT" >>"$LOG_FILE" 2>&1; then
    fail "startdmas.sh không pass sh -n"
fi

info "Đã tạo và kiểm tra syntax: $START_SCRIPT (chạy bằng: $RUN_CMD)"

draw_progress 97 "Bước 11/11 - Kiểm tra cuối cùng..."

if [ -f "$0" ]; then
    if sh -n "$0" >>"$LOG_FILE" 2>&1; then
        info "sh -n linuxdmas.sh pass"
    else
        warn "sh -n linuxdmas.sh báo lỗi (bất thường vì script đang chạy)."
    fi
fi

if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$0" >>"$LOG_FILE" 2>&1; then
        info "shellcheck linuxdmas.sh pass"
    else
        warn "shellcheck linuxdmas.sh có cảnh báo (không chặn cài đặt)."
    fi

    if shellcheck "$START_SCRIPT" >>"$LOG_FILE" 2>&1; then
        info "shellcheck startdmas.sh pass"
    else
        warn "shellcheck startdmas.sh có cảnh báo (không chặn cài đặt)."
    fi
else
    info "shellcheck không tồn tại; bỏ qua lint bổ sung."
fi

if [ ! -f "$START_SCRIPT" ]; then
    fail "startdmas.sh không tồn tại: $START_SCRIPT"
fi

touch "$SETUP_FLAG" || fail "Không tạo được success flag"
log "[INFO] Success flag đã tạo: $SETUP_FLAG"

draw_progress 100 "Cài đặt thành công! Tự khởi động desktop..."

printf '%s\n' "${C_GREEN}[+] Cài đặt hoàn tất.${C_RESET}"
printf '%s\n' "${C_GREEN}[+] Editor chính theo thiết kế: VS Code.${C_RESET}"
if [ "$PKG_EDITOR" = "code" ]; then
    printf '%s\n' "${C_GREEN}[+] VS Code đã được cài và xác minh.${C_RESET}"
else
    printf '%s\n' "${C_YELLOW}[!] VS Code không khả dụng trên môi trường này; Geany đang là fallback.${C_RESET}"
fi
printf '%s\n' "${C_CYAN}[+] Đổi theme thủ công trong XFCE: ${C_YELLOW}/root/.dmas_theme.sh${C_RESET}"
printf '%s\n' "${C_CYAN}[+] Log cài đặt: ${C_YELLOW}$LOG_FILE${C_RESET}"
printf '%s\n' "${C_GREEN}[+] Tự khởi chạy $RUN_CMD sau 3 giây... (Ctrl+C trong 3s để hủy)${C_RESET}"
sleep 3

if [ -x "$HOME/startdmas.sh" ]; then
    "$HOME/startdmas.sh"
    LAUNCH_RC=$?
else
    sh "$HOME/startdmas.sh"
    LAUNCH_RC=$?
fi

info "Desktop đã thoát (mã $LAUNCH_RC). Chạy lại bất cứ lúc nào bằng: $RUN_CMD"
