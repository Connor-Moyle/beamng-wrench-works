// Tests slrr/garageStrings.lua (the garage's player-facing text) outside the game. Needs fengari:  node tools/strings_test.js
const path = require('path'), fs = require('fs');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const file = path.join(__dirname, '..', 'mod/lua/ge/extensions/slrr/garageStrings.lua').split(path.sep).join('/');
const test = `
local S = dofile(${JSON.stringify(file)})
local function check(name, ok) if not ok then error('FAILED: ' .. name, 0) end end
local n = 0
for k, v in pairs(S.TEXT) do n = n + 1 check('every text is a non-empty string: ' .. k, type(v) == 'string' and v ~= '') end
check('the bar has a title and a description for each of its items', n >= 34 and S.TEXT['bar.photo.title'] == 'Photo' and S.TEXT['bar.photomode.desc'] ~= nil and S.TEXT['tab.drivers'] == 'Drivers')
check('t() gives the text, or the key so a gap shows', S.t('bar.tune.title') == 'Tune' and S.t('nothing.here') == 'nothing.here')
print('strings test passed')
`;
if (lauxlib.luaL_dostring(L, to_luastring(test)) !== lua.LUA_OK) { console.error(to_jsstring(lua.lua_tostring(L, -1))); process.exit(1); }
// every key the garage screen asks for is in the table
const app = fs.readFileSync(path.join(__dirname, '..', 'mod/ui/modules/apps/slrrGarage/app.js'), 'utf8');
const lt = fs.readFileSync(path.join(__dirname, '..', 'mod/lua/ge/extensions/slrr/garageStrings.lua'), 'utf8');
const asked = [...app.matchAll(/\$scope\.t\('([^']+)'/g)].map((m) => m[1]);
const missing = asked.filter((k) => !lt.includes("['" + k + "']"));
if (missing.length) { console.error('asked for but not in garageStrings.lua: ' + missing.join(', ')); process.exit(1); }
console.log('and the screen asks for ' + asked.length + ' keys, all in the table');
// the template's {{t('key')}} texts all have their English text in TEMPLATE_TEXT (shown until the table arrives), equal to the table
const tt = eval('(' + app.match(/var TEMPLATE_TEXT = (\{[\s\S]*?\n  \});/)[1] + ')');
const used = [...new Set([...app.matchAll(/\{\{t\(\\'([^']+)\\'\)\}\}/g)].map((m) => m[1]))];
const table = {};
for (const m of lt.matchAll(/\['([^']+)'\] = '((?:[^'\\]|\\.)*)',/g)) table[m[1]] = m[2].replace(/\\(.)/g, '$1');
const bad = used.filter((k) => tt[k] !== table[k]);
if (bad.length || Object.keys(tt).some((k) => !used.includes(k))) { console.error('TEMPLATE_TEXT differs from the table or has unused keys: ' + bad.join(', ')); process.exit(1); }
console.log('template fallbacks match the table (' + used.length + ' keys)');
