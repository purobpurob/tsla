/* TSLA Swing Trader - frontend (fase 1)
   Læser data/tsla.json og data/tsla-history.json og tegner dashboardet. */
(function () {
  'use strict';

  const nf2 = new Intl.NumberFormat('da-DK', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const nf1 = new Intl.NumberFormat('da-DK', { minimumFractionDigits: 1, maximumFractionDigits: 1 });
  const nf0 = new Intl.NumberFormat('da-DK', { maximumFractionDigits: 0 });
  const dtf = new Intl.DateTimeFormat('da-DK', { dateStyle: 'medium', timeStyle: 'short' });
  const df = new Intl.DateTimeFormat('da-DK', { dateStyle: 'medium' });

  const $ = (id) => document.getElementById(id);
  const usd = (v) => (v == null ? '-' : '$' + nf2.format(v));
  const pct = (v) => (v == null ? '-' : (v > 0 ? '+' : '') + nf1.format(v) + '%');
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const cssVar = (name) => getComputedStyle(document.documentElement).getPropertyValue(name).trim();

  const TREND_TXT = { positive: 'Positiv', neutral: 'Neutral', negative: 'Negativ', unknown: 'Ukendt' };
  const TREND_CLS = { positive: 'up', negative: 'down' };

  async function getJson(path) {
    // Cache-busting: GitHub Pages cacher filer i op til 10 minutter
    const res = await fetch(path + '?v=' + Date.now(), { cache: 'no-store' });
    if (!res.ok) throw new Error(path + ': HTTP ' + res.status);
    return res.json();
  }

  function renderHeader(d) {
    const q = d.quote;
    $('price').textContent = usd(q.price);
    const ch = $('change');
    ch.textContent = (q.change > 0 ? '+' : '') + nf2.format(q.change) + ' (' + pct(q.changePct) + ')';
    ch.className = 'chg ' + (q.change >= 0 ? 'up' : 'down');

    const gen = new Date(d.generatedAt);
    const bar = df.format(new Date(d.lastBar.date + 'T12:00:00'));
    const state = d.lastBar.complete ? 'afsluttet' : 'intradag, ikke afsluttet';
    $('updated').textContent = 'Opdateret ' + dtf.format(gen) + '. Seneste handelsdag ' + bar + ' (' + state + ').';

    const ageH = (Date.now() - gen.getTime()) / 36e5;
    if (ageH > 72) showWarnings(['Data er mere end 3 døgn gamle. Tjek at opdateringsjobbet på serveren kører.']);
  }

  function renderTrend(d) {
    const t = d.trend;
    const items = [['Kort trend', t.short, '20 EMA'], ['Mellem trend', t.medium, '50 SMA'], ['Lang trend', t.long, '200 SMA']];
    $('trend').innerHTML = items.map(([label, v, basis]) =>
      '<div><div class="t-label">' + label + ' <span class="muted">(' + basis + ')</span></div>' +
      '<div class="t-val ' + (TREND_CLS[v] || '') + '">' + (TREND_TXT[v] || v) + '</div></div>').join('');

    const fmtVal = (s) => {
      if (s.value == null) return '';
      if (s.key === 'rsi') return nf1.format(s.value);
      if (s.key === 'volume') return nf2.format(s.value) + 'x';
      if (s.key === 'volatility') return nf2.format(s.value) + '%';
      if (s.key === 'macd') return nf2.format(s.value);
      return usd(s.value);
    };
    $('signals').innerHTML = d.signals.map((s) =>
      '<li><button class="sig-row" type="button" aria-expanded="false">' +
      '<span class="sig-dot s-' + esc(s.status) + '" title="' + esc(s.status) + '"></span>' +
      '<span class="sig-label">' + esc(s.label) + '</span>' +
      '<span class="sig-reason">' + esc(s.reason) + '</span>' +
      '<span class="sig-val">' + esc(fmtVal(s)) + '</span></button>' +
      '<div class="sig-rule">Regel: ' + esc(s.rule) + '</div></li>').join('');

    $('signals').querySelectorAll('.sig-row').forEach((btn) => {
      btn.addEventListener('click', () => {
        const li = btn.parentElement;
        li.classList.toggle('open');
        btn.setAttribute('aria-expanded', li.classList.contains('open'));
      });
    });
  }

  function renderKeyFigures(d) {
    const i = d.indicators;
    const rows = [
      ['20 EMA', usd(i.ema20), pct(i.distEma20) + ' fra kurs'],
      ['50 SMA', usd(i.sma50), pct(i.distSma50) + ' fra kurs'],
      ['200 SMA', usd(i.sma200), pct(i.distSma200) + ' fra kurs'],
      ['RSI 14', nf1.format(i.rsi14), ''],
      ['MACD / signal', nf2.format(i.macd) + ' / ' + nf2.format(i.macdSignal), 'Histogram ' + nf2.format(i.macdHist)],
      ['ATR 14', usd(i.atr14), nf2.format(i.atrPct) + '% af kurs'],
      ['Volumen i dag', nf0.format(d.lastBar.volume), nf2.format(i.volumeRatio) + 'x 20d gns.'],
      ['Gns. volumen 20d', nf0.format(i.avgVolume20), 'Forrige 20 dage'],
      ['20d high / low', usd(i.high20) + ' / ' + usd(i.low20), ''],
      ['52u high', usd(i.high52w), pct(i.distHigh52w) + ' fra kurs'],
      ['52u low', usd(i.low52w), pct(i.distLow52w) + ' fra kurs'],
      ['ATR percentil 1 år', nf0.format(i.atrPctRank), '0 = laveste, 100 = højeste'],
    ];
    $('keyfigures').innerHTML = rows.map(([k, v, note]) =>
      '<div><div class="k">' + esc(k) + '</div><div class="v">' + esc(v) + '</div>' +
      (note ? '<div class="k">' + esc(note) + '</div>' : '') + '</div>').join('');
  }

  function showWarnings(list) {
    if (!list || !list.length) return;
    const box = $('warnings');
    box.hidden = false;
    box.innerHTML += list.map((w) => '<div>' + esc(w) + '</div>').join('');
  }

  // ---------- Grafer ----------
  function renderCharts(hist) {
    const LC = window.LightweightCharts;
    if (!LC) throw new Error('Graf-biblioteket kunne ikke indlæses');

    const col = hist.columns;
    const idx = Object.fromEntries(col.map((c, i) => [c, i]));
    const rows = hist.rows;
    const n = rows.length;

    const text = cssVar('--muted'), border = cssVar('--border'), surface = cssVar('--surface');
    const green = cssVar('--green'), red = cssVar('--red');
    const base = {
      autoSize: true,
      layout: { background: { type: 'solid', color: surface }, textColor: text, attributionLogo: true },
      grid: { vertLines: { color: border }, horzLines: { color: border } },
      rightPriceScale: { borderColor: border, minimumWidth: 70 },
      timeScale: { borderColor: border },
      crosshair: { mode: 0 },
      localization: { locale: 'da-DK' },
    };

    // Linjeserie med whitespace for manglende værdier, så alle grafer har samme antal punkter
    const line = (key) => rows.map((r) => (r[idx[key]] == null ? { time: r[0] } : { time: r[0], value: r[idx[key]] }));

    const main = LC.createChart($('chart-price'), base);
    main.addCandlestickSeries({ upColor: green, downColor: red, wickUpColor: green, wickDownColor: red, borderVisible: false })
      .setData(rows.map((r) => ({ time: r[0], open: r[idx.open], high: r[idx.high], low: r[idx.low], close: r[idx.close] })));
    const lineOpts = (c) => ({ color: c, lineWidth: 1.5, priceLineVisible: false, lastValueVisible: false, crosshairMarkerVisible: false });
    main.addLineSeries(lineOpts(cssVar('--ema20'))).setData(line('ema20'));
    main.addLineSeries(lineOpts(cssVar('--sma50'))).setData(line('sma50'));
    main.addLineSeries(lineOpts(cssVar('--sma200'))).setData(line('sma200'));
    const vol = main.addHistogramSeries({ priceFormat: { type: 'volume' }, priceScaleId: 'vol', lastValueVisible: false, priceLineVisible: false });
    vol.priceScale().applyOptions({ scaleMargins: { top: 0.82, bottom: 0 } });
    vol.setData(rows.map((r, i) => ({
      time: r[0], value: r[idx.volume],
      color: (i > 0 && r[idx.close] < rows[i - 1][idx.close] ? red : green) + '66',
    })));

    const sub = Object.assign({}, base, { layout: Object.assign({}, base.layout, { attributionLogo: false }) });
    const rsiChart = LC.createChart($('chart-rsi'), sub);
    const rsi = rsiChart.addLineSeries({ color: cssVar('--accent'), lineWidth: 1.5, priceLineVisible: false });
    rsi.setData(line('rsi14'));
    [70, 50, 30].forEach((p) => rsi.createPriceLine({ price: p, color: border, lineWidth: 1, lineStyle: 2, axisLabelVisible: false }));

    const macdChart = LC.createChart($('chart-macd'), sub);
    macdChart.addHistogramSeries({ priceLineVisible: false, lastValueVisible: false })
      .setData(rows.map((r) => (r[idx.macdHist] == null ? { time: r[0] }
        : { time: r[0], value: r[idx.macdHist], color: (r[idx.macdHist] >= 0 ? green : red) + '99' })));
    macdChart.addLineSeries({ color: cssVar('--accent'), lineWidth: 1.5, priceLineVisible: false }).setData(line('macd'));
    macdChart.addLineSeries({ color: cssVar('--ema20'), lineWidth: 1, priceLineVisible: false }).setData(line('macdSignal'));

    // Synkroniser tidsakser
    const charts = [main, rsiChart, macdChart];
    let syncing = false;
    charts.forEach((c) => c.timeScale().subscribeVisibleLogicalRangeChange((range) => {
      if (syncing || !range) return;
      syncing = true;
      charts.forEach((o) => { if (o !== c) o.timeScale().setVisibleLogicalRange(range); });
      syncing = false;
    }));

    const setRange = (days) => main.timeScale().setVisibleLogicalRange({ from: Math.max(0, n - days), to: n - 1 + 3 });
    $('ranges').querySelectorAll('button').forEach((b) => b.addEventListener('click', () => {
      $('ranges').querySelectorAll('button').forEach((x) => x.classList.toggle('active', x === b));
      setRange(Number(b.dataset.days));
    }));
    setRange(Number($('ranges').querySelector('.active').dataset.days));
  }

  async function main() {
    try {
      const [d, hist] = await Promise.all([getJson('data/tsla.json'), getJson('data/tsla-history.json')]);
      renderHeader(d);
      renderTrend(d);
      renderKeyFigures(d);
      showWarnings(d.dataWarnings);
      $('source').textContent = 'Datakilde: ' + d.source + '. Historik: ' + d.history.bars + ' handelsdage fra ' + d.history.firstDate + '.';
      renderCharts(hist);
    } catch (e) {
      const box = $('error');
      box.hidden = false;
      box.textContent = 'Kunne ikke indlæse data: ' + e.message;
      console.error(e);
    }
  }

  main();
})();
