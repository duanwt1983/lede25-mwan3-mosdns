#!/usr/bin/env python3
# Chinese help on mwan3 IP set pages. ISP update UI is 网络 → 多线负载 → 运营商地址库 only.
from pathlib import Path
import sys

HELP_ZH = [
	("IP sets are nftables address sets referenced by mwan3 rules.",
	 "IP 集是 nftables 地址集合，给 mwan3 规则用来匹配源或目的地址。"),
	("Sets can be populated with static entries, loaded from a file, or populated at runtime by dnsmasq name resolution.",
	 "可以用手动条目填充、从文件加载，或由 dnsmasq 解析域名后动态加入。"),
	("Set names must not begin with \"mwan3_\" (reserved for internal use).",
	 "名称不能以 mwan3_ 开头（系统内部保留）。"),
	("The Enable checkbox is greyed if the set is referenced by an enabled rule.",
	 "若已被已启用的规则引用，「启用」会变灰，不能关掉。"),
]


def zh_ipset_help(path: Path) -> None:
	t = path.read_text(encoding='utf-8')
	orig = t
	for en, zh in HELP_ZH:
		t = t.replace(en, zh)
	# Drop leftover ISP toolbar if an older patch injected it.
	if 'ispUpdateToolbar' in t:
		t = t.replace("\t\tconst box = E('div', {}, [\n\t\t\tispUpdateToolbar(),\n\t\t\tm.render()\n\t\t]);\n\t\treturn box;",
			"\t\treturn m.render();")
		t = t.replace("ispUpdateToolbar(), E('h2'", "E('h2'")
		t = t.replace("ispUpdateToolbar(),\n\t\t\tE('br'),", "")
	if t != orig:
		path.write_text(t, encoding='utf-8')
		print('zh ipset help', path)


if __name__ == '__main__':
	root = Path(sys.argv[1])
	app = next(root.glob('**/luci-app-mwan3'))
	cfg = next(app.glob('**/view/mwan3/network/ipset.js'), None)
	st = next(app.glob('**/view/mwan3/status/ipsets.js'), None)
	if not cfg or not st:
		raise SystemExit('mwan3 ipset views not found')
	zh_ipset_help(cfg)
	zh_ipset_help(st)
