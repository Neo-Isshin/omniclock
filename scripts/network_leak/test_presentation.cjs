const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
class Element {
  constructor(tag = 'div') { this.tagName = tag; this.children = []; this.dataset = {}; this.className = ''; this._text = ''; this.disabled = false; this.checked = false; this.value = ''; }
  set textContent(value) { this._text = String(value ?? ''); this.children = []; }
  get textContent() { return this._text + this.children.map(c => c.textContent).join(''); }
  append(...children) { this.children.push(...children); }
  replaceChildren(...children) { this.children = children; this._text = ''; }
  get lastElementChild() { return this.children.at(-1); }
}
const html = fs.readFileSync(__dirname + '/index.html','utf8');
for (const language of ['en','zh-CN']) {
  const elements = new Map([...html.matchAll(/id="([^"]+)"/g)].map(m => [m[1],new Element()]));
  const document = { getElementById:id=>elements.get(id), createElement:tag=>new Element(tag), documentElement:{}, title:'' };
  const window = { TokenClockLeak:{renderRTC(){},isPublicIP:require('./probe.js').isPublic}, addEventListener(){} };
  const context = { window,document,location:{href:'https://www.ailyre.com/tokenclock/network-check/?lang='+language},navigator:{language},URL,Intl,TextDecoder,AbortController,setTimeout,clearTimeout,console };
  vm.runInNewContext(fs.readFileSync(__dirname+'/diagnostics.js','utf8'),context);
  elements.get('dnsBadge').dataset={state:'review',reason:'noExpectedDNS'};
  elements.get('rtcBadge').dataset={state:'match',reason:'samePublicExit'};
  const rows=[
    {id:'ipify',category:'exit',label:'ipify',state:'observed',ip:'1.1.1.1',country:'AU'},
    {id:'geo',category:'geo',label:'Country.is',state:'observed',ip:'1.1.1.1',country:'AU'},
    ...['ChatGPT','Claude','OpenAI API','Anthropic API','xAI API'].map(label=>({category:'ai',label,state:'observed',ip:'1.1.1.1',country:'AU'})),
    {category:'ai',label:'Gemini',host:'gemini.google.com',state:'responded',httpStatus:200},
    {category:'doh',label:'Cloudflare',state:'verified',host:'cloudflare-dns.com'},
    {category:'doh',label:'Google',state:'verified',host:'dns.google'},
    {category:'dohEcho',label:'Cloudflare',state:'observed',ip:'1.1.1.1'}
  ];
  window.TokenClockDiagnostics.render({rows},'1.1.1.1',[]);
  assert.equal(elements.get('aiBadge').dataset.state,'partial');
  assert.equal(elements.get('dohBadge').dataset.state,'match');
  assert.equal(elements.get('ipv6Badge').dataset.state,'notObserved');
  for(const id of ['ai','doh','consistency','ipv6']) assert(elements.get(id+'Summary').textContent.length>0,id);
  const summary=elements.get('overallSummary').textContent;
  assert(summary.includes('DNS') && summary.includes('IPv6'));
  assert(!summary.includes('AI routing: cannot') && !summary.includes('AI 分流：暂无法'));
  assert(!summary.includes('Risk evidence') && !summary.includes('Insufficient evidence'));
  assert.equal(elements.get('aiAddresses').children.length,6);
}
console.log('English/Chinese card conclusions and partial-result presentation passed');
