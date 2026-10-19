// Checks the Mods menu pages without the game: in every .vue file of the folder the tags of the template are balanced and the script parses as a module, and each page calls
// the registry functions it needs.  node tools/modsmenu_vue_test.js  (needs acorn)
const fs = require('fs'), path = require('path');
const dir = path.join(__dirname, '..', 'mod', 'ui', 'ui-vue', 'mods', 'slrr_settings');
const need = {
  'ModsMenu.vue': ['call("mods"', 'call("page"', 'call("reset"'],
  'SettingRow.vue': ['call("set"', 'call("press"'],
  'FindSetting.vue': ['call("search"'],
  'QuickSetup.vue': ['call("quickSetup"', 'call("applyPreset"'],
  'RouteHost.vue': [],
};
const files = fs.readdirSync(dir).filter((f) => f.endsWith('.vue'));
for (const name of Object.keys(need)) if (!files.includes(name)) { console.error('missing page ' + name); process.exit(1); }
for (const name of files) {
  const src = fs.readFileSync(path.join(dir, name), 'utf8');
  const tpl = src.slice(src.indexOf('<template>'), src.indexOf('<script setup>')).replace(/=>/g, '= ');
  const stack = [];
  const re = /<(\/?)(template|div|button|label|span|p|h2|h3|h4|small|b|input|ul|li|BngSwitch|BngSlider|SettingRow)\b([^>]*?)(\/?)>/g;
  let m;
  while ((m = re.exec(tpl))) {
    const [, close, tag, , self] = m;
    if (tag === 'input' || self) continue;
    const line = tpl.slice(0, m.index).split('\n').length;
    if (!close) stack.push([tag, line]);
    else if (!stack.length || stack[stack.length - 1][0] !== tag) { console.error(`${name}: </${tag}> at line ${line} does not match ${JSON.stringify(stack[stack.length - 1])}`); process.exit(1); }
    else stack.pop();
  }
  if (stack.length) { console.error(`${name}: unclosed ` + JSON.stringify(stack)); process.exit(1); }
  const script = src.slice(src.indexOf('<script setup>') + 14, src.indexOf('</script>'));
  require('acorn').parse(script, { ecmaVersion: 2022, sourceType: 'module' });
  if (/lua\.extensions\.slrr_/.test(src)) { console.error(`${name}: lua.extensions.slrr_* does not exist in the page bridge (only the game's own signature table is there): use call() from settingsApi.js`); process.exit(1); }
  for (const n of need[name] || []) {
    if (!script.includes(n)) { console.error(`${name} does not call ${n}`); process.exit(1); }
  }
}
// a dropdown pick must reach the registry. BngSmartSelect (more items than its threshold shows a dropdown) takes its model with defineModel: a parent that passes
// :modelValue without listening to update:modelValue gets the model updated locally, and the component's own `change` then sees "no change" and never emits (0.40: a pick
// of the Upscaler, a 7+ item list, did nothing). So every BngSmartSelect in these pages must listen to update:modelValue, and none to @change (both would set twice).
for (const name of files) {
  const src = fs.readFileSync(path.join(dir, name), 'utf8');
  for (const m of src.matchAll(/<BngSmartSelect[^>]*>/g)) {
    if (!/@update:modelValue="/.test(m[0]) || /@change=/.test(m[0])) { console.error(`${name}: a BngSmartSelect must use @update:modelValue (and not @change): ${m[0].slice(0, 120)}`); process.exit(1); }
  }
}
// the entry point registers the route that the in-game check navigates to
const entry = fs.readFileSync(path.join(dir, 'index.js'), 'utf8');
require('acorn').parse(entry, { ecmaVersion: 2022, sourceType: 'module' });
if (!entry.includes('menu.slrrMods') || !/export (async )?function onLoad/.test(entry) || !/export (async )?function onUnload/.test(entry)) { console.error('index.js: route name, onLoad or onUnload missing'); process.exit(1); }
if (!/ModsMenu[^>]*full/.test(fs.readFileSync(path.join(dir, 'RouteHost.vue'), 'utf8')) || !fs.readFileSync(path.join(dir, 'settingsApi.js'), 'utf8').includes("navigate('menu.slrrMods'") || !entry.includes('backTarget: "pause"')) { console.error('the pause card must open the full-screen route (settingsApi openFull, RouteHost full, back to pause)'); process.exit(1); }
console.log('mods menu pages ok (' + files.length + ' files + entry)');
