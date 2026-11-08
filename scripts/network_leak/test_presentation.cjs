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

async function testAllResolverRowsRemainAvailable() {
  const elements=new Map([...html.matchAll(/id="([^"]+)"/g)].map(m=>[m[1],new Element()]));
  const addresses=Array.from({length:18},(_,i)=>'8.8.4.'+(i+1));
  const token='a'.repeat(32);
  let lookedUp=[];
  const window={addEventListener(){},TokenClockDiagnostics:{
    reset(){},summarize(){},render(){},stopped(){},
    async start(){return {rows:[{category:'dnsGeo',ip:addresses[0],country:'US',state:'observed'}]};},
    async resolveDNSLocations(values){lookedUp=values;return values.map(ip=>({ip,country:'US',city:'Example city',state:'observed'}));}
  }};
  const context={window,document:{getElementById:id=>elements.get(id),createElement:tag=>new Element(tag),documentElement:{}},
    location:{href:'https://www.ailyre.com/tokenclock/network-check/?lang=en',hash:''},navigator:{language:'en'},URL,Intl,AbortController,setTimeout,clearTimeout,
    crypto:{randomUUID:()=> 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'},
    async fetch(url){
      const payload=url.endsWith('/session')?{token,ip:'1.1.1.1',hosts:[0,1,2].map(i=>'p'+i+'.'+token+'.probe.tokenclock.ailyre.com'),stun:'stun:ns.tokenclock.ailyre.com:3478'}
        :{resolvers:addresses,probesObserved:3};
      return {ok:true,json:async()=>payload};
    }};
  vm.runInNewContext(fs.readFileSync(__dirname+'/probe.js','utf8'),context);
  await elements.get('start').onclick();
  assert.equal(elements.get('dnsAddresses').children.length,18,'No six-result truncation');
  assert.equal(lookedUp.length,17,'Resolve missing locations after final DNS collection');
  assert.equal(window.TokenClockLeak.snapshot().locations.length,18);
  assert(elements.get('dnsAddresses').children[17].textContent.includes('Example city'));
  console.log('All DNS rows retained; later sources receive location lookups');
}
testAllResolverRowsRemainAvailable().catch(error=>{console.error(error);process.exitCode=1;});
