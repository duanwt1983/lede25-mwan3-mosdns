'use strict';
'require baseclass';

const W = 800, H = 200;
const PAD = { l: 10, r: 90, t: 12, b: 28 };
const PAD_LAT = 52;
const COL_LAT = '#ea580c';

function svgEl(name, attrs) {
	const n = document.createElementNS('http://www.w3.org/2000/svg', name);
	if (attrs) {
		for (const k in attrs)
			n.setAttribute(k, attrs[k]);
	}
	return n;
}

function fmtBit(bps) {
	bps = Number(bps) || 0;
	if (!isFinite(bps) || bps < 0)
		bps = 0;
	const mbps = bps / 1e6;
	if (mbps >= 100)
		return mbps.toFixed(1) + ' Mbps';
	if (mbps >= 1)
		return mbps.toFixed(2) + ' Mbps';
	return mbps.toFixed(3) + ' Mbps';
}

function fmtBitFull(bps) {
	bps = Number(bps) || 0;
	if (!isFinite(bps) || bps < 0)
		bps = 0;
	const mbps = bps / 1e6;
	if (mbps >= 100)
		return mbps.toFixed(1) + ' Mbps';
	if (mbps >= 1)
		return mbps.toFixed(2) + ' Mbps';
	return mbps.toFixed(3) + ' Mbps';
}

function fmtWhen(ts) {
	ts = Number(ts) || 0;
	if (ts <= 0)
		return '--:--';
	const d = new Date(ts * 1000);
	const p = n => (n < 10 ? '0' : '') + n;
	return p(d.getHours()) + ':' + p(d.getMinutes()) + ':' + p(d.getSeconds());
}

function fmtWhenLong(ts) {
	ts = Number(ts) || 0;
	if (ts <= 0)
		return '--';
	const d = new Date(ts * 1000);
	const p = n => (n < 10 ? '0' : '') + n;
	return p(d.getMonth() + 1) + '-' + p(d.getDate()) + ' ' +
		p(d.getHours()) + ':' + p(d.getMinutes());
}

function niceMax(v) {
	v = Math.max(1, Number(v) || 1);
	const exp = Math.pow(10, Math.floor(Math.log10(v)));
	const n = v / exp;
	let m = 1;
	if (n > 5)
		m = 10;
	else if (n > 2)
		m = 5;
	else if (n > 1)
		m = 2;
	return m * exp;
}

function fmtMs(v) {
	v = Number(v) || 0;
	if (!isFinite(v) || v < 0)
		v = 0;
	if (v >= 100)
		return v.toFixed(0) + ' ms';
	if (v >= 10)
		return v.toFixed(1) + ' ms';
	return v.toFixed(1) + ' ms';
}

function seriesHasLat(series) {
	return (series || []).some(s => Array.isArray(s.lat) && s.lat.length);
}

function inner(hasLat) {
	const l = hasLat ? PAD_LAT : PAD.l;
	return {
		x: l,
		y: PAD.t,
		w: W - l - PAD.r,
		h: H - PAD.t - PAD.b
	};
}

function yOf(v, max, box) {
	return box.y + box.h - (Math.max(0, Number(v) || 0) / max) * box.h;
}

function xOf(i, n, box) {
	if (n <= 1)
		return box.x;
	return box.x + (i / (n - 1)) * box.w;
}

function polyPoints(arr, max, box) {
	const n = arr.length;
	return arr.map((v, i) => xOf(i, n, box).toFixed(1) + ',' + yOf(v, max, box).toFixed(1)).join(' ');
}

