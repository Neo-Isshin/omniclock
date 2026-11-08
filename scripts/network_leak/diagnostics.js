(function () {
  'use strict';
  function sameFamily(a, b) { return a.includes(':') === b.includes(':'); }
  function publicIP(value) {
    if (typeof module !== 'undefined' && module.exports) return require('./probe.js').isPublic(value);
    return window.TokenClockLeak?.isPublicIP?.(value) === true;
  }
  function exitsVerdict(baseline, rows) {
    const values = rows.filter(x => x.category === 'exit' && x.state === 'observed' && x.ip);
    if (!values.length) return 'incomplete';
    if (values.some(x => sameFamily(x.ip, baseline) && x.ip !== baseline)) return 'review';
    return values.some(x => x.id !== 'ailyre' && sameFamily(x.ip, baseline)) ? 'match' : 'incomplete';
  }
  function locationVerdict(baseline, rows) {
    const values = rows.filter(x => x.ip === baseline && x.country && ['geo', 'exit'].includes(x.category));
    if (new Set(values.map(x => x.country)).size > 1) return 'review';
    // Multiple Cloudflare trace sites share one location database.
    return new Set(values.map(x => x.category === 'exit' ? 'Cloudflare' : x.label)).size >= 2 ? 'match' : 'incomplete';
  }
  function ipv6Verdict(rows, candidates, ipv4Only) {
    const http = [...new Set(rows.filter(x => x.category === 'ipv6' && x.state === 'observed' && x.ip?.includes(':') && publicIP(x.ip)).map(x => x.ip))];
    const rtc = [...new Set(candidates.filter(x => x.kind === 'public' && x.address.includes(':')).map(x => x.address))];
    if (!http.length && !rtc.length) return 'notObserved';
    if (ipv4Only) return 'risk';
    if (http.length && rtc.some(x => !http.includes(x))) return 'risk';
    return http.length && rtc.length ? 'match' : 'review';
  }
  function aiVerdict(baseline, row) {
    if (row.ip && row.state === 'observed') return row.ip === baseline ? 'match' : 'review';
    return 'incomplete';
  }
  function dohAssessment(baseline, rows) {
    const probes = rows.filter(x => x.category === 'doh');
    const verified = probes.filter(x => x.state === 'verified');
    const echoes = rows.filter(x => x.category === 'dohEcho' && x.state === 'observed' && x.ip && publicIP(x.ip));
    const exits = [baseline, ...rows.filter(x => ['exit', 'ipv6'].includes(x.category) && x.state === 'observed').map(x => x.ip)].filter(Boolean);
    if (echoes.some(x => sameFamily(x.ip, baseline) && x.ip !== baseline && !exits.includes(x.ip))) return {state:'risk',reason:'differentDoHExit'};
    if (echoes.some(x => sameFamily(x.ip, baseline) && x.ip !== baseline)) return {state:'review',reason:'differentDoHRoute'};
    if (echoes.some(x => !sameFamily(x.ip, baseline) && exits.some(y => sameFamily(x.ip,y)) && !exits.includes(x.ip))) return {state:'risk',reason:'differentDoHExit'};
    const baseProxy = rows.find(x => x.id === 'ailyre')?.proxy;
    if (baseProxy === true && verified.some(x => x.proxy === false)) return {state:'review',reason:'differentDoHProxy'};
    const matched = echoes.some(x => exits.includes(x.ip));
    if (matched && verified.length >= 2) return {state:'match',reason:'sameDoHExit'};
    if (verified.length) return {state:'partial',reason:matched ? 'partialDoHCheck' : 'noDoHExit'};
    return {state:'incomplete',reason:'noDoHResult'};
  }
  function dohVerdict(baseline, rows) { return dohAssessment(baseline, rows).state; }
  function overall(states) {
    const risk=Object.keys(states).filter(k=>states[k]==='risk');
    const review=Object.keys(states).filter(k=>states[k]==='review');
    const unknown=Object.keys(states).filter(k=>['incomplete','notObserved','partial','invalid'].includes(states[k]));
    return {risk,review,unknown};
  }
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { exitsVerdict, locationVerdict, ipv6Verdict, aiVerdict, dohAssessment, dohVerdict, overall }; return;
  }
  const zh = (new URL(location.href).searchParams.get('lang') || navigator.language).startsWith('zh');
  const T = (en, cn) => zh ? cn : en;
  const $ = id => document.getElementById(id);
  const labels = {
    dohTitle:T('Encrypted DNS (DoH)','加密 DNS（DoH）'),
    dohHint:T('Verified HTTPS DNS queries; readable configuration is a snapshot, not runtime proof.','验证真实 DoH 查询；配置快照不等于当前实际启用状态。'),
    consistencyTitle: T('Exit & location consistency', '出口与落地一致性'),
    consistencyHint: T('Compare observed exits and country data for the same IP.', '核对多个出口，以及同一 IP 的多来源国家/地区信息'),
    ipv6Title: T('IPv6 leak check', 'IPv6 泄漏检测'),
    ipv6Hint: T('IPv6-only HTTPS probe, compared with WebRTC.', '通过 IPv6 专用站点探测，并与 WebRTC 地址对照'),
    aiTitle: T('AI domain routing', 'AI 域名分流自检'),
    aiHint: T('Only a returned client IP establishes an observed exit.', '仅在目标确实返回客户端 IP 时判断出口；HTTP 响应不等于分流成功'),
    ipv4OnlyLabel: T('Expect IPv4-only access', '预期只通过 IPv4 访问'),
    policyHint: T('Enable only if IPv6 should be blocked by your policy.', '仅在你的策略要求阻止 IPv6 时勾选；IPv6 可达本身不等于泄漏。'),
    diagnosticScope: T('App checks use the Mac system proxy/VPN. Browser extensions and account access are outside this check.', '应用内检测使用 Mac 系统代理/VPN；不代表浏览器扩展规则，也不检查账号或模型使用权限。')
  };
  for (const [id, text] of Object.entries(labels)) if ($(id)) $(id).textContent = text;
  const status = {
    idle: T('Not checked', '尚未检测'), running: T('Checking', '检测中'),
    match: T('Consistent', '一致'), review: T('Needs attention', '需要关注'),
    incomplete: T('Cannot determine', '暂无法判断'), risk: T('Possible leak', '可能泄漏'),
    notObserved: T('No IPv6 detected', '未检测到 IPv6'), partial: T('Partly confirmed', '部分确认')
  };
  let previous = null;
  function badge(id, state, text, reason = '') {
    $(id).textContent = text || status[state]; $(id).dataset.state = state; $(id).dataset.reason = reason;
  }
  function summary(id, value) { const node = $(id + 'Summary'); if (node) node.textContent = value; }
  function line(box, title, value, hint) {
    const row = document.createElement('div'); row.className = 'diagnostic-row';
    const name = document.createElement('span'); name.className = 'diagnostic-name'; name.textContent = title;
    const details = document.createElement('div');
    const code = document.createElement('code'); code.textContent = value;
    const tag = document.createElement('small'); tag.textContent = hint || '';
    details.append(code, tag); row.append(name, details); box.append(row);
  }
  function render(data, baseline, candidates) {
    previous = { data, baseline, candidates };
    const rows = Array.isArray(data?.rows) ? data.rows.slice(0, 64) : [];
    const consistency = $('consistencyAddresses'); consistency.replaceChildren();
    const exits = rows.filter(x => x.category === 'exit');
    for (const row of exits) line(consistency, row.label, row.ip || '—', row.country || (row.state === 'unavailable' ? T('Unavailable', '未获取') : ''));
    const geo = rows.filter(x => x.category === 'geo' && x.ip === baseline);
    for (const row of geo) line(consistency, row.label, row.country || '—', [row.region, row.city].filter(Boolean).join(' / '));
    if (!rows.length) line(consistency, '—', T('No result', '没有可用结果'), '');
    const exitState = exitsVerdict(baseline, rows), locState = locationVerdict(baseline, rows);
    const state = [exitState, locState].includes('review') ? 'review' : exitState === 'match' && locState === 'match' ? 'match' : 'incomplete';
    badge('consistencyBadge', state);
    summary('consistency', state === 'match' ? T('Web exits and location look consistent.', '网页出口与地区信息一致。') : state === 'review' ? T('Some exits or locations differ; check your routing.', '不同检测站看到的出口或地区不一致，请检查分流。') : T('Some exit or location information could not be checked.', '部分出口或地区信息尚无法确认。'));
    $('consistencyDetail').textContent = T('Exit: ', '出口：') + status[exitState] + ' · ' + T('Country: ', '地区：') + status[locState];
    const v6 = $('ipv6Addresses'); v6.replaceChildren();
    const ipv6Rows = rows.filter(x => x.category === 'ipv6');
    for (const row of ipv6Rows) line(v6, 'HTTPS IPv6', row.ip || '—', row.ip ? '' : T('Not observed; may be blocked', '未观测到，可能不可达或受阻'));
    for (const candidate of candidates.filter(x => x.kind === 'public' && x.address.includes(':'))) line(v6, 'WebRTC IPv6', candidate.address, '');
    if (!ipv6Rows.length) line(v6, 'HTTPS IPv6', '—', T('No result', '未获取结果'));
    const v6State = ipv6Verdict(rows, candidates, $('ipv4Only').checked);
    badge('ipv6Badge', v6State, ({match:T('No leak found','未发现泄漏'),risk:T('Possible leak','可能泄漏'),review:T('Cannot determine','暂无法判断')})[v6State]);
    summary('ipv6', v6State === 'risk' ? T('Unexpected IPv6 access was found; a leak is possible.', '发现预期之外的 IPv6 出口，可能泄漏。') : v6State === 'match' ? T('The tested IPv6 exits match; no leak was found.', '已核对的 IPv6 出口一致，未发现泄漏。') : v6State === 'notObserved' ? T('No IPv6 exit was detected in this check.', '本次未检测到 IPv6 出口。') : T('IPv6 was detected, but a leak cannot yet be determined.', '已检测到 IPv6，但暂无法判断是否泄漏。'));
    const ai = $('aiAddresses'); ai.replaceChildren();
    const aiRows = rows.filter(x => x.category === 'ai');
    for (const row of aiRows) {
      const verdict = aiVerdict(baseline, row);
      const hint = row.ip ? (row.country || T('Exit confirmed','出口已确认'))
        : row.httpStatus && row.httpStatus < 400 ? T('Connected; exit IP unavailable','可连接，出口尚未确认') : row.httpStatus ? T('Access restricted','访问受限') : T('Could not connect','未能连接');
      line(ai, row.label, row.ip || row.host, hint);
      ai.lastElementChild.dataset.state = verdict;
    }
    if (!aiRows.length) line(ai, T('App check', '应用内检测'), T('Open in TokenClock', '请在 TokenClock 内检测'), T('Browser cross-origin restrictions prevent reliable route checks.', '浏览器跨域限制下无法可靠核对这些域名的出口。'));
    const observedAI = aiRows.filter(x => x.state === 'observed' && x.ip);
    const aiState = observedAI.some(x => aiVerdict(baseline, x) === 'review') ? 'review'
      : aiRows.length && observedAI.length === aiRows.length ? 'match' : observedAI.length ? 'partial' : 'incomplete';
    badge('aiBadge', aiState, aiState === 'review' ? T('Different exits','存在不同出口') : aiState === 'match' ? T('Consistent','出口一致') : aiState === 'partial' ? T('Partly confirmed','部分确认') : T('Cannot determine','暂无法判断'));
    summary('ai', aiState === 'review' ? T('Some AI sites use a different exit; review routing.', '部分 AI 站点使用了不同出口，请检查分流。') : aiState === 'match' ? T('The checked AI sites use the expected exit.', '已核对的 AI 站点出口符合预期。') : observedAI.length ? T(observedAI.length + ' of ' + aiRows.length + ' site exits checked; others did not return an IP.', '已确认 '+observedAI.length+'/'+aiRows.length+' 个站点出口，其余未返回出口 IP。') : T('The AI sites did not provide enough exit information.', 'AI 站点暂未提供足够的出口信息。'));
    const doh=$('dohAddresses');doh.replaceChildren();
    const dohs=rows.filter(x=>['doh','dohEcho'].includes(x.category));
    for(const row of dohs) {
      const hint = row.category === 'doh' ? (row.state === 'verified' ? T('Encrypted DNS works','加密 DNS 可用') : T('No verified reply','未取得有效结果'))
        : row.ip === baseline ? T('Matches web exit','与网页出口一致') : T('Exit needs review','出口需要核对');
      line(doh,row.category === 'dohEcho' ? T('Cloudflare exit','Cloudflare 出口') : row.label,row.ip || row.host || '—',hint);
    }
    if(!dohs.length) line(doh,'DoH',T('Use TokenClock','请使用 TokenClock 内检测'),T('This browser cannot expose its DoH transport or settings.','浏览器页面无法确认其 DoH 传输和配置。'));
    const verified=rows.filter(x=>x.category==='doh'&&x.state==='verified').length;
    const dohResult = dohAssessment(baseline, rows);
    const dohMessages = {
      differentDoHExit:T('Encrypted DNS used a different public exit; a leak is possible.','加密 DNS 使用了不同公网出口，可能泄漏。'),
      differentDoHRoute:T('Encrypted DNS differs from the main web exit; review routing.','加密 DNS 与主要网页出口不同，请核对分流。'),
      differentDoHProxy:T('Encrypted DNS may bypass the expected proxy.','加密 DNS 可能未经过预期代理。'),
      sameDoHExit:T('The checked encrypted DNS exit matches web traffic.','已核对的加密 DNS 出口与网页一致。'),
      partialDoHCheck:T('The checked exit matches; some DNS tests were unavailable.','已核对的出口一致，部分加密 DNS 检测未取得结果。'),
      noDoHExit:T('Encrypted DNS works, but its exit IP could not be confirmed.','加密 DNS 可连接，但出口 IP 尚无法确认。'),
      noDoHResult:T('Encrypted DNS could not be verified in this check.','本次未能确认加密 DNS 的连接与出口。')
    };
    badge('dohBadge',dohResult.state,({match:T('No leak found','未发现泄漏'),risk:T('Possible leak','可能泄漏'),review:T('Needs attention','需要关注'),partial:T('Partly confirmed','部分确认'),incomplete:T('Cannot determine','暂无法判断')})[dohResult.state],dohResult.reason);
    summary('doh',dohMessages[dohResult.reason]);
    window.TokenClockLeak?.renderRTC(data);
    summarize();
  }

  const pending = new Map();
  function nativeHandler() { return window.webkit?.messageHandlers?.networkDiagnostics; }
  function receive(data) {
    if (!data || typeof data.runID !== 'string') return;
    const callback = pending.get(data.runID);
    if (callback) callback(data);
  }
  async function browserRequest(url, signal) {
    const controller = new AbortController(); const abort = () => controller.abort();
    signal.addEventListener('abort', abort, { once: true });
    if (signal.aborted) controller.abort();
    const timer = setTimeout(abort, 4500);
    try {
      const response = await fetch(url, { credentials: 'omit', cache: 'no-store', signal: controller.signal });
      if (!response.ok || Number(response.headers.get('content-length')) > 16384) return null;
      const reader = response.body.getReader(); const parts = []; let size = 0;
      while (true) {
        const chunk = await reader.read(); if (chunk.done) break;
        size += chunk.value.length;
        if (size > 16384) { await reader.cancel(); return null; }
        parts.push(chunk.value);
      }
      const bytes = new Uint8Array(size); let offset = 0;
      for (const part of parts) { bytes.set(part, offset); offset += part.length; }
      return JSON.parse(new TextDecoder().decode(bytes));
    } catch (_) { return null; }
    finally { clearTimeout(timer); signal.removeEventListener('abort', abort); controller.abort(); }
  }
  const resolverLocationCache = new Map();
  async function resolveDNSLocations(resolvers, signal) {
    const clean = window.TokenClockLeak?.normalizeIP;
    const publicIP = window.TokenClockLeak?.isPublicIP;
    const selected = [...new Set(resolvers.map(x => clean?.(x)).filter(x => x && publicIP?.(x)))].slice(0, 6);
    return Promise.all(selected.map(async address => {
      if (resolverLocationCache.has(address)) return resolverLocationCache.get(address);
      const encoded = encodeURIComponent(address);
      const [who, country] = await Promise.all([
        browserRequest('https://ipwho.is/' + encoded + '?fields=ip,success,country_code,region,city', signal),
        browserRequest('https://api.country.is/' + encoded, signal)
      ]);
      const valid = value => value?.success !== false && clean?.(value?.ip) === address && /^[A-Z]{2}$/.test(value.country_code || value.country || '') && !['XX','T1'].includes(value.country_code || value.country);
      const value = valid(who) ? who : valid(country) ? country : null;
      const row = { id:'dns-geo-'+address, category:'dnsGeo', label:'DNS location', host:'', state:value ? 'observed':'unavailable', ip:address };
      if (value) { row.country = value.country_code || value.country; row.region = value.region; row.city = value.city;
        if (resolverLocationCache.size >= 128) resolverLocationCache.delete(resolverLocationCache.keys().next().value);
        resolverLocationCache.set(address,row);
      }
      return row;
    }));
  }
  async function browserCheck(runID, baseline, signal) {
    const [v4, v6] = await Promise.all([
      browserRequest('https://api.ipify.org?format=json', signal),
      browserRequest('https://api6.ipify.org?format=json', signal)
    ]);
    const clean = window.TokenClockLeak?.normalizeIP;
    const ipv4 = clean?.(v4?.ip), ipv6 = clean?.(v6?.ip);
    const rows = [
      {id:'ipify',category:'exit',label:'ipify IPv4',host:'api.ipify.org',state:ipv4 ? 'observed':'unavailable',ip:ipv4},
      {id:'ipv6',category:'ipv6',label:'ipify IPv6',host:'api6.ipify.org',state:ipv6?.includes(':') ? 'observed':'unavailable',ip:ipv6?.includes(':') ? ipv6:null}
    ];
    if (signal.aborted) return {runID,rows:[]};
    const encoded = encodeURIComponent(baseline);
    const [who, country] = await Promise.all([
      browserRequest('https://ipwho.is/' + encoded + '?fields=ip,success,country_code,region,city', signal),
      browserRequest('https://api.country.is/' + encoded, signal)
    ]);
    for (const [source, value] of [['IPWhois', who], ['Country.is', country]]) {
      if (value?.success !== false && clean?.(value?.ip) === baseline) {
        const code = value.country_code || value.country;
        if (/^[A-Z]{2}$/.test(code || '')) rows.push({id:source,category:'geo',label:source,state:'observed',ip:baseline,country:code,region:value.region,city:value.city});
      }
    }
    return {runID,rows};
  }
  function start(runID, baselineIP, signal, dnsToken) {
    const handler = nativeHandler();
    if (!handler) return browserCheck(runID, baselineIP, signal);
    return new Promise(resolve => {
      let timer;
      const finish = result => {
        clearTimeout(timer); pending.delete(runID); signal.removeEventListener('abort', abort); resolve(result);
      };
      const abort = () => { handler.postMessage({action:'cancel',runID}); finish({runID,rows:[]}); };
      pending.set(runID, finish);
      signal.addEventListener('abort', abort, {once:true});
      timer = setTimeout(abort, 18000);
      if (signal.aborted) { abort(); return; }
      handler.postMessage({action:'start',runID,baselineIP,dnsToken});
    });
  }
  function reset() {
    previous = null;
    for (const id of ['consistencyBadge','ipv6Badge','aiBadge','dohBadge']) badge(id,'running');
    for (const id of ['consistencyAddresses','ipv6Addresses','aiAddresses','dohAddresses']) $(id).textContent = '…';
    for (const id of ['consistency','ipv6','ai','doh']) summary(id,T('Checking…','正在检测…'));
    $('consistencyDetail').textContent = '';
  }
  function stopped() {
    if($('overallSummary')) $('overallSummary').textContent=T('Check stopped; partial results are inconclusive.','本次检测已停止，部分结果不能作为安全结论。');
    for (const id of ['consistencyBadge','ipv6Badge','aiBadge','dohBadge']) if ($(id).dataset.state === 'running') badge(id,'incomplete');
  }
  $('ipv4Only').onchange = () => { if (previous) render(previous.data, previous.baseline, previous.candidates); };
  for (const id of ['consistencyBadge','ipv6Badge','aiBadge']) badge(id,'idle');
  function summarize() {
    const names = {dns:'DNS',rtc:'WebRTC',ipv6:'IPv6',doh:'DoH'};
    const states = Object.fromEntries(Object.keys(names).map(id => [id, $(id+'Badge')?.dataset.state || 'idle']));
    const risks = Object.keys(names).filter(id => states[id] === 'risk');
    const local = $('rtcBadge')?.dataset.reason === 'localAddressExposed';
    const uncertain = Object.keys(names).filter(id => ['review','incomplete','partial','notObserved','invalid'].includes(states[id]) && !(id === 'rtc' && local));
    const checked = Object.keys(names).filter(id => states[id] === 'match');
    const out = risks.map(id => names[id] + T(': possible leak', '：可能泄漏'));
    if (local) out.push(T('WebRTC: local address exposed','WebRTC：本地地址已暴露'));
    if (!out.length) out.push(checked.length ? T('No leak found in the checks that could be verified','已核对的项目未发现泄漏') : T('A leak verdict is not yet available','暂无法判断是否存在泄漏'));
    if (uncertain.length) out.push(uncertain.map(id => names[id]).join(T(', ','、')) + T(': cannot determine yet','：暂无法判断'));
    if ($('consistencyBadge')?.dataset.state === 'review') out.push(T('Web exits or locations differ','网页出口或地区不一致'));
    if ($('aiBadge')?.dataset.state === 'review') out.push(T('AI sites use different exits','AI 站点存在不同出口'));
    if ($('overallSummary')) $('overallSummary').textContent = out.join(T('; ','；')) + T('.','。');
  }
  window.TokenClockDiagnostics = {start,receive,render,reset,stopped,summarize,resolveDNSLocations,snapshot:()=>previous};
})();
