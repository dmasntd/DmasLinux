#!/bin/sh
# Bản v2 sử dụng nhiều nhân CPU để tăng tốc

ESC=$(printf '\033')
C_CYAN="${ESC}[38;2;0;220;255m"
C_GREEN="${ESC}[38;2;50;255;120m"
C_YELLOW="${ESC}[38;2;255;200;50m"
C_MAGENTA="${ESC}[38;2;235;90;255m"
C_RED="${ESC}[38;2;255;80;80m"
C_RESET="${ESC}[0m"
TAG="${C_CYAN}[DmasLinux]${C_RESET}"

SETUP_FLAG="$HOME/.dmas_setup_done"
LOG_FILE="$HOME/.dmas_install.log"
STATE_FILE="$HOME/.dmas_distro"
WALLPAPER_URL="https://raw.githubusercontent.com/dmasntd/DmasLinux/main/dmaslinux.png"
PANEL1_IMG_URL="${DMAS_PANEL1_IMG:-https://raw.githubusercontent.com/dmasntd/DmasLinux/main/panel1.png}"
PANEL2_IMG_URL="${DMAS_PANEL2_IMG:-https://raw.githubusercontent.com/dmasntd/DmasLinux/main/panel2.png}"
PKG_EDITOR="code"
PKG_BROWSER="firefox"

APT_IPV4_OPT=""
if [ "${DMAS_FORCE_IPV4:-0}" = "1" ]; then
APT_IPV4_OPT="-o Acquire::ForceIPv4=true "
fi
APT_OPTS="-o APT::Sandbox::User=root -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 -o Acquire::Retries=3 ${APT_IPV4_OPT}"

log() { printf '%s\n' "$*" >>"$LOG_FILE" 2>/dev/null || true; }
say() { printf '%s => %s\n' "$TAG" "$*"; log "[INFO] $*"; }
okay() { printf '%s => %s%s%s\n' "$TAG" "$C_GREEN" "$*" "$C_RESET"; log "[OK] $*"; }
warn() { printf '%s => %s[!] %s%s\n' "$TAG" "$C_YELLOW" "$*" "$C_RESET"; log "[WARN] $*"; }
err() { printf '%s => %s[x] %s%s\n' "$TAG" "$C_RED" "$*" "$C_RESET"; log "[ERROR] $*"; }
fail() { printf '\n'; err "$1"; err "Installer dừng an toàn. Container/dữ liệu được giữ nguyên."; err "Log: $LOG_FILE"; exit 1; }

ROOTED="no"
if [ "$(id -u 2>/dev/null)" = "0" ]; then
ROOTED="yes"
elif [ -x /data/adb/magisk/magisk ] || command -v magisk >/dev/null 2>&1; then
ROOTED="yes"
elif command -v su >/dev/null 2>&1 && su -c 'id -u' 2>/dev/null | grep -q '^0'; then
ROOTED="yes"
fi

BL_STATE="unknown"
_fb=$(getprop ro.boot.flash.locked 2>/dev/null)
if [ "$_fb" = "0" ]; then BL_STATE="UNLOCKED"
elif [ "$_fb" = "1" ]; then BL_STATE="LOCKED"
else
_vb=$(getprop ro.boot.verifiedbootstate 2>/dev/null)
case "$_vb" in
green) BL_STATE="LOCKED" ;;
orange|yellow|red) BL_STATE="UNLOCKED" ;;
*) BL_STATE="UNKNOWN" ;;
esac
fi