function bindHover(wrap, svg, box) {
	const tip = wrap.querySelector('.ratechart-tip');
	const cursor = wrap.querySelector('.ratechart-cursor');
	const hit = wrap.querySelector('.ratechart-hit');
	if (!tip || !cursor || !hit)
		return;
	const hide = function() {
		tip.style.display = 'none';
		cursor.setAttribute('opacity', '0');
		wrap._hovering = false;
	};
	hit.addEventListener('mouseleave', hide);
	hit.addEventListener('mousemove', function(ev) {
		const spec = wrap._spec;
		if (!spec || !spec.t || spec.t.length < 1)
			return;
		const rec = svg.getBoundingClientRect();
		if (rec.width <= 0)
			return;
		const sx = (ev.clientX - rec.left) * (W / rec.width);
		const box = inner(seriesHasLat(spec.series));
		const n = spec.t.length;
		let i = Math.round(((sx - box.x) / box.w) * (n - 1));
		if (i < 0)
			i = 0;
		if (i > n - 1)
			i = n - 1;
		wrap._hovering = true;
		cursor.setAttribute('x1', xOf(i, n, box).toFixed(1));
		cursor.setAttribute('x2', xOf(i, n, box).toFixed(1));
		cursor.setAttribute('opacity', '1');
		const span = spec.t[n - 1] - spec.t[0];
		const when = span >= 12 * 3600 ? fmtWhenLong(spec.t[i]) : fmtWhen(spec.t[i]);
		const lines = [when];
		(spec.series || []).forEach(s => {
			const lab = s.label ? s.label + ' ' : '';
			lines.push(lab + '下行 ' + fmtBitFull(s.rx && s.rx[i]));
			lines.push(lab + '上行 ' + fmtBitFull(s.tx && s.tx[i]));
			if (Array.isArray(s.lat) && s.lat.length)
				lines.push(lab + '延时 ' + fmtMs(s.lat[i]));
		});
		tip.textContent = lines.join('\n');
		tip.style.display = 'block';
		const left = ev.clientX - rec.left + 12;
		const top = ev.clientY - rec.top + 8;
		tip.style.left = Math.min(left, rec.width - 180) + 'px';
		tip.style.top = Math.min(top, rec.height - 88) + 'px';
	});
}

function ensure(wrap) {
	if (wrap._ready)
		return wrap;
	wrap.classList.add('ratechart-wrap');
	const svg = svgEl('svg', {
		viewBox: '0 0 ' + W + ' ' + H,
		class: 'ratechart',
		preserveAspectRatio: 'none'
	});
	svg.style.width = '100%';
	svg.style.height = H + 'px';
	svg.style.display = 'block';
	const gGrid = svgEl('g', { class: 'rc-grid' });
	const gPlot = svgEl('g', { class: 'rc-plot' });
	const gAxis = svgEl('g', { class: 'rc-axis' });
	const cursor = svgEl('line', {
		class: 'ratechart-cursor',
		y1: String(PAD.t),
		y2: String(H - PAD.b),
		stroke: 'rgba(30,41,59,.55)',
		'stroke-width': '1',
		opacity: '0'
	});
	const box = inner();
	const hit = svgEl('rect', {
		class: 'ratechart-hit',
		x: String(box.x),
		y: String(box.y),
		width: String(box.w),
		height: String(box.h),
		fill: 'transparent'
	});
	svg.appendChild(gGrid);
	svg.appendChild(gPlot);
	svg.appendChild(gAxis);
	svg.appendChild(cursor);
	svg.appendChild(hit);
	const tip = document.createElement('div');
	tip.className = 'ratechart-tip';
	wrap.appendChild(svg);
	wrap.appendChild(tip);
	wrap._svg = svg;
	wrap._grid = gGrid;
	wrap._plot = gPlot;
	wrap._axis = gAxis;
	bindHover(wrap, svg, box);
	wrap._ready = true;
	return wrap;
}

