// Wrench Works - the on-screen side of the garage.
// A full-screen app that only exists in the "slrrGarage" layout. It carries over the controls of
// Street Legal Racing: Redline's garage (the icon bar, the mechanic's repair / sell / filter
// buttons, the scrolling parts shelf, the catalog) in BeamNG's own look, and adds the panels that
// go with them: tuning, paint, car info and settings. Mouse input on the 3D view (click a part,
// right-drag to orbit, wheel to zoom, middle-click to look at a part) is forwarded to the
// slrr_garage Lua extension, which owns all the actual state.
//
// The 3D part previews are drawn here: Lua sends each part as a small triangle mesh and a tiny
// software renderer turns it on a 2D canvas (the game's UI browser has no WebGL).
angular.module('beamng.apps')

.directive('slrrGarage', [function () {
  var SLOTS_PER_LINE = 5;
  var CATALOG_PER_PAGE = 6;

  function svg(body) { return '<svg viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">' + body + '</svg>'; }
  var ICONS = {
    // SLRR's garage bar, redrawn as line icons
    drive: svg('<path d="M6 40 18 8M42 40 30 8M24 10v6M24 22v6M24 34v6"/>'),
    catalog: svg('<path d="M24 12c-4-3-10-4-16-3v27c6-1 12 0 16 3 4-3 10-4 16-3V9c-6-1-12 0-16 3zM24 12v27"/>'),
    info: svg('<circle cx="24" cy="24" r="17"/><path d="M24 22v11M24 15v.5"/>'),
    wrench: svg('<path d="M39 13a9 9 0 0 1-12 11L13 38a3.5 3.5 0 0 1-5-5l14-14A9 9 0 0 1 33 7l-6 6 2 6 6 2z"/>'),
    screwdriver: svg('<path d="M30 6h8l4 4v8l-6 0-8-8zM31 15 14 32M17 29l-9 9 2 2 9-9"/><path d="M8 38l-2 4 4-2"/>'),
    lift: svg('<path d="M8 22v-4l5-2 4-6h14l4 6 5 2v4zM14 22v3M34 22v3M24 28v12M17 34l7-7 7 7M10 42h28"/>'),
    spray: svg('<path d="M10 20h18v8H10zM28 22h6l4-5M16 28l-3 13h8l-1-13M36 10v.5M41 13v.5M40 7v.5M43 18v.5"/>'),
    key: svg('<circle cx="15" cy="24" r="8"/><path d="M23 24h19M35 24v6M41 24v5"/>'),
    clock: svg('<circle cx="24" cy="24" r="17"/><path d="M24 13v11l7 5"/>'),
    gear: svg('<circle cx="24" cy="24" r="6"/><path d="M24 5v6M24 37v6M5 24h6M37 24h6M10.5 10.5l4.3 4.3M33.2 33.2l4.3 4.3M10.5 37.5l4.3-4.3M33.2 14.8l4.3-4.3"/>'),
    flag: svg('<path d="M10 42V8M10 10h26l-5 8 5 8H10"/>'),
    driver: svg('<circle cx="24" cy="18" r="9"/><path d="M6 42c2-10 10-14 18-14s16 4 18 14M15 15h18"/>'),
    target: svg('<circle cx="24" cy="24" r="12"/><path d="M24 5v9M24 34v9M5 24h9M34 24h9"/>'),
    // the mechanic's row
    repairPart: svg('<path d="M33 9a8 8 0 0 1-10 10L11 31a3 3 0 0 1-4-4l12-12A8 8 0 0 1 29 5l-5 5 2 5 5 2z"/><path d="M36 30v12M30 36h12"/>'),
    repairCar: svg('<path d="M4 28v-6l6-2 5-8h14l7 8 6 2v6h-4a5 5 0 0 0-10 0H18a5 5 0 0 0-10 0z"/><path d="M24 34v10M19 39h10"/>'),
    sellAll: svg('<circle cx="19" cy="26" r="13"/><path d="M24 21c-1-2-8-3-8 1.500 0 4.500 8 2.300 8 6.800 0 4.500-7.500 3.800-9 .700M19 17v3M19 32.500v3"/><path d="M27 9.500a13 13 0 0 1 10 21.500"/><path d="M34 7a13 13 0 0 1 9 20"/>'),
    sell: svg('<circle cx="24" cy="24" r="17"/><path d="M30 17c-1-3-11-4-11 2 0 6 11 3 11 9 0 6-10 5-12 1M24 11v4M24 33v4"/>'),
    // catalog chapters / filters
    engine: svg('<path d="M10 18h6v-4h10v4h6l4 4h4v12h-4l-4 4H16l-4-4H8V22h2zM19 10h8"/>'),
    body: svg('<path d="M4 30v-6l6-2 6-8h14l8 8 6 2v6h-5a5 5 0 0 0-10 0H19a5 5 0 0 0-10 0z"/>'),
    running: svg('<circle cx="24" cy="24" r="16"/><circle cx="24" cy="24" r="5"/><path d="M24 8v11M24 29v11M8 24h11M29 24h11"/>'),
    interior: svg('<path d="M16 8h8l4 20h10v8H14zM14 36v6M36 36v6"/>'),
    paint: svg('<path d="M14 6h20v12H14zM20 18v8h8v-8M22 26h4v16h-4z"/>'),
    up: svg('<path d="M10 30l14-14 14 14"/>'),
    down: svg('<path d="M10 18l14 14 14-14"/>'),
    close: svg('<path d="M12 12l24 24M36 12 12 36"/>')
  };

  var TEMPLATE = [
    '<div class="sg-root" ng-class="[\'sg-phase-\' + s.phase, \'sg-mode-\' + s.mode]">',
    '<style>',
    '.sg-root{position:fixed;left:0;top:0;right:0;bottom:0;pointer-events:none;z-index:2;',
    '  font-family:"Noto Sans","Open Sans",Arial,sans-serif;color:#fff;user-select:none;-webkit-user-select:none;font-size:14px}',
    '.sg-root *{box-sizing:border-box}',
    '.sg-root svg{display:block;width:100%;height:100%}',
    '.sg-h{font-family:"Overpass","Noto Sans",Arial,sans-serif;font-weight:800;font-style:italic;text-transform:uppercase;letter-spacing:.5px}',
    '.sg-view{position:absolute;left:-200px;top:-200px;right:-200px;bottom:-200px;pointer-events:auto;cursor:default;background:rgba(0,0,0,.016)}',
    '.sg-view.sg-can{cursor:pointer}',
    '.sg-view.sg-dragging{cursor:move}',
    '.sg-panel{pointer-events:auto}',
    '.sg-glass{background:rgba(0,0,0,.62);border-radius:6px}',

    /* top bar */
    '.sg-top{position:absolute;left:14px;right:14px;top:10px;height:46px;display:flex;align-items:center}',
    '.sg-tag{height:46px;padding:0 22px 0 16px;display:flex;align-items:center;background:#ff6600;color:#fff;font-size:24px;',
    '  clip-path:polygon(0 0,100% 0,calc(100% - 14px) 100%,0 100%);border-radius:6px 0 0 6px}',
    '.sg-where{height:46px;margin-left:-8px;padding:0 20px 0 22px;display:flex;flex-direction:column;justify-content:center;background:rgba(0,0,0,.62);',
    '  clip-path:polygon(14px 0,100% 0,calc(100% - 14px) 100%,0 100%)}',
    '.sg-where b{font-size:15px;font-weight:600;line-height:1.15}',
    '.sg-where span{font-size:12px;color:#c8c8c8;line-height:1.15}',
    '.sg-money{margin-left:auto;height:46px;padding:0 18px;display:flex;flex-direction:column;justify-content:center;align-items:flex-end}',
    '.sg-money b{font-size:22px;font-weight:700;line-height:1.05;color:#fff}',
    '.sg-money span{font-size:11px;color:#ffb380;text-transform:uppercase;letter-spacing:1px}',

    /* SLRR icon bar */
    '.sg-bar{position:absolute;left:14px;top:66px;display:flex;align-items:center;padding:6px}',
    '.sg-ib{position:relative;width:46px;height:46px;margin-right:6px;padding:9px;border-radius:5px;background:rgba(255,255,255,.08);color:#fff;cursor:pointer}',
    '.sg-ib:last-child{margin-right:0}',
    '.sg-ib:hover{background:#ff6600}',
    '.sg-ib.sg-on{background:#ff6600;box-shadow:0 0 0 2px rgba(255,255,255,.55) inset}',
    '.sg-ib.sg-dim{opacity:.35;pointer-events:none}',
    '.sg-sep{width:1px;height:34px;margin:0 8px 0 2px;background:rgba(255,255,255,.22)}',
    '.sg-tip{position:absolute;left:14px;top:132px;padding:5px 12px;font-size:13px;background:rgba(0,0,0,.78);border-left:3px solid #ff6600;border-radius:0 4px 4px 0;white-space:nowrap}',
    '.sg-tip small{color:#bdbdbd;margin-left:8px}',
    '.sg-help{position:absolute;right:16px;top:66px;padding:8px 12px;font-size:12px;line-height:1.75;color:#d6d6d6;text-align:right}',
    '.sg-help b{color:#fff;font-weight:600}',
    '.sg-help i{font-style:normal;display:inline-block;padding:0 6px;margin-right:6px;border-radius:3px;background:rgba(255,255,255,.14);color:#fff;font-size:11px}',

    /* info line + messages */
    '.sg-info{position:absolute;left:0;right:0;bottom:calc(21vh + 12px);display:flex;justify-content:center;pointer-events:none}',
    '.sg-info > div{padding:7px 18px;text-align:center}',
    '.sg-info .sg-part{font-size:19px}',
    '.sg-info .sg-flag{color:#ffb380;font-weight:700;margin-left:6px;font-size:13px}',
    '.sg-info .sg-bad{color:#ff5c4d;font-weight:700;margin-left:8px;font-size:12px;letter-spacing:1px}',
    '.sg-info .sg-sub{font-size:13px;color:#d0d0d0;margin-top:1px}',
    '.sg-info .sg-no{color:#ff8d85}',
    '.sg-msg{position:absolute;left:50%;top:24%;transform:translateX(-50%);max-width:60%;padding:12px 22px;font-size:16px;',
    '  background:rgba(0,0,0,.82);border-left:5px solid #ff6600;border-radius:0 6px 6px 0;text-align:center}',

    /* the shelf */
    '.sg-shelf{position:absolute;left:14px;right:14px;bottom:12px;height:21vh;min-height:158px;display:flex;align-items:stretch;padding:10px}',
    '.sg-mech{width:176px;flex:none;display:flex;flex-direction:column;justify-content:center;padding-right:12px;margin-right:10px;border-right:1px solid rgba(255,255,255,.16)}',
    '.sg-cap{font-size:10px;letter-spacing:1.5px;color:#a8a8a8;text-transform:uppercase;margin:0 0 5px 1px}',
    '.sg-row{display:flex;margin-bottom:8px}',
    '.sg-row:last-child{margin-bottom:0}',
    '.sg-row .sg-ib{width:40px;height:40px;padding:8px;margin-right:5px}',
    '.sg-ib.sg-off{background:rgba(255,255,255,.03);color:#777}',
    '.sg-ib.sg-off:after{content:"";position:absolute;left:6px;right:6px;top:50%;height:2px;background:#ff6600;transform:rotate(-38deg)}',
    '.sg-slots{flex:1;display:flex;align-items:stretch;position:relative;min-width:0}',
    '.sg-slot{flex:1 1 0;min-width:0;margin:0 4px;position:relative;display:flex;flex-direction:column;align-items:center;justify-content:flex-end;',
    '  background:rgba(255,255,255,.07);border:1px solid rgba(255,255,255,.12);border-radius:5px;padding:6px 8px 7px 8px;text-align:center;overflow:hidden}',
    '.sg-slot.sg-empty{background:rgba(255,255,255,.02);border:1px dashed rgba(255,255,255,.12)}',
    '.sg-slot.sg-item{cursor:pointer}',
    '.sg-stats{position:absolute;left:6px;right:6px;bottom:6px;padding:6px 8px;border-radius:4px;background:rgba(10,10,14,.88);font-size:11px;z-index:3;pointer-events:none}',
    '.sg-stats .sg-kv{padding:1px 0;border:0}',
    '.sg-open>.sg-glyph{display:none}',
    '.sg-slot.sg-item:hover{background:rgba(255,102,0,.22);border-color:#ff6600}',
    '.sg-slot.sg-fresh{animation:sgdrop .45s ease-out}',
    '@keyframes sgdrop{0%{transform:translateY(-26px);opacity:0}100%{transform:none;opacity:1}}',
    '.sg-slot .sg-prev{position:absolute;left:5px;right:5px;top:26px;bottom:42px;pointer-events:none}',
    '.sg-card .sg-prev{position:absolute;left:0;right:0;top:0;bottom:24px;pointer-events:none}',
    '.sg-slot .sg-glyph{position:absolute;left:50%;top:38%;width:38px;height:38px;margin:-19px 0 0 -19px;color:rgba(255,255,255,.5)}',
    '.sg-slot .sg-txt{position:relative;width:100%;padding-top:3px;background:linear-gradient(rgba(0,0,0,0),rgba(0,0,0,.55) 35%)}',
    '.sg-slot .sg-name{font-size:14px;font-weight:600;line-height:1.15;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
    '.sg-slot .sg-wherep{font-size:11px;color:#c4c4c4;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
    '.sg-badges{position:absolute;left:6px;top:5px;display:flex;flex-direction:column;align-items:flex-start}',
    '.sg-badge{font-size:10px;font-weight:700;letter-spacing:.5px;padding:1px 6px;border-radius:3px;margin-bottom:3px;background:rgba(0,0,0,.6);color:#fff}',
    '.sg-badge.sg-new{background:#ff6600}',
    '.sg-badge.sg-more{cursor:pointer}',
    '.sg-badge.sg-more:hover{background:#ff6600}',
    '.sg-contents{position:absolute;z-index:6;min-width:200px;max-width:320px;max-height:46vh;overflow-y:auto;padding:8px 12px;background:rgba(20,20,22,.96);border:1px solid rgba(255,255,255,.18);border-top:3px solid #ff6600;border-radius:5px;pointer-events:auto}',
    '.sg-ctitle{font-size:11px;font-weight:700;letter-spacing:.6px;text-transform:uppercase;color:#ff9a4d;margin-bottom:5px}',
    '.sg-cline{font-size:13px;line-height:1.5;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
    '.sg-badge.sg-dmg{background:#c0271b}',
    '.sg-val{position:absolute;right:7px;top:5px;font-size:12px;font-weight:700;color:#fff;background:rgba(0,0,0,.55);padding:1px 6px;border-radius:3px}',
    '.sg-val.sg-gain{background:#2f8f3a}',
    '.sg-val.sg-cost{background:#c0271b}',
    '.sg-hint{position:absolute;left:0;right:0;top:50%;text-align:center;font-size:14px;color:#9a9a9a;pointer-events:none;transform:translateY(-50%)}',
    '.sg-scroll{width:58px;flex:none;display:flex;flex-direction:column;align-items:center;justify-content:space-between;margin-left:8px}',
    '.sg-scroll .sg-ib{width:46px;height:30%;margin:0;padding:6px 11px}',
    '.sg-line{font-size:22px;font-weight:700;line-height:1;text-align:center}',
    '.sg-line small{display:block;font-size:10px;color:#a8a8a8;font-weight:400;margin-top:2px}',

    /* side drawers (tune, paint) */
    '.sg-drawer{position:absolute;right:14px;top:66px;bottom:calc(21vh + 60px);width:400px;display:flex;flex-direction:column;padding:14px 14px 12px 14px}',
    '.sg-dhead{display:flex;align-items:center;margin-bottom:10px}',
    '.sg-dhead .sg-h{font-size:21px}',
    '.sg-dhead .sg-x{margin-left:auto;width:30px;height:30px;padding:7px;border-radius:4px;background:rgba(255,255,255,.1);cursor:pointer}',
    '.sg-dhead .sg-x:hover{background:#ff6600}',
    '.sg-tabs{display:flex;flex-wrap:wrap;margin-bottom:8px}',
    '.sg-tab{padding:4px 10px;margin:0 5px 5px 0;font-size:12px;border-radius:3px;background:rgba(255,255,255,.1);cursor:pointer}',
    '.sg-tab:hover{background:rgba(255,102,0,.5)}',
    '.sg-tab.sg-on{background:#ff6600}',
    '.sg-scrolly{flex:1;overflow-y:auto;padding-right:6px;min-height:0}',
    '.sg-scrolly::-webkit-scrollbar{width:6px}.sg-scrolly::-webkit-scrollbar-thumb{background:rgba(255,255,255,.3);border-radius:3px}',
    '.sg-var{padding:7px 0 9px 0;border-bottom:1px solid rgba(255,255,255,.1)}',
    '.sg-var .sg-vt{display:flex;align-items:baseline;font-size:13px}',
    '.sg-var .sg-vt b{font-weight:600}',
    '.sg-var .sg-vt span{margin-left:auto;color:#ffb380;font-weight:700;font-size:13px}',
    '.sg-var .sg-vd{font-size:11px;color:#a8a8a8;margin-top:1px}',
    '.sg-var .sg-vr{display:flex;align-items:center;margin-top:5px}',
    '.sg-var input[type=range],.sg-set input[type=range],.sg-paintrow input[type=range]{flex:1;-webkit-appearance:none;height:4px;background:rgba(255,255,255,.25);border-radius:2px;outline:none;margin:6px 0}',
    '.sg-root input[type=range]::-webkit-slider-thumb{-webkit-appearance:none;width:14px;height:14px;border-radius:50%;background:#ff6600;cursor:pointer}',
    '.sg-mini{margin-left:8px;padding:2px 8px;font-size:11px;border-radius:3px;background:rgba(255,255,255,.1);cursor:pointer;white-space:nowrap}',
    '.sg-mini:hover{background:rgba(255,102,0,.6)}',
    '.sg-foot2{display:flex;align-items:center;padding-top:10px}',
    '.sg-btn{padding:8px 16px;font-size:13px;font-weight:700;letter-spacing:.5px;text-transform:uppercase;border-radius:4px;background:rgba(255,255,255,.12);cursor:pointer;text-align:center}',
    '.sg-btn:hover{background:rgba(255,255,255,.24)}',
    '.sg-btn.sg-go{background:#ff6600}',
    '.sg-btn.sg-go:hover{background:#ff8533}',
    '.sg-btn.sg-nope{opacity:.35;pointer-events:none}',
    '.sg-note{font-size:12px;color:#c4c4c4;line-height:1.45}',
    '.sg-svc{display:flex;align-items:center;gap:10px;padding:9px 10px;margin:4px 0;border-radius:6px;background:rgba(255,255,255,.06);cursor:pointer}',
    '.sg-svc:hover{background:rgba(255,140,40,.22)}',
    '.sg-svct{flex:1;display:flex;flex-direction:column}',
    '.sg-svct b{font-size:14px;color:#fff}',
    '.sg-svct span{font-size:12px;color:#c4c4c4}',
    '.sg-svcp{font-size:14px;color:#ffb36b;font-weight:600}',
    '.sg-swatches{display:flex;flex-wrap:wrap;margin:-3px}',
    '.sg-sw{width:34px;height:34px;margin:3px;border-radius:4px;border:2px solid rgba(255,255,255,.25);cursor:pointer}',
    '.sg-sw:hover{border-color:#fff}',
    '.sg-paintrow{display:flex;align-items:center;font-size:12px;margin-top:4px}',
    '.sg-paintrow label{width:74px;color:#c4c4c4}',
    '.sg-paintrow span{width:38px;text-align:right;color:#ffb380;font-weight:700}',
    '.sg-chip{width:100%;height:46px;border-radius:4px;border:2px solid rgba(255,255,255,.25);margin:8px 0}',

    /* the small tuning menu of one part */
    '.sg-ptune{position:absolute;right:14px;bottom:calc(21vh + 24px);width:380px;max-height:46vh;display:flex;flex-direction:column;padding:12px 14px;border-left:4px solid #ff6600}',
    '.sg-ptune .sg-h{font-size:18px;line-height:1.15}',
    '.sg-ptune .sg-pslot{font-size:11px;letter-spacing:1px;color:#ffb380;text-transform:uppercase}',
    '.sg-ptune .sg-foot2 .sg-btn{margin-left:6px;padding:7px 12px}',

    /* modals (info, settings) */
    '.sg-veil{position:absolute;left:-200px;top:-200px;right:-200px;bottom:-200px;padding:200px;background:rgba(0,0,0,.55);display:flex;align-items:center;justify-content:center;pointer-events:auto}',
    '.sg-modal{width:620px;max-height:82%;display:flex;flex-direction:column;padding:18px 20px 16px 20px;background:rgba(18,18,20,.94);border-radius:8px;border-top:4px solid #ff6600}',
    '.sg-modal.sg-wide{width:760px}',
    '.sg-delta{margin-left:6px;font-size:12px;color:#ff8a80}.sg-delta.sg-up{color:#7ee08a}',
    '.sg-mini.sg-on{background:#ff6600;color:#111}',
    '.sg-dyno{display:block;width:100%;height:190px;margin-top:8px;background:rgba(255,255,255,.04);border-radius:4px}',
    '.sg-dkey{font-size:11px;color:#b8b8b8;margin-top:4px}',
    '.sg-dkey i{display:inline-block;width:14px;height:3px;margin:0 6px 3px 0;vertical-align:middle}',
    '.sg-dkey i+i,.sg-dkey i:nth-of-type(2){margin-left:14px}',
    '.sg-dkey span{float:right}',
    '.sg-kv .sg-bname{color:#fff;font-weight:600;max-width:38%;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
    '.sg-kv .sg-bcost{font-weight:400;color:#b8b8b8;font-size:12px;margin-right:10px;align-self:center}',
    '.sg-btn.sg-small{padding:3px 10px;font-size:11px;margin-left:6px}',
    '.sg-buildrow{display:flex;align-items:center;margin-top:10px}',
    '.sg-buildrow .sg-search{margin-left:0;flex:1;margin-right:10px}',
    '.sg-jline{font-size:13px;line-height:1.5;padding-left:2px}',
    '.sg-sheetbtns{display:flex;justify-content:space-between;margin-top:14px}',
    '.sg-work{position:absolute;left:50%;top:16%;transform:translateX(-50%);min-width:320px;padding:12px 18px 14px 18px;font-size:15px;font-weight:600;text-align:center;background:rgba(18,18,20,.9);border-radius:6px;border-top:3px solid #ff6600;pointer-events:none}',
    '.sg-workbar{height:6px;margin-top:9px;background:rgba(255,255,255,.14);border-radius:3px;overflow:hidden}',
    '.sg-workbar i{display:block;height:100%;width:0;background:#ff6600;transition:width linear}',
    '.sg-badge.sg-used{background:#2f7dd1}',
    '.sg-fitnew{position:absolute;right:14px;bottom:calc(21vh + 22px)}',
    '.sg-kv{display:flex;padding:5px 0;border-bottom:1px solid rgba(255,255,255,.08);font-size:13px}',
    '.sg-kv span{color:#b8b8b8}',
    '.sg-kv b{margin-left:auto;font-weight:600}',
    '.sg-grp{margin:12px 0 4px 0;font-size:12px;letter-spacing:1.5px;color:#ffb380;text-transform:uppercase}',
    '.sg-set{display:flex;align-items:center;padding:8px 0;border-bottom:1px solid rgba(255,255,255,.08)}',
    '.sg-set .sg-st{flex:1;min-width:0;padding-right:14px}',
    '.sg-set .sg-st b{display:block;font-size:14px;font-weight:600}',
    '.sg-set .sg-st span{display:block;font-size:11.5px;color:#a8a8a8;line-height:1.35;margin-top:1px}',
    '.sg-set .sg-sc{width:230px;flex:none;display:flex;align-items:center}',
    '.sg-set .sg-choice{flex-wrap:wrap;gap:4px;justify-content:flex-end}',
    '.sg-chopt{padding:4px 8px;font-size:11.5px;border-radius:4px;background:rgba(255,255,255,.1);cursor:pointer;white-space:nowrap}',
    '.sg-chopt:hover{background:rgba(255,140,40,.3)}',
    '.sg-chopt.sg-on{background:#ff7a1a;color:#111;font-weight:700}',
    '.sg-set .sg-sv{width:70px;text-align:right;color:#ffb380;font-weight:700;font-size:13px}',
    '.sg-set input[type=number]{width:130px;margin-left:auto;padding:5px 8px;font-size:14px;color:#fff;background:rgba(255,255,255,.1);border:1px solid rgba(255,255,255,.25);border-radius:4px;outline:none;text-align:right}',
    '.sg-tog{margin-left:auto;width:46px;height:24px;border-radius:12px;background:rgba(255,255,255,.2);position:relative;cursor:pointer}',
    '.sg-tog:after{content:"";position:absolute;left:3px;top:3px;width:18px;height:18px;border-radius:50%;background:#fff;transition:left .12s}',
    '.sg-tog.sg-on{background:#ff6600}.sg-tog.sg-on:after{left:25px}',

    /* catalog */
    '.sg-cat{position:absolute;left:-200px;top:-200px;right:-200px;bottom:-200px;padding:200px;background:rgba(0,0,0,.7);display:flex;align-items:center;justify-content:center;pointer-events:auto}',
    '.sg-book{width:88%;max-width:1560px;height:86%;display:flex;background:rgba(20,20,22,.96);border-radius:8px;border-top:4px solid #ff6600;overflow:hidden}',
    '.sg-page-l{width:27%;min-width:290px;padding:22px 20px 18px 24px;display:flex;flex-direction:column;background:rgba(255,255,255,.04)}',
    '.sg-page-r{flex:1;padding:22px 26px 14px 26px;display:flex;flex-direction:column;min-width:0}',
    '.sg-cat h1{margin:0;font-size:34px;line-height:1}',
    '.sg-cat .sg-for{font-size:12px;color:#b8b8b8;margin:4px 0 14px 0}',
    '.sg-sec{font-size:16px;padding:8px 10px;margin-top:4px;cursor:pointer;display:flex;align-items:center;border-radius:4px;background:rgba(255,255,255,.06)}',
    '.sg-sec > span:first-child{width:22px;height:22px;margin-right:10px;flex:none}',
    '.sg-sec:hover{background:rgba(255,102,0,.45)}',
    '.sg-sec.sg-act{background:#ff6600}',
    '.sg-sub-row{display:flex;align-items:baseline;padding:5px 10px 5px 42px;font-size:13px;cursor:pointer;color:#dcdcdc;border-radius:3px}',
    '.sg-sub-row:hover{background:rgba(255,255,255,.1)}',
    '.sg-sub-row.sg-act{color:#ff8533;font-weight:700}',
    '.sg-sub-row.sg-none{color:#6a6a6a;cursor:default;pointer-events:none}',
    '.sg-sub-row i{margin-left:auto;font-style:normal;font-size:11px;opacity:.7}',
    '.sg-cart{margin-top:10px;padding-top:10px;border-top:1px solid rgba(255,255,255,.14);font-size:13px}',
    '.sg-carth{font-size:11px;font-weight:700;letter-spacing:1px;text-transform:uppercase;color:#ffb380;margin-bottom:5px}',
    '.sg-carth i{font-style:normal;margin-left:8px;padding:0 6px;border-radius:8px;background:#ff6600;color:#fff}',
    '.sg-cartlist{max-height:17vh;overflow-y:auto}',
    '.sg-cartrow{display:flex;align-items:center;line-height:1.55}',
    '.sg-cartn{flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
    '.sg-cartp{margin-left:8px;color:#e8e8e8;font-variant-numeric:tabular-nums}',
    '.sg-cartx{margin-left:8px;width:18px;text-align:center;cursor:pointer;color:#bbb;border-radius:3px}',
    '.sg-cartx:hover{background:#c0271b;color:#fff}',
    '.sg-carthint{color:#9a9a9a;font-size:12px;line-height:1.35}',
    '.sg-ship{display:flex;align-items:center;margin-top:5px;padding:5px 8px;border:1px solid rgba(255,255,255,.14);border-radius:4px;cursor:pointer}',
    '.sg-ship.sg-act{border-color:#ff6600;background:rgba(255,102,0,.14)}',
    '.sg-dot{width:10px;height:10px;border-radius:50%;border:2px solid #bbb;margin-right:8px}',
    '.sg-ship.sg-act .sg-dot{border-color:#ff6600;background:#ff6600}',
    '.sg-shipt{flex:1}.sg-shipt small{display:block;font-size:11px;color:#a8a8a8}',
    '.sg-total{display:flex;justify-content:space-between;margin-top:8px;font-size:12px;letter-spacing:1px;text-transform:uppercase;color:#ffb380}',
    '.sg-total b{font-size:17px;color:#fff;letter-spacing:0}',
    '.sg-cartbtns{display:flex;justify-content:space-between;margin-top:8px}',
    '.sg-onway{margin-top:9px;font-size:11px;letter-spacing:.6px;text-transform:uppercase;color:#9fc6ff}',
    '.sg-onway .sg-cartrow{font-size:13px;letter-spacing:0;text-transform:none;color:#ddd}',
    '.sg-wallet{margin-top:10px;padding-top:10px;border-top:1px solid rgba(255,255,255,.14);font-size:11px;letter-spacing:1px;color:#ffb380;text-transform:uppercase}',
    '.sg-wallet b{display:block;font-size:24px;color:#fff;letter-spacing:0}',
    '.sg-head{display:flex;align-items:center;padding-bottom:10px;margin-bottom:10px;border-bottom:1px solid rgba(255,255,255,.16)}',
    '.sg-head .sg-h{font-size:24px}',
    '.sg-head .sg-crumb{margin-left:12px;font-size:12px;color:#b8b8b8;text-transform:uppercase;letter-spacing:1px}',
    '.sg-head .sg-btn{margin-left:auto}',
    '.sg-search{margin-left:18px;width:230px;padding:6px 10px;font-size:13px;color:#fff;background:rgba(255,255,255,.1);border:1px solid rgba(255,255,255,.25);border-radius:4px;outline:none}',
    '.sg-search::placeholder{color:#9a9a9a}',
    '.sg-grid{flex:1;display:flex;flex-wrap:wrap;align-content:flex-start;margin:0 -6px;overflow:hidden;min-height:0}',
    '.sg-card{width:calc(33.333% - 12px);height:calc(50% - 12px);margin:6px;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.1);border-radius:6px;',
    '  display:flex;flex-direction:column;position:relative;min-width:0;overflow:hidden}',
    '.sg-card .sg-stage{position:relative;flex:1;min-height:0;background:#0a0a0c}',
    '.sg-smoke{position:absolute;pointer-events:none;z-index:4}',
    '.sg-puff{position:absolute;border-radius:50%;opacity:0;animation:sgpuff 2.3s ease-out forwards}',
    '@keyframes sgpuff{0%{opacity:0;transform:scale(.25)}18%{opacity:1}55%{opacity:1;transform:scale(1.05)}100%{opacity:0;transform:scale(1.35) translateY(-6%)}}',
    '.sg-card .sg-glyph{position:absolute;left:50%;top:50%;width:64px;height:64px;margin:-32px 0 0 -32px;color:rgba(255,255,255,.22)}',
    '.sg-card .sg-meta{padding:8px 12px 10px 12px;background:rgba(0,0,0,.35)}',
    '.sg-card .sg-cslot{font-size:11px;letter-spacing:1px;color:#ffb380;text-transform:uppercase;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
    '.sg-card .sg-cname{font-size:16px;font-weight:600;line-height:1.2;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
    '.sg-card .sg-buyrow{display:flex;align-items:center;margin-top:6px}',
    '.sg-price{font-size:19px;font-weight:700}',
    '.sg-card .sg-btn{margin-left:auto;padding:6px 18px}',
    '.sg-card .sg-badges{left:8px;top:auto;bottom:3px;flex-direction:row}',
    '.sg-card .sg-badges .sg-badge{margin-right:5px}',
    '.sg-foot{display:flex;align-items:center;justify-content:center;padding-top:10px;font-size:13px;color:#c8c8c8}',
    '.sg-foot .sg-btn{margin:0 14px}',
    '.sg-blank{flex:1;display:flex;align-items:center;justify-content:center;font-size:15px;color:#9a9a9a;text-align:center;line-height:1.6}',

    /* body shells, for a visit that starts on foot */
    '.sg-lothead{display:flex;align-items:center;margin-bottom:8px}',
    '.sg-lothead .sg-h{font-size:24px}',
    '.sg-lothead .sg-cash{margin-left:auto;margin-right:14px;font-size:18px;font-weight:700}',
    '.sg-lotrow{display:flex;align-items:center;padding:6px 0;border-bottom:1px solid rgba(255,255,255,.08)}',
    '.sg-lotrow img{width:96px;height:54px;object-fit:cover;border-radius:3px;margin-right:12px;background:rgba(255,255,255,.06)}',
    '.sg-lotn{flex:1;min-width:0}',
    '.sg-lotn span{display:block;font-size:11px;letter-spacing:1px;color:#ffb380;text-transform:uppercase}',
    '.sg-lotn b{font-size:15px;font-weight:600}',
    '.sg-lotrow .sg-price{margin:0 14px}',

    /* slot filters of a chapter */
    '.sg-chips{display:flex;flex-wrap:wrap;margin:-4px 0 8px 0;max-height:62px;overflow-y:auto}',
    '.sg-chips .sg-tab{margin-bottom:4px}',

    /* options of a part, chosen before it is bought */
    '.sg-cfg{z-index:5}',
    '.sg-crow{margin-top:6px;border:1px solid rgba(255,255,255,.14);border-radius:4px;background:rgba(255,255,255,.04)}',
    '.sg-chead{display:flex;align-items:baseline;padding:7px 10px;cursor:pointer;font-size:13px}',
    '.sg-chead:hover{background:rgba(255,102,0,.2)}',
    '.sg-chead span{color:#ffb380;font-size:11px;letter-spacing:1px;text-transform:uppercase;width:34%;flex:none;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;padding-right:10px}',
    '.sg-chead b{flex:1;min-width:0;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
    '.sg-chead i{font-style:normal;color:#c8c8c8;margin-left:10px;font-variant-numeric:tabular-nums}',
    '.sg-chead em{font-style:normal;margin-left:10px;color:#9a9a9a}',
    '.sg-copts{max-height:26vh;overflow-y:auto;border-top:1px solid rgba(255,255,255,.12);padding:4px}',
    '.sg-copt{display:flex;padding:5px 8px;font-size:13px;border-radius:3px;cursor:pointer}',
    '.sg-copt:hover{background:rgba(255,255,255,.1)}',
    '.sg-copt.sg-act{background:#ff6600}',
    '.sg-copt span{flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
    '.sg-copt i{font-style:normal;margin-left:10px;opacity:.85}',
    '.sg-cfgfoot{display:flex;align-items:center;margin-top:14px}',
    '.sg-cfgfoot .sg-total{margin:0;flex:1;justify-content:flex-start;align-items:baseline}',
    '.sg-cfgfoot .sg-total b{margin-left:12px}',
    '.sg-cfgfoot .sg-btn{margin-left:8px}',

    /* the paper catalog (Settings > Catalog): the same book, printed */
    '.sg-retro .sg-book{background:#e9e2cf;color:#1c1a16;border-top:none;border-radius:2px;box-shadow:0 0 0 2px #3a3326,0 18px 50px rgba(0,0,0,.6);',
    '  font-family:"Courier New",Courier,monospace;background-image:repeating-linear-gradient(0deg,rgba(0,0,0,.03) 0,rgba(0,0,0,.03) 1px,transparent 1px,transparent 27px)}',
    '.sg-retro .sg-page-l{background:rgba(120,100,50,.13);position:relative;padding-right:30px}',
    '.sg-retro .sg-page-l:after{content:"";position:absolute;right:-13px;top:0;bottom:0;width:26px;z-index:2;',
    '  background:radial-gradient(circle at 5px 15px,#15130f 0,#15130f 4px,transparent 5px) 0 0/26px 30px repeat-y,',
    '  radial-gradient(circle at 21px 15px,#15130f 0,#15130f 4px,transparent 5px) 0 0/26px 30px repeat-y,',
    '  linear-gradient(#b9b3a2,#77705f) 4px 13px/18px 4px repeat-y;background-size:26px 30px,26px 30px,18px 30px}',
    '.sg-retro .sg-page-r{padding-left:36px}',
    '.sg-retro .sg-h{font-family:Impact,"Arial Narrow Bold","Arial Black",sans-serif;font-style:normal;font-weight:400;letter-spacing:1px}',
    '.sg-retro h1.sg-h{color:#b3261e;text-shadow:2px 2px 0 rgba(0,0,0,.12)}',
    '.sg-retro .sg-for,.sg-retro .sg-crumb,.sg-retro .sg-foot,.sg-retro .sg-carthint,.sg-retro .sg-blank,.sg-retro .sg-shipt small{color:#5a5140}',
    '.sg-retro .sg-sec{background:#cfc4a4;color:#1c1a16;border:1px solid #9c9072;border-radius:0}',
    '.sg-retro .sg-sec:hover{background:#dcbf8a}',
    '.sg-retro .sg-sec.sg-act{background:#b3261e;color:#fff;border-color:#7d1a14}',
    '.sg-retro .sg-sub-row{color:#3a3326;border-radius:0}',
    '.sg-retro .sg-sub-row:hover{background:rgba(0,0,0,.08)}',
    '.sg-retro .sg-sub-row.sg-act{color:#b3261e}',
    '.sg-retro .sg-sub-row.sg-none{color:#a79e86}',
    '.sg-retro .sg-head{border-bottom:3px double #3a3326}',
    '.sg-retro .sg-search{background:#fffdf5;color:#1c1a16;border-color:#9c9072;border-radius:0;font-family:inherit}',
    '.sg-retro .sg-search::placeholder{color:#8a8068}',
    '.sg-retro .sg-card{background:#f6f1e2;border:1px solid #9c9072;border-radius:0;box-shadow:2px 3px 0 rgba(0,0,0,.18)}',
    '.sg-retro .sg-card .sg-stage{border:6px solid #fff;box-shadow:0 0 0 1px #c9c1aa inset}',
    '.sg-retro .sg-card .sg-meta{background:none}',
    '.sg-retro .sg-card .sg-cslot{color:#8a2a22}',
    '.sg-retro .sg-price{color:#b3261e;font-family:Impact,"Arial Black",sans-serif;font-weight:400;font-size:22px}',
    '.sg-retro .sg-btn{background:#3a3326;color:#f6f1e2;border-radius:0}',
    '.sg-retro .sg-btn:hover{background:#5a5140}',
    '.sg-retro .sg-btn.sg-go{background:#b3261e}',
    '.sg-retro .sg-btn.sg-go:hover{background:#cf3b32}',
    '.sg-retro .sg-mini,.sg-retro .sg-tab{background:#cfc4a4;color:#1c1a16;border-radius:0}',
    '.sg-retro .sg-tab.sg-on{background:#b3261e;color:#fff}',
    '.sg-retro .sg-cart,.sg-retro .sg-wallet{border-top:1px dashed #7c7258}',
    '.sg-retro .sg-carth,.sg-retro .sg-total,.sg-retro .sg-wallet{color:#8a2a22}',
    '.sg-retro .sg-carth i{background:#b3261e}',
    '.sg-retro .sg-total b,.sg-retro .sg-wallet b,.sg-retro .sg-cartp{color:#1c1a16}',
    '.sg-retro .sg-cartx{color:#5a5140}',
    '.sg-retro .sg-ship{border-color:#9c9072;border-radius:0}',
    '.sg-retro .sg-ship.sg-act{border-color:#b3261e;background:rgba(179,38,30,.1)}',
    '.sg-retro .sg-dot{border-color:#5a5140}',
    '.sg-retro .sg-ship.sg-act .sg-dot{border-color:#b3261e;background:#b3261e}',
    '.sg-retro .sg-onway{color:#2a4a7a}',
    '.sg-retro .sg-onway .sg-cartrow{color:#1c1a16}',
    '.sg-retro .sg-scrolly::-webkit-scrollbar-thumb{background:rgba(0,0,0,.3)}',

    /* film bars + fade */
    '.sg-lb{position:absolute;left:-200px;right:-200px;height:400px;background:#000;transition:transform .6s ease}',
    '.sg-lb.sg-t{top:-500px}.sg-lb.sg-b{bottom:-500px}',
    '.sg-phase-film .sg-lb.sg-t{transform:translateY(calc(100px + 9vh))}.sg-phase-film .sg-lb.sg-b{transform:translateY(calc(-100px - 9vh))}',
    '.sg-fade{position:absolute;left:-200px;top:-200px;right:-200px;bottom:-200px;background:#000;opacity:0;transition:opacity .2s linear;pointer-events:none}',
    '.sg-fade.sg-in{opacity:1}',
    '</style>',

    '<div class="sg-fitnew sg-btn sg-tonal sg-panel" ng-if="s.phase === \'film\' && s.scene" ng-mouseenter="overUi(true)" ng-click="lua(\'skipScene()\')">Skip</div>',
    '<div class="sg-view" ng-if="s.phase === \'garage\'" ng-class="{\'sg-can\': canAct(), \'sg-dragging\': drag.active}"',
    '     ng-mousedown="viewDown($event)" ng-mouseenter="overUi(false)" oncontextmenu="return false"></div>',

    '<div class="sg-lb sg-t"></div><div class="sg-lb sg-b"></div>',

    '<div ng-if="s.phase === \'garage\' || s.phase === \'busy\'">',

    /* top bar */
    '  <div class="sg-top sg-panel" ng-mouseenter="overUi(true)">',
    '    <div class="sg-tag sg-h">Garage</div>',
    '    <div class="sg-where"><b>{{s.garage}}</b><span>{{s.car}}</span></div>',
    '    <div class="sg-money sg-glass"><b>{{s.unlimited ? \'Unlimited\' : money(s.money)}}</b><span>{{s.career ? \'Career money\' : \'Money\'}}</span></div>',
    '  </div>',

    /* SLRR icon bar */
    '  <div class="sg-bar sg-glass sg-panel" ng-mouseenter="overUi(true)" ng-mouseleave="tip = null">',
    '    <div ng-repeat="b in bar | filter:barVisible track by $index" ng-class="b.sep ? \'sg-sep\' : {\'sg-ib\': true, \'sg-on\': b.on && b.on()}" ng-click="b.act && b.act()" ng-mouseenter="$parent.tip = b.sep ? null : b" ng-focus="$parent.tip = b.sep ? null : b" ng-bind-html="b.sep ? \'\' : icon(b.icon)"></div>',
    '  </div>',
    '  <div class="sg-tip" ng-if="tip">{{tip.title}}<small>{{tip.desc}}</small></div>',

    '  <div class="sg-help sg-glass" ng-if="!panel && s.hints !== false">',
    '    <div ng-if="s.mode === \'mechanic\' && !s.tool"><i>Click</i>a part to take it off</div>',
    '    <div ng-if="s.mode === \'mechanic\' && !s.tool"><i>Click</i>a shelf part to fit it</div>',
    '    <div ng-if="s.mode === \'tune\' && !s.tool"><i>Click</i>a part to pick it and tune it</div>',
    '    <div ng-if="s.tool === \'repair\'"><i>Click</i>a damaged part to repair it</div>',
    '    <div ng-if="s.tool === \'sell\'"><i>Click</i>a part, on the car or the shelf, to sell it</div>',
    '    <div><i>Right-drag</i>look around</div><div><i>Wheel</i>zoom</div><div><i>Middle-click</i>look at a part</div>',
    '  </div>',

    /* hover line */
    '  <div class="sg-info" ng-if="hover.name">',
    '    <div class="sg-glass">',
    '      <div><span class="sg-part sg-h">{{hover.name}}</span><span class="sg-flag" ng-if="hover.complex">+{{hover.count - 1}} parts</span><span class="sg-bad" ng-if="hover.damaged">DAMAGED</span></div>',
    '      <div class="sg-sub" ng-class="{\'sg-no\': hoverBlocked()}">{{hover.slot}} &middot; {{money(hover.value)}} &middot; {{hoverHint()}}</div>',
    '    </div>',
    '  </div>',

    /* the shelf */
    '  <div class="sg-shelf sg-glass sg-panel" ng-mouseenter="overUi(true)">',
    '    <div class="sg-mech">',
    '      <div class="sg-cap">Mechanic</div>',
    '      <div class="sg-row" ng-mouseleave="tip = null">',
    '        <div class="sg-ib" ng-class="{\'sg-on\': s.tool === \'repair\'}" ng-click="lua(\'setTool(\\\'repair\\\')\')" ng-mouseenter="tip = tips.repairPart" ng-focus="tip = tips.repairPart" ng-bind-html="icon(\'repairPart\')"></div>',
    '        <div class="sg-ib" ng-class="{\'sg-dim\': !s.damaged}" ng-click="lua(\'repairAll()\')" ng-mouseenter="tip = repairAllTip()" ng-focus="tip = repairAllTip()" ng-bind-html="icon(\'repairCar\')"></div>',
    '        <div class="sg-ib" ng-class="{\'sg-on\': s.tool === \'sell\'}" ng-click="lua(\'setTool(\\\'sell\\\')\')" ng-mouseenter="tip = tips.sell" ng-focus="tip = tips.sell" ng-bind-html="icon(\'sell\')"></div>',
    '        <div class="sg-ib" ng-class="{\'sg-dim\': !s.inventory.length}" ng-click="lua(\'sellAll()\')" ng-mouseenter="tip = sellAllTip()" ng-focus="tip = sellAllTip()" ng-bind-html="icon(\'sellAll\')"></div>',
    '      </div>',
    '      <div class="sg-cap">Show on car</div>',
    '      <div class="sg-row" ng-mouseleave="tip = null">',
    '        <div class="sg-ib" ng-repeat="f in filterDefs" ng-class="{\'sg-off\': s.filters[f.id]}" ng-click="lua(\'toggleFilter(\\\'\' + f.id + \'\\\')\')" ng-mouseenter="$parent.tip = f.tip" ng-focus="$parent.tip = f.tip" ng-bind-html="icon(f.id)"></div>',
    '      </div>',
    '    </div>',
    '    <div class="sg-slots">',
    '      <div class="sg-slot" ng-repeat="slot in visibleSlots() track by $index" ng-class="{\'sg-empty\': !slot, \'sg-item\': slot, \'sg-fresh\': slot && slot.id === freshId}" ng-click="slot && install(slot)">',
    '        <span class="sg-glyph" ng-if="slot" ng-bind-html="icon(slot.section)"></span>',
    '        <div class="sg-prev" ng-if="slot && hasModel(slot.part)" data-part="{{slot.part}}" data-id="s{{slot.id}}" data-spin="hover"></div>',
    '        <div class="sg-badges" ng-if="slot">',
    '          <span class="sg-badge sg-new" ng-if="slot.new">NEW</span>',
    '          <span class="sg-badge sg-used" ng-if="slot.used">USED<span ng-if="slot.wear != null"> &middot; {{slot.wear}}% WORN</span></span>',
    '          <span class="sg-badge" ng-if="slot.swap" title="{{slot.swapText}}">SWAP &middot; {{slot.swap}} LABOUR</span>',
    '          <span class="sg-badge sg-dmg" ng-if="slot.damaged">DAMAGED</span>',
    '          <span class="sg-badge sg-more" ng-if="slot.count > 1" ng-click="showContents(slot, $event)">+{{slot.count - 1}} parts &#9662;</span>',
    '        </div>',
    '        <div class="sg-val" ng-if="slot && !s.tool">{{money(slot.value)}}</div>',
    '        <div class="sg-val sg-gain" ng-if="slot && s.tool === \'sell\'">+{{money(slot.sellValue)}}</div>',
    '        <div class="sg-val sg-cost" ng-if="slot && s.tool === \'repair\' && slot.damaged">-{{money(slot.repairCost)}}</div>',
    '        <div class="sg-txt" ng-if="slot"><div class="sg-name">{{slot.name}}</div><div class="sg-wherep">{{slot.slot}}</div></div>',
    '      </div>',
    '      <div class="sg-hint" ng-if="!s.inventory.length">The shelf is empty &mdash; click a part on the car to take it off.</div>',
    '    </div>',
    '    <div class="sg-scroll">',
    '      <div class="sg-ib" ng-class="{\'sg-dim\': line <= 0}" ng-click="scroll(-1)" ng-bind-html="icon(\'up\')"></div>',
    '      <div class="sg-line">{{line + 1}}<small>of {{lineCount()}}</small></div>',
    '      <div class="sg-ib" ng-class="{\'sg-dim\': line >= lineCount() - 1}" ng-click="scroll(1)" ng-bind-html="icon(\'down\')"></div>',
    '    </div>',
    '  </div>',

    '  <div class="sg-fitnew sg-btn sg-go sg-panel" ng-if="s.phase === \'garage\' && s.mode === \'mechanic\' && !s.tool && !panel && boughtCount() > 1" ng-mouseenter="overUi(true)" ng-click="lua(\'installNew()\')">Fit all {{boughtCount()}} new parts</div>',

    /* tune drawer */
    '  <div class="sg-drawer sg-glass sg-panel" ng-if="panel === \'tune\'" ng-mouseenter="overUi(true)">',
    '    <div class="sg-dhead"><div class="sg-h">Tuning</div><div class="sg-x" ng-click="closePanel()" ng-bind-html="icon(\'close\')"></div></div>',
    '    <div class="sg-tabs"><div class="sg-tab" ng-class="{\'sg-on\': !tune.category}" ng-click="tune.category = null">All</div><div class="sg-tab" ng-repeat="c in tune.categories" ng-class="{\'sg-on\': c === tune.category}" ng-click="tune.category = c">{{c}}</div></div>',
    '    <div class="sg-scrolly">',
    '     <div ng-repeat="grp in tuneGroups() track by grp.key">',
    '      <div class="sg-cap" style="margin-top:8px" ng-if="grp.name">{{grp.name}}</div>',
    '      <div class="sg-var" ng-repeat="v in grp.vars track by v.name">',
    '        <div class="sg-vt"><b>{{v.title}}</b><span>{{shown(v)}} {{v.unit}}</span></div>',
    '        <div class="sg-vd" ng-if="v.description">{{v.description}}</div>',
    '        <div class="sg-vr"><input type="range" min="{{v.lo}}" max="{{v.hi}}" step="{{v.step}}" ng-model="v.value" ng-change="tuneChanged()"><div class="sg-mini" ng-click="v.value = v.default; tuneChanged()">Default</div></div>',
    '      </div>',
    '     </div>',
    '      <div class="sg-note" ng-if="!tune.vars.length">This car has nothing to adjust with the parts that are on it. Springs, alignment, gearing and the like show up here when the fitted parts allow it.</div>',
    '    </div>',
    '    <div class="sg-foot2"><div class="sg-note" style="flex:1;padding-right:10px">Changes take hold when you apply them &mdash; the car is set up again behind a short fade.</div>',
    '      <div class="sg-btn sg-go" ng-class="{\'sg-nope\': !tune.dirty}" ng-click="applyTune()">Apply</div></div>',
    '  </div>',

    /* one part's tuning menu */
    '  <div class="sg-ptune sg-glass sg-panel" ng-if="s.mode === \'tune\' && pt.name && panel !== \'tune\' && panel !== \'paint\'" ng-mouseenter="overUi(true)">',
    '    <div class="sg-dhead" style="margin-bottom:6px"><div><div class="sg-pslot">{{pt.slot}}</div><div class="sg-h">{{pt.name}}</div></div><div class="sg-x" ng-click="lua(\'clearTunePart()\')" ng-bind-html="icon(\'close\')"></div></div>',
    '    <div class="sg-note" ng-if="pt.owner && pt.vars.length" style="margin-bottom:4px">Set on the {{pt.owner}} it is mounted to.</div>',
    '    <div class="sg-scrolly">',
    '      <div class="sg-var" ng-repeat="v in pt.vars track by v.name">',
    '        <div class="sg-vt"><b>{{v.subCategory ? v.subCategory + \' \' : \'\'}}{{v.title}}</b><span>{{shown(v)}} {{v.unit}}</span></div>',
    '        <div class="sg-vr"><input type="range" min="{{v.lo}}" max="{{v.hi}}" step="{{v.step}}" ng-model="v.value" ng-change="pt.dirty = true"><div class="sg-mini" ng-click="v.value = v.default; pt.dirty = true">Default</div></div>',
    '      </div>',
    '      <div class="sg-note" ng-if="!pt.vars.length">Nothing to adjust on this part{{pt.canOpen ? \', but it opens.\' : \'.\'}}</div>',
    '    </div>',
    '    <div class="sg-foot2"><div class="sg-btn" ng-click="panel = \'tune\'; lua(\'requestTuning()\')">All</div><div style="flex:1"></div>',
    '      <div class="sg-btn" ng-if="pt.canOpen" ng-click="lua(\'toggleOpen()\')">Open / close</div>',
    '      <div class="sg-btn sg-go" ng-if="pt.vars.length" ng-class="{\'sg-nope\': !pt.dirty}" ng-click="applyPartTune()">Apply</div></div>',
    '  </div>',

    /* paint drawer */
    '  <div class="sg-drawer sg-glass sg-panel" ng-if="panel === \'paint\'" ng-mouseenter="overUi(true)">',
    '    <div class="sg-dhead"><div class="sg-h">Paint booth</div><div class="sg-x" ng-click="closePanel()" ng-bind-html="icon(\'close\')"></div></div>',
    '    <div class="sg-tabs"><div class="sg-tab" ng-repeat="n in [1,2,3]" ng-class="{\'sg-on\': paint.slot === n}" ng-click="pickPaintSlot(n)">{{[\'Main colour\',\'Second colour\',\'Third colour\'][n-1]}}</div></div>',
    '    <div class="sg-scrolly">',
    '      <div class="sg-cap">Factory colours</div>',
    '      <div class="sg-swatches"><div class="sg-sw" ng-repeat="sw in paint.swatches track by sw.name" ng-style="{background: css(sw.paint)}" ng-click="useSwatch(sw)" title="{{sw.name}}"></div></div>',
    '      <div class="sg-cap" style="margin-top:12px">Mix your own</div>',
    '      <div class="sg-chip" ng-style="{background: css(paint.cur)}"></div>',
    '      <div class="sg-paintrow" ng-repeat="ch in paintChannels"><label>{{ch.title}}</label><input type="range" min="0" max="1" step="0.01" ng-model="paint.cur[ch.key][ch.idx]" ng-if="ch.idx !== undefined"><input type="range" min="0" max="1" step="0.01" ng-model="paint.cur[ch.key]" ng-if="ch.idx === undefined"><span>{{pct(ch)}}</span></div>',
    '    </div>',
    '    <div class="sg-foot2"><div class="sg-note" style="flex:1;padding-right:10px">A respray costs {{money(paint.price)}} per colour.</div><div class="sg-btn sg-go" ng-click="spray()">Spray</div></div>',
    '  </div>',

    /* services other mods offer (an oil change, a car swap, a race...): their list, their buttons */
    '  <div class="sg-drawer sg-glass sg-panel" ng-if="svcTabs[panel]" ng-mouseenter="overUi(true)">',
    '    <div class="sg-dhead"><div class="sg-h">{{svcTabs[panel].title}}</div><div class="sg-x" ng-click="closePanel()" ng-bind-html="icon(\'close\')"></div></div>',
    '    <div class="sg-scrolly">',
    '      <div ng-repeat="g in serviceGroups(panel)">',
    '        <div class="sg-cap" style="margin-top:8px">{{g.name}}</div>',
    '        <div class="sg-svc" ng-repeat="sv in g.items" ng-class="{\'sg-dim\': sv.disabled}" ng-click="!sv.disabled && lua(\'service(\\\'\' + sv.id + \'\\\')\')">',
    '          <div class="sg-svct"><b>{{sv.label}}</b><span>{{sv.desc}}</span></div><div class="sg-svcp" ng-if="sv.price">{{money(sv.price)}}</div>',
    '        </div>',
    '      </div>',
    '      <div class="sg-note" ng-if="!serviceGroups(panel).length">Nothing on offer here.</div>',
    '    </div>',
    '  </div>',

    '</div>',

    /* car info */
    '<div class="sg-veil" ng-if="panel === \'info\' && s.phase === \'garage\'" ng-mouseenter="overUi(true)">',
    '  <div class="sg-modal">',
    '    <div class="sg-dhead"><div class="sg-h">{{info.name}}</div><div class="sg-x" ng-click="closePanel()" ng-bind-html="icon(\'close\')"></div></div>',
    '    <div class="sg-scrolly">',
    '      <div class="sg-kv" ng-repeat="r in info.rows"><span>{{r.label}}</span><b>{{r.value}}</b></div>',
    '      <div class="sg-grp">In the garage</div>',
    '      <div class="sg-kv"><span>Parts fitted</span><b>{{info.parts}}</b></div>',
    '      <div class="sg-kv"><span>Value of fitted parts</span><b>{{money(info.value)}}</b></div>',
    '      <div class="sg-kv"><span>Parts on the shelf</span><b>{{info.shelfParts}} ({{money(info.shelfValue)}})</b></div>',
    '      <div class="sg-kv"><span>Damaged parts</span><b>{{info.damagedParts}}</b></div>',
    '      <div class="sg-kv" ng-if="info.repairCost > 0"><span>Cost to repair everything</span><b>{{money(info.repairCost)}}</b></div>',
    '      <div class="sg-kv" ng-if="info.missing"><span>Missing</span><b>{{info.missing}}</b></div>',
    '      <div class="sg-note" style="margin-top:10px" ng-if="info.note">{{info.note}}</div>',
    '      <div ng-if="dyno.path">',
    '        <div class="sg-grp">Engine</div>',
    '        <div class="sg-kv"><span>Peak power</span><b>{{dyno.maxPower}} hp at {{dyno.maxPowerRPM}} rpm <span class="sg-delta" ng-if="dyno.base" ng-class="{\'sg-up\': dyno.dPower > 0}">{{dyno.dPower > 0 ? \'+\' : \'\'}}{{dyno.dPower}} hp</span></b></div>',
    '        <div class="sg-kv"><span>Peak torque</span><b>{{dyno.maxTorque}} Nm at {{dyno.maxTorqueRPM}} rpm <span class="sg-delta" ng-if="dyno.base" ng-class="{\'sg-up\': dyno.dTorque > 0}">{{dyno.dTorque > 0 ? \'+\' : \'\'}}{{dyno.dTorque}} Nm</span></b></div>',
    '        <svg class="sg-dyno" viewBox="0 0 560 190" preserveAspectRatio="none">',
    '          <path ng-attr-d="{{dyno.grid}}" fill="none" stroke="rgba(255,255,255,.12)" stroke-width="1"/>',
    '          <path ng-attr-d="{{dyno.torquePath}}" fill="none" stroke="#6fb7ff" stroke-width="2.5"/>',
    '          <path ng-if="dyno.base" ng-attr-d="{{dyno.basePath}}" fill="none" stroke="#ff6600" stroke-opacity=".45" stroke-width="2" stroke-dasharray="6 5"/>',
    '          <path ng-if="dyno.base" ng-attr-d="{{dyno.baseTorquePath}}" fill="none" stroke="#6fb7ff" stroke-opacity=".45" stroke-width="2" stroke-dasharray="6 5"/>',
    '          <path ng-attr-d="{{dyno.path}}" fill="none" stroke="#ff6600" stroke-width="2.5"/>',
    '        </svg>',
    '        <div class="sg-dkey"><i style="background:#ff6600"></i>power<i style="background:#6fb7ff"></i>torque<span ng-if="dyno.base">dashed: before</span><span>0 &ndash; {{dyno.maxRPM}} rpm</span></div>',
    '        <div class="sg-btn sg-small" style="display:inline-block;margin:8px 0 0 0" ng-click="lua(\'pinDyno()\')">Pin this run as the "before"</div>',
    '      </div>',
    '      <div class="sg-grp">Saved builds</div>',
    '      <div class="sg-kv" ng-repeat="b in info.builds track by $index"><span class="sg-bname">{{b.name}}</span>',
    '        <b class="sg-bcost">{{b.toBuy ? b.toBuy + \' parts to buy, \' + money(b.cost) : \'all parts in hand\'}}</b>',
    '        <div class="sg-btn sg-small" ng-click="lua(\'loadBuild(\' + ($index + 1) + \')\')">Fit</div>',
    '        <div class="sg-btn sg-small" ng-click="lua(\'deleteBuild(\' + ($index + 1) + \')\')">&times;</div></div>',
    '      <div class="sg-note" ng-if="!info.builds.length">None yet. A build is the car as it stands now: its parts and its tuning. Fitting one later puts those parts back on, from the shelf where you still have them and bought where you do not.</div>',
    '      <div class="sg-buildrow"><input class="sg-search" type="text" maxlength="40" placeholder="Name this build" ng-model="build.name">',
    '        <div class="sg-btn sg-go" ng-click="saveBuild()">Save the car as it stands</div></div>',
    '    </div>',
    '  </div>',
    '</div>',

    /* job sheet */
    '<div class="sg-veil" ng-if="sheet && s.phase === \'garage\'" ng-mouseenter="overUi(true)">',
    '  <div class="sg-modal">',
    '    <div class="sg-dhead"><div class="sg-h">Job sheet</div><div class="sg-x" ng-click="closeSheet()" ng-bind-html="icon(\'close\')"></div></div>',
    '    <div class="sg-scrolly">',
    '      <div class="sg-grp" ng-if="sheet.fitted.length">Fitted ({{sheet.fitted.length}})</div>',
    '      <div class="sg-jline" ng-repeat="n in sheet.fitted track by $index">{{n}}</div>',
    '      <div class="sg-grp" ng-if="sheet.removed.length">Taken off ({{sheet.removed.length}})</div>',
    '      <div class="sg-jline" ng-repeat="n in sheet.removed track by $index">{{n}}</div>',
    '      <div class="sg-grp" ng-if="sheet.tuned || sheet.painted">Also</div>',
    '      <div class="sg-jline" ng-if="sheet.tuned">Adjustments changed</div>',
    '      <div class="sg-jline" ng-if="sheet.painted">Resprayed</div>',
    '      <div class="sg-grp">Money</div>',
    '      <div class="sg-kv"><span>{{sheet.net >= 0 ? \'Spent this visit\' : \'Made this visit\'}}</span><b>{{money(sheet.net >= 0 ? sheet.net : -sheet.net)}}</b></div>',
    '      <div class="sg-kv" ng-if="!sheet.unlimited"><span>In hand</span><b>{{money(sheet.money)}}</b></div>',
    '      <div class="sg-note" style="margin-top:10px" ng-if="sheet.missing">The car leaves without {{sheet.missing}}.</div>',
    '    </div>',
    '    <div class="sg-sheetbtns"><div class="sg-btn" ng-click="closeSheet()">Keep working</div><div class="sg-btn sg-go" ng-click="driveOut()">Drive out</div></div>',
    '  </div>',
    '</div>',

    /* body shells */
    '<div class="sg-veil" ng-if="s.phase === \'lot\'">',
    '  <div class="sg-modal sg-wide">',
    '    <div class="sg-lothead"><div class="sg-h">Body shells</div><input class="sg-search" type="text" placeholder="Search" ng-model="lot.search">',
    '      <div class="sg-cash">{{s.unlimited ? \'Unlimited\' : money(s.money)}}</div><div class="sg-btn" ng-click="lua(\'leaveLot()\')">Leave</div></div>',
    '    <div class="sg-note" style="margin-bottom:6px">You came on foot, so the lift is empty. Pick the bare body shell of any car and it is put on the lift for you to build up: everything else comes from the catalog.</div>',
    '    <div class="sg-scrolly">',
    '      <div class="sg-lotrow" ng-repeat="m in lotShown() track by m.key">',
    '        <img ng-if="m.preview" ng-src="{{m.preview}}" onerror="this.style.visibility=\'hidden\'">',
    '        <div class="sg-lotn"><span>{{m.brand}}</span><b>{{m.name}}</b></div>',
    '        <div class="sg-price">{{m.price > 0 ? money(m.price) : \'free\'}}</div>',
    '        <div class="sg-btn sg-go" ng-class="{\'sg-nope\': !s.unlimited && m.price > s.money}" ng-click="lua(\'buyShell(\' + quote(m.key) + \')\')">Buy</div>',
    '      </div>',
    '      <div class="sg-note" ng-if="!lotShown().length">{{lot.models.length ? \'No car matches that.\' : \'Looking through the cars you have installed...\'}}</div>',
    '    </div>',
    '  </div>',
    '</div>',

    /* work in progress */
    '<div class="sg-work" ng-if="work">{{work.what}}<div class="sg-workbar"><i ng-style="{\'transition-duration\': work.seconds + \'s\', width: work.go ? \'100%\' : \'0%\'}"></i></div></div>',

    /* settings */
    '<div class="sg-veil" ng-if="panel === \'settings\' && s.phase === \'garage\'" ng-mouseenter="overUi(true)">',
    '  <div class="sg-modal sg-wide">',
    '    <div class="sg-dhead"><div class="sg-h">Garage settings</div><div class="sg-x" ng-click="closePanel()" ng-bind-html="icon(\'close\')"></div></div>',
    '    <div class="sg-scrolly">',
    '      <div ng-repeat="g in settingGroups">',
    '        <div class="sg-grp">{{g.name}}</div>',
    '        <div class="sg-set" ng-repeat="d in g.defs track by d.key">',
    '          <div class="sg-st"><b>{{d.title}}</b><span>{{d.desc}}</span></div>',
    '          <div class="sg-sc" ng-if="d.type === \'bool\'"><div class="sg-tog" ng-class="{\'sg-on\': d.value}" ng-click="setSetting(d, !d.value)"></div></div>',
    '          <div class="sg-sc" ng-if="d.type === \'range\'"><input type="range" min="{{d.min}}" max="{{d.max}}" step="{{d.step}}" ng-model="d.value" ng-change="setSetting(d, d.value)"><div class="sg-sv">{{fix(d.value)}}{{d.unit}}</div></div>',
    '          <div class="sg-sc sg-choice" ng-if="d.type === \'choice\'"><div class="sg-chopt" ng-repeat="o in d.options track by o.id" ng-class="{\'sg-on\': d.value === o.id}" ng-click="setSetting(d, o.id)">{{o.label}}</div></div>',
    '          <div class="sg-sc" ng-if="d.type === \'number\'"><input type="number" min="{{d.min}}" max="{{d.max}}" step="{{d.step}}" ng-model="d.value" ng-change="setSetting(d, d.value)" ng-model-options="{debounce: 350}"></div>',
    '        </div>',
    '      </div>',
    '    </div>',
    '    <div class="sg-foot2"><div class="sg-note" style="flex:1" ng-if="setCareer">You are in career mode: money comes from your career account, not the freeroam budget.</div><div class="sg-note" style="flex:1" ng-if="!setCareer"></div><div class="sg-btn" ng-click="lua(\'setSetting(\\\'__reset\\\')\')">Reset to defaults</div></div>',
    '  </div>',
    '</div>',

    /* catalog */
    '<div class="sg-cat" ng-class="{\'sg-retro\': s.retro}" ng-if="s.phase === \'catalog\' || s.phase === \'shop\'">',
    '  <div class="sg-book">',
    '    <div class="sg-page-l">',
    '      <h1 class="sg-h">{{s.shop ? s.shop.name : \'Catalog\'}}</h1>',
    '      <div class="sg-for" ng-if="!s.shop">Parts for your {{s.car}}, delivered to the garage</div>',
    '      <div class="sg-for" ng-if="s.shop">{{s.shop.trade}} for your {{s.car}}. <span ng-if="!s.shop.yard">Over the counter: no delivery charge, no waiting<span ng-if="s.shop.discount > 0">, and {{s.shop.discount}}% off</span>.</span><span ng-if="s.shop.yard">Second-hand, sold as seen: far below list price and none of it straight. What is here changes from day to day.</span></div>',
    '      <div class="sg-scrolly">',
    '        <div ng-repeat="sec in cat.sections">',
    '          <div class="sg-sec sg-h" ng-class="{\'sg-act\': sec.id === cur.section}" ng-click="openSection(sec)"><span ng-bind-html="icon(sec.id)"></span>{{sec.title}}</div>',
    '          <div ng-if="sec.id === cur.section">',
    '            <div class="sg-sub-row" ng-repeat="sub in sec.subs" ng-class="{\'sg-act\': sub.id === cur.sub, \'sg-none\': !sub.items.length}" ng-click="openSub(sec, sub)">{{sub.title}}<i>{{sub.items.length}}</i></div>',
    '          </div>',
    '        </div>',
    '      </div>',
    '      <div class="sg-cart">',
    '        <div class="sg-carth">Shopping list<i ng-if="cart.items.length">{{cart.items.length}}</i></div>',
    '        <div class="sg-cartlist">',
    '          <div class="sg-cartrow" ng-repeat="c in cart.items track by $index" title="{{c.weight}} kg, {{c.size}} m: {{money(c.fee)}} to deliver">',
    '            <span class="sg-cartn">{{c.name}}</span><span class="sg-cartp">{{money(c.price)}}</span><span class="sg-cartx" ng-click="cartRemove($index)">&times;</span></div>',
    '          <div class="sg-carthint" ng-if="!cart.items.length">Nothing yet. &ldquo;Add&rdquo; puts a part on the list; you pay when you confirm.</div>',
    '        </div>',
    '        <div ng-if="cart.items.length">',
    '          <div class="sg-ship" ng-repeat="o in cart.shipping" ng-class="{\'sg-act\': o.id === ship.id}" ng-click="ship.id = o.id">',
    '            <span class="sg-dot"></span><span class="sg-shipt">{{o.title}}<small ng-if="o.seconds > 0">arrives in {{eta(o.seconds)}}</small></span><span class="sg-cartp">{{o.fee > 0 ? money(o.fee) : \'free\'}}</span></div>',
    '          <div class="sg-total">Total<b>{{money(shipOption().total)}}</b></div>',
    '          <div class="sg-cartbtns"><div class="sg-btn" ng-click="lua(\'cartClear()\')">Clear</div>',
    '            <div class="sg-btn sg-go" ng-class="{\'sg-nope\': shipOption().total > s.money}" ng-click="checkout()">Confirm purchase</div></div>',
    '        </div>',
    '        <div class="sg-onway" ng-if="cart.orders.length">On its way to the garage',
    '          <div class="sg-cartrow" ng-repeat="o in cart.orders track by $index"><span class="sg-cartn">{{o.name}}</span><span class="sg-cartp">{{eta(o.seconds)}}</span></div></div>',
    '      </div>',
    '      <div class="sg-wallet">{{s.career ? \'Career money\' : \'Money\'}}<b>{{s.unlimited ? \'Unlimited\' : money(s.money)}}</b></div>',
    '    </div>',
    '    <div class="sg-page-r">',
    '      <div class="sg-head"><div class="sg-h">{{searching() ? \'Search\' : (curSub() ? curSub().title : \'Choose a chapter\')}}</div><div class="sg-crumb" ng-if="curSec()">{{searching() ? \'All chapters\' : curSec().title}} &middot; {{shownItems().length}} parts</div>',
    '        <input class="sg-search" type="text" placeholder="Search all parts" ng-model="cur.search" ng-change="searchChanged()" ng-if="cat.sections.length">',
    '        <div class="sg-mini" ng-if="shownItems().length > 1" ng-click="cycleSort()">{{sortLabel()}}</div>',
    '        <div class="sg-mini" ng-class="{\'sg-on\': cur.cheap}" ng-click="cur.cheap = !cur.cheap; cur.page = 0" title="Affordable upgrades: parts under $1,500">Under $1,500</div>',
    '        <div class="sg-btn sg-go" ng-click="lua(\'closeCatalog()\')">{{s.shop ? \'Leave shop\' : \'Back to garage\'}}</div></div>',
    '      <div class="sg-chips" ng-if="!searching() && slotChips().length > 1">',
    '        <div class="sg-tab" ng-class="{\'sg-on\': !cur.slot}" ng-click="pickSlot(null)">All</div>',
    '        <div class="sg-tab" ng-repeat="c in slotChips() track by $index" ng-class="{\'sg-on\': cur.slot === c}" ng-click="pickSlot(c)">{{c}}</div>',
    '      </div>',
    '      <div class="sg-grid" ng-if="pageItems().length">',
    '        <div class="sg-card" ng-repeat="it in pageItems() track by it.slotPath + it.part">',
    '          <div class="sg-stage" ng-mouseenter="hoverStats(it)" ng-mouseleave="hoverStats(null)"><span class="sg-glyph" ng-bind-html="icon(curSec().id)"></span>',
    '            <div class="sg-stats" ng-if="statsFor === it.part && stats[it.part].length"><div class="sg-kv" ng-repeat="r in stats[it.part]"><span>{{r.label}}</span><b>{{r.value}}</b></div></div>',
    '            <div class="sg-prev" ng-if="hasModel(it.part)" data-part="{{it.part}}" data-id="c{{it.part}}" data-spin="always"></div>',
    '            <div class="sg-badges"><span class="sg-badge" ng-if="it.fitted">On the car</span><span class="sg-badge sg-new" ng-if="it.owned > 0">On the shelf &times;{{it.owned}}</span><span class="sg-badge sg-used" ng-if="it.used">Used &minus;{{it.used}}%</span></div>',
    '          </div>',
    '          <div class="sg-meta"><div class="sg-cslot">{{it.slot}}</div><div class="sg-cname" title="{{it.part}}">{{it.name}}</div>',
    '            <div class="sg-buyrow"><div class="sg-price">{{money(it.price)}}</div><div class="sg-btn sg-go" ng-click="buy(it)">Add</div></div></div>',
    '        </div>',
    '      </div>',
    '      <div class="sg-blank" ng-if="!pageItems().length && !cur.search">Pick a chapter on the left.<br>Everything you buy lands on the shelf in the garage,<br>ready to be fitted with one click.</div>',
    '      <div class="sg-blank" ng-if="!pageItems().length && cur.search">Nothing here matches &ldquo;{{cur.search}}&rdquo;.</div>',
    '      <div class="sg-foot" ng-if="pageCount() > 1">',
    '        <div class="sg-btn" ng-class="{\'sg-nope\': cur.page <= 0}" ng-click="turn(-1)">&#9664; Prev</div>',
    '        Page {{cur.page + 1}} of {{pageCount()}}',
    '        <div class="sg-btn" ng-class="{\'sg-nope\': cur.page >= pageCount() - 1}" ng-click="turn(1)">Next &#9654;</div>',
    '      </div>',
    '    </div>',
    '  </div>',
    '</div>',

    /* a part's own options */
    '<div class="sg-veil sg-cfg" ng-if="cfg && !cfg.waiting && (s.phase === \'catalog\' || s.phase === \'shop\')">',
    '  <div class="sg-modal sg-wide">',
    '    <div class="sg-dhead"><div><div class="sg-pslot" style="font-size:11px;letter-spacing:1px;color:#ffb380;text-transform:uppercase">{{cfg.item.slot}}</div><div class="sg-h">{{cfg.item.name}}</div></div><div class="sg-x" ng-click="cfgClose()" ng-bind-html="icon(\'close\')"></div></div>',
    '    <div class="sg-note">This part has options of its own. Choose them here and it arrives built that way, ready to fit in one go. Whatever you leave alone comes as standard.</div>',
    '    <div class="sg-scrolly">',
    '      <div class="sg-crow" ng-repeat="r in cfgRows() track by r.slot.path" ng-style="{\'margin-left\': (r.depth * 22) + \'px\'}">',
    '        <div class="sg-chead" ng-click="cfgToggle(r.slot)"><span>{{r.slot.title}}</span><b>{{cfgName(r.slot)}}</b><i>{{cfgCost(r.slot)}}</i><em>{{cfg.open === r.slot.path ? \'▴\' : \'▾\'}}</em></div>',
    '        <div class="sg-copts" ng-if="cfg.open === r.slot.path">',
    '          <div class="sg-copt" ng-if="!r.slot.core" ng-class="{\'sg-act\': !cfg.choice[r.slot.path]}" ng-click="cfgChoose(r.slot, null)"><span>None</span></div>',
    '          <div class="sg-copt" ng-repeat="o in r.slot.options track by o.part" ng-class="{\'sg-act\': cfg.choice[r.slot.path] === o.part}" ng-click="cfgChoose(r.slot, o)" title="{{o.part}}"><span>{{o.name}}</span><i>{{optCost(r.slot, o)}}</i></div>',
    '        </div>',
    '      </div>',
    '    </div>',
    '    <div class="sg-cfgfoot"><div class="sg-total">Total<b>{{money(cfgTotal())}}</b></div><div class="sg-btn" ng-click="cfgPlain()">Add as standard</div><div class="sg-btn sg-go" ng-click="cfgConfirm()">Add to list</div></div>',
    '  </div>',
    '</div>',

    '<div class="sg-contents" ng-if="contents" ng-style="{left: contents.x + \'px\', bottom: contents.b + \'px\'}">',
    '  <div class="sg-ctitle">Comes with the {{contents.name}}</div>',
    '  <div class="sg-cline" ng-repeat="n in contents.list track by $index">{{n}}</div>',
    '</div>',
    '<div class="sg-msg" ng-if="s.message">{{s.message}}</div>',
    '<div class="sg-fade" ng-class="{\'sg-in\': s.fade > 0.5}"></div>',
    '</div>'
  ].join('\n');

  // ---- part previews --------------------------------------------------------------------------
  // The turning parts in the catalog and on the shelf are real 3D objects that the game holds
  // in front of the camera. All the UI does is leave a hole where each one goes and tell the
  // game where the holes are.
  var noModel = {};              // part name -> true when the game has no model for it

  // cut see-through holes into `container` at the given screen rectangles
  function punch(container, rects) {
    if (!container) return;
    var value = '';
    if (rects.length) {
      var box = container.getBoundingClientRect();
      var w = Math.round(box.width), h = Math.round(box.height);
      var pts = ['0px 0px', w + 'px 0px', w + 'px ' + h + 'px', '0px ' + h + 'px', '0px 0px'];
      for (var i = 0; i < rects.length; i++) {
        var r = rects[i], x1 = Math.round(r.left - box.left), y1 = Math.round(r.top - box.top), x2 = Math.round(r.right - box.left), y2 = Math.round(r.bottom - box.top);
        pts.push(x1 + 'px ' + y1 + 'px', x2 + 'px ' + y1 + 'px', x2 + 'px ' + y2 + 'px', x1 + 'px ' + y2 + 'px', x1 + 'px ' + y1 + 'px', '0px 0px');
      }
      value = 'polygon(evenodd, ' + pts.join(', ') + ')';
    }
    if (container.__punch !== value) {
      container.__punch = value;
      container.style.clipPath = value;
      container.style.webkitClipPath = value;
    }
  }

  return {
    restrict: 'EA',
    replace: true,
    scope: true,
    template: TEMPLATE,
    controller: ['$scope', '$sce', '$element', function ($scope, $sce, $element) {
      $scope.s = { phase: 'idle', mode: 'mechanic', fade: 0, inventory: [], filters: {}, money: 0 };
      $scope.hover = {};
      $scope.cat = { sections: [], stamp: 0 };
      $scope.cur = { section: null, sub: null, page: 0 };
      $scope.line = 0;
      $scope.freshId = null;
      $scope.drag = { active: false };
      $scope.panel = null;
      $scope.tip = null;
      $scope.tune = { vars: [], categories: [], category: null, dirty: false };
      $scope.pt = { vars: [] };
      $scope.paint = { slot: 1, swatches: [], slots: [], cur: { baseColor: [1, 1, 1, 1], metallic: 0.5, roughness: 0.5, clearcoat: 1, clearcoatRoughness: 0.05 }, price: 0 };
      $scope.info = {};
      $scope.settingGroups = [];

      var icons = {};
      Object.keys(ICONS).forEach(function (k) { icons[k] = $sce.trustAsHtml(ICONS[k]); });
      $scope.icon = function (id) { return icons[id] || icons.body; };

      $scope.lua = function (call) { bngApi.engineLua('slrr_garage.' + call); };
      $scope.money = function (v) {
        v = Math.round(v || 0);
        return '$' + String(v).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
      };
      $scope.fix = function (v) { v = parseFloat(v); return isNaN(v) ? '' : (Math.round(v * 100) / 100); };

      // ---- panels
      $scope.openPanel = function (name) {
        if ($scope.panel === name) { $scope.closePanel(); return; }
        $scope.panel = name;
        if (name === 'tune') $scope.lua('requestTuning()');
        if (name === 'paint') $scope.lua('requestPaint()');
        if (name === 'info') $scope.lua('requestInfo()');
        if (name === 'settings') $scope.lua('requestSettings()');
      };
      $scope.closePanel = function () { $scope.panel = null; };

      // ---- SLRR's garage bar. Same order of ideas as the original: go places, look things up,
      //      work on the car, test it.
      $scope.bar = [
        { icon: 'drive', title: 'Drive out', desc: 'fit everything and hit the street', act: function () { $scope.closePanel(); $scope.lua('leave()'); } },
        { icon: 'catalog', title: 'Catalog', desc: 'order new parts', act: function () { $scope.closePanel(); $scope.lua('openCatalog()'); } },
        { icon: 'info', title: 'Car info', desc: 'details of this car', act: function () { $scope.openPanel('info'); }, on: function () { return $scope.panel === 'info'; } },
        { sep: true },
        { icon: 'wrench', title: 'Mechanic', desc: 'install and remove parts', act: function () { if ($scope.panel === 'tune') $scope.closePanel(); $scope.lua('setMode(\'mechanic\')'); }, on: function () { return $scope.s.mode === 'mechanic'; } },
        { icon: 'screwdriver', title: 'Tune', desc: 'every tuning item of the car on the right; or click a part to adjust it', act: function () {
          if ($scope.s.mode === 'tune' && $scope.panel === 'tune') { $scope.closePanel(); return; }       // (a second click puts the panel away; the mode stays)
          if ($scope.s.mode !== 'tune') $scope.lua('setMode(\'tune\')');
          $scope.panel = null;
          $scope.openPanel('tune');
        }, on: function () { return $scope.s.mode === 'tune'; } },
        { icon: 'lift', title: 'Lift', desc: 'raise or lower the car', act: function () { $scope.lua('toggleLift()'); }, on: function () { return $scope.s.lift; } },
        { icon: 'spray', title: 'Paint booth', desc: 'respray the car', act: function () { $scope.openPanel('paint'); }, on: function () { return $scope.panel === 'paint'; } },
        { icon: 'engine', title: 'Services', desc: 'oil, coolant, battery, nitrous, engine rebuild and repairs', act: function () { $scope.openPanel('services'); }, on: function () { return $scope.panel === 'services'; }, when: function () { return $scope.serviceGroups('services').length > 0; } },
        { icon: 'flag', title: 'Races', desc: 'pick a race or a track', act: function () { $scope.openPanel('races'); }, on: function () { return $scope.panel === 'races'; }, when: function () { return $scope.serviceGroups('races').length > 0; } },
        { icon: 'driver', title: 'Drivers', desc: 'who sits behind the wheel', act: function () { $scope.openPanel('drivers'); }, on: function () { return $scope.panel === 'drivers'; }, when: function () { return $scope.serviceGroups('drivers').length > 0; } },
        { sep: true },
        { icon: 'key', title: 'Test engine', desc: 'start or stop it where it stands', act: function () { $scope.lua('toggleEngine()'); }, on: function () { return $scope.s.engineOn; } },
        { icon: 'clock', title: 'Advance time', desc: 'move the clock on three hours', act: function () { $scope.lua('advanceTime()'); } },
        { icon: 'target', title: 'Whole car', desc: 'reset the camera', act: function () { $scope.lua('resetView()'); }, on: function () { return $scope.s.focused; } },
        { icon: 'gear', title: 'Settings', desc: 'money, prices, damage and more', act: function () { $scope.openPanel('settings'); }, on: function () { return $scope.panel === 'settings'; } }
      ];
      $scope.barVisible = function (b) { return !b.when || b.when(); };
      // the entries other mods offer, one list per top tab (an entry says which with `tab`; none: car servicing), grouped as their mod said
      $scope.svcTabs = { services: { title: 'Services' }, races: { title: 'Races' }, drivers: { title: 'Drivers' } };
      $scope.serviceGroups = function (tab) {
        var groups = [], byName = {};
        ($scope.s.services || []).forEach(function (sv) {
          if ((sv.tab || 'services') !== (tab || 'services')) return;
          var n = sv.group || 'Services';
          if (!byName[n]) { byName[n] = { name: n, items: [] }; groups.push(byName[n]); }
          byName[n].items.push(sv);
        });
        return groups;
      };
      $scope.tips = {
        repairPart: { title: 'Repair part', desc: 'then click the damaged part' },
        sell: { title: 'Sell part', desc: 'then click a part, on the car or on the shelf' }
      };
      $scope.repairAllTip = function () {
        return { title: 'Repair the whole car', desc: $scope.s.damaged ? ('costs ' + $scope.money($scope.s.repairAllCost)) : 'nothing is damaged' };
      };
      $scope.filterDefs = [
        { id: 'engine', tip: { title: 'Engine parts', desc: 'hide or show' } },
        { id: 'body', tip: { title: 'Body parts', desc: 'hide or show' } },
        { id: 'running', tip: { title: 'Running gear', desc: 'hide or show' } },
        { id: 'interior', tip: { title: 'Interior', desc: 'hide or show' } }
      ];

      // ---- what a click on the car would do
      $scope.canAct = function () {
        var h = $scope.hover;
        if (!h.name) return false;
        if ($scope.s.tool === 'repair') return !!h.damaged;
        if ($scope.s.tool === 'sell') return !!h.removable;
        if ($scope.s.mode === 'tune') return true;
        return !!h.removable;
      };
      $scope.hoverBlocked = function () { return !!$scope.hover.name && !$scope.canAct(); };
      $scope.hoverHint = function () {
        var h = $scope.hover;
        if ($scope.s.tool === 'repair') return h.damaged ? ('click to repair for ' + $scope.money(h.repairCost)) : 'not damaged';
        if ($scope.s.tool === 'sell') return h.removable ? ('click to take it off and sell it for ' + $scope.money(h.sellValue)) : (h.reason || 'cannot be removed');
        if ($scope.s.mode === 'tune') return 'click to pick and tune';
        return h.removable ? 'click to remove' : (h.reason || 'cannot be removed');
      };

      // ---- shelf
      $scope.lineCount = function () { return Math.max(1, Math.ceil(($scope.s.inventory || []).length / SLOTS_PER_LINE)); };
      $scope.visibleSlots = function () {
        var inv = $scope.s.inventory || [], out = [], start = $scope.line * SLOTS_PER_LINE;
        for (var i = 0; i < SLOTS_PER_LINE; i++) out.push(inv[start + i] || null);
        return out;
      };
      $scope.scroll = function (d) { $scope.line = Math.max(0, Math.min($scope.lineCount() - 1, $scope.line + d)); wantPreviews(); };
      $scope.sellAllTip = function () { return { title: 'Sell everything on the shelf', desc: $scope.s.inventory.length ? 'for ' + $scope.money($scope.s.shelfValue) + ' (asks first)' : 'the shelf is empty' }; };
      // parts that were bought and have not been on the car yet
      $scope.boughtCount = function () {
        var inv = $scope.s.inventory || [], n = 0;
        for (var i = 0; i < inv.length; i++) if (inv[i].new || inv[i].used) n++;
        return n;
      };
      $scope.install = function (item) { $scope.contents = null; $scope.lua('install(' + item.id + ')'); };
      // the list behind a "+3 parts" badge
      $scope.contents = null;
      $scope.showContents = function (slot, ev) {
        ev.stopPropagation();
        if ($scope.contents && $scope.contents.id === slot.id) { $scope.contents = null; return; }
        var r = ev.currentTarget.getBoundingClientRect();
        $scope.contents = { id: slot.id, name: slot.name, list: slot.contents || [], x: Math.round(r.left), b: Math.round(window.innerHeight - r.top + 6) };
      };

      // ---- catalog
      $scope.curSec = function () {
        for (var i = 0; i < $scope.cat.sections.length; i++) if ($scope.cat.sections[i].id === $scope.cur.section) return $scope.cat.sections[i];
        return null;
      };
      $scope.curSub = function () {
        var sec = $scope.curSec();
        if (!sec) return null;
        for (var i = 0; i < sec.subs.length; i++) if (sec.subs[i].id === $scope.cur.sub) return sec.subs[i];
        return null;
      };
      // What the right-hand page shows: the open chapter, or - once something is typed in the
      // search box - every part in the book that matches, whatever chapter it is in.
      var CHEAP_PART = 1500;
      var SORTS = [null, 'up', 'down'], SORT_LABELS = { 'null': 'By slot', up: 'Cheapest first', down: 'Dearest first' };
      $scope.cur.sort = null;
      $scope.sortLabel = function () { return SORT_LABELS[String($scope.cur.sort)]; };
      $scope.cycleSort = function () { $scope.cur.sort = SORTS[(SORTS.indexOf($scope.cur.sort) + 1) % SORTS.length]; $scope.cur.page = 0; };
      $scope.searching = function () { return !!($scope.cur.search || '').trim(); };
      var shownKey = null, shownList = [];
      $scope.shownItems = function () {
        var sub = $scope.curSub();
        var q = ($scope.cur.search || '').toLowerCase().trim();
        if (!q && !sub) return [];
        var key = (q ? '*' : $scope.cur.section + '/' + $scope.cur.sub + '/' + ($scope.cur.slot || '')) + '/' + q + '/' + $scope.cur.sort + '/' + !!$scope.cur.cheap + '/' + $scope.cat.stamp;
        if (key !== shownKey) {
          shownKey = key;
          var list = [];
          if (!q) list = $scope.cur.slot ? sub.items.filter(function (it) { return it.slot === $scope.cur.slot; }) : sub.items;
          else {
            var words = q.split(/\s+/);
            $scope.cat.sections.forEach(function (sec) {
              sec.subs.forEach(function (chapter) {
                chapter.items.forEach(function (it) {
                  var text = (it.name + ' ' + it.slot + ' ' + it.part).toLowerCase();
                  for (var i = 0; i < words.length; i++) if (text.indexOf(words[i]) < 0) return;
                  list.push(it);
                });
              });
            });
          }
          // affordable upgrades: what a first part from a few jobs' pay buys
          if ($scope.cur.cheap) list = list.filter(function (it) { return it.price > 0 && it.price <= CHEAP_PART; });
          if ($scope.cur.sort) {
            var dir = $scope.cur.sort === 'up' ? 1 : -1;
            list = list.slice().sort(function (a, b) { return dir * (a.price - b.price) || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0); });
          }
          shownList = list;
        }
        return shownList;
      };
      // A chapter that holds parts for several slots (front wheel diameter, front wheel width, ...)
      // gets one filter per slot, named the way the car - or the mod - names them.
      var chipsKey = null, chips = [];
      $scope.slotChips = function () {
        var sub = $scope.curSub();
        if (!sub) return [];
        var key = $scope.cur.section + '/' + $scope.cur.sub + '/' + $scope.cat.stamp;
        if (key !== chipsKey) {
          chipsKey = key; chips = [];
          sub.items.forEach(function (it) { if (chips.indexOf(it.slot) < 0) chips.push(it.slot); });
          chips.sort();
          if ($scope.cur.slot && chips.indexOf($scope.cur.slot) < 0) $scope.cur.slot = null;
        }
        return chips;
      };
      $scope.pickSlot = function (name) { $scope.cur.slot = name; $scope.cur.page = 0; };
      $scope.pageCount = function () { var n = $scope.shownItems().length; return ($scope.curSub() || $scope.searching()) ? Math.max(1, Math.ceil(n / CATALOG_PER_PAGE)) : 0; };
      $scope.pageItems = function () {
        return $scope.shownItems().slice($scope.cur.page * CATALOG_PER_PAGE, ($scope.cur.page + 1) * CATALOG_PER_PAGE);
      };
      $scope.searchChanged = function () { $scope.cur.page = 0; wantPreviews(); };
      $scope.openSection = function (sec) {
        $scope.cur.section = sec.id; $scope.cur.page = 0; $scope.cur.sub = null; $scope.cur.search = ''; $scope.cur.slot = null;
        for (var i = 0; i < sec.subs.length; i++) if (sec.subs[i].items.length) { $scope.cur.sub = sec.subs[i].id; break; }
        $scope.lua('uiSound("mnuselect.wav")'); wantPreviews();
      };
      $scope.openSub = function (sec, sub) { $scope.cur.section = sec.id; $scope.cur.sub = sub.id; $scope.cur.page = 0; $scope.cur.search = ''; $scope.cur.slot = null; $scope.lua('uiSound("flip.wav")'); wantPreviews(); };
      $scope.turn = function (d) {
        var page = Math.max(0, Math.min($scope.pageCount() - 1, $scope.cur.page + d));
        if (page === $scope.cur.page) return;
        $scope.cur.page = page; $scope.lua('uiSound("flip.wav")'); wantPreviews();
      };
      function addPlain(it) { $scope.lua('buy(' + JSON.stringify(it.slotPath) + ',' + JSON.stringify(it.part) + ')'); }
      $scope.buy = function (it) {
        // a part with slots of its own may have options to choose first (the yard sells as seen)
        if (!it.more || it.used) { addPlain(it); return; }
        $scope.cfg = { item: it, root: it.slotPath + it.part, slots: {}, asked: {}, choice: {}, open: null, waiting: true, version: 0 };
        askSlots(it.slotPath, it.part);
      };

      // ---- choosing a part's own options before buying it.
      // cfg.slots holds, per part ("slot path" + "part name"), the slots Lua says it has; cfg.choice
      // holds what is picked for each slot path. The rows on screen are the tree of those, flattened.
      $scope.cfg = null;
      function askSlots(slotPath, part) {
        var key = slotPath + part;
        if ($scope.cfg.asked[key]) return;
        $scope.cfg.asked[key] = true;
        $scope.lua('requestSlots(' + JSON.stringify(slotPath) + ',' + JSON.stringify(part) + ')');
      }
      function optionOf(slot, part) {
        for (var i = 0; i < slot.options.length; i++) if (slot.options[i].part === part) return slot.options[i];
        return null;
      }
      $scope.$on('slrrGarageSlots', function (ev, data) {
        $scope.$evalAsync(function () {
          var cfg = $scope.cfg;
          if (!cfg || !data || !cfg.asked[data.key]) return;
          var slots = Array.isArray(data.slots) ? data.slots : [];
          slots.forEach(function (slot) { if (!Array.isArray(slot.options)) slot.options = []; });
          cfg.slots[data.key] = slots;
          cfg.version++;
          if (data.key === cfg.root) {
            cfg.waiting = false;
            if (!slots.length) { addPlain(cfg.item); $scope.cfg = null; return; }     // nothing to choose after all
          }
          slots.forEach(function (slot) {
            if (cfg.choice[slot.path] === undefined) cfg.choice[slot.path] = slot.default || '';
            // what it comes with may have options of its own: show those too, no guessing
            var o = optionOf(slot, cfg.choice[slot.path]);
            if (o && o.more) askSlots(slot.path, o.part);
          });
        });
      });
      var rowsVersion = -1, rowsOf = null, rows = [];
      $scope.cfgRows = function () {
        var cfg = $scope.cfg;
        if (!cfg) return [];
        if (rowsOf !== cfg || rowsVersion !== cfg.version) {
          rowsOf = cfg; rowsVersion = cfg.version; rows = [];
          (function walk(key, depth) {
            (cfg.slots[key] || []).forEach(function (slot) {
              if (rows.length >= 80) return;
              rows.push({ slot: slot, depth: depth });
              var o = optionOf(slot, cfg.choice[slot.path]);
              if (o && o.more && depth < 6) walk(slot.path + o.part, depth + 1);
            });
          })(cfg.root, 0);
        }
        return rows;
      };
      $scope.optCost = function (slot, o) { return o.price > 0 ? '+' + $scope.money(o.price) : (o.part === slot.default ? 'standard' : 'free'); };
      $scope.cfgName = function (slot) { var o = optionOf(slot, $scope.cfg.choice[slot.path]); return o ? o.name : 'None'; };
      $scope.cfgCost = function (slot) { var o = optionOf(slot, $scope.cfg.choice[slot.path]); return o ? $scope.optCost(slot, o) : ''; };
      $scope.cfgToggle = function (slot) { $scope.cfg.open = $scope.cfg.open === slot.path ? null : slot.path; };
      $scope.cfgChoose = function (slot, o) {
        var cfg = $scope.cfg;
        cfg.choice[slot.path] = o ? o.part : '';
        cfg.open = null;
        cfg.version++;
        if (o && o.more) askSlots(slot.path, o.part);
        $scope.lua('uiSound("mnuselect.wav")');
      };
      $scope.cfgTotal = function () {
        var cfg = $scope.cfg, total = cfg.item.price;
        $scope.cfgRows().forEach(function (r) { var o = optionOf(r.slot, cfg.choice[r.slot.path]); if (o) total += o.price; });
        return total;
      };
      $scope.cfgClose = function () { $scope.cfg = null; };
      $scope.cfgPlain = function () { addPlain($scope.cfg.item); $scope.cfg = null; };
      $scope.cfgConfirm = function () {
        var cfg = $scope.cfg;
        // only what is on screen is sent: the choice for each slot, and below it the choices for that part's slots
        var sub = (function collect(key, depth) {
          var out = {};
          (cfg.slots[key] || []).forEach(function (slot) {
            var part = cfg.choice[slot.path] || '', o = optionOf(slot, part);
            out[slot.id] = { part: o ? part : '', sub: (o && o.more && depth < 6) ? collect(slot.path + part, depth + 1) : {} };
          });
          return out;
        })(cfg.root, 0);
        bngApi.engineLua('slrr_garage.buy(' + JSON.stringify(cfg.item.slotPath) + ',' + JSON.stringify(cfg.item.part) + ',' + bngApi.serializeToLua(sub) + ')');
        $scope.cfg = null;
      };

      // ---- shopping list
      $scope.cart = { items: [], shipping: [], orders: [] };
      $scope.ship = { id: null };
      $scope.shipOption = function () {
        var list = $scope.cart.shipping;
        for (var i = 0; i < list.length; i++) if (list[i].id === $scope.ship.id) return list[i];
        return list[0] || { total: 0, fee: 0 };
      };
      $scope.eta = function (seconds) {
        seconds = Math.max(0, Math.round(seconds));
        return seconds >= 60 ? Math.floor(seconds / 60) + ':' + ('0' + (seconds % 60)).slice(-2) + ' min' : seconds + ' s';
      };
      $scope.cartRemove = function (index) { $scope.lua('cartRemove(' + (index + 1) + ')'); };
      $scope.checkout = function () { $scope.lua('checkout(' + JSON.stringify($scope.shipOption().id || '') + ')'); };
      $scope.$on('slrrGarageCart', function (ev, data) {
        $scope.$evalAsync(function () {
          data = data || {};
          ['items', 'shipping', 'orders'].forEach(function (k) { if (!Array.isArray(data[k])) data[k] = []; });
          $scope.cart = data;
          var known = false;
          for (var i = 0; i < data.shipping.length; i++) if (data.shipping[i].id === $scope.ship.id) known = true;
          if (!known) $scope.ship.id = data.shipping.length ? data.shipping[0].id : null;
        });
      });
      // parts on their way count down while the catalog is open
      var cartTick = window.setInterval(function () {
        if (($scope.s.phase === 'catalog' || $scope.s.phase === 'shop') && $scope.cart.orders.length) $scope.lua('requestCart()');
      }, 1000);

      // ---- previews: tell the game where the holes for the 3D parts are
      $scope.hasModel = function (part) { return !!$scope.s.previews && !noModel[part]; };
      function wantPreviews() {}     // the frame loop below notices changes by itself
      $scope.$on('slrrGaragePreview', function (ev, data) {
        if (!data || !data.part || !data.none) return;
        $scope.$evalAsync(function () { noModel[data.part] = true; });
      });

      var rootEl = $element[0];
      var rafId = null, sentSlots = '', mouseX = -1, mouseY = -1, holes = [];
      var live = {};                 // preview id -> true while its model is in place behind the UI
      var heldDrag = null;           // camera drag waiting for the previews to be put away
      // hovering a part in the catalog: what it does (power, rpm, strength for an engine; spring rate, grip, weight...), asked from its jbeam once per part
      $scope.stats = {};
      $scope.statsFor = null;
      var statsAsked = {};
      $scope.hoverStats = function (it) {
        $scope.statsFor = it ? it.part : null;
        if (it && !statsAsked[it.part]) { statsAsked[it.part] = true; $scope.lua('requestPartStats(' + $scope.quote(it.part) + ')'); }
      };
      $scope.$on('slrrGaragePartStats', function (ev, data) {
        $scope.$evalAsync(function () { if (data && data.part) $scope.stats[data.part] = Array.isArray(data.rows) ? data.rows : []; });
      });
      $scope.$on('slrrGaragePreviewLive', function (ev, data) {
        live = {};
        var ids = (data && data.ids) || [];
        if (Array.isArray(ids)) for (var i = 0; i < ids.length; i++) live[ids[i]] = true;
      });
      // the camera is about to move: close the holes now, the models cannot keep up with it
      function parkPreviews() {
        var any = false;
        for (var id in live) { any = true; break; }
        live = {};
        bngApi.engineLua('slrr_garage.parkPreviews()');
        return any;
      }
      function holeAt(x, y) {
        for (var i = 0; i < holes.length; i++) {
          var r = holes[i].rect;
          if (x >= r.left && x <= r.right && y >= r.top && y <= r.bottom) return holes[i];
        }
        return null;
      }
      function frame() {
        rafId = window.requestAnimationFrame(frame);
        var phase = $scope.s.phase, on = $scope.s.previews && (phase === 'garage' || phase === 'catalog' || phase === 'busy' || phase === 'shop');
        var els = on ? rootEl.querySelectorAll('.sg-prev') : [];
        var W = window.innerWidth || 1, H = window.innerHeight || 1;
        var list = [], shelfRects = [], bookRects = [], key = '';
        holes = [];
        for (var i = 0; i < els.length; i++) {
          var el = els[i], r = el.getBoundingClientRect();
          if (r.width < 8 || r.height < 8) continue;
          var inBook = el.getAttribute('data-spin') === 'always';
          // on the shelf the catalog covers the parts, so they are put away while it is open
          if (!inBook && phase === 'catalog') continue;
          var id = el.getAttribute('data-id'), open = !!live[id];
          if (el.parentElement && el.__open !== open) { el.__open = open; el.parentElement.classList.toggle('sg-open', open); }
          if (open) {
            holes.push({ el: el, rect: r });
            (inBook ? bookRects : shelfRects).push(r);
          }
          var spin = inBook || (mouseX >= r.left && mouseX <= r.right && mouseY >= r.top && mouseY <= r.bottom);
          var entry = { id: id, part: el.getAttribute('data-part'), x: r.left / W, y: r.top / H, w: r.width / W, h: r.height / H, spin: spin, card: inBook ? 'book' : 'shelf' };
          list.push(entry);
          key += entry.id + ':' + Math.round(r.left) + ',' + Math.round(r.top) + ',' + Math.round(r.width) + ',' + Math.round(r.height) + (spin ? 's' : '') + ';';
        }
        punch(rootEl.querySelector('.sg-shelf'), shelfRects);
        punch(rootEl.querySelector('.sg-cat'), bookRects);
        if (key !== sentSlots) {
          sentSlots = key;
          bngApi.engineLua('slrr_garage.setPreviewSlots(' + bngApi.serializeToLua(list) + ')');
        }
        // a held camera drag goes ahead once the closed holes have been on screen for a frame
        if (heldDrag && --heldDrag.frames <= 0) {
          var held = heldDrag; heldDrag = null;
          if (held.dx || held.dy) bngApi.engineLua('slrr_garage.cameraDrag(' + held.dx + ',' + held.dy + ')');
          if (held.zoom) bngApi.engineLua('slrr_garage.cameraZoom(' + held.zoom + ')');
        }
      }
      rafId = window.requestAnimationFrame(frame);

      // ---- the cloud of spray that hides the car while it changes colour
      $scope.$on('slrrGaragePaintFx', function (ev, data) {
        if (!data || !Array.isArray(data.color) || !data.rect) return;
        var W = window.innerWidth, H = window.innerHeight, r = data.rect;
        function ch(v) { return Math.round(255 * Math.max(0, Math.min(1, Math.pow(parseFloat(v) || 0, 1 / 2.2)))); }
        var rgb = ch(data.color[0]) + ',' + ch(data.color[1]) + ',' + ch(data.color[2]);
        var box = document.createElement('div');
        box.className = 'sg-smoke';
        var bw = r.w * W * 1.5, bh = r.h * H * 1.6;
        box.style.left = ((r.x + r.w / 2) * W - bw / 2) + 'px';
        box.style.top = ((r.y + r.h / 2) * H - bh / 2) + 'px';
        box.style.width = bw + 'px';
        box.style.height = bh + 'px';
        for (var i = 0; i < 22; i++) {
          var puff = document.createElement('div');
          puff.className = 'sg-puff';
          var size = bh * (0.55 + Math.random() * 0.5);
          puff.style.width = size + 'px';
          puff.style.height = size + 'px';
          puff.style.left = (Math.random() * (bw - size * 0.6) - size * 0.2) + 'px';
          puff.style.top = (Math.random() * (bh - size * 0.7) - size * 0.15) + 'px';
          puff.style.background = 'radial-gradient(circle, rgba(' + rgb + ',1) 0%, rgba(' + rgb + ',.93) 38%, rgba(' + rgb + ',0) 70%)';
          puff.style.animationDelay = (Math.random() * 0.28) + 's';
          box.appendChild(puff);
        }
        rootEl.appendChild(box);
        window.setTimeout(function () { if (box.parentNode) box.parentNode.removeChild(box); }, 2800);
      });

      // ---- tuning
      $scope.shown = function (v) {
        var span = (v.max - v.min) || 1, f = (parseFloat(v.value) - v.min) / span;
        var d = v.minDis + f * (v.maxDis - v.minDis);
        var step = Math.abs(v.stepDis || 0.01), digits = step >= 1 ? 0 : (step >= 0.1 ? 1 : (step >= 0.01 ? 2 : 3));
        return d.toFixed(digits);
      };
      $scope.tuneChanged = function () { $scope.tune.dirty = true; };
      $scope.applyTune = function () {
        var out = {};
        $scope.tune.vars.forEach(function (v) { out[v.name] = parseFloat(v.value); });
        $scope.tune.dirty = false;
        bngApi.engineLua('slrr_garage.applyTuning(' + bngApi.serializeToLua(out) + ')');
      };
      function prepVar(v) { v.lo = Math.min(v.min, v.max); v.hi = Math.max(v.min, v.max); v.step = Math.abs(v.step) || ((v.hi - v.lo) / 100); return v; }
      $scope.applyPartTune = function () {
        var out = {};
        $scope.pt.vars.forEach(function (v) { out[v.name] = parseFloat(v.value); });
        $scope.pt.dirty = false;
        bngApi.engineLua('slrr_garage.applyTuning(' + bngApi.serializeToLua(out) + ')');
      };
      $scope.$on('slrrGarageTunePart', function (ev, data) {
        $scope.$evalAsync(function () {
          data = (data && !Array.isArray(data)) ? data : {};
          data.vars = Array.isArray(data.vars) ? data.vars.map(prepVar) : [];
          data.dirty = false;
          $scope.pt = data;
        });
      });
      // the tuning items as the stock tuning menu groups them: by category, then sub-category. One category tab shows its own groups, All shows every
      // item of the car under category / sub-category headings. Cached: a new list every digest would never settle.
      var groupsFor = null, groupsList = [];
      $scope.tuneGroups = function () {
        var t = $scope.tune;
        if (groupsFor && groupsFor.t === t && groupsFor.c === t.category) return groupsList;
        groupsFor = { t: t, c: t.category };
        var byKey = {};
        groupsList = [];
        t.vars.forEach(function (v) {
          if (t.category && v.category !== t.category) return;
          var key = (t.category ? '' : (v.category || '') + '|') + (v.subCategory || '');
          var g = byKey[key];
          if (!g) {
            var name = t.category ? (v.subCategory || '') : ((v.category || '') + (v.subCategory ? ' / ' + v.subCategory : ''));
            g = byKey[key] = { key: key, name: name, vars: [] };
            groupsList.push(g);
          }
          g.vars.push(v);
        });
        return groupsList;
      };
      $scope.$on('slrrGarageTuning', function (ev, data) {
        $scope.$evalAsync(function () {
          var vars = (data && Array.isArray(data.vars)) ? data.vars : [];
          var cats = [];
          vars.forEach(function (v) {
            v.lo = Math.min(v.min, v.max); v.hi = Math.max(v.min, v.max); v.step = Math.abs(v.step) || ((v.hi - v.lo) / 100);
            if (cats.indexOf(v.category) < 0) cats.push(v.category);
          });
          var keep = (data && data.category) || $scope.tune.category;
          $scope.tune = { vars: vars, categories: cats, category: cats.indexOf(keep) >= 0 ? keep : null, dirty: false };       // (null: every item, all categories)
        });
      });

      // ---- paint
      $scope.paintChannels = [
        { title: 'Red', key: 'baseColor', idx: 0 }, { title: 'Green', key: 'baseColor', idx: 1 }, { title: 'Blue', key: 'baseColor', idx: 2 },
        { title: 'Metallic', key: 'metallic' }, { title: 'Roughness', key: 'roughness' }, { title: 'Clearcoat', key: 'clearcoat' }
      ];
      $scope.pct = function (ch) { var v = ch.idx !== undefined ? $scope.paint.cur[ch.key][ch.idx] : $scope.paint.cur[ch.key]; return Math.round(parseFloat(v) * 100); };
      $scope.css = function (p) {
        if (!p || !p.baseColor) return '#888';
        var c = p.baseColor, f = function (x) { return Math.round(Math.max(0, Math.min(1, Math.pow(parseFloat(x) || 0, 1 / 2.2))) * 255); };
        return 'rgb(' + f(c[0]) + ',' + f(c[1]) + ',' + f(c[2]) + ')';
      };
      function copyPaint(p) {
        p = p || {};
        var c = Array.isArray(p.baseColor) ? p.baseColor : [1, 1, 1, 1];
        return { baseColor: [+c[0] || 0, +c[1] || 0, +c[2] || 0, c[3] === undefined ? 1 : +c[3]], metallic: p.metallic === undefined ? 0.5 : +p.metallic,
          roughness: p.roughness === undefined ? 0.5 : +p.roughness, clearcoat: p.clearcoat === undefined ? 1 : +p.clearcoat,
          clearcoatRoughness: p.clearcoatRoughness === undefined ? 0.05 : +p.clearcoatRoughness };
      }
      $scope.pickPaintSlot = function (n) { $scope.paint.slot = n; $scope.paint.cur = copyPaint($scope.paint.slots[n - 1] || $scope.paint.slots[0]); };
      $scope.useSwatch = function (sw) { $scope.paint.cur = copyPaint(sw.paint); };
      $scope.spray = function () {
        var p = copyPaint($scope.paint.cur);
        bngApi.engineLua('slrr_garage.setPaint(' + $scope.paint.slot + ',' + bngApi.serializeToLua(p) + ')');
      };
      $scope.$on('slrrGaragePaint', function (ev, data) {
        $scope.$evalAsync(function () {
          data = data || {};
          $scope.paint.slots = Array.isArray(data.slots) ? data.slots : [];
          $scope.paint.swatches = Array.isArray(data.swatches) ? data.swatches : [];
          $scope.paint.price = data.price || 0;
          $scope.paint.cur = copyPaint($scope.paint.slots[$scope.paint.slot - 1] || $scope.paint.slots[0]);
        });
      });

      // ---- info + settings
      $scope.$on('slrrGarageInfo', function (ev, data) {
        $scope.$evalAsync(function () {
          data = data || {};
          if (!Array.isArray(data.rows)) data.rows = [];
          if (!Array.isArray(data.builds)) data.builds = [];
          $scope.info = data;
        });
      });

      // ---- saved builds
      $scope.build = { name: '' };
      $scope.saveBuild = function () { $scope.lua('saveBuild(' + JSON.stringify($scope.build.name || '') + ')'); $scope.build.name = ''; };

      // ---- the engine's power curve, drawn into a 560 x 190 box
      $scope.dyno = {};
      $scope.$on('slrrGarageDyno', function (ev, data) {
        $scope.$evalAsync(function () {
          if (!data || !Array.isArray(data.power) || data.power.length < 3) { $scope.dyno = {}; return; }
          var W = 560, H = 190, n = data.power.length;
          var b = data.baseline && Array.isArray(data.baseline.power) && data.baseline.power.length > 2 ? data.baseline : null;
          var maxRPM = Math.max(data.maxRPM || 1, b ? b.maxRPM || 1 : 1);
          var top = Math.max(1, Math.max.apply(null, data.power), Math.max.apply(null, data.torque),
            b ? Math.max.apply(null, b.power) : 0, b ? Math.max.apply(null, b.torque) : 0) * 1.08;
          // a curve on the common rpm scale (the "before" may rev to another limit): points every `step` rpm
          function line(values, curveMax) {
            var d = '', m = values.length;
            for (var i = 0; i < m; i++) d += (i ? 'L' : 'M') + (i / (m - 1) * (curveMax || maxRPM) / maxRPM * W).toFixed(1) + ' ' + (H - Math.max(0, values[i]) / top * H).toFixed(1);
            return d;
          }
          var grid = '';
          for (var g = 1; g < 4; g++) grid += 'M0 ' + (H * g / 4) + 'H' + W;
          for (var rpm = 1000; rpm < maxRPM; rpm += 1000) grid += 'M' + (rpm / maxRPM * W).toFixed(1) + ' 0V' + H;
          $scope.dyno = {
            path: line(data.power, data.maxRPM), torquePath: line(data.torque, data.maxRPM), grid: grid, maxRPM: maxRPM,
            base: !!b, basePath: b ? line(b.power, b.maxRPM) : '', baseTorquePath: b ? line(b.torque, b.maxRPM) : '',
            dPower: b ? Math.round(data.maxPower - b.maxPower) : 0, dTorque: b ? Math.round(data.maxTorque - b.maxTorque) : 0,
            maxPower: Math.round(data.maxPower), maxTorque: Math.round(data.maxTorque),
            maxPowerRPM: Math.round((data.maxPowerRPM || 0) / 50) * 50, maxTorqueRPM: Math.round((data.maxTorqueRPM || 0) / 50) * 50
          };
        });
      });

      // ---- body shells: what a visit on foot can start from
      $scope.lot = { models: [], search: '' };
      $scope.quote = function (text) { return JSON.stringify(String(text)); };
      $scope.$on('slrrGarageLot', function (ev, data) {
        $scope.$evalAsync(function () { $scope.lot.models = (data && Array.isArray(data.models)) ? data.models : []; });
      });
      var lotKey = null, lotOf = null, lotList = [];
      $scope.lotShown = function () {
        var q = ($scope.lot.search || '').toLowerCase().trim();
        if (q !== lotKey || lotOf !== $scope.lot.models) {
          lotKey = q; lotOf = $scope.lot.models;
          var words = q ? q.split(/\s+/) : [];
          lotList = lotOf.filter(function (m) {
            var text = (m.brand + ' ' + m.name + ' ' + m.key).toLowerCase();
            for (var i = 0; i < words.length; i++) if (text.indexOf(words[i]) < 0) return false;
            return true;
          });
        }
        return lotList;
      };

      // ---- job sheet, shown before driving out
      $scope.sheet = null;
      $scope.closeSheet = function () { $scope.sheet = null; };
      $scope.driveOut = function () { $scope.sheet = null; $scope.lua('leave(true)'); };
      $scope.$on('slrrGarageJobSheet', function (ev, data) {
        $scope.$evalAsync(function () {
          data = data || {};
          ['fitted', 'removed'].forEach(function (k) { if (!Array.isArray(data[k])) data[k] = []; });
          $scope.panel = null;
          $scope.sheet = data;
        });
      });

      // ---- work that takes time
      $scope.work = null;
      $scope.$on('slrrGarageWork', function (ev, data) {
        $scope.$evalAsync(function () {
          if (!data || !data.seconds) { $scope.work = null; return; }
          $scope.work = { what: data.what, seconds: data.seconds, go: false };
          window.setTimeout(function () { $scope.$evalAsync(function () { if ($scope.work) $scope.work.go = true; }); }, 40);
        });
      });
      $scope.$on('slrrGarageSettings', function (ev, data) {
        $scope.$evalAsync(function () {
          var defs = (data && Array.isArray(data.defs)) ? data.defs : [], groups = [], byName = {};
          defs.forEach(function (d) {
            if (!byName[d.group]) { byName[d.group] = { name: d.group, defs: [] }; groups.push(byName[d.group]); }
            byName[d.group].defs.push(d);
          });
          $scope.settingGroups = groups;
          $scope.setCareer = !!(data && data.career);
        });
      });
      $scope.setSetting = function (d, value) {
        if (d.type !== 'bool' && d.type !== 'choice') { value = parseFloat(value); if (isNaN(value)) return; }
        d.value = value;
        var lua = d.type === 'bool' ? (value ? 'true' : 'false') : d.type === 'choice' ? JSON.stringify(String(value)) : value;
        bngApi.engineLua('slrr_garage.setSetting(' + JSON.stringify(d.key) + ',' + lua + ')');
      };

      // ---- 3D view input: left click acts, right drag orbits, wheel zooms, middle click focuses
      $scope.overUi = function (over) { $scope.lua('setMouseOverUi(' + (over ? 'true' : 'false') + ')'); };
      var down = null;
      $scope.viewDown = function (ev) {
        ev.preventDefault();
        down = { button: ev.button, x: ev.clientX, y: ev.clientY, lastX: ev.clientX, lastY: ev.clientY, moved: 0 };
        $scope.contents = null;
        if (ev.button === 2) {
          $scope.drag.active = true; $scope.lua('setDragging(true)');
          if (parkPreviews()) heldDrag = { frames: 2, dx: 0, dy: 0, zoom: 0 };
        }
      };
      // Lua picks the part under the cursor itself; it only needs to know whether the cursor is
      // on the 3D view or on one of our panels. Worked out from every mouse move, so it can
      // never get stuck the wrong way round.
      var lastOverView = null;
      function trackOver(ev) {
        var t = ev.target;
        var overView = !!(t && t.classList && t.classList.contains('sg-view')) && !holeAt(ev.clientX, ev.clientY);
        if (overView !== lastOverView) {
          lastOverView = overView;
          bngApi.engineLua('slrr_garage.setMouseOverUi(' + (overView ? 'false' : 'true') + ')');
        }
      }
      function onMove(ev) {
        mouseX = ev.clientX; mouseY = ev.clientY;
        if ($scope.s.phase === 'garage') trackOver(ev); else lastOverView = null;
        if (!down) return;
        var dx = ev.clientX - down.lastX, dy = ev.clientY - down.lastY;
        down.lastX = ev.clientX; down.lastY = ev.clientY;
        down.moved += Math.abs(dx) + Math.abs(dy);
        if (down.button === 2 && (dx || dy)) {
          if (heldDrag) { heldDrag.dx += dx; heldDrag.dy += dy; }
          else bngApi.engineLua('slrr_garage.cameraDrag(' + dx + ',' + dy + ')');
        }
      }
      function onUp() {
        if (!down) return;
        var d = down; down = null;
        if (d.button === 2) { $scope.$evalAsync(function () { $scope.drag.active = false; }); $scope.lua('setDragging(false)'); return; }
        if (d.moved > 6 || $scope.s.phase !== 'garage') return;
        // a click that lands in the hole of a shelf part is a click on that part
        var hole = holeAt(d.x, d.y);
        if (hole) { if (d.button === 0 && hole.el.parentElement) hole.el.parentElement.click(); return; }
        if (d.button === 0) $scope.lua('click()');
        else if (d.button === 1) $scope.lua('focus()');
      }
      function onWheel(ev) {
        var phase = $scope.s.phase, t = ev.target;
        // over the shelf the wheel moves it a line, over the catalog's page it turns the page
        // (a part's preview is a hole in the panel: there the element behind the hole counts)
        var hole = holeAt(ev.clientX, ev.clientY), at = hole ? hole.el : t;
        if (at && at.closest) {
          var dir = ev.deltaY > 0 ? 1 : -1;
          if (phase === 'garage' && at.closest('.sg-slots')) { ev.preventDefault(); $scope.$evalAsync(function () { $scope.scroll(dir); }); return; }
          if ((phase === 'catalog' || phase === 'shop') && at.closest('.sg-grid')) { ev.preventDefault(); $scope.$evalAsync(function () { $scope.turn(dir); }); return; }
        }
        if (phase !== 'garage') return;
        if (!t || !t.classList || !t.classList.contains('sg-view')) return;
        ev.preventDefault();
        var steps = ev.deltaY < 0 ? 1 : -1;
        if (heldDrag) heldDrag.zoom += steps;
        else if (parkPreviews()) heldDrag = { frames: 2, dx: 0, dy: 0, zoom: steps };
        else bngApi.engineLua('slrr_garage.cameraZoom(' + steps + ')');
      }
      window.addEventListener('mousemove', onMove);
      window.addEventListener('mouseup', onUp);
      window.addEventListener('wheel', onWheel, { passive: false });

      // ---- gamepad (X51): BeamNG's UI sends every pad action as a 'ui_nav' event; the buttons are ng-click, so the
      // pad already moves between them and A clicks. Here: the right stick orbits the camera, the zoom buttons zoom,
      // centre-camera resets the view, and B closes a panel (else it is left to the game, as before)
      var pad = { h: 0, v: 0 }, PAD_DEAD = 0.15, PAD_SPEED = 14;
      function onNav(ev) {
        var d = ev.detail || {}, n = d.name, v = Number(d.value) || 0, phase = $scope.s.phase;
        if (phase !== 'garage' && phase !== 'catalog' && phase !== 'shop') return;
        if (n === 'rotate_h_cam') { pad.h = Math.abs(v) < PAD_DEAD ? 0 : v; return; }
        if (n === 'rotate_v_cam') { pad.v = Math.abs(v) < PAD_DEAD ? 0 : v; return; }
        if (v !== 1) return;
        if ((n === 'zoom_in' || n === 'zoom_out') && phase === 'garage') bngApi.engineLua('slrr_garage.cameraZoom(' + (n === 'zoom_in' ? 1 : -1) + ')');
        else if (n === 'center_cam' && phase === 'garage') $scope.lua('resetView()');
        else if (n === 'back' && ($scope.panel || $scope.contents)) {
          $scope.$evalAsync(function () { if ($scope.contents) $scope.contents = null; else $scope.closePanel(); });
          if (ev.stopImmediatePropagation) ev.stopImmediatePropagation();
          if (ev.preventDefault) ev.preventDefault();
        }
      }
      window.addEventListener('ui_nav', onNav, true);     // (window capture: before the game's own document handler)
      var padTimer = setInterval(function () {      // ~30 Hz while the stick is held
        if ((pad.h || pad.v) && $scope.s.phase === 'garage') bngApi.engineLua('slrr_garage.cameraDrag(' + (pad.h * PAD_SPEED).toFixed(1) + ',' + (pad.v * PAD_SPEED).toFixed(1) + ')');
      }, 33);
      if (padTimer && padTimer.unref) padTimer.unref();     // (node, in tools/ui_selfcheck.js: the timer must not keep it alive)
      $scope.$on('$destroy', function () { window.removeEventListener('ui_nav', onNav, true); clearInterval(padTimer); });

      // ---- state from Lua
      $scope.$on('slrrGarageState', function (ev, data) {
        $scope.$evalAsync(function () {
          data = data || {};
          if (!Array.isArray(data.inventory)) data.inventory = [];
          if (!data.filters || Array.isArray(data.filters)) data.filters = {};
          var wasPhase = $scope.s.phase;
          $scope.s = data;
          if ($scope.line > $scope.lineCount() - 1) $scope.line = $scope.lineCount() - 1;
          if (data.phase !== 'garage') $scope.hover = {};
          if (data.phase === 'garage' && wasPhase === 'film') { $scope.line = 0; $scope.panel = null; }
          if (data.phase === 'idle' || data.phase === 'leaving') { $scope.panel = null; $scope.contents = null; $scope.sheet = null; $scope.work = null; }
          if (data.phase !== 'catalog' && data.phase !== 'shop') $scope.cfg = null;
          if (data.phase === 'idle') noModel = {};      // another car, another livery: ask again next time
          if (data.mode !== 'tune' && $scope.panel === 'tune') $scope.panel = null;
          if (data.mode !== 'tune') $scope.pt = { vars: [] };
          wantPreviews();
        });
      });
      // another mod's screen (the laptop) asked for a panel to be open on arrival
      $scope.$on('slrrGaragePanel', function (ev, data) {
        $scope.$evalAsync(function () { if (data && data.panel) { $scope.panel = null; $scope.openPanel(data.panel); } });
      });
      $scope.$on('slrrGarageHover', function (ev, data) {
        $scope.$evalAsync(function () { $scope.hover = (data && !Array.isArray(data)) ? data : {}; });
      });
      $scope.$on('slrrGarageItemAdded', function (ev, data) {
        $scope.$evalAsync(function () {
          // jump to the line the new part landed on, like SLRR's shelf does
          var inv = $scope.s.inventory || [];
          for (var i = 0; i < inv.length; i++) if (inv[i].id === data.id) { $scope.line = Math.floor(i / SLOTS_PER_LINE); break; }
          $scope.freshId = data.id;
          wantPreviews();
        });
      });
      $scope.$on('slrrGarageCatalog', function (ev, data) {
        $scope.$evalAsync(function () {
          var sections = (data && data.sections) || [];
          sections.forEach(function (sec) {
            sec.subs = Array.isArray(sec.subs) ? sec.subs : [];
            sec.subs.forEach(function (sub) { if (!Array.isArray(sub.items)) sub.items = []; });
          });
          $scope.cat = { sections: sections, stamp: Date.now() };
          if (!$scope.curSec() && sections.length) {
            $scope.cur.section = sections[0].id; $scope.cur.sub = null; $scope.cur.page = 0;
            for (var i = 0; i < sections[0].subs.length; i++) if (sections[0].subs[i].items.length) { $scope.cur.sub = sections[0].subs[i].id; break; }
          }
          if ($scope.cur.page > $scope.pageCount() - 1) $scope.cur.page = Math.max(0, $scope.pageCount() - 1);
          wantPreviews();
        });
      });

      // The app container is inset (and scaled) by the game's app layout. The garage screen has to
      // cover the whole window - the fades hide vehicle reloads - so the root lives on <body>.
      var placeholder = document.createComment('slrr-garage');
      if (rootEl.parentNode) rootEl.parentNode.insertBefore(placeholder, rootEl);
      document.body.appendChild(rootEl);

      $scope.$on('$destroy', function () {
        window.removeEventListener('mousemove', onMove);
        window.removeEventListener('mouseup', onUp);
        window.removeEventListener('wheel', onWheel);
        if (rafId) window.cancelAnimationFrame(rafId);
        window.clearInterval(cartTick);
        if (rootEl.parentNode) rootEl.parentNode.removeChild(rootEl);
        if (placeholder.parentNode) placeholder.parentNode.removeChild(placeholder);
      });

      $scope.lua('requestState()');
    }]
  };
}]);