CORES=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 2)
[ "$CORES" -ge 1 ] 2>/dev/null || CORES=2
PERF_CPUS=""; EFF_CPUS=""
if [ -d /sys/devices/system/cpu ]; then
_maxf=0
for _f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/cpuinfo_max_freq; do
_v=$(cat "$_f" 2>/dev/null); [ "$_v" -gt "$_maxf" ] 2>/dev/null && _maxf=$_v
done
for _d in /sys/devices/system/cpu/cpu[0-9]*; do
_n=${_d##*/cpu}; _v=$(cat "$_d/cpufreq/cpuinfo_max_freq" 2>/dev/null)
if [ "$_maxf" -gt 0 ] 2>/dev/null && [ -n "$_v" ] && [ "$((_v * 100 / _maxf))" -ge 80 ] 2>/dev/null; then
PERF_CPUS="$PERF_CPUS,$_n"; else EFF_CPUS="$EFF_CPUS,$_n"; fi
done
PERF_CPUS=${PERF_CPUS#,}; EFF_CPUS=${EFF_CPUS#,}
fi
[ -n "$PERF_CPUS" ] || PERF_CPUS="0-$((CORES - 1))"
HAS_TASKSET="no"; command -v taskset >/dev/null 2>&1 && HAS_TASKSET="yes"
HAS_RENICE="no"; command -v renice >/dev/null 2>&1 && HAS_RENICE="yes"

UPDATE_MODE=0
[ -f "$SETUP_FLAG" ] && UPDATE_MODE=1

LOCK_DIR="$HOME/.dmas_install.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
err "Một bản cài DMAS khác đang chạy (lock: $LOCK_DIR)."
say "Nếu chắc chắn không còn tiến trình nào: rm -rf $LOCK_DIR"
exit 1
fi
release_lock() { rmdir "$LOCK_DIR" 2>/dev/null || true; }

POOL_DIR=""; POOL_PIDS=""; POOL_META=""; POOL_BOOSTED=""
stop_all() {
err "Nhận Ctrl+C / Ctrl+Z / TERM -> dừng TOÀN BỘ tiến trình cài đặt..."
for _p in $POOL_PIDS; do kill -9 "$_p" 2>/dev/null || true; done
[ -n "$POOL_DIR" ] && rm -rf "$POOL_DIR" 2>/dev/null
release_lock
exit 130
}
trap stop_all INT TSTP TERM
trap release_lock EXIT

[ -d "$HOME" ] && [ -w "$HOME" ] || { printf '[ERROR] $HOME không ghi được.\n'; exit 1; }
: >>"$LOG_FILE" || { printf '[ERROR] Không tạo được log %s\n' "$LOG_FILE"; exit 1; }
printf '\n==== DMAS installer run %s ====\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo unknown)" >>"$LOG_FILE"

pool_max() {
_pm=$CORES
if [ "$ROOTED" = "yes" ]; then _pm=$((CORES * 2)); [ $_pm -gt 16 ] && _pm=16
else [ $_pm -gt 8 ] && _pm=8; fi
[ $_pm -lt 1 ] && _pm=1
echo $_pm
}
pool_init() {
POOL_TAG=$$
POOL_DIR="$TMPDIR/dmas_pool.$POOL_TAG"
[ -n "$POOL_DIR" ] || POOL_DIR="/tmp/dmas_pool.$POOL_TAG"
rm -rf "$POOL_DIR" 2>/dev/null
mkdir -p "$POOL_DIR/debs" || return 1
: > "$POOL_DIR/failed.list"
POOL_PIDS=""; POOL_META=""; POOL_BOOSTED=""
return 0
}
pool_spawn() {
_w=$1
_now=$(date +%s)
proot-distro login "$DISTRO" --shared-tmp -- /bin/sh -c "P=/tmp/dmas_pool.$POOL_TAG; for u in \$(cat \$P/w$_w 2>/dev/null); do b=\${u##*/}; f=\$P/debs/\$b; if [ -s \"\$f\" ]; then continue; fi; if wget -q -T 90 -O \"\$f.part\" \"\$u\" 2>/dev/null || curl -fsSL --max-time 90 -o \"\$f.part\" \"\$u\" 2>/dev/null; then mv \"\$f.part\" \"\$f\" && echo \"\$b\" >> \$P/done.list; else rm -f \"\$f.part\"; echo \"\$u\" >> \$P/failed.list; fi; done; echo done > \$P/st.w$_w" >>"$LOG_FILE" 2>&1 &
_pid=$!
POOL_PIDS="$POOL_PIDS $_pid"
POOL_META="$POOL_META $_pid:$_w:$_now"
}
pool_active_list() {
_al=""
for _m in $POOL_META; do
_pid=${_m%%:*}; _r=${_m#*:}; _w=${_r%%:*}
[ -f "$POOL_DIR/st.w$_w" ] || _al="$_al $_m"
done
echo "$_al"
}
pool_boost() {
[ "$HAS_TASKSET" = "yes" ] || [ "$HAS_RENICE" = "yes" ] || return 0
_now=$(date +%s); _best=""; _bestel=0
for _m in $(pool_active_list); do
_pid=${_m%%:*}; _r=${_m#*:}; _t0=${_r##*:}
_el=$((_now - _t0))
[ $_el -gt $_bestel ] && { _bestel=$_el; _best=$_pid; }
done
[ -n "$_best" ] || return 0
case " $POOL_BOOSTED " in
*" $_best "*) ;;
*)
if [ "$ROOTED" = "yes" ] && [ "$HAS_RENICE" = "yes" ]; then renice -n -10 -p "$_best" >/dev/null 2>&1 || true; fi
[ "$HAS_TASKSET" = "yes" ] && taskset -pc "$PERF_CPUS" "$_best" >/dev/null 2>&1 || true
POOL_BOOSTED="$POOL_BOOSTED $_best"
say "Boost CPU cho tiến trình tải lâu nhất (pid $_best, ${_bestel}s) -> nhân hiệu năng cao [$PERF_CPUS]"
;;
esac
if [ "$ROOTED" = "yes" ] && [ "$HAS_TASKSET" = "yes" ] && [ -n "$EFF_CPUS" ]; then
for _m in $(pool_active_list); do
_pid=${_m%%:*}
[ "$_pid" = "$_best" ] && continue
taskset -pc "$EFF_CPUS" "$_pid" >/dev/null 2>&1 || true
done
fi
}
pool_wait() {
_tick=0
while :; do
_act=$(pool_active_list)
[ -z "$(echo "$_act" | tr -d ' ')" ] && break
_tick=$((_tick + 1))
[ $((_tick % 3)) -eq 0 ] && pool_boost
sleep 1
done
for _p in $POOL_PIDS; do wait "$_p" 2>/dev/null || true; done
}
pool_kill_all() { for _p in $POOL_PIDS; do kill -9 "$_p" 2>/dev/null || true; done; }

distro_exec() { proot-distro login "$DISTRO" -- /bin/sh -c "$1" >>"$LOG_FILE" 2>&1; }
distro_cap() { proot-distro login "$DISTRO" -- /bin/sh -c "$1" 2>/dev/null; }
distro_exec_live() {
proot-distro login "$DISTRO" -- /bin/sh -c "$1" >>"$LOG_FILE" 2>&1 &
_lp=$!; POOL_PIDS="$POOL_PIDS $_lp"
while kill -0 "$_lp" 2>/dev/null; do
_last=$(tail -n 1 "$LOG_FILE" 2>/dev/null | tr -d '\r' | cut -c1-46)
printf '\r\033[K%s => %s%s' "$TAG" "$C_MAGENTA" "$_last${C_RESET}"
sleep 5
done
wait "$_lp"; _rc=$?
printf '\r\033[K'
return $_rc
}
distro_cmd() { dc_d=$1; dc_c=$2; log "[DISTRO-CMD] $dc_c"; distro_exec "$dc_c" || fail "$dc_d"; }
distro_cmd_live() { dc_d=$1; dc_c=$2; log "[DISTRO-CMD-LIVE] $dc_c"; distro_exec_live "$dc_c" || fail "$dc_d"; }
try_distro() { td_d=$1; td_c=$2; log "[DISTRO-TRY] $td_c"; if distro_exec "$td_c"; then return 0; fi; warn "$td_d"; return 1; }
run() { r_d=$1; shift; log "[RUN] $*"; "$@" >>"$LOG_FILE" 2>&1 || fail "$r_d"; }
run_warn() { r_d=$1; shift; log "[RUN-WARN] $*"; "$@" >>"$LOG_FILE" 2>&1 || { warn "$r_d"; return 1; }; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || fail "Lệnh quan trọng '$1' không tồn tại."; }

show_banner() {
command -v clear >/dev/null 2>&1 && clear || printf '\033[2J\033[H'
printf '%s\n' "${C_CYAN}+---------------------------------------------------+${C_RESET}"
printf '%s\n' "${C_MAGENTA}|          LINUX DMAS AUTOMATED INSTALLER           |${C_RESET}"
printf '%s\n' "${C_CYAN}+---------------------------------------------------+${C_RESET}"
printf '%s => Android Version : %s\n' "$TAG" "$(getprop ro.build.version.release 2>/dev/null || echo N/A)"
printf '%s => Kernel Version  : %s\n' "$TAG" "$(uname -r 2>/dev/null || echo N/A)"
printf '%s => OS Environment  : Termux (Android)\n' "$TAG"
printf '%s => Architecture    : %s\n' "$TAG" "$(uname -m 2>/dev/null || echo N/A)"
printf '%s => CPU Cores       : %s (perf: %s)\n' "$TAG" "$CORES" "$PERF_CPUS"
printf '%s => Bootloader      : %s\n' "$TAG" "$BL_STATE"
printf '%s => Root            : %s\n' "$TAG" "$ROOTED"
printf '%s\n' "${C_CYAN}+---------------------------------------------------+${C_RESET}"
}
draw_progress() {
pct=$1; msg=$2; width=20
filled=$((pct * width / 100)); empty=$((width - filled))
bar=""; i=0
while [ "$i" -lt "$filled" ]; do bar="${bar}#"; i=$((i + 1)); done
i=0
while [ "$i" -lt "$empty" ]; do bar="${bar}-"; i=$((i + 1)); done
printf '\r\033[K%s[%s%s%s]%s %s%3d%%%s => %s' "$C_CYAN" "$C_GREEN" "$bar" "$C_CYAN" "$C_RESET" "$C_YELLOW" "$pct" "$C_RESET" "$msg"
[ "$pct" -eq 100 ] && printf '\n'
return 0
}

install_vscode_debian() {
VC_STEP="Kiểm tra VS Code đã tồn tại"
log "[VSCODE] $VC_STEP"
distro_exec 'command -v code >/dev/null 2>&1' && return 0
VC_STEP="Cài dependency VS Code"
distro_exec "export DEBIAN_FRONTEND=noninteractive; apt-get $APT_OPTS update -y >/dev/null 2>&1 || true; apt-get $APT_OPTS install -y wget curl ca-certificates gnupg apt-transport-https" || return 1
VC_STEP="Cài Microsoft signing key"
distro_exec 'install -m 0755 -d /etc/apt/keyrings && wget -qO /tmp/microsoft.asc https://packages.microsoft.com/keys/microsoft.asc && gpg --dearmor < /tmp/microsoft.asc > /etc/apt/keyrings/microsoft.gpg.tmp && mv /etc/apt/keyrings/microsoft.gpg.tmp /etc/apt/keyrings/microsoft.gpg && chmod a+r /etc/apt/keyrings/microsoft.gpg' || return 1
VC_STEP="Thêm repo VS Code"
distro_exec 'ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m); case "$ARCH" in amd64|arm64) : ;; x86_64) ARCH=amd64 ;; aarch64) ARCH=arm64 ;; *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;; esac; echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list' || return 1
VC_STEP="apt update với repo VS Code"
distro_exec "export DEBIAN_FRONTEND=noninteractive; apt-get $APT_OPTS update -y" || log "[WARN] apt update repo VS Code lỗi; vẫn thử cài."
VC_STEP="Cài gói code"
LIVE_DESC="Cài gói code (VS Code)..."
distro_exec_live "export DEBIAN_FRONTEND=noninteractive; apt-get $APT_OPTS install -y code" || { LIVE_DESC=""; return 1; }
LIVE_DESC=""
VC_STEP="Xác minh VS Code"
distro_exec 'command -v code >/dev/null 2>&1' && return 0
return 1
}
install_vscode_fedora() {
VC_STEP="Kiểm tra VS Code đã tồn tại"
distro_exec 'command -v code >/dev/null 2>&1' && return 0
VC_STEP="Cài dependency + key + repo VS Code"
distro_exec 'dnf install -y curl wget gnupg || yum install -y curl wget gnupg' || return 1
distro_exec 'rpm --import https://packages.microsoft.com/keys/microsoft.asc || { wget -qO /tmp/microsoft.asc https://packages.microsoft.com/keys/microsoft.asc && rpm --import /tmp/microsoft.asc; }' || return 1
distro_exec 'cat > /etc/yum.repos.d/vscode.repo <<EOF
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
' || return 1
distro_exec 'dnf clean all --enablerepo=code >/dev/null 2>&1 || true; dnf makecache --refresh >/dev/null 2>&1 || true' || true
VC_STEP="Cài gói code"
LIVE_DESC="Cài gói code (VS Code)..."
distro_exec_live "dnf -y --setopt=max_parallel_downloads=$CORES install code" || { LIVE_DESC=""; return 1; }
LIVE_DESC=""
distro_exec 'command -v code >/dev/null 2>&1' && return 0
return 1
}
apply_vscode_proot_fix() {
say "Áp dụng wrapper proot cho VS Code (--no-sandbox, retry, log lỗi)..."
distro_exec 'if [ -x /usr/bin/code ]; then printf "#!/bin/sh\nexport DISPLAY=\"\${DISPLAY:-:0}\"\nexport LIBGL_ALWAYS_SOFTWARE=1\nLOG=/root/.dmas_code.log\necho \"=== run \$(date) args: \$*\" >>\"\$LOG\"\n/usr/bin/code --no-sandbox --disable-gpu --disable-dev-shm-usage --no-zygote \"\$@\" 2>>\"\$LOG\"\nrc=\$?\nif [ \"\$rc\" -ne 0 ]; then\n echo \"[dmas] rc=\$rc -> retry bo --no-zygote\" >>\"\$LOG\"\n /usr/bin/code --no-sandbox --disable-gpu --disable-dev-shm-usage \"\$@\" 2>>\"\$LOG\"\n rc=\$?\nfi\nif [ \"\$rc\" -ne 0 ]; then\n echo \"[dmas] rc=\$rc -> retry chi --no-sandbox\" >>\"\$LOG\"\n /usr/bin/code --no-sandbox \"\$@\" 2>>\"\$LOG\"\n rc=\$?\nfi\nexit \"\$rc\"\n" > /usr/local/bin/code && chmod 755 /usr/local/bin/code && sed -i "s|^Exec=/usr/bin/code|Exec=/usr/local/bin/code|" /usr/share/applications/code.desktop 2>/dev/null; echo DMAS_VSCODE_WRAPPER_OK; fi' || warn "Không tạo được wrapper VS Code."
}

install_firefox_debian() {
distro_exec '[ -x /usr/lib/firefox/firefox ] || [ -x /usr/lib/firefox-esr/firefox-esr ]' && { okay "Firefox thật đã có sẵn."; return 0; }
distro_exec 'dpkg-query -W -f="${Version}" firefox 2>/dev/null | grep -q snap' && {
warn "Gói firefox của Ubuntu là stub snap -> gỡ stub..."
distro_exec 'export DEBIAN_FRONTEND=noninteractive; apt-get remove -y firefox || true; apt-get autoremove -y --purge snapd || true' || true
}
if try_distro 'Cài firefox-esr (distro) thất bại' "export DEBIAN_FRONTEND=noninteractive; apt-get $APT_OPTS install -y firefox-esr"; then
distro_exec '[ -x /usr/lib/firefox-esr/firefox-esr ]' && { okay "Firefox ESR đã cài."; return 0; }
fi
warn "Repo distro không có Firefox thật -> dùng repo Mozilla chính chủ."
distro_exec 'install -d -m 0755 /etc/apt/keyrings && { wget -q -T 30 -O /tmp/mozilla.asc https://packages.mozilla.org/apt/repo/signing.key || curl -fsSL --max-time 30 -o /tmp/mozilla.asc https://packages.mozilla.org/apt/repo/signing.key; } && [ -s /tmp/mozilla.asc ] && gpg --dearmor < /tmp/mozilla.asc > /etc/apt/keyrings/mozilla.gpg.tmp && mv /etc/apt/keyrings/mozilla.gpg.tmp /etc/apt/keyrings/mozilla.gpg && chmod a+r /etc/apt/keyrings/mozilla.gpg && echo "deb [signed-by=/etc/apt/keyrings/mozilla.gpg] https://packages.mozilla.org/apt/repo mozilla main" > /etc/apt/sources.list.d/mozilla.list' || { warn "Không thêm được repo Mozilla."; return 1; }
distro_exec "export DEBIAN_FRONTEND=noninteractive; apt-get $APT_OPTS update -y" || true
if try_distro 'Cài Firefox (Mozilla) thất bại' "export DEBIAN_FRONTEND=noninteractive; apt-get $APT_OPTS install -y --no-install-recommends firefox"; then
distro_exec '[ -x /usr/lib/firefox/firefox ]' && { okay "Firefox (Mozilla deb) đã cài."; return 0; }
fi
warn "Không cài được Firefox bằng mọi cách (không chặn cài đặt)."
return 1
}

show_banner
[ "$UPDATE_MODE" -eq 1 ] && say "Đã setup trước -> CHẾ ĐỘ CẬP NHẬT & SỬA CHỮA (chỉ cài thứ thiếu)."
say "Theo dõi trực tiếp: mở session mới chạy tail -f $LOG_FILE"

draw_progress 5 "Kiểm tra môi trường Termux"
need_cmd pkg; need_cmd uname

draw_progress 10 "Cài/kiểm tra gói Termux"
run_warn "pkg update thất bại (dùng chỉ mục hiện có)." pkg update -y
command -v termux-x11 >/dev/null 2>&1 || run "Cài x11-repo thất bại" pkg install -y x11-repo
TERMUX_PKGS=""
command -v proot-distro >/dev/null 2>&1 || TERMUX_PKGS="$TERMUX_PKGS proot-distro"
command -v termux-x11 >/dev/null 2>&1 || TERMUX_PKGS="$TERMUX_PKGS termux-x11-nightly"
command -v wget >/dev/null 2>&1 || TERMUX_PKGS="$TERMUX_PKGS wget"
command -v curl >/dev/null 2>&1 || TERMUX_PKGS="$TERMUX_PKGS curl"
if [ -n "$TERMUX_PKGS" ]; then

run "Cài gói Termux thiếu thất bại" pkg install -y $TERMUX_PKGS
else okay "Gói Termux đã đủ."; fi
need_cmd proot-distro; need_cmd termux-x11
command -v wget >/dev/null 2>&1 || command -v curl >/dev/null 2>&1 || fail "Thiếu wget và curl."

draw_progress 15 "Kiểm tra Termux:X11 Android app"
if command -v pm >/dev/null 2>&1 && pm list packages 2>/dev/null | grep -q "package:com.termux.x11"; then
okay "Termux:X11 Android app đã cài."
else warn "Không thấy package com.termux.x11 -> cài APK Termux:X11 nếu GUI không mở."; fi

printf '\n'
draw_progress 20 "Chọn distro (Enter/bậy = ubuntu)"
printf '%s => 1) Ubuntu  2) Debian  3) Fedora\n' "$TAG"
printf '%s => Nhập lựa chọn [1-3]: %s' "$TAG" "$C_RESET"
read -r DISTRO_CHOICE || DISTRO_CHOICE=""
case "$DISTRO_CHOICE" in
2|debian|Debian) DISTRO="debian" ;;
3|fedora|Fedora) DISTRO="fedora" ;;
*) DISTRO="ubuntu" ;;
esac
okay "Distro được chọn: $DISTRO"

