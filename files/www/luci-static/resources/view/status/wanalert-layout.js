'use strict';
'require baseclass';

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

	sectionEl.querySelectorAll('.cbi-value[data-name="autofix_cooldown"]').forEach(function(box) {
		moveBox(box, grid);
		box.classList.add('lede-fix-cool');
	});

	mount.appendChild(grid);
	wireFixState(root || sectionEl, fixInput(root || sectionEl, 'autofix'));
}

function injectStyle(node) {
	if (!node || node.querySelector('style[data-lede-wanalert-layout]'))
		return;
	node.insertBefore(E('style', {
		type: 'text/css',
		'data-lede-wanalert-layout': '1'
	}, [
		'.lede-ding-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));column-gap:24px;row-gap:8px;padding:4px 0 12px;}',
		'.lede-ding-grid>.cbi-value{border:0;padding:0;margin:0;background:none;}',
		'label.lede-ding-cell{display:flex;align-items:flex-start;gap:8px;margin:0;padding:0;font-weight:normal;cursor:pointer;line-height:1.45;min-width:0;}',
		'label.lede-fix-cell{display:inline-flex;align-items:center;gap:8px;margin:0;padding:0;font-weight:normal;cursor:pointer;line-height:1.45;min-width:0;}',
		'label.lede-ding-cell input,label.lede-fix-cell input{margin:.15em 0 0;flex:0 0 auto;}',
		'label.lede-fix-cell span{min-width:0;}',
		'.lede-fix-grid{display:flex;flex-direction:column;gap:12px;padding:4px 0 8px;}',
		'.lede-fix-master-bar{margin:0 0 4px 0;}',
		'.lede-fix-master-bar>.cbi-value{border:0;padding:0;margin:0;background:none;}',
		'label.lede-fix-master{display:inline-flex;align-items:center;gap:8px;margin:0;cursor:pointer;font-weight:650;font-size:1.05em;}',
		'label.lede-fix-master input{margin:0;}',
		'.lede-fix-group{border:1px solid rgba(127,127,127,.35);border-radius:8px;padding:10px 12px 12px;background:rgba(127,127,127,.08);}',
		'.lede-fix-group.lede-fix-master-off{opacity:.72;}',
		'.lede-fix-group>.cbi-value{border:0;padding:0;margin:0;background:none;}',
		'label.lede-fix-lead{font-weight:650;font-size:1.02em;}',
		'.lede-fix-children{margin:10px 0 0 0;padding:10px 12px 8px 2.2em;border-left:3px solid var(--primary-color-high,#2563eb);border-radius:0 6px 6px 0;background:rgba(127,127,127,.1);}',
		'.lede-fix-children.lede-fix-off{opacity:.45;}',
		'.lede-fix-hint{font-size:.88em;color:var(--muted-color,#64748b);margin:0 0 8px 0;line-height:1.4;}',
		'.lede-fix-row{display:flex!important;flex-flow:row wrap!important;align-items:center!important;gap:10px 24px!important;width:100%;}',
		'.lede-fix-row>.cbi-value{display:block!important;width:auto!important;max-width:none!important;flex:0 0 auto!important;border:0;padding:0;margin:0;background:none;float:none!important;}',
		'.lede-fix-row>.cbi-value .cbi-value-title{display:none!important;}',
		'label.lede-fix-sub{display:inline-flex!important;align-items:center!important;padding-left:0;white-space:nowrap;}',
		'label.lede-fix-off{color:var(--muted-color,#94a3b8);cursor:not-allowed;}',
		'label.lede-fix-off input{cursor:not-allowed;}',
		'.lede-fix-cool{margin:0;padding:10px 0 0;border-top:1px solid rgba(127,127,127,.22);}',
		'.lede-fix-cool.lede-fix-off{opacity:.45;}',
		'@media (max-width:720px){.lede-ding-grid{grid-template-columns:minmax(0,1fr);}}'
	].join('')), node.firstChild);
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
	return node;
}

return baseclass.extend({
	applyPage: applyPage
});
