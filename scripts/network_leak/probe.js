/* No analytics, storage, media capture, or recurring tests. */
(function () {
  'use strict';
  function ip(value) {
    if (typeof value !== 'string') return null;
    if (/^\d+\.\d+\.\d+\.\d+$/.test(value)) {
      const octets = value.split('.').map(Number);
      return octets.every(x => x >= 0 && x <= 255) ? octets.join('.') : null;
    }
    if (!value.includes(':') || !/^[0-9a-f:.]+$/i.test(value)) return null;
    try {
      const normalized = new URL('https://[' + value + ']/').hostname.replace(/[\[\]]/g, '').toLowerCase();
      const mapped = normalized.match(/^::ffff:([0-9a-f]{1,4}):([0-9a-f]{1,4})$/);
      if (mapped) { const a = parseInt(mapped[1],16), b = parseInt(mapped[2],16); return [a >> 8, a & 255, b >> 8, b & 255].join('.'); }
      return normalized;
    }
    catch (_) { return null; }
  }
  function family(value) { return value.includes(':') ? 6 : 4; }
  function isPublic(value) {
    value = ip(value);
    if (!value) return false;
    if (family(value) === 6) {
      // IPv4-mapped and non-global IPv6 are not evidence of a public IPv6 leak.
      return /^[23][0-9a-f]{0,3}:/.test(value) && !value.startsWith('2001:db8:');
    }
    const [a, b, c] = value.split('.').map(Number);
    return !(a === 0 || a === 10 || a === 127 || a >= 224 ||
      (a === 100 && b >= 64 && b <= 127) || (a === 169 && b === 254) ||
      (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) ||
      (a === 192 && b === 0 && (c === 0 || c === 2)) ||
      (a === 198 && (b === 18 || b === 19 || (b === 51 && c === 100))) ||
      (a === 203 && b === 0 && c === 113));
  }
  function isLocal(value) {
    value = ip(value);
    if (!value) return false;
    if (family(value) === 6) return /^(fc|fd)[0-9a-f]{2}:|^fe[89ab][0-9a-f]:/.test(value);
    const [a,b] = value.split('.').map(Number);
    return a === 10 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) ||
      (a === 169 && b === 254) || (a === 100 && b >= 64 && b <= 127);
  }
  function candidate(raw) {
    const parts = String(raw.candidate || '').trim().split(/\s+/);
    const address = raw.address || parts[4] || '';
    if (/\.local\.?$/i.test(address)) return { kind: 'mdns', address: 'mDNS' };
    const normalized = ip(address);
    if (!normalized) return null;
    const marker = parts.indexOf('typ');
    const type = raw.type || (marker >= 0 ? parts[marker + 1] : '');
    if (!['host','srflx','prflx','relay'].includes(type)) return null;
    // A relay's IP does not identify the client. Its related address, if exposed,
    // is still inspected separately below.
    if (type === 'relay') return { kind: 'relay', address: normalized };
    if (isPublic(normalized)) return {kind:'public',address:normalized};
    return isLocal(normalized) ? {kind:'local',address:normalized} : null;
  }
  function candidateAddresses(raw) {
    const first = candidate(raw);
    const values = first ? [first] : [];
    const parts = String(raw.candidate || '').trim().split(/\s+/);
    const index = parts.indexOf('raddr');
    const related = ip(raw.relatedAddress || (index >= 0 ? parts[index + 1] : ''));
    const kind = related && (isPublic(related) ? 'public' : isLocal(related) ? 'local' : null);
    if (kind && !values.some(x => x.address === related && x.kind === kind)) values.push({kind,address:related});
    return values;
  }
  function rtcAssessment(httpIP, candidates, complete, rows = [], ipv4Only = false) {
    const baseline = ip(httpIP);
    const exposed = [...new Set(candidates.filter(x => x.kind === 'public').map(x => ip(x.address)).filter(x => x && isPublic(x)))];
    const local = candidates.some(x => x.kind === 'local');
    const observed = rows.filter(x => ['exit', 'ipv6'].includes(x.category) && x.state === 'observed')
      .map(x => ip(x.ip)).filter(Boolean);
    if (ipv4Only && exposed.some(x => family(x) === 6)) return { state: 'risk', reason: 'unexpectedIPv6' };
    if (!baseline || !isPublic(baseline)) return { state: 'incomplete', reason: 'missingBaseline' };
    let uncertain = false;
    for (const address of exposed) {
      if (family(address) === family(baseline)) {
        if (address !== baseline) {
          if (observed.includes(address)) uncertain = true;
          else return { state: 'risk', reason: 'differentPublicIP' };
        }
      } else {
        const peers = observed.filter(x => family(x) === family(address));
        if (!peers.length) uncertain = true;
        else if (!peers.includes(address)) return { state: 'risk', reason: 'differentPublicIP' };
      }
    }
    if (local) return { state: 'review', reason: 'localAddressExposed' };
    if (!exposed.length) return { state: 'incomplete', reason: 'noPublicSample' };
    if (!complete) return { state: 'incomplete', reason: 'gatheringIncomplete' };
    if (uncertain) return { state: 'review', reason: 'unconfirmedRoute' };
    return { state: 'match', reason: 'samePublicExit' };
  }
  function rtcVerdict(httpIP, candidates, complete, rows = [], ipv4Only = false) {
    return rtcAssessment(httpIP, candidates, complete, rows, ipv4Only).state;
  }
  function dnsVerdict(resolvers, expected, complete = true) {
    if (!resolvers.length) return 'incomplete';
    const tokens = expected.split(/[\s,;，；]+/).filter(Boolean);
    if (!tokens.length) return 'review';
    const allowed = tokens.map(ip);
    if (allowed.some(x => !x)) return 'invalid';
    if (!resolvers.every(x => allowed.includes(ip(x)))) return 'risk';
    return complete ? 'match' : 'incomplete';
  }
  function dnsAssessment(resolvers, expected, complete = true, baseline, locations = [], rows = []) {
    const sources = [...new Set(resolvers.map(ip).filter(Boolean))];
    if (!sources.length) return {state:'incomplete',reason:'noDNSResult'};
    if (expected.trim()) {
      const state = dnsVerdict(sources, expected, complete);
      return {state:state === 'incomplete' ? 'partial' : state,
        reason:state === 'match' ? 'expectedDNS' : state === 'risk' ? 'unexpectedDNS' : state === 'invalid' ? 'invalidDNS' : 'partialExpectedDNS'};
    }
    if (ip(baseline) && sources.every(address => address === ip(baseline))) {
      return complete ? {state:'match',reason:'sameDNSExit'} : {state:'partial',reason:'partialDNSCheck'};
    }
    const norm = value => typeof value === 'string' ? value.normalize('NFKD').replace(/[\u0300-\u036f]/g,'').trim().toLowerCase().replace(/\s+/g,' ') : '';
    const country = value => /^[A-Za-z]{2}$/.test(value || '') ? value.toUpperCase() : '';
    const baselineRows = rows.filter(row => ip(row.ip) === ip(baseline) && row.state === 'observed' && ['geo','exit'].includes(row.category) && country(row.country));
    if (new Set(baselineRows.map(row => country(row.country))).size > 1) return {state:'review',reason:'DNSBaselineLocationConflict'};
    baselineRows.sort((a,b) => Number(!!b.city)-Number(!!a.city) || Number(!!b.region)-Number(!!a.region));
    const base = baselineRows[0];
    const found = sources.map(address => locations.find(row => ip(row.ip) === address && row.state === 'observed' && country(row.country))).filter(Boolean);
    if (!base || !found.length) return {state:'observed',reason:'dnsLocationUnavailable'};
    if (found.some(row => country(row.country) !== country(base.country))) return {state:'review',reason:'differentDNSLocation'};
    const full = found.length === sources.length;
    const cityComparable = full && norm(base.city) && found.every(row => norm(row.city));
    const regionComparable = full && norm(base.region) && found.every(row => norm(row.region));
    if (cityComparable && found.some(row => norm(row.city) !== norm(base.city))) return {state:'review',reason:'differentDNSLocation'};
    if (!cityComparable && regionComparable && found.some(row => norm(row.region) !== norm(base.region))) return {state:'review',reason:'differentDNSLocation'};
    if (!full) return {state:'partial',reason:'partialDNSLocation'};
    if (!complete) return {state:'partial',reason:'partialDNSLocationCheck'};
    return {state:'observed',reason:cityComparable ? 'sameDNSCity' : regionComparable ? 'sameDNSRegion' : 'sameDNSCountry'};
  }
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { ip, isPublic, isLocal, candidate, candidateAddresses, rtcAssessment, rtcVerdict, dnsVerdict, dnsAssessment };
    return;
  }

  const zh = (new URL(location.href).searchParams.get('lang') || navigator.language).startsWith('zh');
  const T = (en, cn) => zh ? cn : en;
  const $ = id => document.getElementById(id);
  const root = '/tokenclock/network-check';
  const embedded = new URL(location.href).searchParams.get('embedded') === '1';
  const labels = {
    title: T('Network Toolbox', '网络工具箱'),
    subtitle: T('Check whether your connection exposes unexpected IP or DNS information.', '检查当前连接是否存在 IP 或 DNS 泄漏'),
    scope: embedded ? T('This app connection', '当前应用的连接') : T('This browser', '当前浏览器环境'),
    start: T('Start check', '开始检测'), stop: T('Stop', '停止'),
    browser: T('Check in browser ↗', '在浏览器中检测 ↗'),
    exitTitle: T('Web exit IP', '网页出口'),
    exitHint: T('The address seen by the HTTPS server.', 'HTTPS 服务端实际看到的公网地址'),
    dnsTitle: T('DNS leak check', 'DNS 泄漏检测'),
    dnsHint: T('Observed from fresh, unique domain queries.', '通过全新随机域名查询实际观测'),
    rtcTitle: T('WebRTC leak check', 'WebRTC 泄漏检测'),
    rtcHint: T('ICE / STUN candidates; no audio or video.', 'ICE / STUN 候选地址，不传输音视频'),
    expectedTitle: T('Expected DNS resolvers · optional', '预期 DNS 解析器 · 可选'),
    expectedHint: T('Optional: copy allowed query-source IPs from the results, separated by commas. Location comparison is automatic.', '可选：从结果复制允许的 DNS 查询来源 IP，以逗号分隔；地区对照会自动完成。'),
    note: T('Different exits or IP databases can disagree without proving a leak. No IPv6 response does not prove it is disabled. Embedded results do not represent other browsers.', '不同出口或 IP 库可能存在差异，不能仅据此确认泄漏。IPv6 无响应也不能证明已禁用。内嵌结果不代表其他浏览器。'),
    privacy: T('Runs on click · no media permissions · observations expire within 135 seconds', '点击才检测 · 无需音视频权限 · 服务端观测记录至多保留 135 秒'),
    idle: T('Ready when you are', '等待开始检测'),
    idleHint: T('No probes are running.', '当前没有进行网络探测。')
  };
  for (const [key, value] of Object.entries(labels)) if ($(key)) $(key).textContent = value;
  document.documentElement.lang = zh ? 'zh-CN' : 'en';
  document.title = labels.title + ' · OmniClock';
  $('expected').placeholder = T('Query-source IPs from the results', '填写结果中的 DNS 查询来源 IP');
  $('browser').hidden = !embedded;

  const words = {
    idle: T('Not checked', '尚未检测'), running: T('Checking', '检测中'), partial:T('Partly confirmed','部分确认'),
    observed: T('Observed', '已观测'), match: T('Matches', '与预期一致'),
    review: T('Review', '需要核对'), risk: T('Unexpected address', '发现预期外地址'),
    incomplete: T('Inconclusive', '未能完成'), invalid: T('Invalid expected IP', '预期 IP 格式有误')
  };
  let active = null, last = null;
  function badge(id, value, reason = '') {
    const leak = id === 'dnsBadge' || id === 'rtcBadge';
    $(id).textContent = leak ? ({ match: T('No leak found', '未发现泄漏'), risk: T('Possible leak', '可能泄漏'), review: T('Cannot determine', '暂无法判断'), incomplete: T('Cannot determine', '暂无法判断') }[value] || words[value]) : words[value];
    if (reason === 'localAddressExposed') $(id).textContent = T('Local IP exposed', '本地地址暴露');
    $(id).dataset.state = value;
    $(id).dataset.reason = reason;
  }
  function summary(id, value) { const element = $(id + 'Summary'); if (element) element.textContent = value; }
  function countryName(code) {
    if (!/^[A-Z]{2}$/.test(code || '')) return '';
    try { return new Intl.DisplayNames([zh ? 'zh-CN' : 'en'], { type: 'region' }).of(code) || code; }
    catch (_) { return code; }
  }
  function addresses(id, items, empty) {
    const box = $(id); box.replaceChildren();
    if (!items.length) { box.textContent = empty; box.className = 'addresses empty'; return; }
    box.className = 'addresses';
    for (const item of items) {
      const line = document.createElement('div'); line.className = 'address';
      const code = document.createElement('code'); code.textContent = item.address;
      const tag = document.createElement('span'); tag.textContent = item.tag || '';
      line.append(code, tag); box.append(line);
    }
  }
  function renderDNS(data) {
    if (!last) return;
    if (data?.rows?.some(row => ['geo','exit'].includes(row.category))) last.diagnosticRows=data.rows;
    const assessment = dnsAssessment(last.resolvers, $('expected').value, last.dnsComplete,
      last.ip, last.locations || [], last.diagnosticRows || []);
    const {state,reason} = assessment;
    badge('dnsBadge', state, reason);
    const status = {
      sameDNSCity:T('Location matches','地区一致'),sameDNSRegion:T('Region matches','地区一致'),sameDNSCountry:T('Country matches','国家/地区一致'),
      differentDNSLocation:T('Different locations','地区存在差异'),DNSBaselineLocationConflict:T('Location needs review','出口位置需核对'),
      partialExpectedDNS:T('Returned DNS matches','已返回结果符合预期'),partialDNSLocation:T('Partly located','部分位置已核对'),
      partialDNSLocationCheck:T('Returned locations match','已返回位置一致'),dnsLocationUnavailable:T('DNS detected','已检测到 DNS')
    };
    if (status[reason]) $('dnsBadge').textContent=status[reason];
    const texts = {
      expectedDNS:T('The observed DNS sources match your expected DNS; no leak was found.','DNS 查询来源符合预期，未发现泄漏。'),
      unexpectedDNS:T('Unexpected DNS sources were found; a leak is possible.','发现预期之外的 DNS，可能存在泄漏。'),
      invalidDNS:T('Correct the expected DNS addresses to finish the comparison.','预期 DNS 格式有误，请修正后再判断。'),
      partialExpectedDNS:T('All returned DNS sources match; some queries did not finish.','已返回的 DNS 均符合预期，另有查询未完成。'),
      sameDNSExit:T('DNS sources match the web exit; no different exit was found.','DNS 查询来源与网页出口一致，未发现不同出口。'),
      sameDNSCity:T('All DNS locations match the web exit city; no location anomaly was found.','DNS 均与当前出口位于同一城市，未发现地区异常。'),
      sameDNSRegion:T('All DNS locations match the web exit region; no location anomaly was found.','DNS 均与当前出口位于同一地区，未发现地区异常。'),
      sameDNSCountry:T('All DNS countries match the web exit; city details are limited.','DNS 所在国家/地区与当前出口一致，部分城市信息未提供。'),
      differentDNSLocation:T('Some DNS locations differ from the web exit; review the expected routing.','部分 DNS 位置与当前出口不同，请核对是否符合你的分流设置。'),
      DNSBaselineLocationConflict:T('Location sources disagree about the web exit; DNS comparison needs review.','不同来源对出口位置的判断不一致，DNS 地区对照需要核对。'),
      partialDNSLocation:T('Located DNS sources match the exit country; some locations are unavailable.','已定位的 DNS 与出口国家/地区一致，部分 DNS 位置尚未取得。'),
      partialDNSLocationCheck:T('Returned DNS locations match the exit; some queries did not finish.','已返回的 DNS 位置与出口一致，另有查询未完成。'),
      dnsLocationUnavailable:T('DNS sources were detected; location comparison is not available yet.','已检测到 DNS 查询来源，暂未取得可对照的位置。'),
      partialDNSCheck:T('Returned DNS matches the exit; some queries did not finish.','已返回的 DNS 与出口一致，另有查询未完成。'),
      noDNSResult:T('No DNS result was received; a leak cannot be determined.','未取得 DNS 结果，暂无法判断是否泄漏。')
    };
    summary('dns',texts[reason]);
    const locations = last.locations || [];
    addresses('dnsAddresses', last.resolvers.map(address => {
      const row = locations.find(x => ip(x.ip) === address);
      const place = row ? [row.city, countryName(row.country)].filter(Boolean).join(', ') : '';
      return { address, tag: place || T('Location unavailable', '位置未知') };
    }), T('No DNS sources returned.', '没有取得 DNS 查询来源。'));
    window.TokenClockDiagnostics?.summarize();
  }
  function renderRTC(data) {
    if (!last) return;
    const assessment = rtcAssessment(last.ip, last.rtc.found, last.rtc.complete, data?.rows || [], $('ipv4Only')?.checked || false);
    const texts = {
      samePublicExit: T('WebRTC uses the same public exit as web traffic.', 'WebRTC 公网出口与网页一致，未发现泄漏。'),
      differentPublicIP: T('WebRTC exposed a different public IP; a leak is possible.', 'WebRTC 暴露了不同的公网 IP，可能泄漏。'),
      localAddressExposed: T('WebRTC exposed a local network address.', 'WebRTC 暴露了本地网络地址。'),
      unexpectedIPv6: T('WebRTC exposed IPv6 although IPv4-only was expected.', '预期只使用 IPv4，但 WebRTC 暴露了 IPv6 地址。'),
      missingBaseline: T('The web exit is unavailable; a leak cannot be determined.', '网页出口未取得，暂无法判断是否泄漏。'),
      noPublicSample: T('No comparable public IP was returned; the result is inconclusive.', '未返回可比较的公网 IP，暂无法判断是否泄漏。'),
      gatheringIncomplete: T('The WebRTC check was incomplete; a leak cannot be ruled out.', 'WebRTC 检测未完成，暂无法判断是否泄漏。'),
      unconfirmedRoute: T('Some WebRTC addresses could not be matched to the web exit.', '部分 WebRTC 地址无法与网页出口核对，暂无法判断。')
    };
    badge('rtcBadge', assessment.state, assessment.reason);
    summary('rtc', texts[assessment.reason]);
  }
  function stop() {
    const run = active;
    if (!run) return;
    active = null;
    clearTimeout(run.deadline);
    run.controller.abort();
    for (const cancel of [...run.cancellations]) cancel();
    if (run.pc) { run.pc.onicecandidate = null; run.pc.close(); }
    $('start').disabled = false; $('stop').hidden = true;
    window.TokenClockDiagnostics?.stopped();
    $('idle').textContent = T('Stopped', '已停止');
    $('idleHint').textContent = T('No probes are running. Partial results are not a safety verdict.', '探测已停止，部分结果不能作为安全结论。');
    for (const key of ['exitBadge', 'dnsBadge', 'rtcBadge']) if ($(key).dataset.state === 'running') badge(key, 'incomplete');
  }
  function wait(run, ms) {
    return new Promise(resolve => {
      let timer;
      const done = () => { clearTimeout(timer); run.cancellations.delete(done); resolve(); };
      run.cancellations.add(done); timer = setTimeout(done, ms);
    });
  }
  async function json(run, path, options = {}) {
    const response = await fetch(root + path, { ...options, credentials: 'omit', cache: 'no-store', signal: run.controller.signal });
    if (!response.ok) throw new Error('service');
    return response.json();
  }
  async function gather(run, server) {
    const found = [];
    let complete = false;
    if (typeof RTCPeerConnection !== 'function') return { found, complete };
    try {
      const pc = new RTCPeerConnection({ iceServers: [{ urls: server }], iceCandidatePoolSize: 0 });
      run.pc = pc;
      let finish;
      const done = new Promise(resolve => { finish = resolve; });
      pc.onicecandidate = event => {
        if (!event.candidate) { complete = true; finish(); return; }
        for (const item of candidateAddresses(event.candidate)) {
          if (!found.some(x => x.address === item.address && x.kind === item.kind)) found.push(item);
        }
      };
      pc.createDataChannel('probe');
      await pc.setLocalDescription(await pc.createOffer());
      await Promise.race([done, wait(run, 6500)]);
      pc.onicecandidate = null; pc.close(); run.pc = null;
    } catch (_) { /* Report no candidates as inconclusive, never as leak-free. */ }
    return { found, complete };
  }
  async function dns(run, session) {
    // The authoritative service intentionally replies NXDOMAIN after observing
    // these names. No HTTPS connection, media, or large payload is needed.
    await Promise.all(session.hosts.map(async host => {
      const controller = new AbortController();
      const abort = () => controller.abort();
      run.controller.signal.addEventListener('abort', abort, { once: true });
      const timer = setTimeout(abort, 2200);
      try { await fetch('https://' + host + '/probe', { mode: 'no-cors', credentials: 'omit', cache: 'no-store', signal: controller.signal }); }
      catch (_) { /* NXDOMAIN is expected. The result comes from authority logs. */ }
      finally { clearTimeout(timer); run.controller.signal.removeEventListener('abort', abort); }
    }));
    let result = { resolvers: [], probesObserved: 0 };
    for (let i = 0; i < 7 && active === run; i++) {
      result = await json(run, '/result/' + session.token);
      if (result.probesObserved >= 3) break;
      await wait(run, 700);
    }
    return result;
  }
  async function start() {
    if (active) return;
    const run = { startedAt: Date.now(), id: crypto.randomUUID(), controller: new AbortController(), pc: null, cancellations: new Set() };
    active = run; last = null;
    run.deadline = setTimeout(() => { if (active === run) stop(); }, 25000);
    if($('overallSummary')) $('overallSummary').textContent=T('Checking; waiting for evidence…','检测中，等待观测证据…');
    window.TokenClockDiagnostics?.reset();
    $('start').disabled = true; $('stop').hidden = false;
    $('idle').textContent = T('Checking this connection', '正在检查当前连接');
    $('idleHint').textContent = T('A few small DNS and STUN probes.', '正在发送少量 DNS 和 STUN 探测请求。');
    for (const key of ['exitBadge', 'dnsBadge', 'rtcBadge']) badge(key, 'running');
    for (const key of ['exitAddresses', 'dnsAddresses', 'rtcAddresses']) addresses(key, [], '…');
    for (const id of ['exit', 'dns', 'rtc']) summary(id, T('Checking…', '正在检测…'));
    try {
      const session = await json(run, '/session', { method: 'POST' });
      if (active !== run) return;
      if (!ip(session.ip) || !/^[a-f0-9]{32}$/.test(session.token) ||
          !Array.isArray(session.hosts) || session.hosts.length !== 3 ||
          !session.hosts.every((h, i) => h === 'p' + i + '.' + session.token + '.probe.tokenclock.ailyre.com') ||
          session.stun !== 'stun:ns.tokenclock.ailyre.com:3478') throw new Error('response');
      addresses('exitAddresses', [{ address: session.ip, tag: 'HTTPS / IPv' + family(session.ip) }], '');
      badge('exitBadge', 'observed');
      summary('exit', T('This is the public IP currently seen by websites.', '这是网站目前看到的公网出口。'));
      const [dnsResult, rtc, diagnostics] = await Promise.all([dns(run, session), gather(run, session.stun),
        window.TokenClockDiagnostics.start(run.id, session.ip, run.controller.signal, session.token)]);
      if (active !== run) return;
      const resolvers = [...new Set(dnsResult.resolvers.map(ip).filter(Boolean))];
      let locations = (diagnostics.rows || []).filter(x => x.category === 'dnsGeo');
      last = { resolvers, rtc, ip: session.ip, locations, diagnosticRows:diagnostics.rows || [], dnsComplete: dnsResult.probesObserved >= 3 };
      renderDNS();
      const tags = { public: T('Public', '公网'), local: T('Local / special', '内网 / 特殊地址'), mdns: T('Local IP hidden', '内网 IP 已隐藏'), relay: T('Relay', '中继') };
      addresses('rtcAddresses', rtc.found.map(x => ({ address: x.address, tag: tags[x.kind] })), T('No address candidates available.', '没有获取到可用候选地址。'));
      renderRTC(diagnostics);
      window.TokenClockDiagnostics.render(diagnostics, session.ip, rtc.found);
      const missingLocations = resolvers.filter(address => !locations.some(row => row.ip === address && row.state === 'observed'));
      if (missingLocations.length) {
        const additional = await window.TokenClockDiagnostics.resolveDNSLocations(missingLocations, run.controller.signal, Math.max(500, Math.min(12000, 24000 - (Date.now() - run.startedAt))));
        locations = [...locations.filter(row => !missingLocations.includes(row.ip)), ...additional];
        if (active !== run) return;
        last.locations = locations;
        renderDNS();
      }
      $('idle').textContent = T('Check finished', '本次检测完成');
      $('idleHint').textContent = T('No probes are running. Results apply to this check only.', '探测已停止，结果仅代表本次检测。');
    } catch (_) {
      if (active === run) {
        $('idle').textContent = T('Check could not finish', '检测未能完成');
        $('idleHint').textContent = T('The service or probes may be blocked. Retry when the connection is available.', '服务或探测请求可能被阻止，请在网络可用时重试。');
        window.TokenClockDiagnostics?.stopped();
        if($('overallSummary')) $('overallSummary').textContent=T('Check incomplete; no safety verdict.','本次检测未完成，不能据此判断安全。');
        for (const key of ['exitBadge', 'dnsBadge', 'rtcBadge']) if ($(key).dataset.state === 'running') badge(key, 'incomplete');
      }
    } finally {
      clearTimeout(run.deadline);
      for (const cancel of [...run.cancellations]) cancel();
      if (run.pc) { run.pc.onicecandidate = null; run.pc.close(); }
      run.controller.abort();
      if (active === run) { active = null; $('start').disabled = false; $('stop').hidden = true; }
    }
  }
  $('start').onclick = start; $('stop').onclick = stop;
  $('expected').oninput = renderDNS;
  $('browser').onclick = () => { location.href = 'tokenclock-network-browser://open'; };
  window.addEventListener('pagehide', stop);
  window.TokenClockLeak = { stop, snapshot:()=>last, normalizeIP: ip, isPublicIP: isPublic, renderRTC, renderDNS, receiveDiagnostics: data => window.TokenClockDiagnostics?.receive(data) };
  for (const key of ['exitBadge', 'dnsBadge', 'rtcBadge']) badge(key, 'idle');
  if (location.hash === '#run') { history.replaceState(null, '', location.pathname + location.search); start(); }
})();