function draw(wrap, spec) {
	ensure(wrap);
	wrap._spec = spec || { t: [], series: [] };
	const t = wrap._spec.t || [];
	const series = wrap._spec.series || [];
	const hasLat = seriesHasLat(series);
	const box = inner(hasLat);
	const n = t.length;
	let rawMax = 1;
	let latRaw = 1;
	series.forEach(s => {
		(s.rx || []).forEach(v => { if (v > rawMax) rawMax = v; });
		(s.tx || []).forEach(v => { if (v > rawMax) rawMax = v; });
		(s.lat || []).forEach(v => { if (v > latRaw) latRaw = v; });
	});
	const max = niceMax(rawMax);
	const latMax = hasLat ? niceMax(Math.max(10, latRaw)) : 1;
	const grid = wrap._grid;
	const plot = wrap._plot;
	const axis = wrap._axis;
	while (grid.firstChild)
		grid.removeChild(grid.firstChild);
	while (plot.firstChild)
		plot.removeChild(plot.firstChild);
	while (axis.firstChild)
		axis.removeChild(axis.firstChild);

	const hit = wrap.querySelector('.ratechart-hit');
	if (hit) {
		hit.setAttribute('x', String(box.x));
		hit.setAttribute('y', String(box.y));
		hit.setAttribute('width', String(box.w));
		hit.setAttribute('height', String(box.h));
	}
	const cursor = wrap.querySelector('.ratechart-cursor');
	if (cursor) {
		cursor.setAttribute('y1', String(box.y));
		cursor.setAttribute('y2', String(box.y + box.h));
	}

	const bg = svgEl('rect', {
		x: String(box.x), y: String(box.y),
		width: String(box.w), height: String(box.h),
		fill: 'rgba(127,127,127,.06)', rx: '4'
	});
	grid.appendChild(bg);

	for (let k = 0; k <= 4; k++) {
		const frac = k / 4;
		const y = box.y + box.h * (1 - frac);
		const line = svgEl('line', {
			x1: String(box.x), x2: String(box.x + box.w),
			y1: y.toFixed(1), y2: y.toFixed(1),
			stroke: 'rgba(127,127,127,.22)',
			'stroke-width': '1'
		});
		grid.appendChild(line);
		const lab = svgEl('text', {
			x: String(box.x + box.w + 8),
			y: String(y + 3),
			'text-anchor': 'start',
			'font-size': '11',
			fill: 'currentColor',
			opacity: '.72'
		});
		lab.textContent = fmtBit(max * frac);
		axis.appendChild(lab);
		if (hasLat) {
			const ll = svgEl('text', {
				x: String(box.x - 6),
				y: String(y + 3),
				'text-anchor': 'end',
				'font-size': '11',
				fill: COL_LAT,
				opacity: '.85'
			});
			ll.textContent = fmtMs(latMax * frac);
			axis.appendChild(ll);
		}
	}

	const span = n >= 2 ? (t[n - 1] - t[0]) : 0;
	const tickN = 5;
	for (let k = 0; k < tickN; k++) {
		const frac = tickN === 1 ? 0 : k / (tickN - 1);
		const i = n <= 1 ? 0 : Math.round(frac * (n - 1));
		const x = n <= 1 ? box.x : xOf(i, n, box);
		const lab = svgEl('text', {
			x: x.toFixed(1),
			y: String(H - 8),
			'text-anchor': k === 0 ? 'start' : (k === tickN - 1 ? 'end' : 'middle'),
			'font-size': '11',
			fill: 'currentColor',
			opacity: '.72'
		});
		lab.textContent = n ? (span >= 12 * 3600 ? fmtWhenLong(t[i]) : fmtWhen(t[i])) : '';
		axis.appendChild(lab);
	}

	if (n >= 2) {
		series.forEach(s => {
			const rx = (s.rx && s.rx.length) ? s.rx : [0, 0];
			const tx = (s.tx && s.tx.length) ? s.tx : [0, 0];
			const down = svgEl('polyline', {
				fill: 'none',
				stroke: s.color || '#16a34a',
				'stroke-width': '2.1',
				points: polyPoints(rx, max, box)
			});
			const up = svgEl('polyline', {
				fill: 'none',
				stroke: s.colorTx || s.color || '#2563eb',
				'stroke-width': '2.1',
				'stroke-dasharray': '6 4',
				points: polyPoints(tx, max, box)
			});
			plot.appendChild(down);
			plot.appendChild(up);
			if (Array.isArray(s.lat) && s.lat.length >= 2) {
				const latLine = svgEl('polyline', {
					fill: 'none',
					stroke: s.colorLat || COL_LAT,
					'stroke-width': '1.7',
					'stroke-dasharray': '2 3',
					points: polyPoints(s.lat, latMax, box)
				});
				plot.appendChild(latLine);
			}
			if (series.length !== 1)
				return;
			const lastRx = Number(rx[rx.length - 1]) || 0;
			const lastTx = Number(tx[tx.length - 1]) || 0;
			let yRx = yOf(lastRx, max, box);
			let yTx = yOf(lastTx, max, box);
			if (Math.abs(yRx - yTx) < 14) {
				if (lastRx >= lastTx)
					yTx = Math.min(box.y + box.h, yRx + 14);
				else
					yRx = Math.min(box.y + box.h, yTx + 14);
			}
			const lx = box.x + box.w + 8;
			const downLab = svgEl('text', {
				x: String(lx), y: String(yRx + 3),
				'text-anchor': 'start',
				'font-size': '11',
				'font-weight': '700',
				fill: s.color || '#16a34a',
				stroke: 'var(--background-color-high, #fff)',
				'stroke-width': '3',
				'paint-order': 'stroke'
			});
			downLab.textContent = fmtBitFull(lastRx);
			const upLab = svgEl('text', {
				x: String(lx), y: String(yTx + 3),
				'text-anchor': 'start',
				'font-size': '11',
				'font-weight': '700',
				fill: s.colorTx || s.color || '#2563eb',
				stroke: 'var(--background-color-high, #fff)',
				'stroke-width': '3',
				'paint-order': 'stroke'
			});
			upLab.textContent = fmtBitFull(lastTx);
			axis.appendChild(downLab);
			axis.appendChild(upLab);
			if (Array.isArray(s.lat) && s.lat.length) {
				const lastLat = Number(s.lat[s.lat.length - 1]) || 0;
				const latLab = svgEl('text', {
					x: String(box.x - 6),
					y: String(yOf(lastLat, latMax, box) + 3),
					'text-anchor': 'end',
					'font-size': '11',
					'font-weight': '700',
					fill: s.colorLat || COL_LAT,
					stroke: 'var(--background-color-high, #fff)',
					'stroke-width': '3',
					'paint-order': 'stroke'
				});
				latLab.textContent = fmtMs(lastLat);
				axis.appendChild(latLab);
			}
		});
	}
}

