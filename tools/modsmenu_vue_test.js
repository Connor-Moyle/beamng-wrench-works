// Checks the Mods menu page without the game: the tags of the template are balanced and the script parses as a module.  node tools/modsmenu_vue_test.js  (needs acorn)
const fs = require('fs'), path = require('path');
const file = path.join(__dirname, '..', 'mod', 'ui', 'ui-vue', 'mods', 'slrr_settings', 'ModsMenu.vue');
const src = fs.readFileSync(file, 'utf8');
const tpl = src.slice(src.indexOf('<template>'), src.indexOf('<script setup>')).replace(/=>/g, '= ');
const stack = [];
const re = /<(\/?)(template|div|button|label|span|p|h2|h3|h4|small|b|input|BngSwitch|BngSlider)\b([^>]*?)(\/?)>/g;
let m;
while ((m = re.exec(tpl))) {
  const [, close, tag, , self] = m;
  if (tag === 'input' || self) continue;
  const line = tpl.slice(0, m.index).split('\n').length;
  if (!close) stack.push([tag, line]);
  else if (!stack.length || stack[stack.length - 1][0] !== tag) { console.error(`template: </${tag}> at line ${line} does not match ${JSON.stringify(stack[stack.length - 1])}`); process.exit(1); }
  else stack.pop();
}
if (stack.length) { console.error('template: unclosed ' + JSON.stringify(stack)); process.exit(1); }
const script = src.slice(src.indexOf('<script setup>') + 14, src.indexOf('</script>'));
require('acorn').parse(script, { ecmaVersion: 2022, sourceType: 'module' });
for (const need of ['slrr_settings.mods', 'slrr_settings.page', 'slrr_settings.set', 'slrr_settings.reset', 'slrr_settings.press']) {
  if (!script.includes(need)) { console.error('the page does not call ' + need); process.exit(1); }
}
console.log('mods menu page ok');
