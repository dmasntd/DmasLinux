#!/bin/sh
# ==========================================
# LINUX DMAS AUTOMATED INSTALLER (POSIX)
# ==========================================
# Chạy lại nhiều lần an toàn; DMAS_FORCE_IPV4=1 sh linuxdmas.sh nếu mạng kẹt IPv6
# ==========================================
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
# ==========================================
# LOCK + BẪY TÍN HIỆU (Ctrl+C / Ctrl+Z / TERM)
# ==========================================
LOCK_DIR="$HOME/.dmas_install.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
printf '%s => %s[ERROR] Một bản cài DMAS khác đang chạy (lock: %s).%s\n' "$TAG" "$C_RED" "$LOCK_DIR" "$C_RESET"
printf '%s => Nếu chắc chắn không còn tiến trình nào: rm -rf %s\n' "$TAG" "$LOCK_DIR"
exit 1
fi
POOL_META_GLOBAL=""
release_lock() { rmdir "$LOCK_DIR" 2>/dev/null || true; }
on_signal_exit() {
for m in $POOL_META_GLOBAL; do
pid=${m%%:*}
kill -TERM "$pid" 2>/dev/null || true
done
release_lock
printf '\n%s => %s[x] Đã dừng toàn bộ tiến trình cài đặt theo yêu cầu.%s\n' "$TAG" "$C_RED" "$C_RESET"
exit 130
}
trap release_lock EXIT
trap on_signal_exit INT TERM TSTP
if [ ! -d "$HOME" ] || [ ! -w "$HOME" ]; then
printf '[ERROR] $HOME không tồn tại hoặc không ghi được.\n'
exit 1
fi
: >>"$LOG_FILE" || { printf '[ERROR] Không tạo được log %s\n' "$LOG_FILE"; exit 1; }
printf '\n==== DMAS installer run %s ====\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo unknown)" >>"$LOG_FILE"
# ==========================================
# HELPER CƠ BẢN
# ==========================================
log() { printf '%s\n' "$*" >>"$LOG_FILE" 2>/dev/null || true; }
info() { printf '%s => %s\n' "$TAG" "$*"; log "[INFO] $*"; }
warn() { printf '%s => %s[!] %s%s\n' "$TAG" "$C_YELLOW" "$*" "$C_RESET"; log "[WARN] $*"; }
error() { printf '%s => %s[x] %s%s\n' "$TAG" "$C_RED" "$*" "$C_RESET"; log "[ERROR] $*"; }
fail() {
printf '\n'
error "$1"
error "Installer dừng an toàn. Container/dữ liệu giữ nguyên."
error "Log: $LOG_FILE"
exit 1
}
run() {
r_desc=$1; shift
log "[RUN] $*"
"$@" >>"$LOG_FILE" 2>&1
r_status=$?
if [ "$r_status" -ne 0 ]; then fail "$r_desc"; fi
return 0
}
run_warn() {
rw_desc=$1; shift
log "[RUN-WARN] $*"
if ! "$@" >>"$LOG_FILE" 2>&1; then warn "$rw_desc"; return 1; fi
return 0
}
need_cmd() { command -v "$1" >/dev/null 2>&1 || fail "Lệnh quan trọng '$1' không tồn tại."; }
spinner_wait() {
sw_pid=$1; sw_desc=$2
while kill -0 "$sw_pid" 2>/dev/null; do
sw_last=$(tail -n 1 "$LOG_FILE" 2>/dev/null | tr -d '\r' | cut -c1-46)
printf '\r\033[K%s => %s | %s%s\033[K' "$TAG" "$sw_desc" "$sw_last" "$C_RESET"
sleep 5
done
wait "$sw_pid"
SPINNER_STATUS=$?
printf '\r\033[K'
return 0
}
run_live() {
rl_desc=$1; shift
log "[RUN-LIVE] $*"
"$@" >>"$LOG_FILE" 2>&1 &
LIVE_PID=$!
POOL_META_GLOBAL="$POOL_META_GLOBAL $LIVE_PID:live:0"
spinner_wait "$LIVE_PID" "$rl_desc"
POOL_META_GLOBAL=""
if [ "$SPINNER_STATUS" -ne 0 ]; then fail "$rl_desc"; fi
return 0
}
# ==========================================
# PHÁT HIỆN CPU / ROOT / BOOTLOADER
# ==========================================
CORES=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 2)
[ "$CORES" -ge 1 ] 2>/dev/null || CORES=2
PERF_CPUS=""; EFF_CPUS=""
if [ -d /sys/devices/system/cpu ]; then
_maxf=0
for _f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/cpuinfo_max_freq; do
_v=$(cat "$_f" 2>/dev/null)
[ "$_v" -gt "$_maxf" ] 2>/dev/null && _maxf=$_v
done
for _d in /sys/devices/system/cpu/cpu[0-9]*; do
_n=${_d##*/cpu}
_v=$(cat "$_d/cpufreq/cpuinfo_max_freq" 2>/dev/null)
if [ "$_maxf" -gt 0 ] 2>/dev/null && [ -n "$_v" ] && [ "$((_v * 100 / _maxf))" -ge 80 ] 2>/dev/null; then
PERF_CPUS="$PERF_CPUS,$_n"
else
EFF_CPUS="$EFF_CPUS,$_n"
fi
done
PERF_CPUS=${PERF_CPUS#,}; EFF_CPUS=${EFF_CPUS#,}
fi
[ -n "$PERF_CPUS" ] || PERF_CPUS="0-$((CORES - 1))"
ROOTED="no"
if [ "$(id -u 2>/dev/null)" = "0" ]; then ROOTED="yes"
elif [ -x /data/adb/magisk/magisk ] || command -v magisk >/dev/null 2>&1; then ROOTED="yes"
elif command -v su >/dev/null 2>&1 && su -c 'id -u' 2>/dev/null | grep -q '^0'; then ROOTED="yes"
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
# ==========================================
# POOL TẢI .deb SONG SONG (watcher + boost CPU)
# ==========================================
pool_max() {
pm=$CORES
if [ "$ROOTED" = "yes" ]; then
pm=$((CORES * 2))
[ "$pm" -gt 16 ] && pm=16
else
[ "$pm" -gt 8 ] && pm=8
fi
[ "$pm" -lt 1 ] && pm=1
printf '%s' "$pm"
}
pd_serial() {
distro_exec "export DEBIAN_FRONTEND=noninteractive; apt-get $APT_OPTS install -y --no-install-recommends $1"
}
pool_install_debs() {
pd_desc="$1"; pd_pkgs="$2"
if [ -z "$(printf '%s' "$pd_pkgs" | tr -d ' ')" ]; then
info "$pd_desc: không thiếu gói nào."
return 0
fi
PD_DIR="${TMPDIR:-$PREFIX/tmp}/dmas_pool.$$"
rm -rf "$PD_DIR" 2>/dev/null
mkdir -p "$PD_DIR/debs" 2>/dev/null || { warn "Không tạo được thư mục pool -> cài tuần tự."; pd_serial "$pd_pkgs"; return $?; }
log "[POOL] Lấy URI cho: $pd_pkgs"
if ! proot-distro login "$DISTRO" -- /bin/sh -c "export DEBIAN_FRONTEND=noninteractive; apt-get $APT_OPTS install -y --print-uris --no-install-recommends $pd_pkgs 2>/dev/null | sed -n \"s/^'\\([^']*\\)'.*/\\1/p\"" > "$PD_DIR/uris.txt" 2>>"$LOG_FILE"; then
warn "Không lấy được URI -> cài tuần tự."
rm -rf "$PD_DIR" 2>/dev/null
pd_serial "$pd_pkgs"
return $?
fi
UCOUNT=$(grep -c '^http' "$PD_DIR/uris.txt" 2>/dev/null)
[ -n "$UCOUNT" ] || UCOUNT=0
if [ "$UCOUNT" -lt 1 ]; then
info "$pd_desc: không có gì cần tải."
rm -rf "$PD_DIR" 2>/dev/null
return 0
fi
NW=$(pool_max)
[ "$NW" -gt "$UCOUNT" ] && NW=$UCOUNT
i=0
while IFS= read -r u; do
case "$u" in http*) : ;; *) continue ;; esac
printf '%s\n' "$u" >> "$PD_DIR/w$((i % NW))"
i=$((i + 1))
done < "$PD_DIR/uris.txt"
POOL_META=""
w=0
while [ "$w" -lt "$NW" ]; do
if [ -s "$PD_DIR/w$w" ]; then
cp "$PD_DIR/w$w" "$PD_DIR/debs/w$w.list" 2>/dev/null
proot-distro login "$DISTRO" --shared-tmp -- /bin/sh -c "mkdir -p /tmp/dmas_debs; while IFS= read -r u; do b=\${u##*/}; f=/tmp/dmas_debs/\$b; if [ -s \"\$f\" ]; then continue; fi; if wget -q -T 60 -O \"\$f.part\" \"\$u\" 2>/dev/null || curl -fsSL --max-time 60 -o \"\$f.part\" \"\$u\" 2>/dev/null; then mv \"\$f.part\" \"\$f\" 2>/dev/null || rm -f \"\$f.part\"; else rm -f \"\$f.part\" 2>/dev/null; fi; done < /tmp/dmas_pool.$$/debs/w$w.list" >>"$LOG_FILE" 2>&1 &
pid=$!
POOL_META="$POOL_META $pid:$w:$(date +%s 2>/dev/null || echo 0)"
POOL_META_GLOBAL="$POOL_META_GLOBAL $pid:$w:0"
fi
w=$((w + 1))
done
info "$pd_desc: tải song song $UCOUNT gói bằng $NW tiến trình (root=$ROOTED)..."
BOOSTED=""
while :; do
active=0
for m in $POOL_META; do
pid=${m%%:*}
if kill -0 "$pid" 2>/dev/null; then active=$((active + 1)); fi
done
[ "$active" -eq 0 ] && break
ndeb=0
if [ -d "$PD_DIR/debs" ]; then ndeb=$(ls "$PD_DIR/debs" 2>/dev/null | grep -c '\.deb$'); fi
printf '\r\033[K%s => %s [%s/%s deb, %s worker]%s\033[K' "$TAG" "$pd_desc" "$ndeb" "$UCOUNT" "$active" "$C_RESET"
if [ "$ROOTED" = "yes" ]; then
best=""; bestel=0; now=$(date +%s 2>/dev/null || echo 0)
for m in $POOL_META; do
pid=${m%%:*}; rest=${m#*:}; t0=${rest##*:}
if kill -0 "$pid" 2>/dev/null; then
el=$((now - t0))
if [ "$el" -gt "$bestel" ]; then bestel=$el; best=$pid; fi
fi
done
if [ -n "$best" ]; then
case " $BOOSTED " in *" $best "*) : ;; *)
if command -v renice >/dev/null 2>&1; then renice -n -10 -p "$best" >/dev/null 2>&1 || true; fi
if command -v taskset >/dev/null 2>&1 && [ -n "$PERF_CPUS" ]; then taskset -pc "$PERF_CPUS" "$best" >/dev/null 2>&1 || true; fi
BOOSTED="$BOOSTED $best"
;; esac
for m in $POOL_META; do
pid=${m%%:*}
[ "$pid" = "$best" ] && continue
kill -0 "$pid" 2>/dev/null || continue
case " $BOOSTED " in *" $pid "*) continue ;; esac
if command -v taskset >/dev/null 2>&1 && [ -n "$EFF_CPUS" ]; then taskset -pc "$EFF_CPUS" "$pid" >/dev/null 2>&1 || true; fi
BOOSTED="$BOOSTED $pid"
done
fi
fi
sleep 3
done
printf '\r\033[K'
for m in $POOL_META; do pid=${m%%:*}; wait "$pid" 2>/dev/null; done
POOL_META_GLOBAL=""
log "[POOL] dpkg -i các deb đã tải"
distro_exec "dpkg -i /tmp/dmas_debs/*.deb 2>&1 | tail -n 5; export DEBIAN_FRONTEND=noninteractive; apt-get $APT_OPTS install -f -y" || true
pd_serial "$pd_pkgs"
rc=$?
rm -rf "$PD_DIR" 2>/dev/null
return $rc
}
# ==========================================
# EXEC VÀO CONTAINER
# ==========================================
distro_exec() { proot-distro login "$DISTRO" -- /bin/sh -c "$1" >>"$LOG_FILE" 2>&1; }
distro_exec_live() {
proot-distro login "$DISTRO" -- /bin/sh -c "$1" >>"$LOG_FILE" 2>&1 &
LIVE_PID=$!
POOL_META_GLOBAL="$POOL_META_GLOBAL $LIVE_PID:live:0"
spinner_wait "$LIVE_PID" "${LIVE_DESC:-đang xử lý trong container...}"
POOL_META_GLOBAL=""
return "$SPINNER_STATUS"
}
distro_cmd() {
dc_desc=$1; dc_cmd=$2
log "[DISTRO-CMD] $dc_cmd"
if ! distro_exec "$dc_cmd"; then fail "$dc_desc"; fi
}
distro_cmd_live() {
dc_desc=$1; dc_cmd=$2
log "[DISTRO-CMD-LIVE] $dc_cmd"
LIVE_DESC="$dc_desc"
if ! distro_exec_live "$dc_cmd"; then LIVE_DESC=""; fail "$dc_desc"; fi
LIVE_DESC=""
}
try_distro() {
td_desc=$1; td_cmd=$2
log "[DISTRO-TRY] $td_cmd"
if distro_exec "$td_cmd"; then return 0; fi
warn "$td_desc"
return 1
}
# ==========================================
# REPO MOZILLA (có fallback trusted=yes khi key 404)
# ==========================================
add_mozilla_repo() {
mi=1
while [ "$mi" -le 3 ]; do
if distro_exec 'install -d -m 0755 /etc/apt/keyrings && { wget -q -T 30 -O /tmp/mozilla.asc https://packages.mozilla.org/apt/repo/signing.key || curl -fsSL --max-time 30 -o /tmp/mozilla.asc https://packages.mozilla.org/apt/repo/signing.key; } && [ -s /tmp/mozilla.asc ] && gpg --dearmor < /tmp/mozilla.asc > /etc/apt/keyrings/mozilla.gpg.tmp && mv /etc/apt/keyrings/mozilla.gpg.tmp /etc/apt/keyrings/mozilla.gpg && chmod a+r /etc/apt/keyrings/mozilla.gpg && echo "deb [signed-by=/etc/apt/keyrings/mozilla.gpg] https://packages.mozilla.org/apt/repo mozilla main" > /etc/apt/sources.list.d/mozilla.list'; then
return 0
fi
warn "Thêm repo Mozilla lần $mi thất bại (key 404?), thử lại..."
mi=$((mi + 1)); sleep 2
done
if distro_exec 'echo "deb [trusted=yes] https://packages.mozilla.org/apt/repo mozilla main" > /etc/apt/sources.list.d/mozilla.list'; then
warn "Dùng repo Mozilla chế độ trusted=yes (không lấy được signing key)."
return 0
fi
return 1
}
# ==========================================
# FIREFOX RIÊNG TỪNG DISTRO
# ==========================================
install_firefox_ubuntu() {
if distro_exec '[ -x /usr/lib/firefox/firefox ] || [ -x /usr/lib/firefox-esr/firefox-esr ]'; then
info "Firefox thật đã có trong container."
return 0
fi
if distro_exec 'command -v firefox >/dev/null 2>&1'; then
info "Firefox đã có sẵn và đang dùng được. Giữ nguyên, không cài lại."
return 0
fi
warn "Ubuntu không có firefox trong repo -> dùng repo Mozilla."
if add_mozilla_repo; then
distro_exec "export DEBIAN_FRONTEND=noninteractive; apt-get $APT_OPTS update -y" || true
if try_distro 'Cài Firefox (Mozilla) thất bại' "export DEBIAN_FRONTEND=noninteractive; apt-get $APT_OPTS install -y --no-install-recommends firefox"; then
if distro_exec '[ -x /usr/lib/firefox/firefox ]'; then info "Firefox (Mozilla deb) đã cài."; return 0; fi
fi
fi
warn "Không cài được Firefox thật; browser sẽ thiếu (không chặn cài đặt)."
return 1
}
install_firefox_debian() {
if distro_exec '[ -x /usr/lib/firefox/firefox ] || [ -x /usr/lib/firefox-esr/firefox-esr ]'; then
info "Firefox thật đã có trong container."
return 0
fi
if try_distro 'Cài firefox-esr thất bại' "export DEBIAN_FRONTEND=noninteractive; apt-get $APT_OPTS install -y --no-install-recommends firefox-esr"; then
if distro_exec '[ -x /usr/lib/firefox-esr/firefox-esr ]'; then info "Firefox ESR đã cài."; return 0; fi
fi
if add_mozilla_repo; then
distro_exec "export DEBIAN_FRONTEND=noninteractive; apt-get $APT_OPTS update -y" || true
if try_distro 'Cài Firefox (Mozilla) thất bại' "export DEBIAN_FRONTEND=noninteractive; apt-get $APT_OPTS install -y --no-install-recommends firefox"; then
if distro_exec '[ -x /usr/lib/firefox/firefox ]'; then info "Firefox (Mozilla deb) đã cài."; return 0; fi
fi
fi
warn "Không cài được Firefox thật; browser sẽ thiếu (không chặn cài đặt)."
return 1
}
install_firefox_fedora() {
if distro_exec 'command -v firefox >/dev/null 2>&1'; then info "Firefox đã có."; return 0; fi
try_distro 'Cài Firefox thất bại' 'dnf install -y firefox' || true
}
# ==========================================
# VS CODE
# ==========================================
install_vscode_debian() {
VC_STEP="Kiểm tra VS Code đã tồn tại"
log "[VSCODE] $VC_STEP"
if distro_exec 'command -v code >/dev/null 2>&1'; then return 0; fi
VC_STEP="Cài dependency VS Code"
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
log "[WARN] apt update repo VS Code lỗi; vẫn thử cài code."
fi
VC_STEP="Cài gói code"
log "[VSCODE] $VC_STEP"
LIVE_DESC="Cài gói code (VS Code)"
distro_exec_live "export DEBIAN_FRONTEND=noninteractive; apt-get $APT_OPTS install -y code" || { LIVE_DESC=""; return 1; }
LIVE_DESC=""
VC_STEP="Xác minh VS Code"
log "[VSCODE] $VC_STEP"
if distro_exec 'command -v code >/dev/null 2>&1'; then return 0; fi
return 1
}
install_vscode_fedora() {
VC_STEP="Kiểm tra VS Code đã tồn tại"
log "[VSCODE] $VC_STEP"
if distro_exec 'command -v code >/dev/null 2>&1'; then return 0; fi
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
LIVE_DESC="Cài gói code (VS Code)"
distro_exec_live 'dnf -y install code' || { LIVE_DESC=""; return 1; }
LIVE_DESC=""
VC_STEP="Xác minh VS Code"
log "[VSCODE] $VC_STEP"
if distro_exec 'command -v code >/dev/null 2>&1'; then return 0; fi
return 1
}
# ==========================================
# FIX VS CODE PROOT: wrapper --no-sandbox + --user-data-dir + retry 3 bậc
# ==========================================
apply_vscode_proot_fix() {
log "[VSCODE] Áp dụng fix proot: wrapper --no-sandbox + --user-data-dir + retry"
if ! distro_exec 'if [ -x /usr/bin/code ]; then mkdir -p /root/.vscode-root; printf "#!/bin/sh\nexport DISPLAY=\"\${DISPLAY:-:0}\"\nexport LIBGL_ALWAYS_SOFTWARE=1\nLOG=/root/.dmas_code.log\necho \"=== run \$(date) args: \$*\" >>\"\$LOG\"\n/usr/bin/code --no-sandbox --disable-gpu --disable-dev-shm-usage --no-zygote --user-data-dir=/root/.vscode-root \"\$@\" 2>>\"\$LOG\"\nrc=\$?\nif [ \"\$rc\" -ne 0 ]; then\n echo \"[dmas] rc=\$rc -> retry bo --no-zygote\" >>\"\$LOG\"\n /usr/bin/code --no-sandbox --disable-gpu --disable-dev-shm-usage --user-data-dir=/root/.vscode-root \"\$@\" 2>>\"\$LOG\"\n rc=\$?\nfi\nif [ \"\$rc\" -ne 0 ]; then\n echo \"[dmas] rc=\$rc -> retry minimal\" >>\"\$LOG\"\n /usr/bin/code --no-sandbox --user-data-dir=/root/.vscode-root \"\$@\" 2>>\"\$LOG\"\n rc=\$?\nfi\nexit \"\$rc\"\n" > /usr/local/bin/code && chmod 755 /usr/local/bin/code && sed -i "s|^Exec=/usr/bin/code|Exec=/usr/local/bin/code|" /usr/share/applications/code.desktop 2>/dev/null; echo DMAS_VSCODE_WRAPPER_OK; fi'; then
warn "Không tạo được wrapper VS Code proot-fix."
fi
}
# ==========================================
# BANNER + PROGRESS
# ==========================================
show_banner() {
if command -v clear >/dev/null 2>&1; then clear; else printf '\033[2J\033[H'; fi
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
printf '\r\033[K%s => [%s%s%s] %s%3d%%%s => %s\033[K' "$TAG" "$C_GREEN" "$bar" "$C_RESET" "$C_YELLOW" "$pct" "$C_RESET" "$msg"
if [ "$pct" -eq 100 ]; then printf '\n'; fi
return 0
}
# ==========================================
# MAIN FLOW
# ==========================================
show_banner
if [ "$UPDATE_MODE" -eq 1 ]; then
info "Đã setup trước đó -> CHẾ ĐỘ CẬP NHẬT & SỬA CHỮA (kiểm tra trước, không cài lại thứ đã có)."
fi
info "Theo dõi trực tiếp: mở session mới chạy tail -f $LOG_FILE"
draw_progress 5 "Kiểm tra môi trường Termux"
need_cmd pkg
need_cmd uname
draw_progress 10 "Cài/kiểm tra gói Termux"
run_warn "pkg update thất bại, dùng chỉ mục hiện có." pkg update -y
if ! command -v termux-x11 >/dev/null 2>&1; then
run "Cài x11-repo thất bại" pkg install -y x11-repo
fi
TERMUX_PKGS=""
command -v proot-distro >/dev/null 2>&1 || TERMUX_PKGS="$TERMUX_PKGS proot-distro"
command -v termux-x11 >/dev/null 2>&1 || TERMUX_PKGS="$TERMUX_PKGS termux-x11-nightly"
command -v wget >/dev/null 2>&1 || TERMUX_PKGS="$TERMUX_PKGS wget"
command -v curl >/dev/null 2>&1 || TERMUX_PKGS="$TERMUX_PKGS curl"
if [ -n "$TERMUX_PKGS" ]; then
# shellcheck disable=SC2086
run "Cài gói Termux thiếu thất bại" pkg install -y $TERMUX_PKGS
else
info "Gói Termux đã đủ."
fi
need_cmd proot-distro
need_cmd termux-x11
if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
fail "Thiếu cả wget và curl."
fi
draw_progress 15 "Kiểm tra Termux:X11 Android app"
if command -v pm >/dev/null 2>&1 && pm list packages 2>/dev/null | grep -q "package:com.termux.x11"; then
info "Termux:X11 Android app đã cài."
else
warn "Không thấy package com.termux.x11 -> cài APK Termux:X11 nếu GUI không mở được."
fi
printf '\n'
draw_progress 20 "Chọn distro (Enter/bậy = ubuntu)"
printf '%s => 1) Ubuntu  2) Debian  3) Fedora\n' "$TAG"
printf '%s => Nhập lựa chọn [1-3]: %s' "$TAG" "$C_RESET"
read -r DISTRO_CHOICE || DISTRO_CHOICE=""
case "$DISTRO_CHOICE" in
2) DISTRO="debian" ;;
3) DISTRO="fedora" ;;
*) DISTRO="ubuntu" ;;
esac
info "Distro được chọn: $DISTRO"
draw_progress 30 "Kiểm tra container $DISTRO"
CONTAINER_EXISTS=0
if [ -n "$PREFIX" ] && [ -d "$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO" ]; then CONTAINER_EXISTS=1; fi
if [ "$CONTAINER_EXISTS" -eq 0 ] && proot-distro login "$DISTRO" -- /bin/sh -c true >/dev/null 2>&1; then CONTAINER_EXISTS=1; fi
if [ "$CONTAINER_EXISTS" -eq 1 ]; then
info "Container $DISTRO đã tồn tại. Không xóa dữ liệu; chỉ cài/sửa gói thiếu."
else
run_live "Cài container $DISTRO (lần đầu)" proot-distro install "$DISTRO"
fi
if ! proot-distro login "$DISTRO" -- /bin/sh -c true >>"$LOG_FILE" 2>&1; then
fail "Container $DISTRO không đăng nhập được."
fi
printf '%s\n' "$DISTRO" > "$STATE_FILE"
draw_progress 45 "Sửa lỗi kẹt + cài gói nền + theme ($DISTRO)"
if [ "$DISTRO" = "fedora" ]; then
try_distro 'Sửa transaction dnf kẹt lần trước thất bại' 'dnf -y complete-transaction || true; dnf clean all || true; dnf makecache --refresh || true'
distro_cmd_live 'Cài gói nền Fedora thất bại' 'miss=""; for p in xfce4-session xfwm4 xfce4-panel xfdesktop xfce4-terminal Thunar dbus-x11 curl wget git gnupg glibc-langpack-en; do rpm -q "$p" >/dev/null 2>&1 || miss="$miss $p"; done; if [ -n "$miss" ]; then case "$miss" in *xfce4-session*) dnf -y groupinstall "Xfce Desktop" || dnf -y install $miss || true ;; *) dnf -y --setopt=max_parallel_downloads=8 install $miss || true ;; esac; else echo "DMAS: gói nền Fedora đã đủ."; fi'
try_distro 'Cài bộ theme Fedora thất bại' 'miss=""; for p in arc-theme numix-gtk-theme materia-gtk-theme greybird-gtk-theme gnome-themes-extra papirus-icon-theme numix-icon-theme numix-icon-theme-circle moka-icon-theme adwaita-icon-theme breeze-icon-theme capitaine-cursors openzone-cursors comixcursors google-noto-emoji-color-fonts jetbrains-mono-fonts firacode-fonts; do rpm -q "$p" >/dev/null 2>&1 || miss="$miss $p"; done; if [ -n "$miss" ]; then dnf -y --setopt=max_parallel_downloads=8 install $miss || for p in $miss; do dnf -y install "$p" || true; done; else echo "DMAS: theme Fedora đã đủ."; fi'
install_firefox_fedora
try_distro 'Thiết lập locale Fedora thất bại' 'if ! locale -a 2>/dev/null | grep -qi "^en_US.utf8"; then dnf install -y glibc-langpack-en || true; fi; printf "LANG=en_US.UTF-8\n" > /etc/locale.conf; printf "export LANG=en_US.UTF-8\nexport LC_ALL=en_US.UTF-8\n" > /etc/profile.d/99-dmas-locale.sh; chmod 644 /etc/profile.d/99-dmas-locale.sh || true'
else
try_distro 'Sửa dpkg/apt kẹt lần trước thất bại' 'if command -v flock >/dev/null 2>&1; then i=0; while [ "$i" -lt 60 ]; do if flock -n /var/lib/dpkg/lock-frontend true 2>/dev/null; then break; fi; sleep 2; i=$((i+2)); done; fi; holder=0; for c in /proc/[0-9]*/comm; do if [ -r "$c" ] && grep -q -e "^apt-get" -e "^dpkg" "$c" 2>/dev/null; then holder=1; break; fi; done; if [ "$holder" -eq 0 ]; then rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock /var/lib/apt/lists/lock 2>/dev/null || true; else echo "DMAS: dpkg lock vẫn được giữ bởi process sống."; fi; dpkg --configure -a || true; apt-get install -f -y || true'
try_distro 'Cập nhật apt thất bại' "export DEBIAN_FRONTEND=noninteractive; apt-get $APT_OPTS update -y"
miss=$(distro_exec "miss=\"\"; for p in dbus-x11 xfce4 xfce4-terminal thunar curl wget ca-certificates gnupg apt-transport-https locales git; do dpkg -s \"\$p\" >/dev/null 2>&1 || miss=\"\$miss \$p\"; done; echo \$miss" | tail -n 1)
if ! pool_install_debs "Gói nền $DISTRO" "$miss"; then fail "Cài gói nền $DISTRO thất bại"; fi
miss2=$(distro_exec 'dpkg -s xfce4-goodies >/dev/null 2>&1 || echo xfce4-goodies' | tail -n 1)
pool_install_debs "xfce4-goodies $DISTRO" "$miss2" || true
miss3=$(distro_exec 'miss=""; for p in arc-theme numix-gtk-theme greybird-gtk-theme gnome-themes-extra gtk2-engines-murrine gtk2-engines-pixbuf papirus-icon-theme numix-icon-theme numix-icon-theme-circle moka-icon-theme elementary-xfce-icon-theme adwaita-icon-theme tango-icon-theme gnome-icon-theme suru-icon-theme faenza-icon-theme breeze-icon-theme humanity-icon-theme comixcursors fonts-ubuntu fonts-noto-color-emoji fonts-firacode fonts-jetbrains-mono; do dpkg -s "$p" >/dev/null 2>&1 || miss="$miss $p"; done; echo $miss' | tail -n 1)
pool_install_debs "Theme/icon $DISTRO" "$miss3" || true
if [ "$DISTRO" = "debian" ]; then install_firefox_debian; else install_firefox_ubuntu; fi
try_distro 'Thiết lập locale Debian/Ubuntu thất bại' "export DEBIAN_FRONTEND=noninteractive; if ! locale -a 2>/dev/null | grep -qi \"^en_US.utf8\"; then apt-get $APT_OPTS install -y locales || true; if [ -f /etc/locale.gen ]; then sed -i \"s/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/\" /etc/locale.gen 2>/dev/null || true; grep -q '^en_US.UTF-8 UTF-8' /etc/locale.gen || echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen; fi; locale-gen en_US.UTF-8 || true; else echo \"DMAS: locale đã có.\"; fi; update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 || true; printf 'export LANG=en_US.UTF-8\nexport LC_ALL=en_US.UTF-8\n' > /etc/profile.d/99-dmas-locale.sh; chmod 644 /etc/profile.d/99-dmas-locale.sh || true"
fi
info "Locale UTF-8 sẵn sàng."
# ---- Tải thêm theme/icon/cursor đẹp từ GitHub (best-effort, có marker) ----
draw_progress 60 "Tải theme/icon/cursor mở rộng từ GitHub"
FETCH_SRC="$HOME/.dmas_fetch_themes.src.$$"
cat <<'FETCHEOF' > "$FETCH_SRC" || fail "Không ghi được fetcher template"
#!/bin/sh
LOG=/root/.dmas_themes.log
log() { printf '[DMAS-THEMES] %s\n' "$*" >>"$LOG" 2>/dev/null || true; }
get() {
u="$1"; d="$2"
if command -v wget >/dev/null 2>&1; then wget -q -T 60 -O "$d" "$u" && return 0; fi
if command -v curl >/dev/null 2>&1; then curl -fsSL --max-time 60 -o "$d" "$u" && return 0; fi
return 1
}
mark_done() { touch "/root/.dmas_done_$1" 2>/dev/null || true; }
is_done() { [ -f "/root/.dmas_done_$1" ]; }
install_gtk() {
key="$1"; u="$2"
is_done "$key" && return 0
n=$(printf '%s' "$u" | sed 's|.*/||; s|\.tar.*||')
t="/tmp/dmas_theme_$n.tar.gz"
log "fetch gtk: $u"
get "$u" "$t" || { log "FAIL fetch $u"; return 1; }
ex="/tmp/dmas_ex_$n"; rm -rf "$ex"; mkdir -p "$ex"
tar -xzf "$t" -C "$ex" || { log "FAIL extract $u"; rm -rf "$ex" "$t"; return 1; }
find "$ex" -maxdepth 4 -type d -name gtk-3.0 2>/dev/null | while IFS= read -r g; do
td=$(dirname "$g"); name=$(basename "$td")
if [ ! -d "/usr/share/themes/$name" ]; then
cp -r "$td" "/usr/share/themes/$name" 2>/dev/null && log "installed gtk theme: $name"
fi
done
rm -rf "$ex" "$t"
mark_done "$key"
return 0
}
install_icons() {
key="$1"; u="$2"; kind="$3"
is_done "$key" && return 0
n=$(printf '%s' "$u" | sed 's|.*/||; s|\.tar.*||')
t="/tmp/dmas_icons_$n.tar.gz"
log "fetch $kind: $u"
get "$u" "$t" || { log "FAIL fetch $u"; return 1; }
ex="/tmp/dmas_exi_$n"; rm -rf "$ex"; mkdir -p "$ex"
tar -xzf "$t" -C "$ex" || { log "FAIL extract $u"; rm -rf "$ex" "$t"; return 1; }
if [ "$kind" = "cursor" ]; then
find "$ex" -maxdepth 4 -type d -name cursors 2>/dev/null | while IFS= read -r g; do
td=$(dirname "$g"); name=$(basename "$td")
if [ ! -d "/usr/share/icons/$name" ]; then
cp -r "$td" "/usr/share/icons/$name" 2>/dev/null && log "installed cursor: $name"
fi
done
else
find "$ex" -maxdepth 4 -type f -name index.theme 2>/dev/null | while IFS= read -r g; do
td=$(dirname "$g"); name=$(basename "$td")
case "$td" in */cursors|*/cursors/*) continue ;; esac
grep -q '^Directories=' "$g" 2>/dev/null || continue
if [ ! -d "/usr/share/icons/$name" ]; then
cp -r "$td" "/usr/share/icons/$name" 2>/dev/null && log "installed icons: $name"
fi
done
fi
rm -rf "$ex" "$t"
mark_done "$key"
return 0
}
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
if command -v tr >/dev/null 2>&1; then
tr -d '\r' < "$FETCH_SRC" > "$FETCH_SRC.clean" 2>>"$LOG_FILE" && mv "$FETCH_SRC.clean" "$FETCH_SRC" || fail "tr CRLF fetcher thất bại"
fi
log "[RUN] ghi /root/.dmas_fetch_themes.sh"
if ! proot-distro login "$DISTRO" -- /bin/sh -c 'cat > /root/.dmas_fetch_themes.sh' < "$FETCH_SRC" >>"$LOG_FILE" 2>&1; then
fail "Không ghi được /root/.dmas_fetch_themes.sh"
fi
rm -f "$FETCH_SRC" 2>/dev/null || true
distro_cmd 'chmod fetcher thất bại' 'chmod 755 /root/.dmas_fetch_themes.sh'
LIVE_DESC="Tải theme/icon/cursor GitHub"
distro_exec_live '/root/.dmas_fetch_themes.sh' || warn "Fetch theme GitHub lỗi (xem /root/.dmas_themes.log); theme apt vẫn dùng được."
LIVE_DESC=""
draw_progress 75 "Cài đặt VS Code (editor chính)"
VSCODE_OK=0; VS_ATTEMPT=1
while [ "$VS_ATTEMPT" -le 2 ]; do
if [ "$DISTRO" = "fedora" ]; then
if install_vscode_fedora; then VSCODE_OK=1; break; fi
else
if install_vscode_debian; then VSCODE_OK=1; break; fi
fi
warn "Cài VS Code thất bại ở bước: $VC_STEP."
[ "$VS_ATTEMPT" -lt 2 ] && { warn "Thử lại VS Code..."; sleep 2; }
VS_ATTEMPT=$((VS_ATTEMPT + 1))
done
if [ "$VSCODE_OK" -eq 1 ]; then
PKG_EDITOR="code"
info "VS Code cài thành công + xác minh. Geany KHÔNG được cài."
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
if distro_exec 'command -v code >/dev/null 2>&1'; then
apply_vscode_proot_fix
info "VS Code có wrapper proot-fix. Không mở được thì xem: proot-distro login $DISTRO -- cat /root/.dmas_code.log"
fi
draw_progress 85 "Wallpaper, theme, panel, icon desktop, autostart"
distro_cmd 'Tạo thư mục UI thất bại' 'mkdir -p /root/.config/autostart /root/Pictures /root/Desktop'
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
P1_URL="__PANEL1_URL__"
P2_URL="__PANEL2_URL__"
P1_FILE="$WALLPAPER_DIR/panel1.png"
P2_FILE="$WALLPAPER_DIR/panel2.png"
UI_LOG="/root/.dmas_ui_fix.log"
ui_log() { printf '[DMAS-UI] %s\n' "$*" >>"$UI_LOG" 2>/dev/null || true; }
verify_image() {
file="$1"; ext="$2"
[ -s "$file" ] || return 1
if ! command -v od >/dev/null 2>&1 || ! command -v tr >/dev/null 2>&1; then return 0; fi
magic=$(od -An -N4 -tx1 "$file" 2>/dev/null | tr -d ' \n')
case "$ext" in
png) [ "$magic" = "89504e47" ] && return 0 ;;
jpg|jpeg) case "$magic" in ffd8ff*) return 0 ;; esac ;;
esac
return 1
}
download_file() {
url="$1"; dest="$2"; ext="$3"; tmp="${dest}.tmp"
if command -v wget >/dev/null 2>&1; then wget -T 30 -q -O "$tmp" "$url" 2>/dev/null || return 1
elif command -v curl >/dev/null 2>&1; then curl -fsSL --max-time 30 -o "$tmp" "$url" 2>/dev/null || return 1
else return 1; fi
if ! verify_image "$tmp" "$ext"; then rm -f "$tmp" 2>/dev/null || true; return 1; fi
mv "$tmp" "$dest" || return 1
}
fetch_once() {
u="$1"; d="$2"; e="$3"
if [ -s "$d" ] && verify_image "$d" "$e"; then return 0; fi
download_file "$u" "$d" "$e"
}
mkdir -p "$WALLPAPER_DIR" /root/Desktop 2>/dev/null || true
WALLPAPER=""
if fetch_once "$PRIMARY_URL" "$PRIMARY_FILE" png; then WALLPAPER="$PRIMARY_FILE"
elif fetch_once "$FALLBACK_URL" "$FALLBACK_FILE" jpg; then WALLPAPER="$FALLBACK_FILE"; ui_log "wallpaper chính lỗi, dùng fallback"; fi
HAS_P1="no"; fetch_once "$P1_URL" "$P1_FILE" png && HAS_P1="yes"
HAS_P2="no"; fetch_once "$P2_URL" "$P2_FILE" png && HAS_P2="yes"
i=0
while [ "$i" -lt 30 ]; do
if xfconf-query -c xfce4-desktop -l >/dev/null 2>&1; then break; fi
sleep 1; i=$((i + 1))
done
if command -v xfconf-query >/dev/null 2>&1; then
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
# ---- Icon desktop: cỡ chuẩn, tránh lệch ----
xfconf-query -c xfce4-desktop -p /desktop-icons/style -s 2 --create -t int 2>/dev/null || true
xfconf-query -c xfce4-desktop -p /desktop-icons/icon-size -s 48 --create -t uint 2>/dev/null || true
# ---- Theme: ưu tiên theme tải từ GitHub ----
pick_dir() {
pd_dir="$1"; shift
for t in "$@"; do
if [ -d "$pd_dir/$t" ]; then printf '%s' "$t"; return 0; fi
done
printf ''
}
GTK_T=$(pick_dir /usr/share/themes Tokyo-Night Tokyo-Night-Dark Dracula Nordic Sweet Catppuccin-Mocha Arc-Dark Materia-dark Numix Greybird Adwaita)
ICO_T=$(pick_dir /usr/share/icons WhiteSur Tela-circle BeautyLine Papirus-Dark Numix-Circle Moka Adwaita)
CUR_T=$(pick_dir /usr/share/icons McMojave-cursors Apple-Cursors ComixCursors-Opaque-Black OpenZone_Black Adwaita)
if [ -n "$GTK_T" ]; then
xfconf-query -c xsettings -p /Net/ThemeName -s "$GTK_T" --create -t string 2>/dev/null || true
xfconf-query -c xfwm4 -p /general/theme -s "$GTK_T" --create -t string 2>/dev/null || true
fi
if [ -n "$ICO_T" ]; then xfconf-query -c xsettings -p /Net/IconThemeName -s "$ICO_T" --create -t string 2>/dev/null || true; fi
if [ -n "$CUR_T" ]; then xfconf-query -c xsettings -p /Gtk/CursorThemeName -s "$CUR_T" --create -t string 2>/dev/null || true; fi
xfconf-query -c xsettings -p /Gtk/CursorThemeSize -s 24 --create -t int 2>/dev/null || true
ui_log "theme: GTK=$GTK_T ICON=$ICO_T CURSOR=$CUR_T"
# ---- Panel-1: dưới cùng, full ngang, autohide, locked, hết lệch hàng ----
P1=panel-1
xfconf-query -c xfce4-panel -p "/panels/$P1/position" -s "p=10;x=0;y=0" --create -t string 2>/dev/null || true
xfconf-query -c xfce4-panel -p "/panels/$P1/length" -s 100 --create -t uint 2>/dev/null || true
xfconf-query -c xfce4-panel -p "/panels/$P1/length-adjust" -s true --create -t bool 2>/dev/null || true
xfconf-query -c xfce4-panel -p "/panels/$P1/size" -s 42 --create -t uint 2>/dev/null || true
xfconf-query -c xfce4-panel -p "/panels/$P1/nrows" -s 1 --create -t uint 2>/dev/null || true
xfconf-query -c xfce4-panel -p "/panels/$P1/autohide-behavior" -s 2 --create -t uint 2>/dev/null || true
xfconf-query -c xfce4-panel -p "/panels/$P1/position-locked" -s true --create -t bool 2>/dev/null || true
if [ "$HAS_P1" = "yes" ]; then
xfconf-query -c xfce4-panel -p "/panels/$P1/background-style" -s 2 --create -t uint 2>/dev/null || true
xfconf-query -c xfce4-panel -p "/panels/$P1/background-image" -s "$P1_FILE" --create -t string 2>/dev/null || true
else
xfconf-query -c xfce4-panel -p "/panels/$P1/background-style" -s 1 --create -t uint 2>/dev/null || true
xfconf-query -c xfce4-panel -p "/panels/$P1/background-rgba" --create --force-array -t double -s 0.08 -s 0.08 -s 0.10 -s 0.85 2>/dev/null || true
fi
# ---- Panel-2: góc phải trên, nhỏ, đồng hồ ----
P2=panel-2
xfconf-query -c xfce4-panel -p "/panels/$P2/position" -s "p=7;x=0;y=0" --create -t string 2>/dev/null || true
xfconf-query -c xfce4-panel -p "/panels/$P2/length" -s 30 --create -t uint 2>/dev/null || true
xfconf-query -c xfce4-panel -p "/panels/$P2/length-adjust" -s false --create -t bool 2>/dev/null || true
xfconf-query -c xfce4-panel -p "/panels/$P2/size" -s 42 --create -t uint 2>/dev/null || true
xfconf-query -c xfce4-panel -p "/panels/$P2/nrows" -s 1 --create -t uint 2>/dev/null || true
xfconf-query -c xfce4-panel -p "/panels/$P2/autohide-behavior" -s 0 --create -t uint 2>/dev/null || true
xfconf-query -c xfce4-panel -p "/panels/$P2/position-locked" -s true --create -t bool 2>/dev/null || true
xfconf-query -c xfce4-panel -p "/panels/$P2/plugins" --create --force-array -t string -s plugin-1 2>/dev/null || true
xfconf-query -c xfce4-panel -p "/panels/$P2/plugin-1" -s "clock" --create -t string 2>/dev/null || true
xfconf-query -c xfce4-panel -p "/panels/$P2/plugin-1/digital-format" -s "%H:%M" --create -t string 2>/dev/null || true
if [ "$HAS_P2" = "yes" ]; then
xfconf-query -c xfce4-panel -p "/panels/$P2/background-style" -s 2 --create -t uint 2>/dev/null || true
xfconf-query -c xfce4-panel -p "/panels/$P2/background-image" -s "$P2_FILE" --create -t string 2>/dev/null || true
else
xfconf-query -c xfce4-panel -p "/panels/$P2/background-style" -s 1 --create -t uint 2>/dev/null || true
xfconf-query -c xfce4-panel -p "/panels/$P2/background-rgba" --create --force-array -t double -s 0.08 -s 0.08 -s 0.10 -s 0.85 2>/dev/null || true
fi
# ---- Áp dụng ngay ----
xfce4-panel -r 2>/dev/null || true
ui_log "panel1=bottom+img($HAS_P1), panel2=top-right+clock+img($HAS_P2)"
# ---- Icon desktop cho VS Code + Firefox ----
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
gio set /root/Desktop/code.desktop metadata::trusted true 2>/dev/null || true
fi
FFBIN=""
if [ -x /usr/lib/firefox/firefox ]; then FFBIN="/usr/lib/firefox/firefox"
elif [ -x /usr/lib/firefox-esr/firefox-esr ]; then FFBIN="/usr/lib/firefox-esr/firefox-esr"
elif command -v firefox >/dev/null 2>&1; then FFBIN="firefox"; fi
if [ -n "$FFBIN" ]; then
cat > /root/Desktop/firefox.desktop <<DESK2
[Desktop Entry]
Version=1.0
Type=Application
Name=Firefox
Comment=DMAS Browser
Exec=$FFBIN %u
Icon=firefox
Terminal=false
StartupNotify=true
Categories=Network;WebBrowser;
DESK2
chmod +x /root/Desktop/firefox.desktop 2>/dev/null || true
gio set /root/Desktop/firefox.desktop metadata::trusted true 2>/dev/null || true
fi
# ---- Theme switcher ----
cat > /root/.dmas_theme.sh <<'SWEOF'
#!/bin/sh
echo "=== GTK themes ==="; ls /usr/share/themes 2>/dev/null
echo "=== Icon themes ==="; ls /usr/share/icons 2>/dev/null
echo "=== Cursor themes ==="; ls /usr/share/icons 2>/dev/null | grep -i -e cursor -e comix -e mojomave -e mcmojave -e apple -e adwaita
printf 'GTK theme moi (Enter = giu): '; read -r GT
printf 'Icon theme moi (Enter = giu): '; read -r IT
printf 'Cursor theme moi (Enter = giu): '; read -r CT
[ -n "$GT" ] && { xfconf-query -c xsettings -p /Net/ThemeName -s "$GT" --create -t string 2>/dev/null || true; xfconf-query -c xfwm4 -p /general/theme -s "$GT" --create -t string 2>/dev/null || true; }
[ -n "$IT" ] && xfconf-query -c xsettings -p /Net/IconThemeName -s "$IT" --create -t string 2>/dev/null || true
[ -n "$CT" ] && xfconf-query -c xsettings -p /Gtk/CursorThemeName -s "$CT" --create -t string 2>/dev/null || true
echo "Da ap dung."
SWEOF
chmod 755 /root/.dmas_theme.sh 2>/dev/null || true
else
ui_log "xfconf-query không tồn tại, bỏ qua UI."
fi
exit 0
UIEOF
log "[RUN] sed thay URL wallpaper + panel images"
if ! sed -e "s#__WALLPAPER_URL__#$WALLPAPER_URL#" -e "s#__PANEL1_URL__#https://raw.githubusercontent.com/dmasntd/DmasLinux/main/panel1.png#" -e "s#__PANEL2_URL__#https://raw.githubusercontent.com/dmasntd/DmasLinux/main/panel2.png#" "$UI_SRC" > "$UI_OUT" 2>>"$LOG_FILE"; then
fail "sed UI thất bại"
fi
if command -v tr >/dev/null 2>&1; then
if ! tr -d '\r' < "$UI_OUT" > "$UI_OUT.clean" 2>>"$LOG_FILE"; then fail "tr CRLF UI thất bại"; fi
mv "$UI_OUT.clean" "$UI_OUT" || fail "mv UI thất bại"
fi
log "[RUN] ghi /root/.dmas_ui_fix.sh"
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
if ! tr -d '\r' < "$DESKTOP_SRC" > "$DESKTOP_OUT" 2>>"$LOG_FILE"; then fail "tr CRLF desktop thất bại"; fi
else
cat "$DESKTOP_SRC" > "$DESKTOP_OUT" 2>>"$LOG_FILE" || fail "cat desktop thất bại"
fi
log "[RUN] ghi autostart dmas_ui.desktop"
if ! proot-distro login "$DISTRO" -- /bin/sh -c 'cat > /root/.config/autostart/dmas_ui.desktop' < "$DESKTOP_OUT" >>"$LOG_FILE" 2>&1; then
fail "Không ghi được autostart desktop"
fi
distro_cmd 'chmod desktop file thất bại' 'chmod 644 /root/.config/autostart/dmas_ui.desktop'
rm -f "$UI_SRC" "$UI_OUT" "$DESKTOP_SRC" "$DESKTOP_OUT" 2>/dev/null || true
# ==========================================
# LAUNCHER startdmas.sh + UNINSTALLER unidmas.sh
# ==========================================
draw_progress 92 "Tạo startdmas.sh + unidmas.sh"
START_SRC="$HOME/.startdmas.src.$$"
START_TMP="$HOME/.startdmas.tmp.$$"
cat <<'START_EOF' > "$START_SRC" || fail "Không ghi được startdmas template"
#!/bin/sh
# Generated by linuxdmas.sh - DO NOT EDIT WITH CRLF
ESC=$(printf '\033')
C_CYAN="${ESC}[38;2;0;220;255m"
C_GREEN="${ESC}[38;2;50;255;120m"
C_RED="${ESC}[38;2;255;80;80m"
C_RESET="${ESC}[0m"
TAG="${C_CYAN}[DmasLinux]${C_RESET}"
DISTRO="__DMAS_DISTRO__"
DISPLAY_NUM=":0"
START_LOG="$HOME/.dmas_start.log"
CLEANED=0
XSERVER_PID=""
log() { printf '%s\n' "$*" >>"$START_LOG" 2>/dev/null || true; }
dmas() { printf '%s => %s\n' "$TAG" "$*"; log "$*"; }
stop_x11() {
[ "$CLEANED" -eq 1 ] && return 0
CLEANED=1
if [ -n "$XSERVER_PID" ] && kill -0 "$XSERVER_PID" 2>/dev/null; then
kill "$XSERVER_PID" 2>/dev/null || true
sleep 1
kill -9 "$XSERVER_PID" 2>/dev/null || true
fi
pkill -f "termux-x11 ${DISPLAY_NUM}" 2>/dev/null || true
pkill -f "Xwayland ${DISPLAY_NUM}" 2>/dev/null || true
termux-wake-unlock 2>/dev/null || true
return 0
}
on_signal() { stop_x11; exit 130; }
trap stop_x11 EXIT
trap on_signal INT TERM
if [ -z "$DISTRO" ]; then dmas "ERROR: DISTRO chưa cấu hình."; exit 1; fi
command -v proot-distro >/dev/null 2>&1 || { dmas "ERROR: thiếu proot-distro."; exit 1; }
command -v termux-x11 >/dev/null 2>&1 || { dmas "ERROR: thiếu termux-x11."; exit 1; }
if ! proot-distro login "$DISTRO" -- /bin/sh -c true >/dev/null 2>&1; then
dmas "ERROR: container $DISTRO chưa sẵn sàng."
exit 1
fi
start_stack() {
CLEANED=0
termux-wake-lock 2>/dev/null || true
dmas "Dọn tiến trình X11 cũ cho display ${DISPLAY_NUM}..."
pkill -f "termux-x11 ${DISPLAY_NUM}" 2>/dev/null || true
pkill -f "Xwayland ${DISPLAY_NUM}" 2>/dev/null || true
sleep 1
if [ -n "$TMPDIR" ]; then rm -f "$TMPDIR/.X11-unix/X0" "$TMPDIR/.X0-lock" 2>/dev/null || true; fi
rm -f /tmp/.X11-unix/X0 /tmp/.X0-lock 2>/dev/null || true
dmas "Mở ứng dụng Termux:X11..."
if command -v am >/dev/null 2>&1; then
am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >>"$START_LOG" 2>&1 || log "[WARN] am start failed"
else
log "[WARN] am không khả dụng"
fi
sleep 2
dmas "Khởi chạy termux-x11 server ${DISPLAY_NUM}..."
termux-x11 "$DISPLAY_NUM" -ac >>"$START_LOG" 2>&1 &
XSERVER_PID=$!
SOCKET="$TMPDIR/.X11-unix/X0"
[ -n "$TMPDIR" ] || SOCKET="/tmp/.X11-unix/X0"
i=0
while [ "$i" -lt 20 ]; do
[ -e "$SOCKET" ] && break
sleep 1; i=$((i + 1))
done
if [ ! -e "$SOCKET" ]; then
dmas "ERROR: không thấy X11 socket $SOCKET."
return 1
fi
return 0
}
run_xfce() {
dmas "Đăng nhập $DISTRO XFCE4..."
proot-distro login "$DISTRO" --shared-tmp --env DISPLAY="$DISPLAY_NUM" -- /bin/sh -c 'export LANG=en_US.UTF-8; export LC_ALL=en_US.UTF-8; if ! command -v dbus-launch >/dev/null 2>&1; then echo "[ERROR] dbus-launch thiếu" >&2; exit 70; fi; if ! command -v startxfce4 >/dev/null 2>&1; then echo "[ERROR] startxfce4 thiếu" >&2; exit 71; fi; mkdir -p /tmp/xdg 2>/dev/null || true; chmod 700 /tmp/xdg 2>/dev/null || true; exec dbus-launch --exit-with-session startxfce4'
return $?
}
start_stack || { dmas "ERROR: khởi động X11 thất bại."; exit 1; }
dmas "Đã khởi động thành công."
run_xfce
RC=$?
[ "$RC" -eq 70 ] && dmas "ERROR: DBus thiếu/không khởi động được."
[ "$RC" -eq 71 ] && dmas "ERROR: XFCE4 thiếu/không khởi động được."
while :; do
dmas "Đang thoát..."
dmas "Đang dừng tiến trình..."
stop_x11
dmas "Đã dừng"
printf '%s => Chọn: [1] Thoát hẳn  [2] Khởi động lại Linux: %s' "$TAG" "$C_RESET"
if ! read -r CHOICE </dev/tty 2>/dev/null; then read -r CHOICE; fi
case "$CHOICE" in
2)
dmas "Đang khởi động lại..."
if start_stack; then
dmas "Đã khởi động thành công."
run_xfce
RC=$?
continue
else
dmas "Khởi động lại thất bại."
continue
fi
;;
*) break ;;
esac
done
dmas "Hẹn gặp lại ở phiên DMAS kế tiếp."
exit "$RC"
START_EOF
log "[RUN] sed DISTRO vào startdmas.sh"
if ! sed "s#__DMAS_DISTRO__#$DISTRO#" "$START_SRC" > "$START_TMP" 2>>"$LOG_FILE"; then fail "sed startdmas thất bại"; fi
if command -v tr >/dev/null 2>&1; then
if ! tr -d '\r' < "$START_TMP" > "$START_TMP.clean" 2>>"$LOG_FILE"; then fail "tr CRLF startdmas thất bại"; fi
mv "$START_TMP.clean" "$START_TMP" || fail "mv startdmas thất bại"
fi
PREV_CAND=""
for cand in "$PWD/startdmas.sh" "$HOME/startdmas.sh"; do
[ "$cand" = "$PREV_CAND" ] && continue
PREV_CAND=$cand
if cp "$START_TMP" "$cand" 2>>"$LOG_FILE"; then
chmod +x "$cand" 2>/dev/null || true
log "[INFO] Đã ghi launcher: $cand"
else
warn "Không ghi được launcher: $cand"
fi
done
rm -f "$START_SRC" "$START_TMP" 2>/dev/null || true
START_SCRIPT=""; RUN_CMD=""
if [ -x "$PWD/startdmas.sh" ]; then START_SCRIPT="$PWD/startdmas.sh"; RUN_CMD="./startdmas.sh"
elif [ -x "$HOME/startdmas.sh" ]; then START_SCRIPT="$HOME/startdmas.sh"; RUN_CMD="~/startdmas.sh"
elif [ -f "$HOME/startdmas.sh" ]; then START_SCRIPT="$HOME/startdmas.sh"; RUN_CMD="sh ~/startdmas.sh"
elif [ -f "$PWD/startdmas.sh" ]; then START_SCRIPT="$PWD/startdmas.sh"; RUN_CMD="sh $PWD/startdmas.sh"
else fail "Không ghi được startdmas.sh."; fi
log "[RUN] sh -n $START_SCRIPT"
if ! sh -n "$START_SCRIPT" >>"$LOG_FILE" 2>&1; then fail "startdmas.sh không pass sh -n"; fi
info "Đã tạo launcher: $START_SCRIPT ($RUN_CMD)"
UNI_SRC="$HOME/.unidmas.src.$$"
UNI_TMP="$HOME/.unidmas.tmp.$$"
cat <<'UNI_EOF' > "$UNI_SRC" || fail "Không ghi được unidmas template"
#!/bin/sh
DISTRO="__DMAS_DISTRO__"
echo "!!! GO CAI DAT LINUX DMAS (container: $DISTRO) !!!"
printf 'Nhập đúng chữ "yes" để xác nhận: '
read -r CONF
[ "$CONF" = "yes" ] || { echo "Huy lenh go."; exit 1; }
echo "[*] Dung X11..."
pkill -f "termux-x11 :0" 2>/dev/null
pkill -f "Xwayland :0" 2>/dev/null
sleep 1
if command -v proot-distro >/dev/null 2>&1; then
echo "[*] Go container $DISTRO..."
proot-distro remove "$DISTRO" 2>/dev/null || true
fi
if command -v pkg >/dev/null 2>&1; then
echo "[*] Gỡ termux-x11-nightly..."
pkg remove -y termux-x11-nightly >/dev/null 2>&1 || true
fi
H="$HOME"
echo "[*] Xóa file DMAS..."
rm -f "$H/startdmas.sh" "$H/.dmas_setup_done" "$H/.dmas_install.log" "$H/.dmas_start.log" "$H/.dmas_distro" "$H/.dmas_themes.log"
rm -f "$H/.dmas_ui_fix.src."* "$H/.dmas_ui_fix.out."* "$H/.dmas_ui_desktop.src."* "$H/.dmas_ui_desktop.out."*
rm -f "$H/.startdmas.src."* "$H/.startdmas.tmp."* "$H/.unidmas.src."* "$H/.unidmas.tmp."*
rm -rf "$H/.dmas_install.lock"
[ "$(pwd)" != "$H" ] && rm -f "./startdmas.sh" 2>/dev/null
echo "[+] Đă gỡ sạch Linux DMAS."
rm -f "$H/unidmas.sh"
UNI_EOF
log "[RUN] sed DISTRO vào unidmas.sh"
if ! sed "s#__DMAS_DISTRO__#$DISTRO#" "$UNI_SRC" > "$UNI_TMP" 2>>"$LOG_FILE"; then fail "sed unidmas thất bại"; fi
if command -v tr >/dev/null 2>&1; then
if ! tr -d '\r' < "$UNI_TMP" > "$UNI_TMP.clean" 2>>"$LOG_FILE"; then fail "tr CRLF unidmas thất bại"; fi
mv "$UNI_TMP.clean" "$UNI_TMP" || fail "mv unidmas thất bại"
fi
PREV_CAND=""
for cand in "$PWD/unidmas.sh" "$HOME/unidmas.sh"; do
[ "$cand" = "$PREV_CAND" ] && continue
PREV_CAND=$cand
if cp "$UNI_TMP" "$cand" 2>>"$LOG_FILE"; then
chmod +x "$cand" 2>/dev/null || true
log "[INFO] Đã ghi uninstaller: $cand"
else
warn "Không ghi được uninstaller: $cand"
fi
done
rm -f "$UNI_SRC" "$UNI_TMP" 2>/dev/null || true
if [ -f "$HOME/unidmas.sh" ]; then
sh -n "$HOME/unidmas.sh" >>"$LOG_FILE" 2>&1 || fail "unidmas.sh không pass sh -n"
info "Đã tạo uninstaller: ~/unidmas.sh"
fi
# ==========================================
# CHECK CUỐI + FLAG + AUTO-LAUNCH
# ==========================================
draw_progress 97 "Kiểm tra cuối"
if [ -f "$0" ]; then
if sh -n "$0" >>"$LOG_FILE" 2>&1; then info "sh -n linuxdmas.sh pass"; else warn "sh -n linuxdmas.sh báo lỗi."; fi
fi
if command -v shellcheck >/dev/null 2>&1; then
shellcheck "$0" >>"$LOG_FILE" 2>&1 || warn "shellcheck có cảnh báo (không chặn)."
shellcheck "$START_SCRIPT" >>"$LOG_FILE" 2>&1 || warn "shellcheck startdmas có cảnh báo (không chặn)."
else
info "shellcheck không tồn tại; bỏ qua."
fi
[ -f "$START_SCRIPT" ] || fail "startdmas.sh không tồn tại."
touch "$SETUP_FLAG" || fail "Không tạo được success flag"
log "[INFO] Success flag: $SETUP_FLAG"
draw_progress 100 "Cài đặt thành công"
info "Cài đặt hoàn tất. Editor chính: VS Code ($PKG_EDITOR)."
info "Đổi theme/icon/cursor trong XFCE: /root/.dmas_theme.sh | Gỡ cài: sh ~/unidmas.sh"
info "Tự khởi chạy $RUN_CMD sau 3 giây... (Ctrl+C trong 3s để hủy)"
sleep 3
if [ -x "$HOME/startdmas.sh" ]; then
"$HOME/startdmas.sh"
LAUNCH_RC=$?
else
sh "$HOME/startdmas.sh"
LAUNCH_RC=$?
fi
info "Desktop đã thoát (mã $LAUNCH_RC). Chạy lại: $RUN_CMD"
