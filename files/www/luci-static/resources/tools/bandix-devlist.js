'use strict';
'require baseclass';

var _ctrl = null;

return baseclass.extend({
	mount: function(parent, opts) {
		if (!parent)
			return Promise.reject(new Error('missing parent'));
		return L.require('view.bandix_plus.index').then(function(BandixView) {
			if (_ctrl && _ctrl.unmountDeviceListEmbed) {
				_ctrl.unmountDeviceListEmbed();
				_ctrl = null;
			}
			if (!BandixView.createDeviceListEmbed)
				return Promise.reject(new Error('bandix embed API missing'));
			return BandixView.createDeviceListEmbed(parent, opts || {}).then(function(ctrl) {
				_ctrl = ctrl;
				return ctrl;
			});
		});
	},

	unmount: function() {
		if (_ctrl && _ctrl.unmountDeviceListEmbed)
			_ctrl.unmountDeviceListEmbed();
		_ctrl = null;
	}
});
