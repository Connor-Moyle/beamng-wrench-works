// SLRR Garage - the on-screen side of the garage.
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
    target: svg('<circle cx="24" cy="24" r="12"/><path d="M24 5v9M24 34v9M5 24h9M34 24h9"/>'),
    // the mechanic's row
    repairPart: svg('<path d="M33 9a8 8 0 0 1-10 10L11 31a3 3 0 0 1-4-4l12-12A8 8 0 0 1 29 5l-5 5 2 5 5 2z"/><path d="M36 30v12M30 36h12"/>'),
    repairCar: svg('<path d="M4 28v-6l6-2 5-8h14l7 8 6 2v6h-4a5 5 0 0 0-10 0H18a5 5 0 0 0-10 0z"/><path d="M24 34v10M19 39h10"/>'),
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
    '.sg-glass{background:rgba(0,0,0,.62);border-radius:6px;-webkit-backdrop-filter:blur(8px);backdrop-filter:blur(8px)}',

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
    '.sg-slot.sg-item:hover{background:rgba(255,102,0,.22);border-color:#ff6600}',
    '.sg-slot.sg-fresh{animation:sgdrop .45s ease-out}',
    '@keyframes sgdrop{0%{transform:translateY(-26px);opacity:0}100%{transform:none;opacity:1}}',
    '.sg-slot canvas,.sg-card canvas{position:absolute;left:0;top:0;width:100%;height:100%;pointer-events:none}',
    '.sg-slot .sg-glyph{position:absolute;left:50%;top:38%;width:38px;height:38px;margin:-19px 0 0 -19px;color:rgba(255,255,255,.5)}',
    '.sg-slot .sg-txt{position:relative;width:100%;padding-top:3px;background:linear-gradient(rgba(0,0,0,0),rgba(0,0,0,.55) 35%)}',
    '.sg-slot .sg-name{font-size:14px;font-weight:600;line-height:1.15;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
    '.sg-slot .sg-wherep{font-size:11px;color:#c4c4c4;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
    '.sg-badges{position:absolute;left:6px;top:5px;display:flex;flex-direction:column;align-items:flex-start}',
    '.sg-badge{font-size:10px;font-weight:700;letter-spacing:.5px;padding:1px 6px;border-radius:3px;margin-bottom:3px;background:rgba(0,0,0,.6);color:#fff}',
    '.sg-badge.sg-new{background:#ff6600}',
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
    '.sg-kv{display:flex;padding:5px 0;border-bottom:1px solid rgba(255,255,255,.08);font-size:13px}',
    '.sg-kv span{color:#b8b8b8}',
    '.sg-kv b{margin-left:auto;font-weight:600}',
    '.sg-grp{margin:12px 0 4px 0;font-size:12px;letter-spacing:1.5px;color:#ffb380;text-transform:uppercase}',
    '.sg-set{display:flex;align-items:center;padding:8px 0;border-bottom:1px solid rgba(255,255,255,.08)}',
    '.sg-set .sg-st{flex:1;min-width:0;padding-right:14px}',
    '.sg-set .sg-st b{display:block;font-size:14px;font-weight:600}',
    '.sg-set .sg-st span{display:block;font-size:11.5px;color:#a8a8a8;line-height:1.35;margin-top:1px}',
    '.sg-set .sg-sc{width:230px;flex:none;display:flex;align-items:center}',
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
    '.sg-card .sg-stage{position:relative;flex:1;min-height:0;background:radial-gradient(ellipse at 50% 55%,rgba(255,255,255,.26),rgba(255,255,255,.04) 72%)}',
    '.sg-card .sg-glyph{position:absolute;left:50%;top:50%;width:64px;height:64px;margin:-32px 0 0 -32px;color:rgba(255,255,255,.22)}',
    '.sg-card .sg-meta{padding:8px 12px 10px 12px;background:rgba(0,0,0,.35)}',
    '.sg-card .sg-cslot{font-size:11px;letter-spacing:1px;color:#ffb380;text-transform:uppercase;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
    '.sg-card .sg-cname{font-size:16px;font-weight:600;line-height:1.2;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
    '.sg-card .sg-buyrow{display:flex;align-items:center;margin-top:6px}',
    '.sg-price{font-size:19px;font-weight:700}',
    '.sg-card .sg-btn{margin-left:auto;padding:6px 18px}',
    '.sg-card .sg-badges{left:8px;top:8px}',
    '.sg-foot{display:flex;align-items:center;justify-content:center;padding-top:10px;font-size:13px;color:#c8c8c8}',
    '.sg-foot .sg-btn{margin:0 14px}',
    '.sg-blank{flex:1;display:flex;align-items:center;justify-content:center;font-size:15px;color:#9a9a9a;text-align:center;line-height:1.6}',

    /* film bars + fade */
    '.sg-lb{position:absolute;left:-200px;right:-200px;height:400px;background:#000;transition:transform .6s ease}',
    '.sg-lb.sg-t{top:-500px}.sg-lb.sg-b{bottom:-500px}',
    '.sg-phase-film .sg-lb.sg-t{transform:translateY(calc(100px + 9vh))}.sg-phase-film .sg-lb.sg-b{transform:translateY(calc(-100px - 9vh))}',
    '.sg-fade{position:absolute;left:-200px;top:-200px;right:-200px;bottom:-200px;background:#000;opacity:0;transition:opacity .2s linear;pointer-events:none}',
    '.sg-fade.sg-in{opacity:1}',
    '</style>',

    '<div class="sg-view" ng-if="s.phase === \'garage\'" ng-class="{\'sg-can\': canAct(), \'sg-dragging\': drag.active}"',
    '     ng-mousedown="viewDown($event)" ng-mouseenter="overUi(false)" oncontextmenu="return false"></div>',

    '<div class="sg-lb sg-t"></div><div class="sg-lb sg-b"></div>',

    '<div ng-if="s.phase === \'garage\' || s.phase === \'busy\'">',

    /* top bar */
    '  <div class="sg-top sg-panel" ng-mouseenter="overUi(true)">',
    '    <div class="sg-tag sg-h">Garage</div>',
    '    <div class="sg-where"><b>{{s.garage}}</b><span>{{s.car}}</span></div>',
    '    <div class="sg-money sg-glass"><b>{{money(s.money)}}</b><span>{{s.career ? \'Career money\' : \'Freeroam budget\'}}</span></div>',
    '  </div>',

    /* SLRR icon bar */
    '  <div class="sg-bar sg-glass sg-panel" ng-mouseenter="overUi(true)" ng-mouseleave="tip = null">',
    '    <div ng-repeat="b in bar track by $index" ng-class="b.sep ? \'sg-sep\' : {\'sg-ib\': true, \'sg-on\': b.on && b.on()}" ng-click="b.act && b.act()" ng-mouseenter="$parent.tip = b.sep ? null : b" ng-bind-html="b.sep ? \'\' : icon(b.icon)"></div>',
    '  </div>',
    '  <div class="sg-tip" ng-if="tip">{{tip.title}}<small>{{tip.desc}}</small></div>',

    '  <div class="sg-help sg-glass" ng-if="!panel">',
    '    <div ng-if="s.mode === \'mechanic\' && !s.tool"><i>Click</i>a part to take it off</div>',
    '    <div ng-if="s.mode === \'mechanic\' && !s.tool"><i>Click</i>a shelf part to fit it</div>',
    '    <div ng-if="s.mode === \'tune\' && !s.tool"><i>Click</i>a part to pick it and tune it</div>',
    '    <div ng-if="s.tool === \'repair\'"><i>Click</i>a damaged part to repair it</div>',
    '    <div ng-if="s.tool === \'sell\'"><i>Click</i>a shelf part to sell it</div>',
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
    '        <div class="sg-ib" ng-class="{\'sg-on\': s.tool === \'repair\'}" ng-click="lua(\'setTool(\\\'repair\\\')\')" ng-mouseenter="tip = tips.repairPart" ng-bind-html="icon(\'repairPart\')"></div>',
    '        <div class="sg-ib" ng-class="{\'sg-dim\': !s.damaged}" ng-click="lua(\'repairAll()\')" ng-mouseenter="tip = repairAllTip()" ng-bind-html="icon(\'repairCar\')"></div>',
    '        <div class="sg-ib" ng-class="{\'sg-on\': s.tool === \'sell\'}" ng-click="lua(\'setTool(\\\'sell\\\')\')" ng-mouseenter="tip = tips.sell" ng-bind-html="icon(\'sell\')"></div>',
    '      </div>',
    '      <div class="sg-cap">Show on car</div>',
    '      <div class="sg-row" ng-mouseleave="tip = null">',
    '        <div class="sg-ib" ng-repeat="f in filterDefs" ng-class="{\'sg-off\': s.filters[f.id]}" ng-click="lua(\'toggleFilter(\\\'\' + f.id + \'\\\')\')" ng-mouseenter="$parent.tip = f.tip" ng-bind-html="icon(f.id)"></div>',
    '      </div>',
    '    </div>',
    '    <div class="sg-slots">',
    '      <div class="sg-slot" ng-repeat="slot in visibleSlots() track by $index" ng-class="{\'sg-empty\': !slot, \'sg-item\': slot, \'sg-fresh\': slot && slot.id === freshId}" ng-click="slot && install(slot)">',
    '        <span class="sg-glyph" ng-if="slot && !hasPicture(slot.part, slot.photo)" ng-bind-html="icon(slot.section)"></span>',
    '        <canvas class="sg-prev" ng-if="slot && s.previews" data-part="{{slot.part}}" data-photo="{{slot.photo}}" data-spin="hover"></canvas>',
    '        <div class="sg-badges" ng-if="slot">',
    '          <span class="sg-badge sg-new" ng-if="slot.new">NEW</span>',
    '          <span class="sg-badge sg-dmg" ng-if="slot.damaged">DAMAGED</span>',
    '          <span class="sg-badge" ng-if="slot.count > 1">+{{slot.count - 1}} parts</span>',
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

    /* tune drawer */
    '  <div class="sg-drawer sg-glass sg-panel" ng-if="panel === \'tune\'" ng-mouseenter="overUi(true)">',
    '    <div class="sg-dhead"><div class="sg-h">Tuning</div><div class="sg-x" ng-click="closePanel()" ng-bind-html="icon(\'close\')"></div></div>',
    '    <div class="sg-tabs"><div class="sg-tab" ng-repeat="c in tune.categories" ng-class="{\'sg-on\': c === tune.category}" ng-click="tune.category = c">{{c}}</div></div>',
    '    <div class="sg-scrolly">',
    '      <div class="sg-var" ng-repeat="v in tune.vars | filter:{category: tune.category}:true track by v.name">',
    '        <div class="sg-vt"><b>{{v.subCategory ? v.subCategory + \' \' : \'\'}}{{v.title}}</b><span>{{shown(v)}} {{v.unit}}</span></div>',
    '        <div class="sg-vd" ng-if="v.description">{{v.description}}</div>',
    '        <div class="sg-vr"><input type="range" min="{{v.lo}}" max="{{v.hi}}" step="{{v.step}}" ng-model="v.value" ng-change="tuneChanged()"><div class="sg-mini" ng-click="v.value = v.default; tuneChanged()">Default</div></div>',
    '      </div>',
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
    '    </div>',
    '  </div>',
    '</div>',

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
    '          <div class="sg-sc" ng-if="d.type === \'number\'"><input type="number" min="{{d.min}}" max="{{d.max}}" step="{{d.step}}" ng-model="d.value" ng-change="setSetting(d, d.value)" ng-model-options="{debounce: 350}"></div>',
    '        </div>',
    '      </div>',
    '    </div>',
    '    <div class="sg-foot2"><div class="sg-note" style="flex:1" ng-if="setCareer">You are in career mode: money comes from your career account, not the freeroam budget.</div><div class="sg-note" style="flex:1" ng-if="!setCareer"></div><div class="sg-btn" ng-click="lua(\'setSetting(\\\'__reset\\\')\')">Reset to defaults</div></div>',
    '  </div>',
    '</div>',

    /* catalog */
    '<div class="sg-cat" ng-if="s.phase === \'catalog\'">',
    '  <div class="sg-book">',
    '    <div class="sg-page-l">',
    '      <h1 class="sg-h">Catalog</h1><div class="sg-for">Parts for your {{s.car}}</div>',
    '      <div class="sg-scrolly">',
    '        <div ng-repeat="sec in cat.sections">',
    '          <div class="sg-sec sg-h" ng-class="{\'sg-act\': sec.id === cur.section}" ng-click="openSection(sec)"><span ng-bind-html="icon(sec.id)"></span>{{sec.title}}</div>',
    '          <div ng-if="sec.id === cur.section">',
    '            <div class="sg-sub-row" ng-repeat="sub in sec.subs" ng-class="{\'sg-act\': sub.id === cur.sub, \'sg-none\': !sub.items.length}" ng-click="openSub(sec, sub)">{{sub.title}}<i>{{sub.items.length}}</i></div>',
    '          </div>',
    '        </div>',
    '      </div>',
    '      <div class="sg-wallet">{{s.career ? \'Career money\' : \'Freeroam budget\'}}<b>{{money(s.money)}}</b></div>',
    '    </div>',
    '    <div class="sg-page-r">',
    '      <div class="sg-head"><div class="sg-h">{{curSub() ? curSub().title : \'Choose a chapter\'}}</div><div class="sg-crumb" ng-if="curSec()">{{curSec().title}} &middot; {{shownItems().length}} parts</div>',
    '        <input class="sg-search" type="text" placeholder="Search this chapter" ng-model="cur.search" ng-change="searchChanged()" ng-if="curSub() && curSub().items.length > 6">',
    '        <div class="sg-btn sg-go" ng-click="lua(\'closeCatalog()\')">Back to garage</div></div>',
    '      <div class="sg-grid" ng-if="pageItems().length">',
    '        <div class="sg-card" ng-repeat="it in pageItems() track by it.slotPath + it.part">',
    '          <div class="sg-stage"><span class="sg-glyph" ng-if="!hasPicture(it.part, photoKey(it.part))" ng-bind-html="icon(curSec().id)"></span>',
    '            <canvas class="sg-prev" ng-if="s.previews" data-part="{{it.part}}" data-photo="{{photoKey(it.part)}}" data-spin="always"></canvas>',
    '            <div class="sg-badges"><span class="sg-badge" ng-if="it.fitted">On the car</span><span class="sg-badge sg-new" ng-if="it.owned > 0">On the shelf &times;{{it.owned}}</span></div>',
    '          </div>',
    '          <div class="sg-meta"><div class="sg-cslot">{{it.slot}}</div><div class="sg-cname" title="{{it.part}}">{{it.name}}</div>',
    '            <div class="sg-buyrow"><div class="sg-price">{{money(it.price)}}</div><div class="sg-btn sg-go" ng-class="{\'sg-nope\': it.price > s.money}" ng-click="buy(it)">Buy</div></div></div>',
    '        </div>',
    '      </div>',
    '      <div class="sg-blank" ng-if="!pageItems().length && !cur.search">Pick a chapter on the left.<br>Everything you buy lands on the shelf in the garage,<br>ready to be fitted with one click.</div>',
    '      <div class="sg-blank" ng-if="!pageItems().length && cur.search">Nothing in this chapter matches &ldquo;{{cur.search}}&rdquo;.</div>',
    '      <div class="sg-foot" ng-if="pageCount() > 1">',
    '        <div class="sg-btn" ng-class="{\'sg-nope\': cur.page <= 0}" ng-click="turn(-1)">&#9664; Prev</div>',
    '        Page {{cur.page + 1}} of {{pageCount()}}',
    '        <div class="sg-btn" ng-class="{\'sg-nope\': cur.page >= pageCount() - 1}" ng-click="turn(1)">Next &#9654;</div>',
    '      </div>',
    '    </div>',
    '  </div>',
    '</div>',

    '<div class="sg-msg" ng-if="s.message">{{s.message}}</div>',
    '<div class="sg-fade" ng-class="{\'sg-in\': s.fade > 0.5}"></div>',
    '</div>'
  ].join('\n');

  // ---- renderer for the part previews --------------------------------------------------------
  // Parts are shown as smooth white models on a turntable. A small depth-buffered triangle
  // rasteriser draws each part once per turntable step; the pictures are then simply played
  // back. The game's UI allows no worker threads, so the drawing is done a few milliseconds at
  // a time between screen updates.
  var FRAMES = 60;               // pictures per full turn
  var FRAME_SIZE = 176;          // picture size in pixels
  var KEEP_PARTS = 12;           // parts whose pictures are kept in memory at once
  var DRAW_BUDGET = 7;           // milliseconds of drawing per screen update

  function rasterCore() {
    var models = {};
    var TILT = 0.40, COS_T = Math.cos(TILT), SIN_T = Math.sin(TILT);
    var LX = -0.39, LY = 0.54, LZ = 0.75;
    var zbuf = null, shade = null, sx = null, sy = null, sz = null, lit = null;

    function store(part, v, t) {
      var nv = v.length / 3, nt = t.length / 3, i;
      var min = [Infinity, Infinity, Infinity], max = [-Infinity, -Infinity, -Infinity];
      for (i = 0; i < v.length; i++) { var ax = i % 3; if (v[i] < min[ax]) min[ax] = v[i]; if (v[i] > max[ax]) max[ax] = v[i]; }
      var cx = (min[0] + max[0]) / 2, cy = (min[1] + max[1]) / 2, cz = (min[2] + max[2]) / 2;
      // scale by the diagonal so the part fits whichever way it is turned
      var diag = Math.sqrt(Math.pow(max[0] - min[0], 2) + Math.pow(max[1] - min[1], 2) + Math.pow(max[2] - min[2], 2)) || 1;
      var V = new Float32Array(nv * 3), N = new Float32Array(nv * 3), T = new Uint32Array(t);
      for (i = 0; i < nv; i++) { V[i * 3] = (v[i * 3] - cx) / diag; V[i * 3 + 1] = (v[i * 3 + 1] - cy) / diag; V[i * 3 + 2] = (v[i * 3 + 2] - cz) / diag; }
      // smooth normals: every vertex takes the area-weighted average of the faces around it
      for (i = 0; i < nt; i++) {
        var a = T[i * 3] * 3, b = T[i * 3 + 1] * 3, c = T[i * 3 + 2] * 3;
        var ux = V[b] - V[a], uy = V[b + 1] - V[a + 1], uz = V[b + 2] - V[a + 2];
        var wx = V[c] - V[a], wy = V[c + 1] - V[a + 1], wz = V[c + 2] - V[a + 2];
        var nx = uy * wz - uz * wy, ny = uz * wx - ux * wz, nz = ux * wy - uy * wx;
        // faces that point the other way round still describe the same surface
        if (N[a] * nx + N[a + 1] * ny + N[a + 2] * nz < 0) { nx = -nx; ny = -ny; nz = -nz; }
        N[a] += nx; N[a + 1] += ny; N[a + 2] += nz; N[b] += nx; N[b + 1] += ny; N[b + 2] += nz; N[c] += nx; N[c + 1] += ny; N[c + 2] += nz;
      }
      for (i = 0; i < nv; i++) {
        var l = Math.sqrt(N[i * 3] * N[i * 3] + N[i * 3 + 1] * N[i * 3 + 1] + N[i * 3 + 2] * N[i * 3 + 2]) || 1;
        N[i * 3] /= l; N[i * 3 + 1] /= l; N[i * 3 + 2] /= l;
      }
      models[part] = { V: V, N: N, T: T };
    }

    // one picture: RGBA bytes, size x size, see-through around the part
    function render(part, angle, size) {
      var model = models[part];
      if (!model) return null;
      var V = model.V, N = model.N, T = model.T, nv = V.length / 3, nt = T.length / 3, i;
      var w = size * 2;                        // drawn at twice the size and scaled down, for smooth edges
      if (!sx || sx.length < nv) { sx = new Float32Array(nv); sy = new Float32Array(nv); sz = new Float32Array(nv); lit = new Float32Array(nv); }
      if (!zbuf || zbuf.length !== w * w) { zbuf = new Float32Array(w * w); shade = new Float32Array(w * w); }
      for (i = 0; i < w * w; i++) { zbuf[i] = Infinity; shade[i] = -1; }
      var ca = Math.cos(angle), sa = Math.sin(angle), scale = w * 0.98, o = w / 2;
      for (i = 0; i < nv; i++) {
        var x = V[i * 3], y = V[i * 3 + 1], z = V[i * 3 + 2];
        var rx = x * ca - y * sa, ry = x * sa + y * ca;                 // turn about the upright axis
        sx[i] = o + rx * scale;
        sy[i] = o - (z * COS_T - ry * SIN_T) * scale;                   // camera tilted down a little
        sz[i] = ry * COS_T + z * SIN_T;                                 // depth: smaller is nearer
        var nx = N[i * 3], ny = N[i * 3 + 1], nz = N[i * 3 + 2];
        var nrx = nx * ca - ny * sa, nry = nx * sa + ny * ca;
        // normal in view space: right, up, towards the viewer
        var vx = nrx, vy = nz * COS_T - nry * SIN_T, vz = -(nry * COS_T + nz * SIN_T);
        if (vz < 0) { vx = -vx; vy = -vy; vz = -vz; }                   // thin parts are lit on both faces
        var d = vx * LX + vy * LY + vz * LZ;
        lit[i] = 0.34 + 0.6 * Math.max(0, d) + 0.1 * Math.max(0, -d) + 0.1 * Math.pow(Math.max(0, d), 18);
      }
      for (i = 0; i < nt; i++) {
        var a = T[i * 3], b = T[i * 3 + 1], c = T[i * 3 + 2];
        var ax = sx[a], ay = sy[a], bx = sx[b], by = sy[b], cx = sx[c], cy = sy[c];
        var area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
        if (area > -1e-7 && area < 1e-7) continue;
        var minX = Math.max(0, Math.floor(Math.min(ax, bx, cx))), maxX = Math.min(w - 1, Math.ceil(Math.max(ax, bx, cx)));
        var minY = Math.max(0, Math.floor(Math.min(ay, by, cy))), maxY = Math.min(w - 1, Math.ceil(Math.max(ay, by, cy)));
        if (minX > maxX || minY > maxY) continue;
        var inv = 1 / area;
        for (var yy = minY; yy <= maxY; yy++) {
          var pyc = yy + 0.5, row = yy * w;
          for (var xx = minX; xx <= maxX; xx++) {
            var pxc = xx + 0.5;
            var w0 = ((bx - pxc) * (cy - pyc) - (by - pyc) * (cx - pxc)) * inv;
            var w1 = ((cx - pxc) * (ay - pyc) - (cy - pyc) * (ax - pxc)) * inv;
            var w2 = 1 - w0 - w1;
            if (w0 < -0.001 || w1 < -0.001 || w2 < -0.001) continue;
            var depth = w0 * sz[a] + w1 * sz[b] + w2 * sz[c];
            var k = row + xx;
            if (depth >= zbuf[k]) continue;
            zbuf[k] = depth;
            shade[k] = w0 * lit[a] + w1 * lit[b] + w2 * lit[c];
          }
        }
      }
      var out = new Uint8ClampedArray(size * size * 4);
      for (var py = 0; py < size; py++) {
        for (var px = 0; px < size; px++) {
          var k0 = py * 2 * w + px * 2, sum = 0, n = 0, q;
          q = shade[k0]; if (q >= 0) { sum += q; n++; }
          q = shade[k0 + 1]; if (q >= 0) { sum += q; n++; }
          q = shade[k0 + w]; if (q >= 0) { sum += q; n++; }
          q = shade[k0 + w + 1]; if (q >= 0) { sum += q; n++; }
          if (!n) continue;
          var g = sum / n * 255, at = (py * size + px) * 4;
          out[at] = g * 0.975; out[at + 1] = g * 0.985; out[at + 2] = g; out[at + 3] = n * 63.75;
        }
      }
      return out;
    }

    return { store: store, render: render, drop: function (part) { delete models[part]; } };
  }

  // meshes[part] = true (model handed to the renderer) | false (no model)
  // clay[part] = { list: [canvas per turntable step], count, used }
  var meshes = {}, clay = {};
  var raster = rasterCore();
  // draw one turntable step of a part into clay[part]
  function drawStep(part, idx) {
    var entry = clay[part];
    var out = raster.render(part, -idx * 2 * Math.PI / FRAMES, FRAME_SIZE);     // clockwise seen from above
    var c = document.createElement('canvas'); c.width = FRAME_SIZE; c.height = FRAME_SIZE;
    if (out) c.getContext('2d').putImageData(new ImageData(out, FRAME_SIZE, FRAME_SIZE), 0, 0);
    entry.list[idx] = c; entry.count++;
  }

  // ---- photographed previews ----------------------------------------------------------------
  // photos[key] = { frames: [canvas...], ready } | false (nothing to show) ; filled from pictures
  // the game saved, one per turntable step.
  var photos = {};
  function loadPhoto(info, done) {
    var count = info.frames, old = photos[info.key], bust = Date.now();
    if (old && old.count >= count) return;
    // a single still may already be showing; it stays up until the full turn has loaded
    var left = count, imgs = new Array(count), failed = false;
    var entry = { frames: old ? old.frames : null, ready: !!(old && old.ready), count: count };
    photos[info.key] = entry;
    function finish() {
      if (failed) { if (!entry.ready) photos[info.key] = false; done(); return; }
      // the pictures come on a magenta backdrop; make it transparent so the card shows through
      entry.frames = imgs.map(function (img) {
        var c = document.createElement('canvas'); c.width = img.width; c.height = img.height;
        var x = c.getContext('2d'); x.drawImage(img, 0, 0);
        var d = x.getImageData(0, 0, c.width, c.height), p = d.data;
        for (var i = 0; i < p.length; i += 4) {
          var m = Math.min(p[i], p[i + 2]) - p[i + 1];      // how much backdrop is in this pixel
          if (m <= 24) continue;
          if (m >= 235) { p[i + 3] = 0; continue; }
          var a = 1 - m / 255;                               // edge pixel: take the backdrop back out
          p[i] = Math.max(0, (p[i] - 255 * (1 - a)) / a); p[i + 2] = Math.max(0, (p[i + 2] - 255 * (1 - a)) / a);
          p[i + 3] = Math.round(255 * a);
        }
        x.putImageData(d, 0, 0);
        return c;
      });
      entry.ready = true;
      done();
    }
    for (var i = 0; i < count; i++) (function (i) {
      var img = new Image();
      img.onload = function () { imgs[i] = img; if (--left === 0) finish(); };
      img.onerror = function () { failed = true; if (--left === 0) finish(); };
      img.src = info.base + '_' + i + '.png?' + bust;
    })(i);
  }

  // show a turntable at `turn` (in turns). list may still have gaps while it is being drawn.
  function drawTurn(canvas, list, turn, zoom) {
    var cw = canvas.clientWidth, ch = canvas.clientHeight;
    if (!cw || !ch) return;
    if (canvas.width !== cw || canvas.height !== ch) { canvas.width = cw; canvas.height = ch; }
    var n = list.length, f = ((turn % 1) + 1) % 1 * n, i0 = Math.floor(f) % n, i1 = (i0 + 1) % n, t = f - Math.floor(f);
    var ctx = canvas.getContext('2d');
    var side = Math.min(cw, ch) * zoom, x = (cw - side) / 2, y = (ch - side) / 2 - ch * 0.03;
    ctx.clearRect(0, 0, cw, ch);
    if (!list[i0]) {
      // not drawn yet: hold the nearest step that is
      for (var back = 1; back < n; back++) { var j = (i0 - back + n) % n; if (list[j]) { ctx.drawImage(list[j], x, y, side, side); break; } }
      return;
    }
    ctx.drawImage(list[i0], x, y, side, side);
    if (t > 0.02 && list[i1]) { ctx.globalAlpha = t; ctx.drawImage(list[i1], x, y, side, side); ctx.globalAlpha = 1; }   // blend into the next step
  }

  // forget the pictures of parts that have not been on screen for a while
  function trimFrames(now) {
    var parts = Object.keys(clay);
    if (parts.length <= KEEP_PARTS) return;
    parts.sort(function (p, q) { return clay[p].used - clay[q].used; });
    for (var i = 0; i < parts.length - KEEP_PARTS; i++) if (now - clay[parts[i]].used > 1500) delete clay[parts[i]];
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
        { icon: 'screwdriver', title: 'Tune', desc: 'click a part to adjust or open it', act: function () { $scope.closePanel(); $scope.lua('setMode(\'tune\')'); }, on: function () { return $scope.s.mode === 'tune'; } },
        { icon: 'lift', title: 'Lift', desc: 'raise or lower the car', act: function () { $scope.lua('toggleLift()'); }, on: function () { return $scope.s.lift; } },
        { icon: 'spray', title: 'Paint booth', desc: 'respray the car', act: function () { $scope.openPanel('paint'); }, on: function () { return $scope.panel === 'paint'; } },
        { sep: true },
        { icon: 'key', title: 'Test engine', desc: 'start or stop it where it stands', act: function () { $scope.lua('toggleEngine()'); }, on: function () { return $scope.s.engineOn; } },
        { icon: 'clock', title: 'Advance time', desc: 'move the clock on three hours', act: function () { $scope.lua('advanceTime()'); } },
        { icon: 'target', title: 'Whole car', desc: 'reset the camera', act: function () { $scope.lua('resetView()'); }, on: function () { return $scope.s.focused; } },
        { icon: 'gear', title: 'Settings', desc: 'money, prices, damage and more', act: function () { $scope.openPanel('settings'); }, on: function () { return $scope.panel === 'settings'; } }
      ];
      $scope.tips = {
        repairPart: { title: 'Repair part', desc: 'then click the damaged part' },
        sell: { title: 'Sell part', desc: 'then click a part on the shelf' }
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
        if ($scope.s.mode === 'tune') return true;
        return !!h.removable;
      };
      $scope.hoverBlocked = function () { return !!$scope.hover.name && !$scope.canAct(); };
      $scope.hoverHint = function () {
        var h = $scope.hover;
        if ($scope.s.tool === 'repair') return h.damaged ? ('click to repair for ' + $scope.money(h.repairCost)) : 'not damaged';
        if ($scope.s.tool === 'sell') return 'take it off first to sell it';
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
      $scope.install = function (item) { $scope.lua('install(' + item.id + ')'); };

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
      // chapter contents, narrowed by whatever is typed in the search box
      var shownKey = null, shownList = [];
      $scope.shownItems = function () {
        var sub = $scope.curSub();
        if (!sub) return [];
        var q = ($scope.cur.search || '').toLowerCase().trim();
        var key = $scope.cur.section + '/' + $scope.cur.sub + '/' + q + '/' + sub.items.length + '/' + $scope.cat.stamp;
        if (key !== shownKey) {
          shownKey = key;
          if (!q) shownList = sub.items;
          else {
            var words = q.split(/\s+/);
            shownList = sub.items.filter(function (it) {
              var text = (it.name + ' ' + it.slot + ' ' + it.part).toLowerCase();
              for (var i = 0; i < words.length; i++) if (text.indexOf(words[i]) < 0) return false;
              return true;
            });
          }
        }
        return shownList;
      };
      $scope.pageCount = function () { var n = $scope.shownItems().length; return $scope.curSub() ? Math.max(1, Math.ceil(n / CATALOG_PER_PAGE)) : 0; };
      $scope.pageItems = function () {
        return $scope.shownItems().slice($scope.cur.page * CATALOG_PER_PAGE, ($scope.cur.page + 1) * CATALOG_PER_PAGE);
      };
      $scope.searchChanged = function () { $scope.cur.page = 0; wantPreviews(); };
      $scope.openSection = function (sec) {
        $scope.cur.section = sec.id; $scope.cur.page = 0; $scope.cur.sub = null; $scope.cur.search = '';
        for (var i = 0; i < sec.subs.length; i++) if (sec.subs[i].items.length) { $scope.cur.sub = sec.subs[i].id; break; }
        $scope.lua('uiSound("mnuselect.wav")'); wantPreviews();
      };
      $scope.openSub = function (sec, sub) { $scope.cur.section = sec.id; $scope.cur.sub = sub.id; $scope.cur.page = 0; $scope.cur.search = ''; $scope.lua('uiSound("flip.wav")'); wantPreviews(); };
      $scope.turn = function (d) { $scope.cur.page = Math.max(0, Math.min($scope.pageCount() - 1, $scope.cur.page + d)); $scope.lua('uiSound("flip.wav")'); wantPreviews(); };
      $scope.buy = function (it) { $scope.lua('buy(' + JSON.stringify(it.slotPath) + ',' + JSON.stringify(it.part) + ')'); };

      // ---- previews: ask Lua for the models of whatever is on screen
      var asked = {};
      $scope.hasMesh = function (part) { return !!meshes[part]; };
      $scope.photoKey = function (part) { return 'part_' + part + '_' + ($scope.s.photoStamp || ''); };
      $scope.hasPicture = function (part, photo) { return !!(photos[photo] && photos[photo].ready) || !!(clay[part] && clay[part].count); };
      var askedPhotos = {};
      function wantPreviews() {
        if (!$scope.s.previews) return;
        var names = [], items = [], catalogParts = [], i;
        var slots = $scope.visibleSlots();
        for (i = 0; i < slots.length; i++) if (slots[i]) { names.push(slots[i].part); items.push(slots[i].id); }
        if ($scope.s.phase === 'catalog') { var page = $scope.pageItems(); for (i = 0; i < page.length; i++) { names.push(page[i].part); catalogParts.push(page[i].part); } }
        if ($scope.s.photos) {
          // photographs: ask every time, the game side drops what is no longer on screen
          var key = items.join(',') + '|' + catalogParts.join(',');
          if (key !== askedPhotos.last) {
            askedPhotos.last = key;
            bngApi.engineLua('slrr_garage.requestPhotos(' + bngApi.serializeToLua(items) + ',' + bngApi.serializeToLua(catalogParts) + ')');
          }
          return;
        }
        var need = [];
        for (i = 0; i < names.length; i++) if (meshes[names[i]] === undefined && !asked[names[i]]) { asked[names[i]] = true; need.push(names[i]); }
        if (need.length) bngApi.engineLua('slrr_garage.requestPreviews(' + bngApi.serializeToLua(need) + ')');
      }
      $scope.$on('slrrGaragePhoto', function (ev, info) {
        if (!info || !info.key) return;
        if (info.none || !info.frames) { photos[info.key] = false; askedPhotos.last = null; return; }
        loadPhoto(info, function () { $scope.$evalAsync(function () {}); });
      });
      $scope.$on('slrrGaragePreview', function (ev, data) {
        if (!data || !data.part) return;
        if (data.none || !Array.isArray(data.v) || !Array.isArray(data.t) || !data.t.length) meshes[data.part] = false;
        else { raster.store(data.part, data.v, data.t); meshes[data.part] = true; delete clay[data.part]; }
        $scope.$evalAsync(function () {});
      });

      var rootEl = $element[0];
      var spinStart = Date.now(), lastDraw = 0, rafId = null, hoverTurn = {};
      function frame() {
        rafId = window.requestAnimationFrame(frame);
        var now = Date.now();
        if (now - lastDraw < 12) return;       // a higher bar would drop every other update of a 30 fps UI
        var dt = Math.min(0.1, (now - lastDraw) / 1000); lastDraw = now;
        if (!$scope.s.previews || $scope.s.phase === 'idle' || $scope.s.phase === 'film') return;
        var speed = ($scope.s.spinSpeed === undefined ? 1 : $scope.s.spinSpeed) * 0.75;
        var canvases = rootEl.querySelectorAll('canvas.sg-prev');
        var unfinished = [];                          // parts that still need pictures drawn
        for (var i = 0; i < canvases.length; i++) {
          var c = canvases[i], part = c.getAttribute('data-part');
          var photo = photos[c.getAttribute('data-photo')];
          var isPhoto = !!(photo && photo.ready), list, zoom, have;
          if (isPhoto) { list = photo.frames; zoom = 1.3; have = list.length; }
          else if (meshes[part]) {
            var entry = clay[part] || (clay[part] = { list: new Array(FRAMES), count: 0, used: 0 });
            entry.used = now;
            list = entry.list; zoom = 1.12; have = entry.count;
          } else { if (c.width) c.width = 0; continue; }
          var turn, moving = true;                    // position on the turntable, in turns
          if (c.getAttribute('data-spin') === 'always') {
            turn = ((now - spinStart) / 1000) * speed / (2 * Math.PI) + i * 0.11;
          } else {
            // shelf parts rest at a three-quarter view and turn while the cursor is on them
            turn = hoverTurn[part] === undefined ? 0.11 : hoverTurn[part];
            moving = !!(c.parentElement && c.parentElement.matches(':hover'));
            if (moving) turn += dt * speed * 1.5 / (2 * Math.PI);
            hoverTurn[part] = turn;
          }
          if (!isPhoto && have < FRAMES) {
            unfinished.push({ part: part, entry: clay[part], at: ((Math.floor(turn * FRAMES) % FRAMES) + FRAMES) % FRAMES });
            if (!have) { drawStep(part, unfinished[unfinished.length - 1].at); have = 1; }     // never leave a card empty
          }
          if (!have) { if (c.width) c.width = 0; continue; }
          var stamp = list.length + ':' + have + ':' + turn;
          if (!moving && c.__stamp === stamp && c.width === c.clientWidth) continue;
          c.__stamp = stamp;
          drawTurn(c, list, turn, zoom);
        }
        // spare time goes to the part that is furthest behind, starting from where it is showing now
        var drawUntil = now + DRAW_BUDGET;
        while (unfinished.length && Date.now() < drawUntil) {
          var job = unfinished[0];
          for (var u = 1; u < unfinished.length; u++) if (unfinished[u].entry.count < job.entry.count) job = unfinished[u];
          if (job.entry.count >= FRAMES) break;
          var step = job.at;
          while (job.entry.list[step]) step = (step + 1) % FRAMES;
          drawStep(job.part, step);
        }
        trimFrames(now);
      }
      rafId = window.requestAnimationFrame(frame);

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
      $scope.$on('slrrGarageTuning', function (ev, data) {
        $scope.$evalAsync(function () {
          var vars = (data && Array.isArray(data.vars)) ? data.vars : [];
          var cats = [];
          vars.forEach(function (v) {
            v.lo = Math.min(v.min, v.max); v.hi = Math.max(v.min, v.max); v.step = Math.abs(v.step) || ((v.hi - v.lo) / 100);
            if (cats.indexOf(v.category) < 0) cats.push(v.category);
          });
          var keep = (data && data.category) || $scope.tune.category;
          $scope.tune = { vars: vars, categories: cats, category: cats.indexOf(keep) >= 0 ? keep : (cats[0] || null), dirty: false };
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
        $scope.$evalAsync(function () { data = data || {}; if (!Array.isArray(data.rows)) data.rows = []; $scope.info = data; });
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
        if (d.type !== 'bool') { value = parseFloat(value); if (isNaN(value)) return; }
        d.value = value;
        bngApi.engineLua('slrr_garage.setSetting(' + JSON.stringify(d.key) + ',' + (d.type === 'bool' ? (value ? 'true' : 'false') : value) + ')');
      };

      // ---- 3D view input: left click acts, right drag orbits, wheel zooms, middle click focuses
      $scope.overUi = function (over) { $scope.lua('setMouseOverUi(' + (over ? 'true' : 'false') + ')'); };
      var down = null;
      $scope.viewDown = function (ev) {
        ev.preventDefault();
        down = { button: ev.button, x: ev.clientX, y: ev.clientY, lastX: ev.clientX, lastY: ev.clientY, moved: 0 };
        if (ev.button === 2) { $scope.drag.active = true; $scope.lua('setDragging(true)'); }
      };
      // Lua picks the part under the cursor itself; it only needs to know whether the cursor is
      // on the 3D view or on one of our panels. Worked out from every mouse move, so it can
      // never get stuck the wrong way round.
      var lastOverView = null;
      function trackOver(ev) {
        var t = ev.target;
        var overView = !!(t && t.classList && t.classList.contains('sg-view'));
        if (overView !== lastOverView) {
          lastOverView = overView;
          bngApi.engineLua('slrr_garage.setMouseOverUi(' + (overView ? 'false' : 'true') + ')');
        }
      }
      function onMove(ev) {
        if ($scope.s.phase === 'garage') trackOver(ev); else lastOverView = null;
        if (!down) return;
        var dx = ev.clientX - down.lastX, dy = ev.clientY - down.lastY;
        down.lastX = ev.clientX; down.lastY = ev.clientY;
        down.moved += Math.abs(dx) + Math.abs(dy);
        if (down.button === 2 && (dx || dy)) bngApi.engineLua('slrr_garage.cameraDrag(' + dx + ',' + dy + ')');
      }
      function onUp() {
        if (!down) return;
        var d = down; down = null;
        if (d.button === 2) { $scope.$evalAsync(function () { $scope.drag.active = false; }); $scope.lua('setDragging(false)'); return; }
        if (d.moved > 6 || $scope.s.phase !== 'garage') return;
        if (d.button === 0) $scope.lua('click()');
        else if (d.button === 1) $scope.lua('focus()');
      }
      function onWheel(ev) {
        if ($scope.s.phase !== 'garage') return;
        var t = ev.target;
        if (!t || !t.classList || !t.classList.contains('sg-view')) return;
        ev.preventDefault();
        bngApi.engineLua('slrr_garage.cameraZoom(' + (ev.deltaY < 0 ? 1 : -1) + ')');
      }
      window.addEventListener('mousemove', onMove);
      window.addEventListener('mouseup', onUp);
      window.addEventListener('wheel', onWheel, { passive: false });

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
          if (data.phase === 'idle' || data.phase === 'leaving') { $scope.panel = null; asked = {}; askedPhotos = {}; photos = {}; }
          if (data.mode !== 'tune' && $scope.panel === 'tune') $scope.panel = null;
          if (data.mode !== 'tune') $scope.pt = { vars: [] };
          wantPreviews();
        });
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
        if (rootEl.parentNode) rootEl.parentNode.removeChild(rootEl);
        if (placeholder.parentNode) placeholder.parentNode.removeChild(placeholder);
      });

      $scope.lua('requestState()');
    }]
  };
}]);