draw_progress 30 "Kiểm tra container $DISTRO"
CONTAINER_EXISTS=0
if [ -n "$PREFIX" ] && [ -d "$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO" ]; then CONTAINER_EXISTS=1; fi
if [ "$CONTAINER_EXISTS" -eq 0 ] && proot-distro login "$DISTRO" -- /bin/sh -c true >/dev/null 2>&1; then CONTAINER_EXISTS=1; fi
if [ "$CONTAINER_EXISTS" -eq 1 ]; then
okay "Container $DISTRO đã tồn tại -> giữ nguyên, chỉ cài thứ thiếu."
else
say "Cài container $DISTRO (lần đầu)..."
run_live "Cài container $DISTRO thất bại" proot-distro install "$DISTRO"
fi
proot-distro login "$DISTRO" -- /bin/sh -c true >>"$LOG_FILE" 2>&1 || fail "Container $DISTRO không đăng nhập được."
printf '%s\n' "$DISTRO" > "$STATE_FILE"

draw_progress 45 "Sửa lỗi kẹt lần trước + cài gói nền (song song)"
if [ "$ROOTED" = "yes" ]; then
distro_exec 'mkdir -p /etc/dpkg/dpkg.cfg.d 2>/dev/null && echo force-unsafe-io > /etc/dpkg/dpkg.cfg.d/dmas-speed 2>/dev/null' || true
say "Root: bật dpkg force-unsafe-io để tăng tốc install."
fi
if [ "$DISTRO" = "fedora" ]; then
try_distro 'Sửa transaction dnf kẹt thất bại' 'dnf -y complete-transaction || true; dnf clean all || true; dnf makecache --refresh || true'
distro_cmd_live 'Cài gói nền Fedora thất bại' "miss=\"\"; for p in xfce4-session xfwm4 xfce4-panel xfdesktop xfce4-terminal Thunar dbus-x11 curl wget git gnupg glibc-langpack-en; do rpm -q \"\$p\" >/dev/null 2>&1 || miss=\"\$miss \$p\"; done; if [ -n \"\$miss\" ]; then case \"\$miss\" in *xfce4-session*) dnf -y --setopt=max_parallel_downloads=$CORES groupinstall \"Xfce Desktop\" || dnf -y --setopt=max_parallel_downloads=$CORES install \$miss || true ;; *) dnf -y --setopt=max_parallel_downloads=$CORES install \$miss || true ;; esac; else echo DMAS_FEDORA_BASE_OK; fi"
try_distro 'Cài bộ theme Fedora thất bại' "miss=\"\"; for p in arc-theme numix-gtk-theme materia-gtk-theme greybird-gtk-theme gnome-themes-extra papirus-icon-theme numix-icon-theme numix-icon-theme-circle moka-icon-theme adwaita-icon-theme breeze-icon-theme capitaine-cursors openzone-cursors comixcursors google-noto-emoji-color-fonts jetbrains-mono-fonts firacode-fonts; do rpm -q \"\$p\" >/dev/null 2>&1 || miss=\"\$miss \$p\"; done; if [ -n \"\$miss\" ]; then dnf -y --setopt=max_parallel_downloads=$CORES install \$miss || for p in \$miss; do dnf -y install \"\$p\" || true; done; else echo DMAS_FEDORA_THEME_OK; fi"
else
try_distro 'Sửa dpkg/apt kẹt lần trước thất bại' 'if command -v flock >/dev/null 2>&1; then i=0; while [ "$i" -lt 60 ]; do if flock -n /var/lib/dpkg/lock-frontend true 2>/dev/null; then break; fi; sleep 2; i=$((i+2)); done; fi; holder=0; for c in /proc/[0-9]*/comm; do if [ -r "$c" ] && grep -q -e "^apt-get" -e "^dpkg" "$c" 2>/dev/null; then holder=1; break; fi; done; if [ "$holder" -eq 0 ]; then rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock /var/lib/apt/lists/lock 2>/dev/null || true; else echo "DMAS: lock còn được giữ bởi process sống."; fi; dpkg --configure -a || true; apt-get install -f -y || true'
try_distro 'Cập nhật apt thất bại' "export DEBIAN_FRONTEND=noninteractive; apt-get $APT_OPTS update -y"

