'use strict';
'require form';

return L.Class.extend({
	attach(ss, ifc) {
		if (!ss || !ifc)
			return;
		const name = ifc.getName ? ifc.getName() : '';
		if (name === 'loopback' || name === 'lo')
			return;

		let so = ss.taboption('general', form.Value, 'lede_bw_down', _('下行带宽'));
		so.datatype = 'uinteger';
		so.placeholder = 'Mbps';
		so.rmempty = true;
		so.description = _('接口下行容量，单位 Mbps。概览拓扑图勾选「宽带使用率」后按此计算百分比。');

		so = ss.taboption('general', form.Value, 'lede_bw_up', _('上行带宽'));
		so.datatype = 'uinteger';
		so.placeholder = 'Mbps';
		so.rmempty = true;
		so.description = _('接口上行容量，单位 Mbps。概览拓扑图勾选「宽带使用率」后按此计算百分比。');
	}
});