const COMBO_W = 800;
const COMBO_H = 240;
const COMBO_PAD = { l: 118, r: 78, t: 22, b: 24 };

function comboPlotBox() {
	return {
		x: COMBO_PAD.l,
		y: COMBO_PAD.t,
		w: COMBO_W - COMBO_PAD.l - COMBO_PAD.r,
		h: COMBO_H - COMBO_PAD.t - COMBO_PAD.b
	};
}

function comboAxisText(x, y, text, anchor, color, weight, inside) {
	const n = svgEl('text', {
		x: String(x),
		y: String(y),
		'text-anchor': anchor || 'start',
		'font-size': '11',
		'font-weight': weight || '400',
		fill: color || 'currentColor'
	});
	n.textContent = text == null ? '' : String(text);
	if (inside) {
		n.setAttribute('stroke', 'var(--background-color-high, #fff)');
		n.setAttribute('stroke-width', '4');
		n.setAttribute('paint-order', 'stroke');
	}
	return n;
}

function comboLinePath(values, max, box, pointCount) {
	const n = Math.max(2, +(pointCount || 0) || (values ? values.length : 0) || 2);
	const arr = values && values.length ? values : [];
	const pts = [];
	for (let i = 0; i < n; i++) {
		const v = i < arr.length ? (Number(arr[i]) || 0) : 0;
		const x = box.x + (i / (n - 1)) * box.w;
		pts.push(x.toFixed(1) + ',' + yOf(v, max, box).toFixed(1));
	}
	return pts.join(' ');
}

