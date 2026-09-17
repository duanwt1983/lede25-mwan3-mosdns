#!/usr/bin/env ucode
'use strict';

import { popen, stat, readfile } from 'fs';

const LOG = '/var/log/isp-ip-update.log';
const LOCK = '/var/lock/isp-ip-update.lock';

function exec_sys(cmd) {
	let p = popen(cmd + ' 2>&1', 'r');
	if (!p)
		return { code: -1, stdout: '' };
	let stdout = p.read('all');
	let code = p.close();
	if (type(stdout) == 'string')
		stdout = replace(stdout, /^\s+|\s+$/g, '');
	return { code: code, stdout: stdout || '' };
}

const methods = {
	start_update: {
		call: function() {
			try {
				if (stat(LOCK))
					return { success: false, error: 'Another update is already in progress.' };
				exec_sys('echo "" > ' + LOG);
				exec_sys('/usr/libexec/isp-ip-update >/dev/null 2>&1 &');
				return { success: true };
			} catch (e) {
				return { success: false, error: String(e) };
			}
		}
	},

	get_update_log: {
		call: function() {
			try {
				if (stat(LOG))
					return { log: readfile(LOG) || '' };
				return { log: '' };
			} catch (e) {
				return { error: String(e) };
			}
		}
	}
};

return { 'luci.ispip': methods };
