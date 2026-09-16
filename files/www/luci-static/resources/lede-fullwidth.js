'use strict';
'require baseclass';

/* Deprecated: keep module for old requires; no layout overrides. */
return baseclass.extend({
	inject: function() {},
	wrap: function(node) { return node; }
});
