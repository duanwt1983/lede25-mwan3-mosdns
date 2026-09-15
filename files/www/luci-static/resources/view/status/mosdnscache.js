'use strict';
'require view';

return view.extend({
	load() {
		return L.require('view.mosdns.statistics').then(L.bind(function(mod) {
			this._mod = mod;
			const fn = (mod && typeof mod.load === 'function') ? mod.load
				: (mod && mod.prototype && typeof mod.prototype.load);
			return fn ? fn.call(mod) : null;
		}, this));
	},

	render(data) {
		const mod = this._mod;
		const fn = (mod && typeof mod.render === 'function') ? mod.render
			: (mod && mod.prototype && typeof mod.prototype.render);
		if (!fn)
			return E('p', {}, '未找到 MosDNS 统计页。请用 服务 → MosDNS → 统计。');
		const node = fn.call(mod, data);
		if (node && node.querySelectorAll) {
			const hs = node.querySelectorAll('h2');
			for (let i = 0; i < hs.length; i++)
				hs[i].parentNode.removeChild(hs[i]);
		}
		return node;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
