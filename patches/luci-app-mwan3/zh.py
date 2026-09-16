# -*- coding: utf-8 -*-
"""Replace luci-app-mwan3 gettext English with Chinese in cloned JS/JSON."""
from pathlib import Path
import json
import sys

# Longer keys first.
MAP = [
    ("Enter traffic parameters to simulate which mwan3 rule matches and which policy would handle the traffic. IP fields accept addresses or hostnames - hostnames are resolved via the local DNS server. Rules with a constraint on a field you leave blank will not match.",
     "填写流量参数，看会命中哪条 mwan3 规则、走哪条策略。IP 可填地址或域名（域名用本机 DNS 解析）。规则里限制了某项而你留空，这条规则就不会命中。"),
    ("IP sets are nftables address sets referenced by mwan3 rules.",
     "IP 集是 nftables 地址集合，给 mwan3 规则用来匹配源或目的地址。"),
    ("Sets can be populated with static entries, loaded from a file, or populated at runtime by dnsmasq name resolution.",
     "可以用手动条目填充、从文件加载，或由 dnsmasq 解析域名后动态加入。"),
    ("Set names must not begin with \"mwan3_\" (reserved for internal use).",
     "名称不能以 mwan3_ 开头（系统内部保留）。"),
    ("The Enable checkbox is greyed if the set is referenced by an enabled rule.",
     "若已被已启用的规则引用，「启用」会变灰，不能关掉。"),
    ("Cannot delete IP set \"%s\": referenced by rule(s): %s. Remove those rule references first.",
     "无法删除 IP 集「%s」：仍被规则引用：%s。请先改掉那些规则。"),
    ("Invalid name: use letters, digits, _ . or - only, starting with a letter or _",
     "名称只能用字母、数字、下划线、点和短横线，且必须以字母或下划线开头"),
    ("Names beginning with \"mwan3_\" are reserved for internal use",
     "不能用 mwan3_ 开头，这是系统保留前缀"),
    ("A set with this name already exists", "已有同名集合"),
    ("Static entries: IP addresses or CIDR subnets (eg \"192.168.1.1\" or \"10.0.0.0/8\")",
     "静态条目：IP 或网段，例如 192.168.1.1 或 10.0.0.0/8"),
    ("Invalid IP address or prefix", "IP 或前缀无效"),
    ("Entry must be an IPv4 address when family is set to IPv4", "地址族为 IPv4 时只能填 IPv4"),
    ("Entry must be an IPv6 address when family is set to IPv6", "地址族为 IPv6 时只能填 IPv6"),
    ("Domain names resolved by dnsmasq and added to the set at runtime (eg \"youtube.com\")",
     "由 dnsmasq 解析域名后动态加入集合，例如 youtube.com"),
    ("File of IP addresses or CIDRs, one per line; lines beginning with # are ignored",
     "每行一个 IP 或 CIDR，以 # 开头的行会忽略"),
    ("Maximum number of elements in the set. Leave empty for no limit",
     "集合最多容纳多少条，留空表示不限制"),
    ("Entry lifetime in seconds. 0 means entries do not expire",
     "条目存活秒数，0 表示不过期"),
    ("Track per-element packet and byte counts", "统计每条的包数和字节数"),
    ("MultiWAN Manager - IP Sets", "多线负载 - IP 集"),
    ("MultiWAN Manager - Traffic Path Simulator", "多线负载 - 流量路径模拟"),
    ("Could not resolve destination hostname", "无法解析目的主机名"),
    ("Could not resolve source hostname", "无法解析源主机名"),
    ("Invalid destination IP address", "目的 IP 无效"),
    ("Invalid source IP address", "源 IP 无效"),
    ("Also matched (shadowed by first rule)", "也会命中（被前面的规则挡住，实际走不到）"),
    ("All members offline - last resort", "成员全部离线，走兜底"),
    ("mwan3 not running - cannot show live member state", "mwan3 未运行，看不到成员实时状态"),
    ("mwan3 rules bypassed - directly connected network", "目的是直连网段，不走 mwan3 规则"),
    ("Policy not found in configuration", "配置里找不到这条策略"),
    ("First matching rule", "最先命中的规则"),
    ("Shadowed rule", "被挡住的规则"),
    ("No rule matched", "没有规则命中"),
    ("Live member state", "成员实时状态"),
    ("Terminal policy", "终结策略"),
    ("Traffic will be load-balanced across ", "流量将在以下成员之间负载："),
    ("Traffic will be routed using the main routing table.", "流量走主路由表。"),
    ("Traffic will use", "流量将使用"),
    ("blackhole (drop)", "黑洞（丢弃）"),
    ("unreachable (reject)", "不可达（拒绝）"),
    ("use main routing table", "使用主路由表"),
    ("is in the connected set", "属于直连网段"),
    ("IPv4 and IPv6", "IPv4 和 IPv6"),
    ("IPv4 only", "仅 IPv4"),
    ("IPv6 only", "仅 IPv6"),
    ("Address family", "地址族"),
    ("Destination IP/Name", "目的 IP / 域名"),
    ("Source IP/Name", "源 IP / 域名"),
    ("Destination port", "目的端口"),
    ("Source port", "源端口"),
    ("e.g. 192.168.1.5 or hostname", "例如 192.168.1.5 或主机名"),
    ("e.g. 8.8.4.4 or hostname", "例如 8.8.4.4 或主机名"),
    ("e.g. 80 or 443 1024:2048 or 80,443", "例如 80，或 443，或 1024:2048，或 80,443"),
    ("No user-defined IP sets configured.", "还没有自定义 IP 集。"),
    ("Failed to load members", "加载条目失败"),
    ("Flush: flush the nft set of all elements.", "清空：删掉 nft 集合里的全部条目。"),
    ("Reload: reload the set with static entries defined in the config and from the loadfile.",
     "重载：按配置里的静态条目和导入文件重新装入集合。"),
    ("Resolve: flush dnsmasq's cache and explicitly resolve every defined domain using dnsmasq to populate the set.",
     "解析：清 dnsmasq 缓存，并把已填域名重新解析写入集合。"),
    ("Showing first %d entries. The set may contain more elements.",
     "只显示前 %d 条，集合里可能还有更多。"),
    ("Set is empty", "集合是空的"),
    ("Load all (5000)", "加载全部（最多 5000）"),
    ("Load more (1000)", "再加载 1000 条"),
    ("IPs / Networks", "IP / 网段"),
    ("Include File", "从文件导入"),
    ("Max Entries", "最大条目数"),
    ("all traffic", "全部流量"),
    ("Members", "成员列表"),
    ("src nftset", "源 NFT 集"),
    ("Loading...", "加载中…"),
    ("unlimited", "不限制"),
    ("counters", "计数"),
    ("Domains", "域名"),
    ("Timeout", "超时"),
    ("Enable", "启用"),
    ("Family", "地址族"),
    ("Protocol", "协议"),
    ("Destination", "目的"),
    ("Fwmark", "防火墙标记"),
    ("Simulate", "开始模拟"),
    ("Resolved", "已解析"),
    ("Address", "地址"),
    ("Packets", "包数"),
    ("Bytes", "字节"),
    ("Collapse", "收起"),
    ("Expand", "展开"),
    ("Flush", "清空"),
    ("Reload", "重载"),
    ("Resolve", "解析域名"),
    ("Policy", "策略"),
    ("Match", "匹配"),
    ("None", "无"),
    (" members", " 个成员"),
    ("metric", "跃点数"),
    ("weight", "权重"),
    ("sticky", "粘滞"),
    ("nftset", "NFT 集"),
    ("dport", "目的端口"),
    ("sport", "源端口"),
    ("mark", "标记"),
    ("more", "个"),
    ("IP Sets", "IP 集"),
]


