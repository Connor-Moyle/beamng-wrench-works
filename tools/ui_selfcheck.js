// Runs the garage screen's controller outside the game, with the browser and Angular stubbed,
// and checks the catalog search / sort / paging and the sell and fit-all helpers.
//   node tools/ui_selfcheck.js
const assert = require('assert'), path = require('path');
const luaCalls = [], handlers = {};
let directive;
global.window = { innerWidth: 1920, innerHeight: 1080, requestAnimationFrame: () => 1, cancelAnimationFrame() {}, setInterval: () => 1, clearInterval() {}, setTimeout() {}, addEventListener() {}, removeEventListener() {} };
global.document = { createComment: () => ({}), createElement: () => ({ style: {}, appendChild() {} }), body: { appendChild() {} } };
global.bngApi = { engineLua: (s) => luaCalls.push(s), serializeToLua: JSON.stringify };
global.angular = { module: () => ({ directive: (name, def) => { directive = def[def.length - 1](); } }) };
require(path.join(__dirname, '..', 'mod', 'ui', 'modules', 'apps', 'slrrGarage', 'app.js'));

const $scope = { $on: (name, fn) => { handlers[name] = fn; }, $evalAsync: (fn) => fn() };
const ctrl = directive.controller[directive.controller.length - 1];
ctrl($scope, { trustAsHtml: (x) => x }, [{ parentNode: null, querySelector: () => null, querySelectorAll: () => [] }]);

const item = (part, name, slot, price) => ({ part, name, slot, price, slotPath: '/' + slot + '/' });
const sections = [
  { id: 'engine', title: 'Engine', subs: [
    { id: 'forced', title: 'Turbos', items: [item('turbo_a', 'Stage 1 Turbo', 'Turbocharger', 900), item('turbo_b', 'Race Turbo', 'Turbocharger', 2500)] },
    { id: 'exhaust', title: 'Exhausts', items: [item('exh_a', 'Sport Exhaust', 'Exhaust', 400)] }] },
  { id: 'body', title: 'Body', subs: [
    { id: 'hoods', title: 'Hoods', items: [1, 2, 3, 4, 5, 6, 7].map((i) => item('hood_' + i, 'Hood ' + i, 'Hood', i * 100)).concat([item('hood_t', 'Turbo Scoop Hood', 'Hood', 50)]) }] },
];
handlers.slrrGarageCatalog(null, { sections });
const names = () => $scope.shownItems().map((it) => it.part);

// a chapter shows its own parts, in the order Lua sent them
assert.deepStrictEqual(names(), ['turbo_a', 'turbo_b']);
assert.strictEqual($scope.pageCount(), 1);

// a search goes through every chapter; every word has to match
$scope.cur.search = 'turbo'; $scope.searchChanged();
assert.deepStrictEqual(names(), ['turbo_a', 'turbo_b', 'hood_t']);
$scope.cur.search = 'turbo hood';
assert.deepStrictEqual(names(), ['hood_t']);
$scope.cur.search = 'nothing like it';
assert.deepStrictEqual(names(), []);
assert.strictEqual($scope.pageCount(), 1);

// sorting by price, both ways, leaves the catalog's own lists alone
$scope.cur.search = 'turbo';
$scope.cycleSort(); assert.strictEqual($scope.sortLabel(), 'Cheapest first');
assert.deepStrictEqual(names(), ['hood_t', 'turbo_a', 'turbo_b']);
$scope.cycleSort(); assert.strictEqual($scope.sortLabel(), 'Dearest first');
assert.deepStrictEqual(names(), ['turbo_b', 'turbo_a', 'hood_t']);
$scope.cycleSort(); assert.strictEqual($scope.sortLabel(), 'By slot');
assert.deepStrictEqual(sections[0].subs[0].items.map((it) => it.part), ['turbo_a', 'turbo_b']);

// paging: eight hoods are two pages; turning past either end does nothing (and makes no sound)
$scope.openSub(sections[1], sections[1].subs[0]);
assert.strictEqual($scope.searching(), false);
assert.strictEqual($scope.pageCount(), 2);
luaCalls.length = 0;
$scope.turn(-1); assert.strictEqual($scope.cur.page, 0); assert.strictEqual(luaCalls.length, 0);
$scope.turn(1); assert.strictEqual($scope.cur.page, 1); assert.strictEqual($scope.pageItems().length, 2);
$scope.turn(1); assert.strictEqual($scope.cur.page, 1); assert.strictEqual(luaCalls.length, 1);

// shelf: parts that were bought and never fitted
handlers.slrrGarageState(null, { phase: 'garage', mode: 'mechanic', tool: 'sell', inventory: [{ id: 1, new: true }, { id: 2, used: true }, { id: 3 }] });
assert.strictEqual($scope.boughtCount(), 2);

// the sell tool works on the car too, and says what the part would fetch
handlers.slrrGarageHover(null, { name: 'Hood', removable: true, sellValue: 1250 });
assert.strictEqual($scope.canAct(), true);
assert.strictEqual($scope.hoverHint(), 'click to take it off and sell it for $1,250');
handlers.slrrGarageHover(null, { name: 'Body', removable: false, reason: 'The body shell stays where it is.' });
assert.strictEqual($scope.canAct(), false);
assert.strictEqual($scope.hoverHint(), 'The body shell stays where it is.');

