// every {{t('key')}} of the garage template sits in element text, never inside a tag (an attribute or an expression)
const fs = require('fs'), { JSDOM } = require('jsdom');
const app = fs.readFileSync(require('path').join(__dirname, '..', 'mod/ui/modules/apps/slrrGarage/app.js'), 'utf8');
const a = app.indexOf('var TEMPLATE = ['), b = app.indexOf("].join('\\n');", a);
const html = eval(app.slice(a + 'var TEMPLATE = '.length, b + 1)).join('\n');
const doc = new JSDOM('<body>' + html + '</body>').window.document;
let bad = 0, n = 0;
for (const el of doc.querySelectorAll('*')) for (const at of el.attributes) {
  if (/\{\{\s*t\(/.test(at.value) || /\{\{\s*t\(/.test(at.name)) { bad++; console.log('in a tag:', el.tagName, at.name, at.value.slice(0, 80)); }
}
for (const m of html.matchAll(/\{\{t\(/g)) n++;
// a t() call's text must not have become markup: no text node should hold a stray tag or attribute remainder
for (const w = doc.createTreeWalker(doc.body, 4); w.nextNode();) {
  if (/(ng-[a-z]+|class|style|title)="|<\/?[a-z]/.test(w.currentNode.nodeValue)) { bad++; console.log('markup in text:', w.currentNode.nodeValue.slice(0, 90)); }
}
console.log('template texts', n, 'problems', bad);
process.exit(bad ? 1 : 0);