def zh_js(path: Path) -> None:
    import re
    t = path.read_text(encoding="utf-8")
    n = 0
    for en, zh in sorted(MAP, key=lambda p: -len(p[0])):
        if len(en) < 5 and en not in ("Enable", "Flush", "Reload"):
            continue
        zh_esc = zh.replace("\\", "\\\\").replace("'", "\\'")
        en_esc = re.escape(en)
        for q in ("'", '"'):
            pat = re.compile(r"_\(" + q + en_esc + q + r"\)")
            repl = "_(" + q + zh_esc + q + ")"
            t2, c = pat.subn(repl, t)
            if c:
                t = t2
                n += c
    path.write_text(t, encoding="utf-8")
    print("zh", path, "hits", n)


def zh_menu(path: Path) -> None:
    data = json.loads(path.read_text(encoding="utf-8"))
    titles = {
        "IP Sets": "IP 集",
        "Simulator": "流量模拟",
        "MultiWAN Manager": "多线负载",
        "Overview": "概览",
        "Status": "状态",
        "Diagnostics": "诊断",
        "Troubleshooting": "排障",
        "Routing": "路由",
        "Globals": "自动配置",
        "Interface": "接口",
        "Member": "成员",
        "Policy": "策略",
        "Rule": "规则",
        "Configuration": "配置",
        "Notify": "通知",
    }
    for key, body in data.items():
        t = body.get("title")
        if t in titles:
            body["title"] = titles[t]
    path.write_text(json.dumps(data, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8")
    print("zh menu", path)


if __name__ == "__main__":
    p = Path(sys.argv[1])
    if p.suffix == ".json":
        zh_menu(p)
    else:
        zh_js(p)
