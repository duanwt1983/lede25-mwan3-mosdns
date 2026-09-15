#!/bin/sh
# Disable Add/Edit/Remove on mwan3 stock config pages.
for f in interface member policy rule; do
	p="/www/luci-static/resources/view/mwan3/network/${f}.js"
	[ -f "$p" ] || continue
	sed -i 's/s.addremove=true/s.addremove=false/g' "$p"
	sed -i 's/s.addremove = true/s.addremove = false/g' "$p"
	if ! grep -q 's.renderRowActions=function' "$p"; then
		sed -i "s/s.nodescriptions=true;/s.nodescriptions=true;s.renderRowActions=function(){return E('td',{'class':'td'});};/" "$p"
		sed -i "s/s.nodescriptions = true;/s.nodescriptions = true; s.renderRowActions=function(){return E('td',{'class':'td'});};/" "$p"
	fi
done
echo locked
grep -o 'addremove=[a-z]*' /www/luci-static/resources/view/mwan3/network/interface.js /www/luci-static/resources/view/mwan3/network/member.js /www/luci-static/resources/view/mwan3/network/policy.js /www/luci-static/resources/view/mwan3/network/rule.js
