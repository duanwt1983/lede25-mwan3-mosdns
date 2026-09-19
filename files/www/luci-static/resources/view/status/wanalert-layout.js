'use strict';
'require baseclass';
'require lede-theme-page as ledeTheme';

function moveBox(box, parent) {
	if (box && parent)
		parent.appendChild(box);
}

function buildGrid(root, selector, gridClass) {
	const cells = root.querySelectorAll(selector);
	if (!cells.length)
		return;
	const host = cells[0].closest('.cbi-section-node') || root;
	if (host.querySelector('.' + gridClass))
		return;
	const grid = E('div', { 'class': gridClass });
	for (let i = 0; i < cells.length; i++) {
		const box = cells[i].closest('.cbi-value');
		if (box)
			moveBox(box, grid);
	}
	host.appendChild(grid);
}

function optionBox(root, opt) {
	return root.querySelector('.cbi-value[data-name="' + opt + '"]') ||
		root.querySelector('#cbi-wanalert-main-' + opt) ||
		root.querySelector('.cbi-value[id$="-' + opt + '"]');
}

function layoutThresholdPairs(root) {
	[
		[ 'cpu_percent', 'cpu_hold_min' ],
		[ 'load_warn', 'load_hold_min' ],
		[ 'mem_percent', 'mem_hold_min' ],
		[ 'temp_c', 'temp_hold_min' ],
		[ 'wan_bw_percent', 'wan_bw_hold_min' ]
	].forEach(function(pair) {
		const threshold = optionBox(root, pair[0]);
		const hold = optionBox(root, pair[1]);
		if (!threshold || !hold || threshold.classList.contains('wanalert-threshold-row'))
			return;
		const thresholdField = threshold.querySelector('.cbi-value-field');
		const holdField = hold.querySelector('.cbi-value-field');
		const holdTitle = hold.querySelector('.cbi-value-title');
		if (!thresholdField || !holdField)
			return;
		const holdDesc = holdField.querySelector('.cbi-value-description');
		const inline = E('span', {
			'class': 'wanalert-duration-inline',
			'title': holdDesc ? holdDesc.textContent.trim() : ''
		}, [
			E('span', { 'class': 'wanalert-duration-label' },
				holdTitle ? holdTitle.textContent.trim() : _('持续时间（分钟）'))
		]);
		Array.from(holdField.childNodes).forEach(function(child) {
			if (child !== holdDesc)
				inline.appendChild(child);
		});
		const thresholdDesc = thresholdField.querySelector('.cbi-value-description');
		const controls = E('div', { 'class': 'wanalert-threshold-controls' });
		Array.from(thresholdField.childNodes).forEach(function(child) {
			if (child !== thresholdDesc)
				controls.appendChild(child);
		});
		controls.appendChild(inline);
		thresholdField.insertBefore(controls, thresholdDesc || null);
		threshold.classList.add('wanalert-threshold-row');
		hold.remove();
	});
}

function layoutCards(root) {
	const map = root && root.classList && root.classList.contains('cbi-map')
		? root : root.querySelector('.cbi-map');
	if (!map || map.querySelector(':scope > .wanalert-card-grid'))
		return;
	map.classList.add('wanalert-mosdns-page');
	const sections = Array.from(map.children).filter(function(el) {
		return el.classList && el.classList.contains('cbi-section');
	});
	if (!sections.length)
		return;
	const grid = E('div', { 'class': 'wanalert-card-grid' });
	map.insertBefore(grid, sections[0]);
	sections.forEach(function(sec) {
		sec.classList.add('wanalert-card');
		if ((optionBox(sec, 'dingtalk_webhook') && optionBox(sec, 'security')) ||
		    optionBox(sec, 'pushplus_token') ||
		    sec.querySelector('.cbi-value[data-name^="alert_"]') ||
		    optionBox(sec, 'cpu_percent'))
			sec.classList.add('wanalert-card-wide');
		grid.appendChild(sec);
	});
}