function comboTrafficMax(traffic) {
	let maxBps = 1;
	(traffic || []).forEach(l => {
		(l.values || []).forEach(v => {
			const n = Number(v) || 0;
			if (n > maxBps)
				maxBps = n;
		});
	});
	return niceMax(Math.max(maxBps, 50000));
}

function drawComboPanel(wrap, spec) {
	ensureCombo(wrap);
	wrap._comboSpec = spec || { t: [], traffic: [], quality: [] };
	const t = wrap._comboSpec.t || [];
	const traffic = wrap._comboSpec.traffic || [];
	const quality = wrap._comboSpec.quality || [];
	const n = t.length;
	const box = comboPlotBox();
	wrap._comboBox = box;
	const svg = wrap._comboSvg;
	const gGrid = wrap._comboGrid;
	const gPlot = wrap._comboPlot;
	const gAxis = wrap._comboAxis;
	while (gGrid.firstChild)
		gGrid.removeChild(gGrid.firstChild);
	while (gPlot.firstChild)
		gPlot.removeChild(gPlot.firstChild);
	while (gAxis.firstChild)
		gAxis.removeChild(gAxis.firstChild);

	const maxBps = comboTrafficMax(traffic);
	let maxLat = 10;
	let maxLoss = 10;
	quality.forEach(l => {
		const arr = l.values || [];
		if (l.kind === 'pct')
			arr.forEach(v => { if (v > maxLoss) maxLoss = v; });
		else
			arr.forEach(v => { if (v > maxLat) maxLat = v; });
	});
	maxLat = niceMax(Math.max(10, maxLat));
	maxLoss = niceMax(Math.max(10, Math.min(100, maxLoss)));
	const xLossLab = 8;
	const xLatLab = 58;
	const xLossAxis = 104;
	const xLatAxis = 112;

	gGrid.appendChild(svgEl('rect', {
		x: String(box.x), y: String(box.y),
		width: String(box.w), height: String(box.h),
		fill: 'rgba(127,127,127,.06)', rx: '4'
	}));

	gAxis.appendChild(svgEl('line', {
		x1: String(box.x + box.w), x2: String(box.x + box.w),
		y1: String(box.y), y2: String(box.y + box.h),
		stroke: '#2563eb', 'stroke-width': '1.5', opacity: '0.65'
	}));
	gAxis.appendChild(svgEl('line', {
		x1: String(xLatAxis), x2: String(xLatAxis),
		y1: String(box.y), y2: String(box.y + box.h),
		stroke: COL_LAT, 'stroke-width': '1.5', opacity: '0.65'
	}));
	gAxis.appendChild(svgEl('line', {
		x1: String(xLossAxis), x2: String(xLossAxis),
		y1: String(box.y), y2: String(box.y + box.h),
		stroke: '#dc2626', 'stroke-width': '1.5', opacity: '0.65'
	}));

	for (let k = 0; k <= 4; k++) {
		const frac = k / 4;
		const y = box.y + box.h * (1 - frac);
		gGrid.appendChild(svgEl('line', {
			x1: String(box.x), x2: String(box.x + box.w),
			y1: y.toFixed(1), y2: y.toFixed(1),
			stroke: 'rgba(127,127,127,.22)', 'stroke-width': '1'
		}));
		if (frac < 1)
			gAxis.appendChild(comboAxisText(box.x + box.w + 6, y + 4, fmtBit(maxBps * frac), 'start', '#1d4ed8', '600'));
		if (frac < 1) {
			gAxis.appendChild(comboAxisText(xLatLab, y + 4, fmtMs(maxLat * frac), 'start', COL_LAT, '600', true));
			gAxis.appendChild(comboAxisText(xLossLab, y + 4, (maxLoss * frac).toFixed(0) + '%', 'start', '#dc2626', '600', true));
		}
	}

	const span = n >= 2 ? (t[n - 1] - t[0]) : 0;
	const tickN = 6;
	for (let k = 0; k < tickN; k++) {
		const frac = tickN === 1 ? 0 : k / (tickN - 1);
		const i = n <= 1 ? 0 : Math.round(frac * (n - 1));
		const x = n <= 1 ? box.x : box.x + (i / Math.max(1, n - 1)) * box.w;
		const lab = svgEl('text', {
			x: x.toFixed(1),
			y: String(COMBO_H - 4),
			'text-anchor': k === 0 ? 'start' : (k === tickN - 1 ? 'end' : 'middle'),
			'font-size': '10',
			fill: 'currentColor',
			opacity: '.72'
		});
		lab.textContent = n ? (span >= 12 * 3600 ? fmtWhenLong(t[i]) : fmtWhen(t[i])) : '';
		gAxis.appendChild(lab);
	}

	if (n >= 2) {
		traffic.forEach(l => {
			const pts = comboLinePath(l.values, maxBps, box, n);
			const isTotal = (l.label || '').indexOf('总') >= 0;
			const isUp = (l.label || '').indexOf('上行') >= 0;
			gPlot.appendChild(svgEl('polyline', {
				fill: 'none',
				stroke: l.color || '#2563eb',
				'stroke-width': String(l.width || (isTotal ? 1.6 : 1.15)),
				'stroke-dasharray': l.dash || '',
				'stroke-linecap': 'round',
				'stroke-linejoin': 'round',
				opacity: isUp ? '0.88' : '1',
				points: pts
			}));
		});
		quality.forEach(l => {
			const max = l.kind === 'pct' ? maxLoss : maxLat;
			gPlot.appendChild(svgEl('polyline', {
				fill: 'none',
				stroke: l.color || COL_LAT,
				'stroke-width': String(l.kind === 'pct' ? '0.95' : '1.05'),
				'stroke-dasharray': l.dash || (l.kind === 'pct' ? '4 3' : '2 2'),
				'stroke-linecap': 'round',
				opacity: l.kind === 'pct' ? '0.88' : '0.78',
				points: comboLinePath(l.values, max, box, n)
			}));
		});
	}

	const hit = wrap.querySelector('.ratecombo-hit');
	if (hit) {
		hit.setAttribute('x', String(box.x));
		hit.setAttribute('y', String(box.y));
		hit.setAttribute('width', String(box.w));
		hit.setAttribute('height', String(box.h));
	}
	const cursor = wrap.querySelector('.ratecombo-cursor');
	if (cursor) {
		cursor.setAttribute('y1', String(box.y));
		cursor.setAttribute('y2', String(box.y + box.h));
	}
}

