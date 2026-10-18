// Runs tools/gfxmenu_test.lua (the graphics package's Mods menu page on the real registry) outside the game.  npm i fengari (once);  node tools/gfxmenu_test.js
const path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const root = path.join(__dirname, '..');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const lp = (p) => JSON.stringify(path.join(root, p).split(path.sep).join('/'));
if (lauxlib.luaL_dostring(L, to_luastring(`package.path = ${lp('mod/lua/ge/extensions/?.lua')} .. ';' .. package.path`)) !== lua.LUA_OK) throw new Error('setup failed');
const status = lauxlib.luaL_dofile(L, to_luastring(path.join(__dirname, 'gfxmenu_test.lua')));
if (status !== lua.LUA_OK) { console.error(to_jsstring(lua.lua_tostring(L, -1))); process.exit(1); }