function fixInput(root, opt) {
	const box = root.querySelector('.cbi-value[data-name="' + opt + '"]');
	return box ? box.querySelector('input[type="checkbox"]') : null;
}

function setDisabled(box, on) {
	if (!box)
		return;
	box.classList.toggle('lede-fix-off', !on);
	box.querySelectorAll('input,select,textarea,button').forEach(function(el) {
		if (el.type === 'checkbox' && el.closest('label.lede-fix-lead'))
			return;
		el.disabled = !on;
	});
	box.querySelectorAll('label.lede-fix-sub').forEach(function(lab) {
		lab.style.pointerEvents = on ? '' : 'none';
	});
}

function wireFixState(root, master) {
	const wanLead = fixInput(root, 'autofix_wan');
	const wanBox = root.querySelector('.lede-fix-group-wan .lede-fix-children');
	const cool = root.querySelector('.lede-fix-cool');
	const sync = function() {
		const masterOn = !!(master && master.checked);
		const wanOn = masterOn && !!(wanLead && wanLead.checked);
		setDisabled(wanBox, wanOn);
		if (cool)
			cool.classList.toggle('lede-fix-off', !masterOn);
		root.querySelectorAll('.lede-fix-group').forEach(function(g) {
			g.classList.toggle('lede-fix-master-off', !masterOn);
		});
	};
	[ master, wanLead ].forEach(function(inp) {
		if (inp)
			inp.addEventListener('change', sync);
	});
	sync();
}

function collectFixOpts(root) {
	const byOpt = {};
	root.querySelectorAll('.cbi-value[data-name]').forEach(function(box) {
		const opt = box.getAttribute('data-name') || '';
		if (opt === 'autofix' || opt.indexOf('autofix_') === 0 || opt.indexOf('wfix_') === 0)
			byOpt[opt] = box;
	});
	return byOpt;
}

function layoutAutofixSection(sectionEl, root) {
	if (!sectionEl || sectionEl.getAttribute('data-lede-fix-layout') === '1')
		return;
	const byOpt = collectFixOpts(sectionEl);
	if (!byOpt.autofix_wan)
		return;
	sectionEl.setAttribute('data-lede-fix-layout', '1');

	function markLead(box) {
		if (!box)
			return box;
		const lab = box.querySelector('label.lede-fix-cell');
		if (lab)
			lab.classList.add('lede-fix-lead');
		return box;
	}

	function markSub(box) {
		if (!box)
			return box;
		const lab = box.querySelector('label.lede-fix-cell');
		if (lab)
			lab.classList.add('lede-fix-sub');
		return box;
	}

	const mount = sectionEl.querySelector('.cbi-section-node') || sectionEl;
	const old = sectionEl.querySelector('.lede-fix-grid');
	if (old)
		old.remove();

	const grid = E('div', { 'class': 'lede-fix-grid' });
	if (byOpt.autofix) {
		const bar = E('div', { 'class': 'lede-fix-master-bar' });
		moveBox(byOpt.autofix, bar);
		grid.appendChild(bar);
	}

	const grpWan = E('div', { 'class': 'lede-fix-group lede-fix-group-wan' });
	moveBox(markLead(byOpt.autofix_wan), grpWan);
	const wanKids = E('div', { 'class': 'lede-fix-children' });
	wanKids.appendChild(E('div', { 'class': 'lede-fix-hint' }, _('勾选上方开关后，选择要自动重拨的 WAN 口：')));
	const rowW = E('div', { 'class': 'lede-fix-row lede-fix-row-wan' });
	Object.keys(byOpt).sort().forEach(function(opt) {
		if (opt.indexOf('wfix_') !== 0)
			return;
		moveBox(markSub(byOpt[opt]), rowW);
	});
	if (rowW.childNodes.length)
		wanKids.appendChild(rowW);
	grpWan.appendChild(wanKids);
	grid.appendChild(grpWan);

	sectionEl.querySelectorAll('.cbi-value[data-name="autofix_hold_min"], .cbi-value[data-name="autofix_cooldown"]').forEach(function(box) {
		moveBox(box, grid);
		box.classList.add('lede-fix-cool');
	});

	mount.appendChild(grid);
	wireFixState(root || sectionEl, fixInput(root || sectionEl, 'autofix'));
}