function bindComboHover(wrap) {
	const tip = wrap.querySelector('.ratecombo-tip');
	const cursor = wrap.querySelector('.ratecombo-cursor');
	const svg = wrap._comboSvg;
	const hide = function() {
		tip.style.display = 'none';
		cursor.setAttribute('opacity', '0');
	};
	const hit = wrap.querySelector('.ratecombo-hit');
	if (!hit)
		return;
	hit.addEventListener('mouseleave', hide);
	hit.addEventListener('mousemove', function(ev) {
		const spec = wrap._comboSpec;
		const box = wrap._comboBox || comboPlotBox();
		if (!spec || !spec.t || !spec.t.length)
			return;
		const rec = svg.getBoundingClientRect();
		if (rec.width <= 0)
			return;
		const sx = (ev.clientX - rec.left) * (COMBO_W / rec.width);
		const n = spec.t.length;
		let i = Math.round(((sx - box.x) / box.w) * (n - 1));
		if (i < 0)
			i = 0;
		if (i > n - 1)
			i = n - 1;
		const x = box.x + (i / Math.max(1, n - 1)) * box.w;
		cursor.setAttribute('x1', x.toFixed(1));
		cursor.setAttribute('x2', x.toFixed(1));
		cursor.setAttribute('opacity', '1');
		const span = spec.t[n - 1] - spec.t[0];
		const when = span >= 12 * 3600 ? fmtWhenLong(spec.t[i]) : fmtWhen(spec.t[i]);
		const lines = [when];
		(spec.traffic || []).forEach(l => {
			lines.push(l.label + '  ' + fmtBitFull((l.values || [])[i]));
		});
		(spec.quality || []).forEach(l => {
			const v = (l.values || [])[i];
			if (l.kind === 'pct')
				lines.push(l.label + '  ' + (Number(v) || 0).toFixed(1) + ' %');
			else
				lines.push(l.label + '  ' + fmtMs(v));
		});
		tip.textContent = lines.join('\n');
		tip.style.display = 'block';
		const left = ev.clientX - rec.left + 14;
		const top = ev.clientY - rec.top + 10;
		tip.style.left = Math.min(left, rec.width - 200) + 'px';
		tip.style.top = Math.min(top, rec.height - 100) + 'px';
	});
}