MISS_LIST=$(distro_cap 'miss=""; for p in dbus-x11 xfce4 xfce4-terminal thunar curl wget ca-certificates gnupg apt-transport-https locales git xfce4-goodies arc-theme numix-gtk-theme greybird-gtk-theme gnome-themes-extra gtk2-engines-murrine gtk2-engines-pixbuf papirus-icon-theme numix-icon-theme numix-icon-theme-circle moka-icon-theme elementary-xfce-icon-theme adwaita-icon-theme tango-icon-theme gnome-icon-theme suru-icon-theme faenza-icon-theme breeze-icon-theme humanity-icon-theme comixcursors fonts-ubuntu fonts-noto-color-emoji fonts-firacode fonts-jetbrains-mono; do dpkg -s "$p" >/dev/null 2>&1 || miss="$miss $p"; done; echo $miss')
if [ -z "$(echo "$MISS_LIST" | tr -d ' ')" ]; then
okay "Gói nền + theme Debian/Ubuntu đã đủ."
elif pool_init; then
say "Thiếu: $MISS_LIST"
URIS=$(distro_cap "export DEBIAN_FRONTEND=noninteractive; apt-get $APT_OPTS install -y --print-uris $MISS_LIST 2>/dev/null | sed -n \"s/^'\\(http[^']*\\)'.*/\\1/p\"")
UCOUNT=$(printf '%s\n' "$URIS" | grep -c '^http' 2>/dev/null || echo 0)
if [ "$UCOUNT" -gt 0 ] 2>/dev/null; then
WORKERS=$(pool_max); [ "$WORKERS" -gt "$UCOUNT" ] && WORKERS=$UCOUNT
say "Tải song song $UCOUNT gói .deb bằng $WORKERS tiến trình con (root=$ROOTED)..."
printf '%s\n' "$URIS" | grep '^http' > "$POOL_DIR/urls.list"
awk -v n="$WORKERS" '{print > (sprintf("%s/w%d", ENVIRON["POOL_DIR"], NR % n))}' "$POOL_DIR/urls.list" 2>/dev/null POOL_DIR="$POOL_DIR" || {
i=0
while IFS= read -r _u; do printf '%s\n' "$_u" >> "$POOL_DIR/w$((i % WORKERS))"; i=$((i + 1)); done < "$POOL_DIR/urls.list"
}
wi=0
while [ "$wi" -lt "$WORKERS" ]; do
[ -s "$POOL_DIR/w$wi" ] && pool_spawn "$wi"
wi=$((wi + 1))
done
pool_wait
say "Tải song song hoàn tất -> kiểm tra mục lỗi..."
if [ -s "$POOL_DIR/failed.list" ]; then
warn "Retry tuần tự các mục tải lỗi..."
distro_exec "P=/tmp/dmas_pool.$POOL_TAG; [ -f \$P/failed.list ] || exit 0; : > \$P/failed2.list; while IFS= read -r u; do b=\${u##*/}; f=\$P/debs/\$b; [ -s \"\$f\" ] && continue; if wget -q -T 90 -O \"\$f\" \"\$u\" 2>/dev/null || curl -fsSL --max-time 90 -o \"\$f\" \"\$u\" 2>/dev/null; then :; else echo \"\$u\" >> \$P/failed2.list; fi; done < \$P/failed.list; exit 0" || true
fi
STILL=""
if [ -s "$POOL_DIR/failed2.list" ]; then
STILL=$(sed 's|.*/||; s|_[0-9][0-9a-zA-Z.~-]*\.deb$||; s|_[a-z0-9-]*\.deb$||' "$POOL_DIR/failed2.list" 2>/dev/null | sort -u | tr '\n' ' ')
warn "Còn lỗi tải: $STILL -> cài tuần tự phần còn sót."
fi
distro_cmd 'Cài các gói .deb đã tải song song' "P=/tmp/dmas_pool.$POOL_TAG; ls \$P/debs/*.deb >/dev/null 2>&1 && dpkg -i \$P/debs/*.deb || true; export DEBIAN_FRONTEND=noninteractive; apt-get $APT_OPTS install -f -y"
if [ -n "$(echo "$STILL" | tr -d ' ')" ]; then
try_distro 'Cài tuần tự phần còn sót thất bại' "export DEBIAN_FRONTEND=noninteractive; apt-get $APT_OPTS install -y --no-install-recommends $STILL"
fi
okay "Hoàn tất cài gói nền + theme (song song)."
else
warn "Không lấy được URI -> cài tuần tự cổ điển."
distro_cmd_live 'Cài gói nền Debian thất bại' "export DEBIAN_FRONTEND=noninteractive; apt-get $APT_OPTS install -y --no-install-recommends $MISS_LIST"
fi
rm -rf "$POOL_DIR" 2>/dev/null; POOL_DIR=""
else
distro_cmd_live 'Cài gói nền Debian thất bại' "export DEBIAN_FRONTEND=noninteractive; miss=\"\"; for p in dbus-x11 xfce4 xfce4-terminal thunar curl wget ca-certificates gnupg apt-transport-https locales git; do dpkg -s \"\$p\" >/dev/null 2>&1 || miss=\"\$miss \$p\"; done; if [ -n \"\$miss\" ]; then apt-get $APT_OPTS install -y --no-install-recommends \$miss || true; else echo DMAS_BASE_OK; fi"
fi
fi

pool_wait
pool_kill_all 2>/dev/null
okay "Toàn bộ tiến trình cài nền đã xong -> chuyển sang bước giao diện."

