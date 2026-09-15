[ -n "$SSH_CONNECTION" ] || return 0
ip=$(echo "$SSH_CONNECTION" | awk '{print $1}')
mac=$(awk -v ip="$ip" '$1==ip {print $4; exit}' /proc/net/arp 2>/dev/null)
[ "$mac" = "00:00:00:00:00:00" ] && mac=""
logger -t lede-login "SSH 登录 user=$(id -un 2>/dev/null) ip=$ip${mac:+ mac=$mac}"