function injectStyle(node) {
	if (!node)
		return;
	ledeTheme.injectBase();
	ledeTheme.injectStyles('lede-wanalert-layout', [
		'.lede-ding-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));column-gap:24px;row-gap:8px;padding:4px 0 12px;}',
		'.lede-ding-grid>.cbi-value{border:0;padding:0;margin:0;background:none;}',
		'label.lede-ding-cell{display:flex;align-items:flex-start;gap:8px;margin:0;padding:0;font-weight:normal;cursor:pointer;line-height:1.45;min-width:0;color:inherit;}',
		'label.lede-fix-cell{display:inline-flex;align-items:center;gap:8px;margin:0;padding:0;font-weight:normal;cursor:pointer;line-height:1.45;min-width:0;color:inherit;}',
		'label.lede-ding-cell input,label.lede-fix-cell input{margin:.15em 0 0;flex:0 0 auto;}',
		'label.lede-fix-cell span{min-width:0;}',
		'.lede-fix-grid{display:flex;flex-direction:column;gap:12px;padding:4px 0 8px;}',
		'.lede-fix-master-bar{margin:0 0 4px 0;}',
		'.lede-fix-master-bar>.cbi-value{border:0;padding:0;margin:0;background:none;}',
		'label.lede-fix-master{display:inline-flex;align-items:center;gap:8px;margin:0;cursor:pointer;font-weight:650;font-size:1.05em;color:inherit;}',
		'label.lede-fix-master input{margin:0;}',
		'.lede-fix-group{border:1px solid rgba(0,0,0,0.08);border-radius:8px;padding:10px 12px 12px;background:var(--cbi-section-bg,var(--background-color-high,#fff));box-shadow:0 2px 6px rgba(0,0,0,0.03);}',
		'.lede-fix-group.lede-fix-master-off{opacity:.72;}',
		'.lede-fix-group>.cbi-value{border:0;padding:0;margin:0;background:none;}',
		'label.lede-fix-lead{font-weight:650;font-size:1.02em;}',
		'.lede-fix-children{margin:10px 0 0 0;padding:10px 12px 8px 2.2em;border-left:3px solid var(--primary,var(--primary-color-high,#2563eb));border-radius:0 6px 6px 0;background:rgba(125,125,125,0.04);}',
		'.lede-fix-children.lede-fix-off{opacity:.45;}',
		'.lede-fix-hint{font-size:.88em;color:var(--muted-color,rgba(127,127,127,.75));margin:0 0 8px 0;line-height:1.4;}',
		'.lede-fix-row{display:flex!important;flex-flow:row wrap!important;align-items:center!important;gap:10px 24px!important;width:100%;}',
		'.lede-fix-row>.cbi-value{display:block!important;width:auto!important;max-width:none!important;flex:0 0 auto!important;border:0;padding:0;margin:0;background:none;float:none!important;}',
		'.lede-fix-row>.cbi-value .cbi-value-title{display:none!important;}',
		'label.lede-fix-sub{display:inline-flex!important;align-items:center!important;padding-left:0;white-space:nowrap;}',
		'label.lede-fix-off{color:var(--muted-color,rgba(127,127,127,.75));cursor:not-allowed;}',
		'label.lede-fix-off input{cursor:not-allowed;}',
		'.lede-fix-cool{margin:0;padding:10px 0 0;border-top:1px solid var(--border-color-medium,rgba(127,127,127,.22));}',
		'.lede-fix-cool.lede-fix-off{opacity:.45;}',
		'.wanalert-mosdns-page{width:100%;min-width:0;}',
		'.wanalert-mosdns-page>h2{margin:0 0 1rem;font-size:1.45rem;font-weight:700;line-height:1.2;}',
		'.wanalert-mosdns-page>.cbi-map-descr{margin:-.35rem 0 1.25rem;opacity:.72;line-height:1.55;}',
		'.wanalert-card-grid{display:grid;grid-template-columns:minmax(0,1fr);gap:1rem;margin:0 0 1.25rem;align-items:start;}',
		'.wanalert-card{min-width:0!important;margin:0!important;padding:1rem 1.1rem!important;background:var(--cbi-section-bg,#fff)!important;border:1px solid rgba(0,0,0,.08)!important;border-radius:8px!important;box-shadow:0 2px 6px rgba(0,0,0,.03)!important;overflow:visible!important;}',
		'.wanalert-card-wide{grid-column:1/-1;}',
		'.wanalert-card>h3{display:flex;align-items:center;justify-content:space-between;margin:0 0 .85rem!important;padding:0 0 .7rem!important;border-bottom:1px solid rgba(125,125,125,.14);font-size:.98rem!important;font-weight:600!important;line-height:1.3;}',
		'.wanalert-card>.cbi-section-descr{margin:-.3rem 0 .8rem;opacity:.68;font-size:.86rem;line-height:1.5;}',
		'.wanalert-card .cbi-section-node{min-width:0;}',
		'.wanalert-card .cbi-value{box-sizing:border-box;}',
		'.wanalert-threshold-controls{display:flex!important;align-items:center;gap:18px;flex-wrap:nowrap;min-width:0;}',
		'.wanalert-threshold-controls>div:first-child{flex:0 0 288px;min-width:0;}',
		'.wanalert-threshold-controls>div:first-child input{width:100%!important;min-width:0!important;box-sizing:border-box;}',
		'.wanalert-duration-inline{display:inline-flex!important;align-items:center;gap:8px;margin:0;vertical-align:middle;white-space:nowrap;flex:0 0 auto;}',
		'.wanalert-duration-label{font-weight:400;line-height:2.2;}',
		'.wanalert-duration-inline input{width:90px!important;min-width:70px!important;max-width:90px!important;box-sizing:border-box;}',
		'.wanalert-threshold-row>.cbi-value-field>.cbi-value-description{display:block;clear:both;margin-top:5px!important;}',
		'@media (max-width:720px){.lede-ding-grid{grid-template-columns:minmax(0,1fr);}.wanalert-threshold-controls{gap:10px;}.wanalert-threshold-controls>div:first-child{flex:1 1 auto;min-width:0;}}'
	].join('\n'), [
		'.lede-fix-group{background:rgba(255,255,255,0.03);border-color:rgba(255,255,255,0.08);box-shadow:none;}',
		'.lede-fix-children{background:rgba(255,255,255,0.04);}',
		'.lede-fix-cool{border-top-color:rgba(255,255,255,0.08);}',
		'.wanalert-card{background:rgba(255,255,255,.03)!important;border-color:rgba(255,255,255,.08)!important;box-shadow:none!important;}',
		'.wanalert-card>h3{border-bottom-color:rgba(255,255,255,.08);}'
	].join('\n'));
}

function applyPage(node) {
	if (!node || node.getAttribute('data-lede-wanalert-layout') === '1')
		return node;
	node.setAttribute('data-lede-wanalert-layout', '1');
	injectStyle(node);

	node.querySelectorAll('.cbi-section').forEach(function(sec) {
		if (sec.querySelector('.cbi-value[data-name^="alert_"]'))
			buildGrid(sec, 'label.lede-ding-cell', 'lede-ding-grid');
		if (sec.querySelector('.cbi-value[data-name="autofix_wan"]'))
			layoutAutofixSection(sec, node);
	});
	layoutThresholdPairs(node);
	layoutCards(node);
	return node;
}

return baseclass.extend({
	applyPage: applyPage
});