draw_progress 60 "Tải thêm theme nguồn mở từ GitHub (best-effort)"
FETCH_SRC="$HOME/.dmas_fetch_themes.src.$$"
cat <<'FETCHEOF' > "$FETCH_SRC" || fail "Không ghi được fetcher template"
#!/bin/sh
LOG=/root/.dmas_themes.log
log() { printf '[DMAS-THEMES] %s\n' "$*" >>"$LOG" 2>/dev/null || true; }
get() { u="$1"; d="$2"; if command -v wget >/dev/null 2>&1; then wget -q -T 60 -O "$d" "$u" && return 0; fi; command -v curl >/dev/null 2>&1 && curl -fsSL --max-time 60 -o "$d" "$u" && return 0; return 1; }
mark_done() { touch "/root/.dmas_done_$1" 2>/dev/null || true; }
is_done() { [ -f "/root/.dmas_done_$1" ]; }
install_gtk() { k="$1"; u="$2"; is_done "$k" && return 0; n=$(printf '%s' "$u" | sed 's|.*/||; s|\.tar.*||'); t="/tmp/dmas_theme_$n.tar.gz"; log "fetch gtk: $u"; get "$u" "$t" || { log "FAIL fetch $u"; return 1; }; ex="/tmp/dmas_ex_$n"; rm -rf "$ex"; mkdir -p "$ex"; tar -xzf "$t" -C "$ex" || { rm -rf "$ex" "$t"; return 1; }; find "$ex" -maxdepth 4 -type d -name gtk-3.0 2>/dev/null | while IFS= read -r g; do td=$(dirname "$g"); nm=$(basename "$td"); [ -d "/usr/share/themes/$nm" ] || cp -r "$td" "/usr/share/themes/$nm" 2>/dev/null && log "installed gtk: $nm"; done; rm -rf "$ex" "$t"; mark_done "$k"; }
install_icons() { k="$1"; u="$2"; kind="$3"; is_done "$k" && return 0; n=$(printf '%s' "$u" | sed 's|.*/||; s|\.tar.*||'); t="/tmp/dmas_icons_$n.tar.gz"; log "fetch $kind: $u"; get "$u" "$t" || { log "FAIL fetch $u"; return 1; }; ex="/tmp/dmas_exi_$n"; rm -rf "$ex"; mkdir -p "$ex"; tar -xzf "$t" -C "$ex" || { rm -rf "$ex" "$t"; return 1; }; if [ "$kind" = "cursor" ]; then find "$ex" -maxdepth 4 -type d -name cursors 2>/dev/null | while IFS= read -r g; do td=$(dirname "$g"); nm=$(basename "$td"); [ -d "/usr/share/icons/$nm" ] || cp -r "$td" "/usr/share/icons/$nm" 2>/dev/null && log "installed cursor: $nm"; done; else find "$ex" -maxdepth 4 -type f -name index.theme 2>/dev/null | while IFS= read -r g; do td=$(dirname "$g"); nm=$(basename "$td"); case "$td" in */cursors|*/cursors/*) continue ;; esac; grep -q '^Directories=' "$g" 2>/dev/null || continue; [ -d "/usr/share/icons/$nm" ] || cp -r "$td" "/usr/share/icons/$nm" 2>/dev/null && log "installed icons: $nm"; done; fi; rm -rf "$ex" "$t"; mark_done "$k"; }
install_gtk nordic https://github.com/EliverLara/Nordic/archive/refs/heads/master.tar.gz
install_gtk dracula https://github.com/dracula/gtk/archive/refs/heads/master.tar.gz
install_gtk tokyonight https://github.com/Fausto-Korps/tokyo-night-gtk/archive/refs/heads/master.tar.gz
install_gtk sweet https://github.com/EliverLara/Sweet/archive/refs/heads/master.tar.gz
install_icons whitesur https://github.com/vinceliuice/WhiteSur-icon-theme/archive/refs/heads/master.tar.gz icon
install_icons tela https://github.com/vinceliuice/Tela-circle-icon-theme/archive/refs/heads/master.tar.gz icon
install_icons beautyline https://github.com/vinceliuice/BeautyLine-icon-theme/archive/refs/heads/master.tar.gz icon
install_icons mcmojave https://github.com/vinceliuice/McMojave-cursors/archive/refs/heads/master.tar.gz cursor
install_icons apple https://github.com/ful1e5/Apple_Cursors/archive/refs/heads/main.tar.gz cursor
log "hoàn tất fetch themes"
FETCHEOF
command -v tr >/dev/null 2>&1 && { tr -d '\r' < "$FETCH_SRC" > "$FETCH_SRC.c" 2>>"$LOG_FILE" && mv "$FETCH_SRC.c" "$FETCH_SRC" || fail "tr CRLF fetcher thất bại"; }
log "[RUN] ghi /root/.dmas_fetch_themes.sh"
proot-distro login "$DISTRO" -- /bin/sh -c 'cat > /root/.dmas_fetch_themes.sh' < "$FETCH_SRC" >>"$LOG_FILE" 2>&1 || fail "Không ghi được fetcher vào container"
rm -f "$FETCH_SRC" 2>/dev/null
distro_cmd 'chmod fetcher thất bại' 'chmod 755 /root/.dmas_fetch_themes.sh'
LIVE_DESC="Tải theme GitHub..."
distro_exec_live '/root/.dmas_fetch_themes.sh' || warn "Fetch theme GitHub lỗi (xem /root/.dmas_themes.log); theme apt vẫn dùng được."
LIVE_DESC=""

draw_progress 70 "Firefox + Locale"
if [ "$DISTRO" = "fedora" ]; then
distro_exec 'command -v firefox >/dev/null 2>&1' && okay "Firefox đã có." || try_distro 'Cài Firefox thất bại' 'dnf -y install firefox' || true
try_distro 'Locale Fedora thất bại' 'if ! locale -a 2>/dev/null | grep -qi "^en_US.utf8"; then dnf install -y glibc-langpack-en || true; fi; printf "LANG=en_US.UTF-8\n" > /etc/locale.conf; printf "export LANG=en_US.UTF-8\nexport LC_ALL=en_US.UTF-8\n" > /etc/profile.d/99-dmas-locale.sh; chmod 644 /etc/profile.d/99-dmas-locale.sh || true'
else
install_firefox_debian || true
try_distro 'Locale Debian/Ubuntu thất bại' "export DEBIAN_FRONTEND=noninteractive; if ! locale -a 2>/dev/null | grep -qi \"^en_US.utf8\"; then apt-get $APT_OPTS install -y locales || true; if [ -f /etc/locale.gen ]; then sed -i \"s/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/\" /etc/locale.gen 2>/dev/null || true; grep -q '^en_US.UTF-8 UTF-8' /etc/locale.gen || echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen; fi; locale-gen en_US.UTF-8 || true; else echo DMAS_LOCALE_OK; fi; update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 || true; printf 'export LANG=en_US.UTF-8\nexport LC_ALL=en_US.UTF-8\n' > /etc/profile.d/99-dmas-locale.sh; chmod 644 /etc/profile.d/99-dmas-locale.sh || true"
fi
okay "Locale UTF-8 sẵn sàng."

draw_progress 75 "VS Code (editor chính)"
VSCODE_OK=0; VS_ATTEMPT=1
while [ "$VS_ATTEMPT" -le 2 ]; do
if [ "$DISTRO" = "fedora" ]; then install_vscode_fedora && { VSCODE_OK=1; break; }
else install_vscode_debian && { VSCODE_OK=1; break; }; fi
warn "Cài VS Code thất bại ở bước: $VC_STEP"
[ "$VS_ATTEMPT" -lt 2 ] && { say "Thử lại VS Code..."; sleep 2; }
VS_ATTEMPT=$((VS_ATTEMPT + 1))
done
if [ "$VSCODE_OK" -eq 1 ]; then
PKG_EDITOR="code"; okay "VS Code cài + xác minh OK. Geany KHÔNG được cài."
else
warn "[!] VS Code không thể cài trên môi trường này."
warn "[+] Fallback sang Geany."
if [ "$DISTRO" = "fedora" ]; then
try_distro 'Cài Geany fallback thất bại' 'dnf install -y geany' || fail "VS Code lỗi và Geany cũng lỗi."
else
try_distro 'Cài Geany fallback thất bại' "export DEBIAN_FRONTEND=noninteractive; apt-get $APT_OPTS install -y geany" || fail "VS Code lỗi và Geany cũng lỗi."
fi
PKG_EDITOR="geany"
fi
distro_exec 'command -v code >/dev/null 2>&1' && apply_vscode_proot_fix

draw_progress 85 "Wallpaper, icon desktop, panel 1+2, ảnh panel, autostart"
distro_cmd 'Tạo thư mục UI thất bại' 'mkdir -p /root/.config/autostart /root/Pictures /root/Desktop'
UI_SRC="$HOME/.dmas_ui_fix.src.$$"; UI_OUT="$HOME/.dmas_ui_fix.out.$$"
DESKTOP_SRC="$HOME/.dmas_ui_desktop.src.$$"; DESKTOP_OUT="$HOME/.dmas_ui_desktop.out.$$"
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
P1_URL="__PANEL1_URL__"
P2_URL="__PANEL2_URL__"
P1_FILE="$WALLPAPER_DIR/panel1.png"
P2_FILE="$WALLPAPER_DIR/panel2.png"
UI_LOG="/root/.dmas_ui_fix.log"
ui_log() { printf '[DMAS-UI] %s\n' "$*" >>"$UI_LOG" 2>/dev/null || true; }
verify_image() {
f="$1"; e="$2"
[ -s "$f" ] || return 1
command -v od >/dev/null 2>&1 && command -v tr >/dev/null 2>&1 || return 0
m=$(od -An -N4 -tx1 "$f" 2>/dev/null | tr -d ' \n')
case "$e" in
png) [ "$m" = "89504e47" ] && return 0 ;;
jpg|jpeg) case "$m" in ffd8ff*) return 0 ;; esac ;;
esac
return 1
}
download_file() {
u="$1"; d="$2"; e="$3"; t="${d}.tmp"
if command -v wget >/dev/null 2>&1; then wget -T 30 -q -O "$t" "$u" 2>/dev/null || return 1
elif command -v curl >/dev/null 2>&1; then curl -fsSL --max-time 30 -o "$t" "$u" 2>/dev/null || return 1
else return 1; fi
verify_image "$t" "$e" || { rm -f "$t" 2>/dev/null; return 1; }
mv "$t" "$d" || return 1
}
fetch_once() { u="$1"; d="$2"; e="$3"; if [ -s "$d" ] && verify_image "$d" "$e"; then return 0; fi; download_file "$u" "$d" "$e"; }
mkdir -p "$WALLPAPER_DIR" /root/Desktop 2>/dev/null || true
WALLPAPER=""
if fetch_once "$PRIMARY_URL" "$PRIMARY_FILE" png; then WALLPAPER="$PRIMARY_FILE"
elif fetch_once "$FALLBACK_URL" "$FALLBACK_FILE" jpg; then WALLPAPER="$FALLBACK_FILE"; ui_log "wallpaper chính lỗi, dùng fallback"; fi
HAS_P1="no"; fetch_once "$P1_URL" "$P1_FILE" png && HAS_P1="yes"
HAS_P2="no"; fetch_once "$P2_URL" "$P2_FILE" png && HAS_P2="yes"
i=0
while [ "$i" -lt 30 ]; do xfconf-query -c xfce4-desktop -l >/dev/null 2>&1 && break; sleep 1; i=$((i + 1)); done
command -v xfconf-query >/dev/null 2>&1 || { ui_log "xfconf-query thiếu, bỏ qua UI."; exit 0; }
# ---- Wallpaper ----
if [ -n "$WALLPAPER" ]; then
for prop in $(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep '/last-image$'); do
xfconf-query -c xfce4-desktop -p "$prop" -s "$WALLPAPER" 2>/dev/null || true
done
# shellcheck disable=SC2086
MONS=$(xrandr 2>/dev/null | grep ' connected' | cut -d' ' -f1)
for mon in $MONS monitor0; do
xfconf-query -c xfce4-desktop -p "/backdrop/screen0/monitor$mon/workspace0/last-image" -s "$WALLPAPER" --create -t string 2>/dev/null || true
xfconf-query -c xfce4-desktop -p "/backdrop/screen0/monitor$mon/workspace0/image-style" -s 5 --create -t int 2>/dev/null || true
xfconf-query -c xfce4-desktop -p "/backdrop/screen0/monitor$mon/image-show" -s true --create -t bool 2>/dev/null || true
done
ui_log "wallpaper: $WALLPAPER"
fi
# ---- Icon desktop: VS Code + Firefox ----
FF_BIN=""
command -v firefox >/dev/null 2>&1 && [ -x /usr/lib/firefox/firefox ] && FF_BIN="firefox"
[ -z "$FF_BIN" ] && command -v firefox-esr >/dev/null 2>&1 && FF_BIN="firefox-esr"
if command -v code >/dev/null 2>&1; then
cat > /root/Desktop/code.desktop <<'DESK1'
[Desktop Entry]
Version=1.0
Type=Application
Name=Visual Studio Code
Comment=DMAS Editor
Exec=/usr/local/bin/code %F
Icon=com.visualstudio.code
Terminal=false
StartupNotify=true
Categories=Development;IDE;
DESK1
chmod +x /root/Desktop/code.desktop 2>/dev/null || true
fi
if [ -n "$FF_BIN" ]; then
cat > /root/Desktop/firefox.desktop <<DESK2
[Desktop Entry]
Version=1.0
Type=Application
Name=Firefox
Comment=DMAS Browser
Exec=$FF_BIN %u
Icon=firefox
Terminal=false
StartupNotify=true
Categories=Network;WebBrowser;
DESK2
chmod +x /root/Desktop/firefox.desktop 2>/dev/null || true
fi
for dfile in /root/Desktop/code.desktop /root/Desktop/firefox.desktop; do
[ -f "$dfile" ] || continue
chmod +x "$dfile" 2>/dev/null || true
gio set "$dfile" metadata::trusted true 2>/dev/null || setfattr -n user.trusted -v 1 "$dfile" 2>/dev/null || true
done
xfconf-query -c xfce4-desktop -p /desktop-icons/style -s 2 --create -t int 2>/dev/null || true
xfconf-query -c xfce4-desktop -p /desktop-icons/icon-size -s 48 --create -t int 2>/dev/null || true
ui_log "desktop icons: code.desktop firefox.desktop"
# ---- Theme chọn tự động ----
pick_dir() { pd="$1"; shift; for t in "$@"; do [ -d "$pd/$t" ] && { printf '%s' "$t"; return 0; }; done; printf ''; }
GTK_T=$(pick_dir /usr/share/themes Tokyo-Night Tokyo-Night-Dark Dracula Nordic Sweet Arc-Dark Materia-dark Numix Greybird Adwaita)
ICO_T=$(pick_dir /usr/share/icons WhiteSur Tela-circle BeautyLine Papirus-Dark Numix-Circle Moka Adwaita)
CUR_T=$(pick_dir /usr/share/icons McMojave-cursors Apple-Cursors ComixCursors-Opaque-Black Adwaita)
[ -n "$GTK_T" ] && { xfconf-query -c xsettings -p /Net/ThemeName -s "$GTK_T" --create -t string 2>/dev/null || true; xfconf-query -c xfwm4 -p /general/theme -s "$GTK_T" --create -t string 2>/dev/null || true; }
[ -n "$ICO_T" ] && xfconf-query -c xsettings -p /Net/IconThemeName -s "$ICO_T" --create -t string 2>/dev/null || true
[ -n "$CUR_T" ] && xfconf-query -c xsettings -p /Gtk/CursorThemeName -s "$CUR_T" --create -t string 2>/dev/null || true
xfconf-query -c xsettings -p /Gtk/CursorThemeSize -s 24 --create -t int 2>/dev/null || true
ui_log "theme: GTK=$GTK_T ICON=$ICO_T CURSOR=$CUR_T"
# ---- PANEL 1: dưới cùng, full ngang, ảnh riêng ----
P1=/panels/panel-1
xfconf-query -c xfce4-panel -p "$P1/position" -s "p=10;x=0;y=0" --create -t string 2>/dev/null || true
xfconf-query -c xfce4-panel -p "$P1/length" -s 100 --create -t int 2>/dev/null || true
xfconf-query -c xfce4-panel -p "$P1/length-adjust" -s true --create -t bool 2>/dev/null || true
xfconf-query -c xfce4-panel -p "$P1/autohide-behavior" -s 2 --create -t int 2>/dev/null || true
xfconf-query -c xfce4-panel -p "$P1/position-locked" -s true --create -t bool 2>/dev/null || true
if [ "$HAS_P1" = "yes" ]; then
xfconf-query -c xfce4-panel -p "$P1/background-style" -s 2 --create -t int 2>/dev/null || true
xfconf-query -c xfce4-panel -p "$P1/background-image" -s "$P1_FILE" --create -t string 2>/dev/null || true
else
xfconf-query -c xfce4-panel -p "$P1/background-style" -s 1 --create -t int 2>/dev/null || true
xfconf-query -c xfce4-panel -p "$P1/background-rgba" --create --force-array -t double -s 0.08 -s 0.08 -s 0.10 -s 0.85 2>/dev/null || true
fi
# ---- PANEL 2: góc phải trên, nhỏ, clock, ảnh riêng ----
P2=/panels/panel-2
xfconf-query -c xfce4-panel -p "$P2/position" -s "p=7;x=0;y=0" --create -t string 2>/dev/null || true
xfconf-query -c xfce4-panel -p "$P2/length" -s 30 --create -t int 2>/dev/null || true
xfconf-query -c xfce4-panel -p "$P2/length-adjust" -s false --create -t bool 2>/dev/null || true
xfconf-query -c xfce4-panel -p "$P2/autohide-behavior" -s 0 --create -t int 2>/dev/null || true
xfconf-query -c xfce4-panel -p "$P2/position-locked" -s true --create -t bool 2>/dev/null || true
xfconf-query -c xfce4-panel -p "$P2/plugins" --create --force-array -t string -s plugin-1 2>/dev/null || true
xfconf-query -c xfce4-panel -p "$P2/plugin-1" -s "clock" --create -t string 2>/dev/null || true
if [ "$HAS_P2" = "yes" ]; then
xfconf-query -c xfce4-panel -p "$P2/background-style" -s 2 --create -t int 2>/dev/null || true
xfconf-query -c xfce4-panel -p "$P2/background-image" -s "$P2_FILE" --create -t string 2>/dev/null || true
else
xfconf-query -c xfce4-panel -p "$P2/background-style" -s 1 --create -t int 2>/dev/null || true
xfconf-query -c xfce4-panel -p "$P2/background-rgba" --create --force-array -t double -s 0.08 -s 0.08 -s 0.10 -s 0.85 2>/dev/null || true
fi
ui_log "panel1=bottom+img($HAS_P1), panel2=top-right+clock+img($HAS_P2)"
# ---- Theme switcher ----
cat > /root/.dmas_theme.sh <<'SWEOF'
#!/bin/sh
echo "=== GTK themes ==="; ls /usr/share/themes 2>/dev/null
echo "=== Icon themes ==="; ls /usr/share/icons 2>/dev/null
printf 'GTK theme moi (Enter = giu): '; read -r GT
printf 'Icon theme moi (Enter = giu): '; read -r IT
printf 'Cursor theme moi (Enter = giu): '; read -r CT
[ -n "$GT" ] && { xfconf-query -c xsettings -p /Net/ThemeName -s "$GT" --create -t string 2>/dev/null; xfconf-query -c xfwm4 -p /general/theme -s "$GT" --create -t string 2>/dev/null; }
[ -n "$IT" ] && xfconf-query -c xsettings -p /Net/IconThemeName -s "$IT" --create -t string 2>/dev/null
[ -n "$CT" ] && xfconf-query -c xsettings -p /Gtk/CursorThemeName -s "$CT" --create -t string 2>/dev/null
echo "Da ap dung."
SWEOF
chmod 755 /root/.dmas_theme.sh 2>/dev/null || true
exit 0
UIEOF
log "[RUN] sed thay URL wallpaper + panel images"
sed -e "s#__WALLPAPER_URL__#$WALLPAPER_URL#" -e "s#__PANEL1_URL__#$PANEL1_IMG_URL#" -e "s#__PANEL2_URL__#$PANEL2_IMG_URL#" "$UI_SRC" > "$UI_OUT" 2>>"$LOG_FILE" || fail "sed UI thất bại"
command -v tr >/dev/null 2>&1 && { tr -d '\r' < "$UI_OUT" > "$UI_OUT.c" 2>>"$LOG_FILE" && mv "$UI_OUT.c" "$UI_OUT" || fail "tr CRLF UI thất bại"; }
log "[RUN] ghi /root/.dmas_ui_fix.sh"
proot-distro login "$DISTRO" -- /bin/sh -c 'cat > /root/.dmas_ui_fix.sh' < "$UI_OUT" >>"$LOG_FILE" 2>&1 || fail "Không ghi được /root/.dmas_ui_fix.sh"
distro_cmd 'chmod UI script thất bại' 'chmod 755 /root/.dmas_ui_fix.sh'
cat <<'DEOF' > "$DESKTOP_SRC" || fail "Không ghi được desktop template"
[Desktop Entry]
Type=Application
Name=DMAS_UI_Fix
Exec=/root/.dmas_ui_fix.sh
OnlyShowIn=XFCE;
DEOF
command -v tr >/dev/null 2>&1 && { tr -d '\r' < "$DESKTOP_SRC" > "$DESKTOP_OUT" 2>>"$LOG_FILE" || fail "tr CRLF desktop thất bại"; } || cat "$DESKTOP_SRC" > "$DESKTOP_OUT"
log "[RUN] ghi autostart dmas_ui.desktop"
proot-distro login "$DISTRO" -- /bin/sh -c 'cat > /root/.config/autostart/dmas_ui.desktop' < "$DESKTOP_OUT" >>"$LOG_FILE" 2>&1 || fail "Không ghi được autostart desktop"
distro_cmd 'chmod desktop file thất bại' 'chmod 644 /root/.config/autostart/dmas_ui.desktop'
rm -f "$UI_SRC" "$UI_OUT" "$DESKTOP_SRC" "$DESKTOP_OUT" 2>/dev/null || true
okay "UI config đã ghi vào container."

draw_progress 92 "Tạo startdmas.sh + unidmas.sh"
START_SRC="$HOME/.startdmas.src.$$"; START_TMP="$HOME/.startdmas.tmp.$$"
cat <<'START_EOF' > "$START_SRC" || fail "Không ghi được startdmas template"
#!/bin/sh
# Generated by linuxdmas.sh - DO NOT EDIT WITH CRLF
ESC=$(printf '\033')
C_CYAN="${ESC}[38;2;0;220;255m"
C_GREEN="${ESC}[38;2;50;255;120m"
C_RED="${ESC}[38;2;255;80;80m"
C_RESET="${ESC}[0m"
TAG="${C_CYAN}[DmasLinux]${C_RESET}"
SELF=$0
DISTRO="__DMAS_DISTRO__"
DISPLAY_NUM=":0"
START_LOG="$HOME/.dmas_start.log"
CLEANED=0; XSERVER_PID=""
log() { printf '%s\n' "$*" >>"$START_LOG" 2>/dev/null || true; }
dmas() { printf '%s => %s\n' "$TAG" "$*"; log "$*"; }
dmas_ok() { printf '%s => %s%s%s\n' "$TAG" "$C_GREEN" "$*" "$C_RESET"; log "$*"; }
dmas_err() { printf '%s => %s%s%s\n' "$TAG" "$C_RED" "$*" "$C_RESET"; log "$*"; }
stop_x11() {
[ "$CLEANED" -eq 1 ] && return
CLEANED=1
if [ -n "$XSERVER_PID" ] && kill -0 "$XSERVER_PID" 2>/dev/null; then
kill "$XSERVER_PID" 2>/dev/null || true; sleep 1; kill -9 "$XSERVER_PID" 2>/dev/null || true
fi
pkill -f "termux-x11 ${DISPLAY_NUM}" 2>/dev/null || true
pkill -f "Xwayland ${DISPLAY_NUM}" 2>/dev/null || true
termux-wake-unlock 2>/dev/null || true
}
on_sig() { dmas "Đang thoát..."; dmas "Đang dừng tiến trình..."; stop_x11; dmas_ok "Đã dừng"; exit 130; }
trap on_sig INT TERM
trap stop_x11 EXIT
[ -n "$DISTRO" ] || { dmas_err "DISTRO chưa cấu hình."; exit 1; }
command -v proot-distro >/dev/null 2>&1 || { dmas_err "Thiếu proot-distro."; exit 1; }
command -v termux-x11 >/dev/null 2>&1 || { dmas_err "Thiếu termux-x11."; exit 1; }
proot-distro login "$DISTRO" -- /bin/sh -c true >/dev/null 2>&1 || { dmas_err "Container $DISTRO chưa sẵn sàng."; exit 1; }
start_stack() {
CLEANED=0
termux-wake-lock 2>/dev/null || true
dmas "Đang dọn tiến trình X11 cũ cho display ${DISPLAY_NUM}..."
pkill -f "termux-x11 ${DISPLAY_NUM}" 2>/dev/null || true
pkill -f "Xwayland ${DISPLAY_NUM}" 2>/dev/null || true
sleep 1
[ -n "$TMPDIR" ] && rm -f "$TMPDIR/.X11-unix/X0" "$TMPDIR/.X0-lock" 2>/dev/null
rm -f /tmp/.X11-unix/X0 /tmp/.X0-lock 2>/dev/null
dmas "Mở ứng dụng Termux:X11..."
command -v am >/dev/null 2>&1 && am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >>"$START_LOG" 2>&1
sleep 2
dmas "Khởi chạy termux-x11 server ${DISPLAY_NUM}..."
termux-x11 "$DISPLAY_NUM" -ac >>"$START_LOG" 2>&1 &
XSERVER_PID=$!
SOCKET="$TMPDIR/.X11-unix/X0"; [ -n "$TMPDIR" ] || SOCKET="/tmp/.X11-unix/X0"
i=0
while [ "$i" -lt 20 ]; do [ -e "$SOCKET" ] && break; sleep 1; i=$((i + 1)); done
[ -e "$SOCKET" ] || { dmas_err "Không thấy X11 socket $SOCKET."; return 1; }
dmas_ok "Đã khởi động thành công."
return 0
}
run_xfce() {
dmas "Đăng nhập $DISTRO XFCE4..."
proot-distro login "$DISTRO" --shared-tmp --env DISPLAY="$DISPLAY_NUM" -- /bin/sh -c 'export LANG=en_US.UTF-8; export LC_ALL=en_US.UTF-8; if ! command -v dbus-launch >/dev/null 2>&1; then echo "[ERROR] dbus-launch thiếu" >&2; exit 70; fi; if ! command -v startxfce4 >/dev/null 2>&1; then echo "[ERROR] startxfce4 thiếu" >&2; exit 71; fi; mkdir -p /tmp/xdg 2>/dev/null; chmod 700 /tmp/xdg 2>/dev/null; exec dbus-launch --exit-with-session startxfce4'
return $?
}
start_stack || { dmas_err "Khởi động X11 thất bại."; exit 1; }
run_xfce
RC=$?
[ "$RC" -eq 70 ] && dmas_err "DBus thiếu/không khởi động được."
[ "$RC" -eq 71 ] && dmas_err "XFCE4 thiếu/không khởi động được."
while :; do
dmas "Đang thoát..."
dmas "Đang dừng tiến trình..."
stop_x11
dmas_ok "Đã dừng"
printf '%s => Chọn: [1] Thoát hẳn   [2] Khởi động lại Linux : %s' "$TAG" "$C_RESET"
read -r CHOICE </dev/tty 2>/dev/null || read -r CHOICE
case "$CHOICE" in
2)
dmas "Đang khởi động lại..."
start_stack || { dmas_err "Khởi động lại thất bại."; continue; }
run_xfce; RC=$?
continue
;;
*) break ;;
esac
done
dmas "Hẹn gặp lại ở phiên DMAS kế tiếp."
exit "$RC"
START_EOF
log "[RUN] sed DISTRO vào startdmas.sh"
sed "s#__DMAS_DISTRO__#$DISTRO#" "$START_SRC" > "$START_TMP" 2>>"$LOG_FILE" || fail "sed startdmas thất bại"
command -v tr >/dev/null 2>&1 && { tr -d '\r' < "$START_TMP" > "$START_TMP.c" 2>>"$LOG_FILE" && mv "$START_TMP.c" "$START_TMP" || fail "tr CRLF startdmas thất bại"; }
PREV_CAND=""
for cand in "$PWD/startdmas.sh" "$HOME/startdmas.sh"; do
[ "$cand" = "$PREV_CAND" ] && continue
PREV_CAND=$cand
cp "$START_TMP" "$cand" 2>>"$LOG_FILE" && { chmod +x "$cand" 2>/dev/null || true; say "Đã ghi launcher: $cand"; } || warn "Không ghi được launcher: $cand"
done
rm -f "$START_SRC" "$START_TMP" 2>/dev/null || true
START_SCRIPT=""; RUN_CMD=""
if [ -x "$PWD/startdmas.sh" ]; then START_SCRIPT="$PWD/startdmas.sh"; RUN_CMD="./startdmas.sh"
elif [ -x "$HOME/startdmas.sh" ]; then START_SCRIPT="$HOME/startdmas.sh"; RUN_CMD="~/startdmas.sh"
elif [ -f "$HOME/startdmas.sh" ]; then START_SCRIPT="$HOME/startdmas.sh"; RUN_CMD="sh ~/startdmas.sh"
elif [ -f "$PWD/startdmas.sh" ]; then START_SCRIPT="$PWD/startdmas.sh"; RUN_CMD="sh $PWD/startdmas.sh"
else fail "Không ghi được startdmas.sh."; fi
sh -n "$START_SCRIPT" >>"$LOG_FILE" 2>&1 || fail "startdmas.sh không pass sh -n"
okay "startdmas.sh sẵn sàng ($RUN_CMD)."
# ---- unidmas ----
UNI_SRC="$HOME/.unidmas.src.$$"; UNI_TMP="$HOME/.unidmas.tmp.$$"
cat <<'UNI_EOF' > "$UNI_SRC" || fail "Không ghi được unidmas template"
#!/bin/sh
DISTRO="__DMAS_DISTRO__"
printf '[DmasLinux] => GO CAI DAT LINUX DMAS (container: %s)\n' "$DISTRO"
printf '[DmasLinux] => Nhap dung chu "yes" de xac nhan: '
read -r CONF
[ "$CONF" = "yes" ] || { echo "Huy."; exit 1; }
pkill -f "termux-x11 :0" 2>/dev/null; pkill -f "Xwayland :0" 2>/dev/null; sleep 1
command -v proot-distro >/dev/null 2>&1 && proot-distro remove "$DISTRO" 2>/dev/null
command -v pkg >/dev/null 2>&1 && pkg remove -y termux-x11-nightly >/dev/null 2>&1
H="$HOME"
rm -f "$H/startdmas.sh" "$H/.dmas_setup_done" "$H/.dmas_install.log" "$H/.dmas_start.log" "$H/.dmas_distro" "$H/.dmas_themes.log"
rm -f "$H/.dmas_ui_fix.src."* "$H/.dmas_ui_fix.out."* "$H/.dmas_ui_desktop.src."* "$H/.dmas_ui_desktop.out."*
rm -f "$H/.startdmas.src."* "$H/.startdmas.tmp."* "$H/.unidmas.src."* "$H/.unidmas.tmp."*
rm -rf "$H/.dmas_install.lock"
[ "$(pwd)" != "$H" ] && rm -f "./startdmas.sh" 2>/dev/null
echo "[DmasLinux] => Da go sach Linux DMAS."
rm -f "$H/unidmas.sh"
UNI_EOF
sed "s#__DMAS_DISTRO__#$DISTRO#" "$UNI_SRC" > "$UNI_TMP" 2>>"$LOG_FILE" || fail "sed unidmas thất bại"
command -v tr >/dev/null 2>&1 && { tr -d '\r' < "$UNI_TMP" > "$UNI_TMP.c" 2>>"$LOG_FILE" && mv "$UNI_TMP.c" "$UNI_TMP" || fail "tr CRLF unidmas thất bại"; }
PREV_CAND=""
for cand in "$PWD/unidmas.sh" "$HOME/unidmas.sh"; do
[ "$cand" = "$PREV_CAND" ] && continue
PREV_CAND=$cand
cp "$UNI_TMP" "$cand" 2>>"$LOG_FILE" && { chmod +x "$cand" 2>/dev/null || true; say "Đã ghi uninstaller: $cand"; } || true
done
rm -f "$UNI_SRC" "$UNI_TMP" 2>/dev/null || true
[ -f "$HOME/unidmas.sh" ] && sh -n "$HOME/unidmas.sh" >>"$LOG_FILE" 2>&1 || true

draw_progress 97 "Kiểm tra cuối"
[ -f "$0" ] && sh -n "$0" >>"$LOG_FILE" 2>&1 && say "sh -n linuxdmas.sh pass"
command -v shellcheck >/dev/null 2>&1 && { shellcheck "$0" >>"$LOG_FILE" 2>&1 || warn "shellcheck có cảnh báo (không chặn)."; }
[ -f "$START_SCRIPT" ] || fail "startdmas.sh không tồn tại."
touch "$SETUP_FLAG" || fail "Không tạo được success flag"
log "[INFO] Success flag: $SETUP_FLAG"

draw_progress 100 "Cài đặt thành công"
okay "Cài đặt hoàn tất. Editor chính: VS Code ($PKG_EDITOR)."
say "Đổi theme/icon/cursor: /root/.dmas_theme.sh | Gỡ cài: sh ~/unidmas.sh"
say "Tự khởi chạy $RUN_CMD sau 3 giây... (Ctrl+C để hủy)"
sleep 3
if [ -x "$HOME/startdmas.sh" ]; then "$HOME/startdmas.sh"; LAUNCH_RC=$?
else sh "$HOME/startdmas.sh"; LAUNCH_RC=$?; fi
okay "Desktop đã thoát (mã $LAUNCH_RC). Chạy lại: $RUN_CMD"