// a chapter with parts for several slots gets a filter per slot
handlers.slrrGarageState(null, { phase: 'catalog', mode: 'mechanic', inventory: [] });
const wheels = { id: 'running', title: 'Running gear', subs: [{ id: 'rims_f', title: 'Front wheels', items: [
  item('rim_a', 'Steelie', 'Front Wheels', 100), item('drag_f', 'Drag Wheel', 'Front Wheels', 300),
  item('hubcap', 'Hub Cap', 'Front Hub Caps', 20)] }] };
wheels.subs[0].items[1].more = true;
handlers.slrrGarageCatalog(null, { sections: [wheels] });
$scope.openSub(wheels, wheels.subs[0]);
assert.deepStrictEqual($scope.slotChips(), ['Front Hub Caps', 'Front Wheels']);
$scope.pickSlot('Front Hub Caps');
assert.deepStrictEqual(names(), ['hubcap']);
$scope.pickSlot(null);
assert.strictEqual(names().length, 3);

// a plain part goes straight on the list; one with slots of its own asks for its options first
luaCalls.length = 0;
$scope.buy(wheels.subs[0].items[0]);
assert.ok(/^slrr_garage\.buy\(/.test(luaCalls[0]) && !$scope.cfg);
luaCalls.length = 0;
const drag = wheels.subs[0].items[1];
$scope.buy(drag);
assert.strictEqual(luaCalls[0], 'slrr_garage.requestSlots("/Front Wheels/","drag_f")');
assert.strictEqual($scope.cfg.waiting, true);
handlers.slrrGarageSlots(null, { key: '/Front Wheels/drag_f', slots: [
  { id: 'dia', path: '/Front Wheels/dia/', title: 'Diameter', default: 'd15', core: true, options: [
    { part: 'd15', name: '15 inch', price: 0, more: true }, { part: 'd17', name: '17 inch', price: 50, more: true }] }] });
// what it comes with has options of its own: they are asked for without a click
assert.ok(luaCalls.indexOf('slrr_garage.requestSlots("/Front Wheels/dia/","d15")') >= 0);
handlers.slrrGarageSlots(null, { key: '/Front Wheels/dia/d15', slots: [
  { id: 'width', path: '/Front Wheels/dia/width/', title: 'Width', default: '', options: [{ part: 'w15x4', name: '4 inch', price: 30 }] }] });
assert.deepStrictEqual($scope.cfgRows().map((r) => r.slot.title + '@' + r.depth), ['Diameter@0', 'Width@1']);
assert.strictEqual($scope.cfgRows(), $scope.cfgRows());        // the same list until something changes
assert.strictEqual($scope.cfgTotal(), 300);
// another diameter: its own widths replace the old ones, and the price follows
$scope.cfgChoose($scope.cfgRows()[0].slot, $scope.cfgRows()[0].slot.options[1]);
assert.deepStrictEqual($scope.cfgRows().map((r) => r.slot.title), ['Diameter']);
handlers.slrrGarageSlots(null, { key: '/Front Wheels/dia/d17', slots: [
  { id: 'width', path: '/Front Wheels/dia/width/', title: 'Width', default: '', options: [{ part: 'w17x8', name: '8 inch', price: 70 }] }] });
assert.strictEqual($scope.cfgName($scope.cfgRows()[1].slot), 'None');
$scope.cfgChoose($scope.cfgRows()[1].slot, $scope.cfgRows()[1].slot.options[0]);
assert.strictEqual($scope.cfgTotal(), 300 + 50 + 70);
luaCalls.length = 0;
$scope.cfgConfirm();
assert.strictEqual(luaCalls[0], 'slrr_garage.buy("/Front Wheels/","drag_f",' + JSON.stringify({ dia: { part: 'd17', sub: { width: { part: 'w17x8', sub: {} } } } }) + ')');
assert.strictEqual($scope.cfg, null);
// a part whose slots turn out to offer no choice is simply added
luaCalls.length = 0;
$scope.buy(drag);
handlers.slrrGarageSlots(null, { key: '/Front Wheels/drag_f', slots: {} });
assert.ok(/^slrr_garage\.buy\("\/Front Wheels\/","drag_f"\)$/.test(luaCalls[1]) && !$scope.cfg);

// body shells: the list narrows as you type, and stays the same list in between
handlers.slrrGarageLot(null, { models: [{ key: 'pickup', name: 'D-Series', brand: 'Gavril', price: 2000 }, { key: 'covet', name: 'Covet', brand: 'Ibishu', price: 900 }] });
assert.strictEqual($scope.lotShown().length, 2);
assert.strictEqual($scope.lotShown(), $scope.lotShown());
$scope.lot.search = 'ibishu cov';
assert.deepStrictEqual($scope.lotShown().map((m) => m.key), ['covet']);
assert.strictEqual($scope.quote('a"b'), '"a\\"b"');

console.log('ui self-check passed');