function ensureCombo(wrap) {
	if (wrap._comboReady)
		return wrap;
	wrap.classList.add('ratecombo-wrap');
	const svg = svgEl('svg', {
		viewBox: '0 0 ' + COMBO_W + ' ' + COMBO_H,
		class: 'ratecombo',
		preserveAspectRatio: 'none'
	});
	svg.style.width = '100%';
	svg.style.height = COMBO_H + 'px';
	svg.style.display = 'block';
	svg.style.overflow = 'visible';
	wrap._comboSvg = svg;
	wrap._comboGrid = svgEl('g');
	wrap._comboPlot = svgEl('g');
	wrap._comboAxis = svgEl('g');
	svg.appendChild(wrap._comboGrid);
	svg.appendChild(wrap._comboPlot);
	svg.appendChild(wrap._comboAxis);
	svg.appendChild(svgEl('line', {
		class: 'ratecombo-cursor',
		stroke: 'rgba(30,41,59,.55)',
		'stroke-width': '1',
		opacity: '0'
	}));
	svg.appendChild(svgEl('rect', { class: 'ratecombo-hit', fill: 'transparent' }));
	const tip = document.createElement('div');
	tip.className = 'ratecombo-tip';
	wrap.appendChild(svg);
	wrap.appendChild(tip);
	bindComboHover(wrap);
	wrap._comboReady = true;
	return wrap;
}

function drawCombo(wrap, spec) {
	ensureCombo(wrap);
	drawComboPanel(wrap, spec);
	return wrap;
}

return baseclass.extend({
	COLORS: ['#16a34a', '#2563eb', '#ea580c', '#7c3aed', '#db2777', '#0891b2'],
	WAN_TRAFFIC_COLORS: ['#dc2626', '#2563eb', '#ca8a04', '#059669', '#7c3aed', '#db2777'],
	WAN_TOTAL_COLOR: '#0f172a',

	renderInto(el, spec) {
		if (!el)
			return el;
		draw(el, spec);
		return el;
	},

	spark(rxHist, txHist, times) {
		const wrap = document.createElement('div');
		draw(wrap, {
			t: times && times.length ? times : [],
			series: [{
				rx: rxHist && rxHist.length ? rxHist : [0, 0],
				tx: txHist && txHist.length ? txHist : [0, 0],
				color: '#16a34a',
				colorTx: '#2563eb'
			}]
		});
		return wrap;
	},

	combo(series, times) {
		const wrap = document.createElement('div');
		draw(wrap, { t: times && times.length ? times : [], series: series || [] });
		return wrap;
	},

	renderCombo(el, spec) {
		if (!el)
			return el;
		drawCombo(el, spec);
		return el;
	}
});
