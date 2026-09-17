# Turn tshark key-event fields into Chinese timeline lines.
# Input columns (tab):
#  1 rel_time  2 abs_time  3 src  4 dst  5 sport  6 dport
#  7 dns_name  8 dns_resp  9 sni  10 syn  11 ack  12 fin  13 rst  14 retrans
BEGIN {
	FS = "\t"
	CLIENT = ENVIRON["PCAP_CLIENT"]
	DOMAIN = ENVIRON["PCAP_DOMAIN"]
	MAX = 400
	shown = 0
}

function ts(t) {
	if (t ~ /^[0-9]/) {
		sub(/\.[0-9]+$/, "", t)
		return t
	}
	sub(/\.[0-9]+ /, " ", t)
	return t
}

function is_client(ip) {
	return (CLIENT != "" && ip == CLIENT)
}

function is_server(ip) {
	return (CLIENT != "" && ip != CLIENT && ip !~ /^192\.168\./ && ip !~ /^10\./ && ip !~ /^172\.(1[6-9]|2[0-9]|3[0-1])\./)
}

function svc(port) {
	p = port + 0
	if (p == 53) return "DNS"
	if (p == 80) return "HTTP"
	if (p == 443) return "HTTPS"
	if (p == 61624) return "MQTT"
	if (p == 22) return "SSH"
	return "TCP:" p
}

function domain_hit(name) {
	if (DOMAIN == "" || name == "") return 1
	return index(name, DOMAIN) > 0
}

function emit(line) {
	if (shown >= MAX) return
	print line
	shown++
}

{
	rel = $1; abs = $2
	sip = $3; dip = $4
	sp = $5; dp = $6
	dns = $7; dns_r = $8
	sni = $9
	syn = $10 + 0; ack = $11 + 0; fin = $12 + 0; rst = $13 + 0
	retr = $14

	t = ts(abs != "" ? abs : rel)

	if (dns != "" && !domain_hit(dns)) next

	if (dns != "" && (dns_r == "0" || dns_r == "False" || dns_r == "")) {
		if (CLIENT == "" || sip == CLIENT)
			emit(t "  客户端 " sip "  查询 DNS → " dns "  →  等待应答")
		next
	}
	if (dns != "" && (dns_r == "1" || dns_r == "True")) {
		if (CLIENT == "" || dip == CLIENT || sip == CLIENT)
			emit(t "  DNS 服务器  返回 " dns "  的解析结果给 " (dip == CLIENT ? dip : sip))
		next
	}

	if (sni != "" && domain_hit(sni)) {
		emit(t "  客户端 " sip "  通过 HTTPS 访问 " sni "（" dip ":" dp "）  →  加密握手")
		next
	}

	if (syn && !ack) {
		who = is_client(sip) ? "客户端 " sip : sip
		emit(t "  " who "  发起 TCP 连接 → " dip ":" dp "（" svc(dp) "）  →  等待 SYN-ACK")
		next
	}
	if (syn && ack) {
		emit(t "  " sip "  同意 TCP 连接 ← " dip "  →  连接建立")
		next
	}

	if (rst) {
		who = sip
		tag = "失败/被重置"
		if (is_client(sip))
			tag = "客户端主动 RST"
		else if (is_server(sip))
			tag = "服务器 RST（会话被踢或异常）"
		emit(t "  " who "  发送 TCP RST → " dip ":" dp "  →  " tag)
		next
	}

	if (fin) {
		emit(t "  " sip "  发送 TCP FIN，结束与 " dip " 的 " svc(dp) " 连接  →  正常关闭阶段")
		next
	}

	if (retr == "1" || retr == "True") {
		# Only show retrans bursts occasionally - skip individual to avoid flood
		key = sip "->" dip ":" dp
		retr_cnt[key]++
		if (retr_cnt[key] == 1 || retr_cnt[key] == 10 || retr_cnt[key] == 50)
			emit(t "  " sip " → " dip ":" dp "  出现 TCP 重传（第 " retr_cnt[key] " 次）  →  链路或对端可能丢包")
		next
	}
}

END {
	if (shown >= MAX)
		print "… 时间线超过 " MAX " 条，后续关键事件已省略。完整数据请下载 pcap 用 Wireshark 查看。"
}
