
/// The complete third-person shooter, authored as a single QuickJS program.
///
/// Everything game-specific lives here as JavaScript: state management, the
/// 3D scene-graph DSL, enemy AI, weapons, particles/effects, the HUD, and the
/// on-screen touch controls. It drives Elpian's renderer through
/// `askHost('render', ...)` and runs its frame loop via `askHost('setInterval')`.
///
/// The world is a fully detailed, dusk-lit **downtown city block** — a grid of
/// streets and avenues with sidewalks, crosswalks and lane markings; a central
/// park with a working fountain; and a surrounding skyline of varied
/// high-rises with lit windows, neon storefront signage and rooftop machinery.
/// It is populated with diverse props (street lamps, traffic lights, benches,
/// hydrants, planters, trees, barriers, dumpsters, crates, bus stops, bollards,
/// billboards) and with **real glTF 2.0 / GLB models streamed live from the
/// internet** (the Khronos sample-asset CDN): the player and enemies are rigged
/// humanoids, delivery trucks are parked at the curb and drive the avenues with
/// spinning wheels, foxes roam the streets with their skeletal walk cycle, and
/// rubber ducks bob in the fountain.
///
/// Only foundational, reusable capabilities live in the Dart/Elpian layer: the
/// `GameScene` 3D widget, the geometry cache in the software renderer, and the
/// glTF 2.0 / GLB pipeline (streaming model loader, CPU skeletal-animation
/// skinning, and textured `drawVertices` batching). To keep the rich static
/// city cheap to stream every frame it is serialized to JSON exactly once at
/// boot and spliced into the per-frame payload, so only the moving entities are
/// re-encoded each tick.
library;

const String tpsGameProgram = r'''
// ════════════════════════════════════════════════════════════════════════
//  ELPIAN STRIKE FORCE — DOWNTOWN  ·  a third-person shooter in one script
// ════════════════════════════════════════════════════════════════════════

// ---- Typed-value decoding (event payloads arrive as Elpian typed values) ---
function decodeTypedValue(value) {
  if (value === null || value === undefined) return value;
  if (typeof value !== 'object') return value;
  if (!('type' in value) || !('data' in value)) return value;
  var t = value.type;
  var raw = (value.data || {}).value;
  if (t === 'object') {
    var o = {};
    if (raw && typeof raw === 'object') {
      for (var k in raw) { o[k] = decodeTypedValue(raw[k]); }
    }
    return o;
  }
  if (t === 'array') {
    if (!Array.isArray(raw)) return [];
    return raw.map(decodeTypedValue);
  }
  return raw;
}
function decodeEvent(input) {
  try { var v = decodeTypedValue(input); if (v && typeof v === 'object') return v; }
  catch (e) {}
  return {};
}

// ---- Tiny math helpers ----------------------------------------------------
var PI = Math.PI;
function numOr(v, d) { return (typeof v === 'number' && isFinite(v)) ? v : d; }
function clamp(v, a, b) { return v < a ? a : (v > b ? b : v); }
function lerp(a, b, t) { return a + (b - a) * t; }
function rand(a, b) { return a + Math.random() * (b - a); }
function deg(r) { return r * 180 / PI; }
function wrapAngle(a) { while (a > PI) a -= 2 * PI; while (a < -PI) a += 2 * PI; return a; }
// Step `cur` toward `target` (both radians) by at most `maxStep`, taking the
// shortest way around the circle. Used to make the camera trail the joystick.
function approachAngle(cur, target, maxStep) {
  var d = wrapAngle(target - cur);
  if (d > maxStep) d = maxStep; else if (d < -maxStep) d = -maxStep;
  return cur + d;
}
function dist2(ax, az, bx, bz) { var dx = bx - ax, dz = bz - az; return Math.sqrt(dx * dx + dz * dz); }
function col(r, g, b, a) { return { r: r, g: g, b: b, a: (a === undefined ? 1 : a) }; }
function vec(x, y, z) { return { x: x, y: y, z: z }; }

// Deterministic PRNG (mulberry32) so the procedurally-built city is identical
// every run — a designed layout, not random noise each launch.
var _seed = 0x51f57a1d;
function sreset() { _seed = 0x51f57a1d; }
function srand() {
  _seed |= 0; _seed = (_seed + 0x6D2B79F5) | 0;
  var t = Math.imul(_seed ^ (_seed >>> 15), 1 | _seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
function srange(a, b) { return a + srand() * (b - a); }
function spick(arr) { return arr[Math.floor(srand() * arr.length) % arr.length]; }

// ---- Tunables -------------------------------------------------------------
var DT = 0.0333;
var PLAY = 15.5;            // half-extent the player/enemies may roam (the square + ring road)
var SPAWN_R = 14.0;        // radius hostiles spawn at (street ring around the park)
var PARK = 10.0;           // half-extent of the central park block
var CITY = 36.0;           // visual extent of the surrounding city
var PLAYER_RADIUS = 0.5;
var CAM_DIST = 6.4, CAM_LOOK_H = 1.55;
var MOVE_SPEED = 6.4;
var GRAVITY = 19.0, JUMP_V = 7.4;
var FIRE_COOLDOWN = 0.11;
var MAG_SIZE = 24, RESERVE_START = 120;
var RELOAD_TIME = 1.15;
var BULLET_RANGE = 64;
var BULLET_DMG = 26;
var LOOK_SENS_X = 0.0066, LOOK_SENS_Y = 0.0055;
// How fast (rad/s) the camera yaw swings to follow the joystick travel
// direction, so the view + gun automatically aim where the player is heading.
var CAM_FOLLOW_RATE = 7.0;
var JOY = 132, JOY_HALF = 66, THUMB = 56;

// ---- Viewport (read from host environment) --------------------------------
var VP = { w: 420, h: 840 };
function readViewport() {
  var env = globalThis.__ELPIAN_HOST_ENV__ || globalThis.ELPIAN_HOST_ENV;
  if (env && env.viewport) {
    VP.w = numOr(env.viewport.width, VP.w);
    VP.h = numOr(env.viewport.height, VP.h);
  }
}

// ---- Real glTF 2.0 / GLB models, streamed live from the internet ----------
// Downloaded, parsed, skinned and animated on the fly by Elpian's renderer
// from the Khronos sample-asset CDN (CORS-enabled). Capsule placeholders stand
// in until each model arrives. Dimensions/clip names below were measured from
// the assets so they sit on the ground at a believable scale.
var GLTF_BASE = 'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/';
var MODEL_PLAYER = GLTF_BASE + 'CesiumMan/glTF-Binary/CesiumMan.glb';        // rigged walking human (player)
var MODEL_GRUNT  = GLTF_BASE + 'RiggedFigure/glTF-Binary/RiggedFigure.glb';  // articulated humanoid (grunt)
var MODEL_HEAVY  = GLTF_BASE + 'RiggedFigure/glTF-Binary/RiggedFigure.glb';  // (heavy — up-scaled + tinted)
var MODEL_TRUCK  = GLTF_BASE + 'CesiumMilkTruck/glTF-Binary/CesiumMilkTruck.glb'; // delivery truck (Wheels clip)
var MODEL_FOX    = GLTF_BASE + 'Fox/glTF-Binary/Fox.glb';                    // animal (Survey/Walk/Run clips)
var MODEL_DUCK   = GLTF_BASE + 'Duck/glTF-Binary/Duck.glb';                  // classic rubber duck

// Per-model tuning: uniform scale + yaw offset (deg) so each rig faces its
// travel direction in Elpian's -Z-forward, +Y-up world, and grounding offsets
// for models whose origin sits at their centre rather than their feet.
var PLAYER_SCALE = 1.12, PLAYER_YAW = 180;
var GRUNT_SCALE = 1.15, GRUNT_YAW = 180;
var HEAVY_SCALE = 1.62, HEAVY_YAW = 180;
var TRUCK_SCALE = 1.0, TRUCK_YAW = 90, TRUCK_Y = 1.42;   // bbox y ±1.4 → lift to rest wheels on the road
var FOX_SCALE = 0.011, FOX_YAW = 180;                    // native ~79 units tall → dog-sized
var DUCK_SCALE = 0.0036, DUCK_YAW = 0;                   // native ~164 units tall → ~0.6 tall

// ════════════════════════════════════════════════════════════════════════
//  GAME STATE
// ════════════════════════════════════════════════════════════════════════
var G = null;
var CITY_FRAGMENT = '';   // the entire static city, serialized to JSON once at boot

function newGame() {
  var city = buildCity();
  CITY_FRAGMENT = city.fragment;
  G = {
    state: 'menu',
    time: 0,
    wave: 0, kills: 0, score: 0,
    player: { x: 0, z: 7, y: 0, vy: 0, yaw: 0, health: 100, maxHealth: 100, grounded: true, hurtT: 0, animTime: 0 },
    cam: { yaw: 0.5, pitch: -0.22, recoil: 0 },
    weapon: { mag: MAG_SIZE, reserve: RESERVE_START, reloading: false, reloadT: 0, cool: 0 },
    input: { joyActive: false, jx: 0, jz: 0, jmag: 0, jdx: 0, jdy: 0, firing: false, joyPointer: -1 },
    enemies: [],
    ebullets: [],
    fx: [],
    pickups: [],
    enemiesToSpawn: 0, spawnT: 0,
    hitMarker: 0, banner: 0, bannerText: '',
    obstacles: city.obstacles,
    foxes: makeFoxes(),
    traffic: makeTraffic(),
    ducks: makeDucks()
  };
}

// ════════════════════════════════════════════════════════════════════════
//  CORE VECTOR / AIM
// ════════════════════════════════════════════════════════════════════════
function forwardVec(yaw, pitch) {
  return {
    x: Math.sin(yaw) * Math.cos(pitch),
    y: Math.sin(pitch),
    z: -Math.cos(yaw) * Math.cos(pitch)
  };
}
function camPitchEff() { return clamp(G.cam.pitch + G.cam.recoil, -1.2, 0.5); }
function camForward() { return forwardVec(G.cam.yaw, camPitchEff()); }

function aimDir() {
  var f = camForward();
  var p = G.player, mx = p.x, my = p.y + CAM_LOOK_H, mz = p.z;
  var best = null, bestDot = Math.cos(0.21), bestDist = 1e9;
  for (var i = 0; i < G.enemies.length; i++) {
    var e = G.enemies[i];
    if (!e.alive) continue;
    var dx = e.x - mx, dy = (e.y + 1.0) - my, dz = e.z - mz;
    var d = Math.sqrt(dx * dx + dy * dy + dz * dz);
    if (d < 0.001 || d > BULLET_RANGE) continue;
    var dot = (dx * f.x + dy * f.y + dz * f.z) / d;
    if (dot > bestDot && d < bestDist) { best = { x: dx / d, y: dy / d, z: dz / d }; bestDist = d; }
  }
  return best || f;
}

// ════════════════════════════════════════════════════════════════════════
//  COLLISION
// ════════════════════════════════════════════════════════════════════════
function resolveObstacles(o, radius) {
  for (var i = 0; i < G.obstacles.length; i++) {
    var b = G.obstacles[i];
    var hx = b.sx / 2 + radius, hz = b.sz / 2 + radius;
    var dx = o.x - b.x, dz = o.z - b.z;
    if (Math.abs(dx) < hx && Math.abs(dz) < hz) {
      var px = hx - Math.abs(dx), pz = hz - Math.abs(dz);
      if (px < pz) { o.x = b.x + (dx < 0 ? -hx : hx); }
      else { o.z = b.z + (dz < 0 ? -hz : hz); }
    }
  }
}
function rayBlocked(mx, my, mz, dir, maxT) {
  var step = 0.45, t = 0;
  while (t < maxT) {
    var x = mx + dir.x * t, y = my + dir.y * t, z = mz + dir.z * t;
    if (y < 0) return t;
    for (var i = 0; i < G.obstacles.length; i++) {
      var b = G.obstacles[i];
      if (Math.abs(x - b.x) < b.sx / 2 && Math.abs(z - b.z) < b.sz / 2 && y < b.sy && y > 0) return t;
    }
    t += step;
  }
  return maxT;
}
function hasLineOfSight(e, p) {
  var ax = e.x, ay = 1.1, az = e.z;
  var dx = p.x - ax, dy = (p.y + 1.0) - ay, dz = p.z - az;
  var d = Math.sqrt(dx * dx + dy * dy + dz * dz);
  if (d < 0.001) return true;
  dx /= d; dy /= d; dz /= d;
  var t = 0.5;
  while (t < d) {
    var x = ax + dx * t, y = ay + dy * t, z = az + dz * t;
    for (var i = 0; i < G.obstacles.length; i++) {
      var b = G.obstacles[i];
      if (Math.abs(x - b.x) < b.sx / 2 && Math.abs(z - b.z) < b.sz / 2 && y < b.sy && y > 0) return false;
    }
    t += 0.55;
  }
  return true;
}

// ════════════════════════════════════════════════════════════════════════
//  WEAPONS / EFFECTS
// ════════════════════════════════════════════════════════════════════════
function addTracer(ax, ay, az, bx, by, bz) { G.fx.push({ k: 'tracer', ax: ax, ay: ay, az: az, bx: bx, by: by, bz: bz, life: 0.075, max: 0.075 }); }
function addMuzzle(x, y, z) { G.fx.push({ k: 'muzzle', x: x, y: y, z: z, life: 0.06, max: 0.06 }); }
function addImpact(x, y, z, c) { G.fx.push({ k: 'impact', x: x, y: y, z: z, color: c, life: 0.28, max: 0.28 }); }

function fireHitscan() {
  var p = G.player;
  var dir = aimDir();
  var mx = p.x + dir.x * 0.6, my = p.y + CAM_LOOK_H + dir.y * 0.6, mz = p.z + dir.z * 0.6;
  var bestT = rayBlocked(mx, my, mz, dir, BULLET_RANGE);
  var hit = null;
  for (var i = 0; i < G.enemies.length; i++) {
    var e = G.enemies[i];
    if (!e.alive) continue;
    var ex = e.x - mx, ey = (e.y + 1.05) - my, ez = e.z - mz;
    var t = ex * dir.x + ey * dir.y + ez * dir.z;
    if (t < 0 || t > bestT) continue;
    var cx = mx + dir.x * t, cy = my + dir.y * t, cz = mz + dir.z * t;
    var dd = Math.sqrt((cx - e.x) * (cx - e.x) + (cy - (e.y + 1.05)) * (cy - (e.y + 1.05)) + (cz - e.z) * (cz - e.z));
    if (dd < 0.75) { bestT = t; hit = e; }
  }
  var hx = mx + dir.x * bestT, hy = my + dir.y * bestT, hz = mz + dir.z * bestT;
  addTracer(mx, my, mz, hx, hy, hz);
  addMuzzle(mx, my, mz);
  if (hit) { damageEnemy(hit, BULLET_DMG, hx, hy, hz); G.hitMarker = 0.16; }
  else { addImpact(hx, hy, hz, col(0.95, 0.88, 0.7)); }
}

function damageEnemy(e, dmg, hx, hy, hz) {
  e.health -= dmg; e.flash = 0.12;
  addImpact(hx, hy, hz, col(1.0, 0.45, 0.25));
  if (e.health <= 0 && e.alive) {
    e.alive = false; e.dying = 0.5;
    G.kills++; G.score += e.score;
    for (var i = 0; i < 7; i++) addImpact(e.x + rand(-0.4, 0.4), 0.6 + rand(0, 1.1), e.z + rand(-0.4, 0.4), col(1.0, 0.35, 0.2));
    maybeDropPickup(e);
  }
}

function startReload() {
  var w = G.weapon;
  if (w.reloading || w.mag === MAG_SIZE || w.reserve <= 0) return;
  w.reloading = true; w.reloadT = RELOAD_TIME;
}
function finishReload() {
  var w = G.weapon;
  var take = Math.min(MAG_SIZE - w.mag, w.reserve);
  w.mag += take; w.reserve -= take; w.reloading = false;
}

// ════════════════════════════════════════════════════════════════════════
//  ENEMIES
// ════════════════════════════════════════════════════════════════════════
function countAlive() { var n = 0; for (var i = 0; i < G.enemies.length; i++) if (G.enemies[i].alive) n++; return n; }

function spawnEnemy() {
  var ang = Math.random() * PI * 2;
  var ex = Math.cos(ang) * SPAWN_R, ez = Math.sin(ang) * SPAWN_R;
  var heavy = (G.wave >= 3 && Math.random() < 0.32);
  var ne = {
    x: ex, z: ez, y: 0, yaw: 0, animTime: rand(0, 2),
    health: heavy ? 170 : 80, maxHealth: heavy ? 170 : 80, alive: true, flash: 0, dying: 0,
    speed: heavy ? 2.5 : 3.5, attackRange: heavy ? 6 : 9, viewRange: 30,
    fireT: rand(0.6, 1.8), fireRate: heavy ? 1.5 : 2.0, projSpeed: heavy ? 13 : 11,
    dmg: heavy ? 16 : 10, melee: 26, score: heavy ? 25 : 10, type: heavy ? 'heavy' : 'grunt'
  };
  resolveObstacles(ne, 0.55);          // never spawn embedded in a curb/prop
  ne.x = clamp(ne.x, -PLAY + 1, PLAY - 1);
  ne.z = clamp(ne.z, -PLAY + 1, PLAY - 1);
  G.enemies.push(ne);
}

function enemyShoot(e, p) {
  var ax = e.x, ay = 1.15, az = e.z;
  var dx = p.x - ax, dy = (p.y + 1.0) - ay, dz = p.z - az;
  var d = Math.sqrt(dx * dx + dy * dy + dz * dz);
  if (d < 0.01) return;
  var s = e.projSpeed;
  G.ebullets.push({ x: ax, y: ay, z: az, vx: dx / d * s, vy: dy / d * s, vz: dz / d * s, life: 3.5, dmg: e.dmg });
  addImpact(ax + dx / d * 0.6, ay + dy / d * 0.6, az + dz / d * 0.6, col(1.0, 0.5, 0.15));
}

function updateEnemies() {
  var p = G.player;
  for (var i = 0; i < G.enemies.length; i++) {
    var e = G.enemies[i];
    if (e.flash > 0) e.flash -= DT;
    if (!e.alive) { e.dying -= DT; continue; }
    var dx = p.x - e.x, dz = p.z - e.z;
    var d = Math.sqrt(dx * dx + dz * dz);
    e.yaw = Math.atan2(dx, -dz);
    if (d > e.attackRange) {
      var sp = e.speed * DT;
      e.x += dx / d * sp; e.z += dz / d * sp;
      resolveObstacles(e, 0.55);
      e.x = clamp(e.x, -PLAY + 0.6, PLAY - 0.6);
      e.z = clamp(e.z, -PLAY + 0.6, PLAY - 0.6);
      // Drive the skeletal walk cycle while the enemy is on the move.
      e.animTime += DT * (1.0 + e.speed * 0.16);
    }
    e.fireT -= DT;
    if (G.state === 'playing' && d < e.viewRange && e.fireT <= 0 && hasLineOfSight(e, p)) {
      e.fireT = e.fireRate; enemyShoot(e, p);
    }
    if (d < 1.2) hurtPlayer(e.melee * DT);
  }
  G.enemies = G.enemies.filter(function (e) { return e.alive || e.dying > 0; });
}

// ════════════════════════════════════════════════════════════════════════
//  PROJECTILES / PICKUPS / WAVES
// ════════════════════════════════════════════════════════════════════════
function updateEBullets() {
  var p = G.player;
  for (var i = 0; i < G.ebullets.length; i++) {
    var b = G.ebullets[i];
    b.x += b.vx * DT; b.y += b.vy * DT; b.z += b.vz * DT; b.life -= DT;
    var dx = b.x - p.x, dy = b.y - (p.y + 1.0), dz = b.z - p.z;
    if (dx * dx + dy * dy + dz * dz < 0.62 * 0.62) { hurtPlayer(b.dmg); b.life = 0; addImpact(b.x, b.y, b.z, col(1, 0.4, 0.2)); continue; }
    if (b.y < 0) { b.life = 0; addImpact(b.x, 0.05, b.z, col(0.85, 0.5, 0.2)); continue; }
    for (var j = 0; j < G.obstacles.length; j++) {
      var o = G.obstacles[j];
      if (Math.abs(b.x - o.x) < o.sx / 2 && Math.abs(b.z - o.z) < o.sz / 2 && b.y < o.sy && b.y > 0) { b.life = 0; addImpact(b.x, b.y, b.z, col(0.85, 0.5, 0.2)); break; }
    }
  }
  G.ebullets = G.ebullets.filter(function (b) { return b.life > 0; });
}

function maybeDropPickup(e) {
  var r = Math.random();
  if (r < 0.20) G.pickups.push({ x: e.x, z: e.z, y: 0.6, kind: 'health', spin: 0 });
  else if (r < 0.46) G.pickups.push({ x: e.x, z: e.z, y: 0.6, kind: 'ammo', spin: 0 });
}
function updatePickups() {
  var p = G.player;
  for (var i = 0; i < G.pickups.length; i++) {
    var pk = G.pickups[i];
    pk.spin += DT * 130;
    if (dist2(pk.x, pk.z, p.x, p.z) < 1.25) {
      pk.taken = true;
      if (pk.kind === 'health') { p.health = clamp(p.health + 30, 0, p.maxHealth); flashBanner('+30 HP', 1.0); addImpact(pk.x, 1.0, pk.z, col(0.3, 1, 0.4)); }
      else { G.weapon.reserve += 24; flashBanner('+24 AMMO', 1.0); addImpact(pk.x, 1.0, pk.z, col(1, 0.85, 0.3)); }
    }
  }
  G.pickups = G.pickups.filter(function (pk) { return !pk.taken; });
}

function startWave(n) {
  G.wave = n;
  G.enemiesToSpawn = 3 + n * 2;
  G.spawnT = 0;
  flashBanner('WAVE ' + n, 2.0);
}
function updateWaves() {
  if (G.state !== 'playing') return;
  if (G.enemiesToSpawn > 0) {
    G.spawnT -= DT;
    if (G.spawnT <= 0 && countAlive() < 7) { spawnEnemy(); G.enemiesToSpawn--; G.spawnT = 0.7; }
  } else if (G.enemies.length === 0) {
    startWave(G.wave + 1);
  }
}
function flashBanner(txt, t) { G.bannerText = txt; G.banner = t; }

// ════════════════════════════════════════════════════════════════════════
//  PLAYER
// ════════════════════════════════════════════════════════════════════════
function hurtPlayer(dmg) {
  if (G.state !== 'playing') return;
  G.player.health -= dmg; G.player.hurtT = 0.5;
  if (G.player.health <= 0) { G.player.health = 0; G.state = 'dead'; G.input.firing = false; }
}

function updatePlayer() {
  var p = G.player, inp = G.input, c = G.cam, w = G.weapon;
  // Single-stick steering. The joystick maps to an ABSOLUTE world heading
  // (up = forward / world -Z, right = world +X), independent of where the
  // camera is currently pointing. The camera then yaws to FOLLOW that heading,
  // so the direction you push == the way the player runs == where the camera
  // looks == the gun's aim.
  var mx = inp.jx;    // stick right -> world +X
  var mz = -inp.jz;   // stick up    -> world -Z (forward, into the city)
  var ml = Math.sqrt(mx * mx + mz * mz);
  var movingNow = false;
  if (ml > 0.001) {
    mx /= ml; mz /= ml;
    var spd = MOVE_SPEED * Math.min(1, inp.jmag);
    p.x += mx * spd * DT; p.z += mz * spd * DT;
    movingNow = inp.jmag > 0.06;
    var targetYaw = Math.atan2(mx, -mz);
    c.yaw = approachAngle(c.yaw, targetYaw, CAM_FOLLOW_RATE * Math.min(1, inp.jmag) * DT);
  }
  p.animTime += DT * (movingNow ? (1.1 + Math.min(1, inp.jmag) * 0.7) : 0.0);
  p.yaw = c.yaw;
  p.x = clamp(p.x, -PLAY + 0.7, PLAY - 0.7);
  p.z = clamp(p.z, -PLAY + 0.7, PLAY - 0.7);
  resolveObstacles(p, PLAYER_RADIUS);

  if (!p.grounded || p.y > 0) {
    p.vy -= GRAVITY * DT; p.y += p.vy * DT;
    if (p.y <= 0) { p.y = 0; p.vy = 0; p.grounded = true; }
  }

  if (w.cool > 0) w.cool -= DT;
  if (w.reloading) { w.reloadT -= DT; if (w.reloadT <= 0) finishReload(); }
  if (inp.firing && !w.reloading && w.cool <= 0) {
    if (w.mag > 0) { w.mag--; w.cool = FIRE_COOLDOWN; c.recoil = Math.min(0.10, c.recoil + 0.022); fireHitscan(); }
    else { startReload(); }
  }
  c.recoil *= 0.80;
  if (p.hurtT > 0) p.hurtT -= DT;
  if (p.hurtT <= 0 && p.health < p.maxHealth) p.health = clamp(p.health + 7 * DT, 0, p.maxHealth);
}

function updateFx() {
  for (var i = 0; i < G.fx.length; i++) G.fx[i].life -= DT;
  G.fx = G.fx.filter(function (f) { return f.life > 0; });
  if (G.hitMarker > 0) G.hitMarker -= DT;
  if (G.banner > 0) G.banner -= DT;
}

// ════════════════════════════════════════════════════════════════════════
//  AMBIENT CITY LIFE  (foxes, traffic, fountain ducks)
// ════════════════════════════════════════════════════════════════════════
function makeFoxes() {
  var arr = [];
  for (var i = 0; i < 4; i++) {
    var a = rand(0, PI * 2), r = rand(4, PLAY - 2);
    arr.push({ x: Math.cos(a) * r, z: Math.sin(a) * r, yaw: rand(-PI, PI), animTime: rand(0, 3), tx: 0, tz: 0, repick: 0 });
  }
  return arr;
}
function makeTraffic() {
  // Trucks cruise the outer avenue segments (well beyond the play bound) so the
  // city reads as alive without driving through the plaza.
  return [
    { axis: 'z', lane: 1.9, pos: 16, dir: 1, speed: 7.5, animTime: 0, tint: col(0.92, 0.93, 0.96) },
    { axis: 'z', lane: -1.9, pos: -36, dir: 1, speed: 6.0, animTime: 0, tint: col(0.55, 0.62, 0.78) },
    { axis: 'x', lane: 1.9, pos: -36, dir: 1, speed: 6.8, animTime: 0, tint: col(0.80, 0.32, 0.28) }
  ];
}
function makeDucks() {
  return [
    { ang: 0.0, r: 0.95, bob: rand(0, PI * 2), spin: 1.0 },
    { ang: 2.1, r: 0.70, bob: rand(0, PI * 2), spin: -0.8 },
    { ang: 4.3, r: 1.10, bob: rand(0, PI * 2), spin: 0.6 }
  ];
}
function updateAmbient() {
  // ---- foxes wander the streets, steering around obstacles ----
  for (var i = 0; i < G.foxes.length; i++) {
    var fx = G.foxes[i];
    fx.repick -= DT;
    var dx = fx.tx - fx.x, dz = fx.tz - fx.z, dd = Math.sqrt(dx * dx + dz * dz);
    if (dd < 0.8 || fx.repick <= 0) {
      var a = rand(0, PI * 2), r = rand(3, PLAY - 2);
      fx.tx = Math.cos(a) * r; fx.tz = Math.sin(a) * r; fx.repick = rand(2.5, 6);
      dx = fx.tx - fx.x; dz = fx.tz - fx.z; dd = Math.sqrt(dx * dx + dz * dz) || 1;
    }
    var sp = 2.6 * DT;
    fx.x += dx / dd * sp; fx.z += dz / dd * sp;
    resolveObstacles(fx, 0.4);
    fx.x = clamp(fx.x, -PLAY + 0.8, PLAY - 0.8);
    fx.z = clamp(fx.z, -PLAY + 0.8, PLAY - 0.8);
    fx.yaw = Math.atan2(dx, -dz);
    fx.animTime += DT * 1.9;
  }
  // ---- traffic loops the far avenues ----
  for (var t = 0; t < G.traffic.length; t++) {
    var tr = G.traffic[t];
    tr.pos += tr.dir * tr.speed * DT;
    if (tr.pos > CITY + 4) tr.pos = -CITY - 4;
    if (tr.pos < -CITY - 4) tr.pos = CITY + 4;
    tr.animTime += DT * tr.speed * 0.15;
  }
  // ---- ducks paddle around the fountain ----
  for (var d = 0; d < G.ducks.length; d++) {
    var dk = G.ducks[d];
    dk.ang += DT * dk.spin * 0.5;
    dk.bob += DT * 2.4;
  }
}

function updateGame() {
  G.time += DT;
  updateAmbient();
  if (G.state === 'menu') { G.cam.yaw += DT * 0.12; updateFx(); return; }
  if (G.state === 'dead') { updateEnemies(); updateEBullets(); updateFx(); return; }
  updatePlayer();
  updateWaves();
  updateEnemies();
  updateEBullets();
  updatePickups();
  updateFx();
}

// ════════════════════════════════════════════════════════════════════════
//  3D SCENE DSL  (geometry helpers)
// ════════════════════════════════════════════════════════════════════════
function meshOf(shape, params) {
  if (!params) return shape;
  var m = { shape: shape };
  for (var k in params) m[k] = params[k];
  return m;
}
function mesh3d(shape, pos, rot, scale, mat, params) {
  return {
    type: 'mesh3d', mesh: meshOf(shape, params), material: mat,
    transform: { position: pos, rotation: rot || vec(0, 0, 0), scale: scale || vec(1, 1, 1) }
  };
}
function box(pos, size, mat) { return mesh3d('Cube', pos, vec(0, 0, 0), size, mat); }
function boxR(pos, size, yawDeg, mat) { return mesh3d('Cube', pos, vec(0, yawDeg, 0), size, mat); }
function cyl(pos, radius, height, rot, mat, seg) { return mesh3d('Cylinder', pos, rot || vec(0, 0, 0), vec(1, 1, 1), mat, { radius: radius, height: height, segments: seg || 12 }); }
function cone3(pos, radius, height, rot, mat, seg) { return mesh3d('Cone', pos, rot || vec(0, 0, 0), vec(1, 1, 1), mat, { radius: radius, height: height, segments: seg || 10 }); }
function sph(pos, r, mat, seg) { return mesh3d('Sphere', pos, vec(0, 0, 0), vec(1, 1, 1), mat, { radius: r, segments: seg || 12 }); }
function plane(pos, size, mat) { return mesh3d('Plane', pos, vec(0, 0, 0), vec(1, 1, 1), mat, { size: size }); }

function matC(c, o) {
  o = o || {};
  var m = { base_color: c, metallic: o.metallic || 0.0, roughness: (o.roughness === undefined ? 0.7 : o.roughness) };
  if (o.emissive) { m.emissive = o.emissive; m.emissive_strength = o.estr || 1.0; }
  if (o.unlit) m.unlit = true;
  if (o.alpha !== undefined) { m.alpha = o.alpha; m.alpha_mode = 'blend'; }
  if (o.double) m.double_sided = true;
  if (o.tex) { m.texture = o.tex; if (o.tex2) m.texture_color2 = o.tex2; if (o.texScale) m.texture_scale = o.texScale; }
  return m;
}
function mixHurt(c, h) { if (h <= 0) return c; return col(lerp(c.r, 1, h), lerp(c.g, 0.3, h), lerp(c.b, 0.3, h)); }
function neon(c, str) { return matC(c, { unlit: true, emissive: c, estr: str || 2.2 }); }

// Emit a real rigged glTF character/vehicle node. The renderer streams/caches
// the model, samples the requested clip at `animTime`, skins the mesh on the
// CPU and draws it textured + lit. `yaw` is the entity's facing (radians);
// `yawOff` rotates the rig to face its travel direction.
function modelNode(url, x, y, z, yaw, animTime, scale, yawOff, opts) {
  opts = opts || {};
  var n = {
    type: 'model3d',
    model: url,
    anim_time: animTime,
    transform: {
      position: vec(x, y, z),
      rotation: vec(0, deg(yaw) + (yawOff || 0), 0),
      scale: vec(scale, scale, scale)
    }
  };
  if (opts.anim !== undefined) n.animation = opts.anim;     // glTF clip name / index
  if (opts.tint) n.tint = opts.tint;
  if (opts.emissive) { n.emissive = opts.emissive; n.emissive_strength = opts.estr || 1.0; }
  return n;
}

// A held weapon prop, parented to the character's right side and aimed along
// its facing. (The glTF rigs have no gun, so we attach one procedurally.)
function addWeaponProp(w, x, y, z, yaw) {
  var ch = [];
  ch.push(box(vec(0, 0, -0.42), vec(0.12, 0.12, 0.72), matC(col(0.08, 0.09, 0.11), { roughness: 0.4, metallic: 0.6 })));
  ch.push(box(vec(0, 0, -0.88), vec(0.10, 0.10, 0.18), matC(col(0.05, 0.05, 0.06), {})));
  ch.push(box(vec(0, -0.13, -0.06), vec(0.08, 0.18, 0.12), matC(col(0.10, 0.10, 0.13), { roughness: 0.5 })));
  var rgtx = Math.cos(yaw), rgtz = Math.sin(yaw), fwx = Math.sin(yaw), fwz = -Math.cos(yaw);
  var gx = x + rgtx * 0.32 + fwx * 0.14;
  var gz = z + rgtz * 0.32 + fwz * 0.14;
  w.push({ type: 'group', transform: { position: vec(gx, y + 1.15, gz), rotation: vec(0, deg(yaw), 0), scale: vec(1, 1, 1) }, children: ch });
}

function addPlayerModel(w) {
  var p = G.player;
  var opts = {};
  if (p.hurtT > 0) { var h = clamp(p.hurtT / 0.5, 0, 1); opts.emissive = col(0.7 * h, 0.04, 0.04); opts.estr = 2.2; }
  w.push(modelNode(MODEL_PLAYER, p.x, p.y, p.z, p.yaw, p.animTime, PLAYER_SCALE, PLAYER_YAW, opts));
  addWeaponProp(w, p.x, p.y, p.z, p.yaw);
}

function addEnemyModel(w, e) {
  var heavy = e.type === 'heavy';
  var sc = heavy ? HEAVY_SCALE : GRUNT_SCALE;
  var topple = 0;
  if (!e.alive) { var k = clamp(e.dying / 0.5, 0, 1); sc *= Math.max(0.2, k); topple = (1 - k) * 82; }
  var opts = { tint: heavy ? col(0.72, 0.45, 1.0) : col(1.0, 0.55, 0.5) };
  if (e.flash > 0) { opts.emissive = col(0.95, 0.92, 0.92); opts.estr = 2.0; }
  else { opts.emissive = heavy ? col(0.20, 0.0, 0.24) : col(0.22, 0.0, 0.0); opts.estr = 0.55; }
  var url = heavy ? MODEL_HEAVY : MODEL_GRUNT;
  var yawOff = heavy ? HEAVY_YAW : GRUNT_YAW;
  var n = modelNode(url, e.x, e.y, e.z, e.yaw, e.animTime, sc, yawOff, opts);
  n.transform.rotation = vec(topple, deg(e.yaw) + yawOff, 0);
  w.push(n);
  if (e.alive) {
    var frac = clamp(e.health / e.maxHealth, 0, 1);
    w.push(box(vec(e.x, 2.4, e.z), vec(1.0, 0.10, 0.06), matC(col(0.08, 0.08, 0.08), { unlit: true })));
    w.push(box(vec(e.x - (1.0 * (1 - frac)) / 2, 2.41, e.z), vec(Math.max(0.03, 1.0 * frac), 0.13, 0.07),
      matC(frac > 0.5 ? col(0.2, 0.9, 0.3) : col(0.95, 0.6, 0.1), { unlit: true, emissive: col(0.1, 0.4, 0.1), estr: 0.4 })));
  }
}

function addAmbientModels(w) {
  // Foxes trotting through the streets (skeletal Walk clip, driven per-fox).
  for (var i = 0; i < G.foxes.length; i++) {
    var fx = G.foxes[i];
    w.push(modelNode(MODEL_FOX, fx.x, 0, fx.z, fx.yaw, fx.animTime, FOX_SCALE, FOX_YAW, { anim: 'Walk', tint: col(0.95, 0.55, 0.22) }));
  }
  // Delivery trucks cruising the far avenues, wheels spinning (Wheels clip).
  for (var t = 0; t < G.traffic.length; t++) {
    var tr = G.traffic[t];
    var tx, tz, tyaw;
    if (tr.axis === 'z') { tx = tr.lane; tz = tr.pos; tyaw = tr.dir > 0 ? 0 : PI; }
    else { tx = tr.pos; tz = tr.lane; tyaw = tr.dir > 0 ? PI / 2 : -PI / 2; }
    w.push(modelNode(MODEL_TRUCK, tx, TRUCK_Y, tz, tyaw, tr.animTime, TRUCK_SCALE, TRUCK_YAW, { anim: 'Wheels', tint: tr.tint }));
  }
  // Rubber ducks bobbing in the fountain (centre of the park, y from water line).
  for (var d = 0; d < G.ducks.length; d++) {
    var dk = G.ducks[d];
    var dx = Math.cos(dk.ang) * dk.r, dz = Math.sin(dk.ang) * dk.r;
    var by = 0.62 + Math.sin(dk.bob) * 0.04;
    w.push(modelNode(MODEL_DUCK, dx, by, dz, dk.ang + PI / 2, 0, DUCK_SCALE, DUCK_YAW, { tint: col(1.0, 0.92, 0.3) }));
  }
}

function addEffects(w) {
  for (var i = 0; i < G.fx.length; i++) {
    var f = G.fx[i], a = clamp(f.life / f.max, 0, 1);
    if (f.k === 'muzzle') {
      var s = 0.32 + (1 - a) * 0.22;
      w.push(box(vec(f.x, f.y, f.z), vec(s, s, s), matC(col(1, 0.9, 0.45), { unlit: true, emissive: col(1, 0.85, 0.3), estr: 3, alpha: a })));
    } else if (f.k === 'impact') {
      var r = 0.16 + (1 - a) * 0.55;
      w.push(mesh3d('Sphere', vec(f.x, f.y, f.z), vec(0, 0, 0), vec(1, 1, 1),
        matC(f.color || col(1, 0.8, 0.4), { unlit: true, emissive: f.color || col(1, 0.8, 0.4), estr: 2, alpha: a }), { radius: r, segments: 6 }));
    } else if (f.k === 'tracer') {
      var n = 6;
      for (var j = 0; j < n; j++) {
        var tt = j / (n - 1);
        w.push(mesh3d('Sphere', vec(lerp(f.ax, f.bx, tt), lerp(f.ay, f.by, tt), lerp(f.az, f.bz, tt)), vec(0, 0, 0), vec(1, 1, 1),
          matC(col(1, 0.95, 0.6), { unlit: true, emissive: col(1, 0.9, 0.4), estr: 3, alpha: a }), { radius: 0.05, segments: 4 }));
      }
    }
  }
}

// ════════════════════════════════════════════════════════════════════════
//  STATIC CITY BUILDER  (runs once at boot, serialized into CITY_FRAGMENT)
// ════════════════════════════════════════════════════════════════════════
var _CN = null;   // collected static scene nodes
var _OB = null;   // collected collision boxes {x,z,sx,sy,sz}

function cnPush(n) { _CN.push(n); }
function obBox(x, z, sx, sy, sz) { _OB.push({ x: x, z: z, sx: sx, sy: sy, sz: sz }); }

// ---- Material palette -----------------------------------------------------
function mAsphalt() { return matC(col(0.085, 0.090, 0.105), { roughness: 0.95, tex: 'noise', tex2: col(0.12, 0.125, 0.14), texScale: 26 }); }
function mConcrete() { return matC(col(0.48, 0.49, 0.52), { roughness: 0.9, tex: 'noise', tex2: col(0.42, 0.43, 0.46), texScale: 14 }); }
function mCurb() { return matC(col(0.58, 0.59, 0.62), { roughness: 0.85 }); }
function mGrass() { return matC(col(0.15, 0.33, 0.16), { roughness: 1.0, tex: 'noise', tex2: col(0.11, 0.26, 0.12), texScale: 16 }); }
function mPaintW() { return matC(col(0.88, 0.89, 0.92), { unlit: true, emissive: col(0.30, 0.30, 0.32), estr: 0.4 }); }
function mPaintY() { return matC(col(0.95, 0.78, 0.18), { unlit: true, emissive: col(0.35, 0.28, 0.05), estr: 0.4 }); }
function mMetal() { return matC(col(0.34, 0.36, 0.40), { roughness: 0.45, metallic: 0.6 }); }
function mMetalDark() { return matC(col(0.10, 0.11, 0.13), { roughness: 0.4, metallic: 0.7 }); }
function mWood() { return matC(col(0.36, 0.24, 0.13), { roughness: 0.8 }); }
function mTrunk() { return matC(col(0.27, 0.19, 0.12), { roughness: 0.9 }); }
function mLeaf(g) { return matC(col(0.09 + 0.05 * g, 0.28 + 0.13 * g, 0.11 + 0.05 * g), { roughness: 1.0 }); }
function mHydrant() { return matC(col(0.80, 0.13, 0.10), { roughness: 0.5, metallic: 0.2 }); }
function mWater() { return matC(col(0.18, 0.44, 0.60), { roughness: 0.12, metallic: 0.1, alpha: 0.72, emissive: col(0.05, 0.18, 0.24), estr: 0.7 }); }
function mStone() { return matC(col(0.60, 0.58, 0.53), { roughness: 0.85 }); }

// Facade styles: base wall colour + window tint (the checkerboard texture
// paints a window grid), plus PBR feel. Window tint reads as "lit" at dusk.
var FACADES = [
  { base: col(0.33, 0.30, 0.29), win: col(0.78, 0.74, 0.52), met: 0.0, rgh: 0.85 },  // concrete
  { base: col(0.41, 0.23, 0.18), win: col(0.85, 0.68, 0.42), met: 0.0, rgh: 0.80 },  // brick
  { base: col(0.16, 0.21, 0.30), win: col(0.50, 0.72, 0.92), met: 0.55, rgh: 0.28 }, // glass (blue)
  { base: col(0.29, 0.30, 0.34), win: col(0.80, 0.82, 0.70), met: 0.25, rgh: 0.55 }, // steel
  { base: col(0.47, 0.42, 0.33), win: col(0.86, 0.74, 0.48), met: 0.0, rgh: 0.80 }   // sandstone
];
var NEONS = [col(0.95, 0.22, 0.52), col(0.20, 0.72, 0.96), col(0.98, 0.62, 0.12), col(0.42, 0.92, 0.45), col(0.66, 0.40, 0.98)];

// ---- Environment + lighting (dusk / blue hour) ----------------------------
function cityEnvironment() {
  cnPush({
    type: 'environment',
    ambient_light: { r: 0.30, g: 0.33, b: 0.43 }, ambient_intensity: 0.55,
    sky_color_top: { r: 0.035, g: 0.055, b: 0.135 }, sky_color_bottom: { r: 0.58, g: 0.42, b: 0.30 },
    fog_type: 'linear', fog_color: { r: 0.34, g: 0.33, b: 0.40 }, fog_near: 24, fog_distance: 62
  });
  // Warm low dusk sun + cool sky fill.
  cnPush({ type: 'light', light_type: 'Directional', color: { r: 1.0, g: 0.82, b: 0.58 }, intensity: 1.4, transform: { rotation: { x: -28, y: 40, z: 0 } } });
  cnPush({ type: 'light', light_type: 'Directional', color: { r: 0.34, g: 0.44, b: 0.78 }, intensity: 0.55, transform: { rotation: { x: -22, y: 215, z: 0 } } });
  // Atmospheric point lights: fountain glow + two plaza lamps (kept few for speed).
  cnPush({ type: 'light', light_type: 'Point', color: { r: 0.45, g: 0.72, b: 1.0 }, intensity: 1.4, range: 11, transform: { position: { x: 0, y: 1.6, z: 0 } } });
  cnPush({ type: 'light', light_type: 'Point', color: { r: 1.0, g: 0.80, b: 0.50 }, intensity: 1.1, range: 12, transform: { position: { x: 11.5, y: 3.4, z: 11.5 } } });
  cnPush({ type: 'light', light_type: 'Point', color: { r: 1.0, g: 0.80, b: 0.50 }, intensity: 1.1, range: 12, transform: { position: { x: -11.5, y: 3.4, z: -11.5 } } });
}

// ---- Ground, roads, sidewalks, markings -----------------------------------
function cityGround() {
  // Base asphalt slab covering the whole map.
  cnPush(box(vec(0, -0.05, 0), vec(CITY * 2 + 8, 0.1, CITY * 2 + 8), mAsphalt()));

  // Sidewalk frame (raised curb) around the park: 4 concrete strips.
  var sw = mConcrete(), so = 12.8;     // sidewalk outer edge
  cnPush(box(vec(0, 0.06, -11.6), vec(so * 2, 0.14, 2.4), sw));
  cnPush(box(vec(0, 0.06, 11.6), vec(so * 2, 0.14, 2.4), sw));
  cnPush(box(vec(-11.6, 0.06, 0), vec(2.4, 0.14, so * 2), sw));
  cnPush(box(vec(11.6, 0.06, 0), vec(2.4, 0.14, so * 2), sw));
  // Curb lip (lighter) along the park edge.
  var cu = mCurb();
  cnPush(box(vec(0, 0.10, -10.4), vec(so * 2, 0.22, 0.25), cu));
  cnPush(box(vec(0, 0.10, 10.4), vec(so * 2, 0.22, 0.25), cu));
  cnPush(box(vec(-10.4, 0.10, 0), vec(0.25, 0.22, so * 2), cu));
  cnPush(box(vec(10.4, 0.10, 0), vec(0.25, 0.22, so * 2), cu));
}

function cityRoadMarkings() {
  // Dashed yellow centre lines down the two main avenues (x=0 and z=0),
  // skipping the park interior.
  var py = mPaintY();
  for (var s = -CITY; s <= CITY; s += 4) {
    if (Math.abs(s) < 13) continue;
    cnPush(box(vec(0, 0.11, s), vec(0.22, 0.02, 1.8), py));   // N/S avenue
    cnPush(box(vec(s, 0.11, 0), vec(1.8, 0.02, 0.22), py));   // E/W avenue
  }
  // Zebra crosswalks at the four avenue mouths onto the ring road.
  var pw = mPaintW();
  function crosswalk(cx, cz, horiz) {
    for (var k = -2; k <= 2; k++) {
      if (horiz) cnPush(box(vec(cx + k * 0.55, 0.115, cz), vec(0.34, 0.02, 2.0), pw));
      else cnPush(box(vec(cx, 0.115, cz + k * 0.55), vec(2.0, 0.02, 0.34), pw));
    }
  }
  crosswalk(0, -11.7, true);
  crosswalk(0, 11.7, true);
  crosswalk(-11.7, 0, false);
  crosswalk(11.7, 0, false);
}

// ---- Central park ---------------------------------------------------------
function cityPark() {
  // Grass lawn (raised slightly above the asphalt).
  cnPush(box(vec(0, 0.08, 0), vec(PARK * 2 - 0.4, 0.14, PARK * 2 - 0.4), mGrass()));
  // Diagonal foot-path crossing the lawn.
  var pth = matC(col(0.55, 0.52, 0.46), { roughness: 0.9 });
  cnPush(box(vec(0, 0.16, 0), vec(PARK * 2 - 1, 0.06, 2.0), pth));
  cnPush(box(vec(0, 0.16, 0), vec(2.0, 0.06, PARK * 2 - 1), pth));

  buildFountain(0, 0);
  // Park trees (kept clear of the fountain + paths).
  var spots = [[-6, -6], [6, -6], [-6, 6], [6, 6], [-7.5, 0.5], [7.5, -0.5], [0.5, -7.5], [-0.5, 7.5]];
  for (var i = 0; i < spots.length; i++) buildTree(spots[i][0], spots[i][1], srange(0.85, 1.25));
  // Park benches facing the fountain + ornamental lamps at the corners.
  buildBench(-3.2, -3.2, 45); buildBench(3.2, -3.2, -45);
  buildBench(-3.2, 3.2, 135); buildBench(3.2, 3.2, -135);
  buildLamp(-8.5, -8.5, true); buildLamp(8.5, 8.5, true);
  buildLamp(8.5, -8.5, true); buildLamp(-8.5, 8.5, true);
  // Low hedge border with gaps at the path entrances (cover for combat).
  buildHedgeRun(-9, -9.6, 9, -9.6);   // south, broken by path
  buildHedgeRun(-9, 9.6, 9, 9.6);     // north
}

function buildFountain(cx, cz) {
  cnPush(cyl(vec(cx, 0.30, cz), 2.0, 0.6, null, mStone(), 20));         // outer basin
  cnPush(cyl(vec(cx, 0.55, cz), 1.7, 0.18, null, mWater(), 20));        // water surface
  cnPush(cyl(vec(cx, 0.75, cz), 0.45, 1.0, null, mStone(), 14));        // central pillar
  cnPush(cyl(vec(cx, 1.35, cz), 0.85, 0.16, null, mWater(), 16));       // upper bowl water
  cnPush(sph(vec(cx, 1.7, cz), 0.22, neon(col(0.6, 0.85, 1.0), 1.4), 10)); // glowing finial
  obBox(cx, cz, 4.0, 1.5, 4.0);
}

function buildTree(x, z, s) {
  cnPush(cyl(vec(x, 0.9 * s, z), 0.16 * s, 1.8 * s, null, mTrunk(), 8));
  var g0 = srand(), g1 = srand();
  cnPush(sph(vec(x, 2.0 * s, z), 0.95 * s, mLeaf(g0), 10));
  cnPush(sph(vec(x - 0.5 * s, 1.7 * s, z + 0.3 * s), 0.62 * s, mLeaf(g1), 8));
  cnPush(sph(vec(x + 0.5 * s, 1.8 * s, z - 0.2 * s), 0.6 * s, mLeaf(g0), 8));
  obBox(x, z, 0.5, 2.0, 0.5);
}

function buildHedgeRun(x1, z1, x2, z2) {
  var len = Math.sqrt((x2 - x1) * (x2 - x1) + (z2 - z1) * (z2 - z1));
  var n = Math.max(1, Math.round(len / 1.4));
  for (var i = 0; i <= n; i++) {
    if (Math.abs(i - n / 2) < 0.7) continue;   // leave a gap at the midpoint (path)
    var tt = i / n, x = lerp(x1, x2, tt), z = lerp(z1, z2, tt);
    cnPush(box(vec(x, 0.45, z), vec(1.3, 0.8, 0.7), mLeaf(0.3)));
  }
}

// ---- Street furniture -----------------------------------------------------
function buildLamp(x, z, ornamental) {
  cnPush(cyl(vec(x, 1.7, z), 0.10, 3.4, null, mMetalDark(), 8));        // pole
  cnPush(cyl(vec(x, 3.5, z), 0.34, 0.18, null, mMetalDark(), 8));       // head housing
  cnPush(sph(vec(x, 3.42, z), 0.22, neon(col(1.0, 0.88, 0.6), 2.6), 8)); // glowing bulb
  if (ornamental) cnPush(cyl(vec(x, 0.25, z), 0.22, 0.5, null, mMetal(), 8)); // base
  obBox(x, z, 0.35, 3.4, 0.35);
}

function buildTrafficLight(x, z, yaw) {
  cnPush(cyl(vec(x, 1.3, z), 0.09, 2.6, null, mMetalDark(), 6));
  var ax = Math.sin(yaw * PI / 180), az = -Math.cos(yaw * PI / 180);
  cnPush(box(vec(x + ax * 0.5, 2.6, z + az * 0.5), vec(0.9, 0.18, 0.18), mMetalDark()));
  var hx = x + ax * 1.0, hz = z + az * 1.0;
  cnPush(box(vec(hx, 2.6, hz), vec(0.26, 0.78, 0.26), mMetalDark()));
  cnPush(sph(vec(hx, 2.86, hz), 0.10, neon(col(0.95, 0.2, 0.15), 2.2), 6));
  cnPush(sph(vec(hx, 2.60, hz), 0.10, matC(col(0.4, 0.32, 0.05), { roughness: 0.6 }), 6));
  cnPush(sph(vec(hx, 2.34, hz), 0.10, neon(col(0.25, 0.95, 0.35), 2.2), 6));
  obBox(x, z, 0.3, 2.6, 0.3);
}

function buildBench(x, z, yaw) {
  var w = mWood();
  cnPush(boxR(vec(x, 0.45, z), vec(1.7, 0.12, 0.55), yaw, w));      // seat
  cnPush(boxR(vec(x, 0.78, z), vec(1.7, 0.45, 0.10), yaw, w));      // backrest (approx — offset omitted for simplicity)
  cnPush(boxR(vec(x, 0.22, z), vec(0.12, 0.45, 0.5), yaw, mMetalDark()));
  obBox(x, z, 1.7, 0.6, 0.7);
}

function buildHydrant(x, z) {
  cnPush(cyl(vec(x, 0.32, z), 0.18, 0.64, null, mHydrant(), 8));
  cnPush(sph(vec(x, 0.66, z), 0.18, mHydrant(), 8));
  cnPush(box(vec(x + 0.22, 0.4, z), vec(0.22, 0.12, 0.12), mHydrant()));
  obBox(x, z, 0.4, 0.7, 0.4);
}

function buildTrashCan(x, z) {
  cnPush(cyl(vec(x, 0.45, z), 0.28, 0.9, null, matC(col(0.20, 0.30, 0.24), { roughness: 0.6, metallic: 0.3 }), 10));
  cnPush(cyl(vec(x, 0.92, z), 0.30, 0.08, null, mMetalDark(), 10));
  obBox(x, z, 0.6, 0.9, 0.6);
}

function buildBollard(x, z) {
  cnPush(cyl(vec(x, 0.4, z), 0.12, 0.8, null, matC(col(0.18, 0.20, 0.24), { roughness: 0.5, metallic: 0.4 }), 8));
  cnPush(sph(vec(x, 0.82, z), 0.12, neon(col(0.9, 0.5, 0.1), 1.2), 6));
}

function buildPlanter(x, z) {
  cnPush(box(vec(x, 0.3, z), vec(1.2, 0.6, 1.2), mStone()));
  cnPush(sph(vec(x, 0.95, z), 0.55, mLeaf(srand()), 8));
  cnPush(sph(vec(x - 0.3, 0.8, z + 0.2), 0.35, mLeaf(srand()), 6));
  obBox(x, z, 1.2, 0.7, 1.2);
}

function buildBarrier(x, z, yaw) {
  // Concrete jersey barrier with a reflective stripe — combat cover.
  cnPush(boxR(vec(x, 0.45, z), vec(2.0, 0.9, 0.6), yaw, mConcrete()));
  cnPush(boxR(vec(x, 0.7, z), vec(2.02, 0.16, 0.62), yaw, mPaintW()));
  var ax = Math.cos(yaw * PI / 180), az = Math.sin(yaw * PI / 180);
  obBox(x, z, Math.abs(ax) > 0.5 ? 2.0 : 0.6, 0.9, Math.abs(ax) > 0.5 ? 0.6 : 2.0);
}

function buildCone(x, z) {
  cnPush(cone3(vec(x, 0.3, z), 0.22, 0.6, null, neon(col(0.98, 0.45, 0.08), 1.0), 8));
  cnPush(box(vec(x, 0.04, z), vec(0.5, 0.08, 0.5), matC(col(0.9, 0.42, 0.07), { roughness: 0.6 })));
}

function buildCrates(x, z) {
  var m = mWood();
  cnPush(box(vec(x, 0.4, z), vec(0.8, 0.8, 0.8), m));
  cnPush(box(vec(x + 0.85, 0.4, z + 0.1), vec(0.8, 0.8, 0.8), m));
  cnPush(box(vec(x + 0.3, 1.1, z - 0.1), vec(0.8, 0.8, 0.8), m));
  obBox(x + 0.3, z, 1.7, 1.5, 1.0);
}

function buildDumpster(x, z, yaw) {
  cnPush(boxR(vec(x, 0.6, z), vec(2.2, 1.2, 1.2), yaw, matC(col(0.18, 0.42, 0.30), { roughness: 0.6, metallic: 0.3 })));
  cnPush(boxR(vec(x, 1.24, z), vec(2.24, 0.12, 1.24), yaw, mMetalDark()));
  obBox(x, z, 2.2, 1.3, 1.4);
}

function buildBusStop(x, z, yaw) {
  var m = matC(col(0.20, 0.22, 0.26), { roughness: 0.4, metallic: 0.5 });
  cnPush(boxR(vec(x, 1.3, z), vec(3.2, 0.14, 1.4), yaw, m));           // roof
  cnPush(boxR(vec(x - 1.4 * Math.cos(yaw * PI / 180), 0.65, z - 1.4 * Math.sin(yaw * PI / 180)), vec(0.12, 1.3, 1.3), yaw, m));
  cnPush(boxR(vec(x + 1.4 * Math.cos(yaw * PI / 180), 0.65, z + 1.4 * Math.sin(yaw * PI / 180)), vec(0.12, 1.3, 1.3), yaw, m));
  cnPush(boxR(vec(x, 0.65, z + 0.6), vec(3.0, 1.2, 0.05), yaw, matC(col(0.5, 0.7, 0.85), { alpha: 0.35, roughness: 0.1, metallic: 0.2 })));
  cnPush(boxR(vec(x, 0.7, z - 0.55), vec(1.6, 0.7, 0.06), yaw, neon(spick(NEONS), 1.6))); // ad panel
  obBox(x, z, 3.2, 1.4, 1.5);
}

function buildBillboardOn(x, y, z, yaw) {
  cnPush(boxR(vec(x, y, z), vec(4.0, 2.2, 0.18), yaw, neon(spick(NEONS), 1.8)));
  cnPush(boxR(vec(x, y, z + 0.12), vec(4.3, 2.5, 0.10), yaw, mMetalDark()));
}

// ---- Vehicles parked at the curb (real glTF trucks) -----------------------
function buildParkedTruck(x, z, yaw, tint) {
  cnPush(modelNode(MODEL_TRUCK, x, TRUCK_Y, z, yaw, 0, TRUCK_SCALE, TRUCK_YAW, { tint: tint }));
  obBox(x, z, 3.0, 2.4, 3.0);
}

// ---- Surrounding skyline of buildings -------------------------------------
function buildBuilding(cx, cz, w, d, h, fi) {
  var F = FACADES[fi % FACADES.length];
  var floors = Math.max(3, Math.round(h * 0.9));
  var facade = matC(F.base, { roughness: F.rgh, metallic: F.met, tex: 'checkerboard', tex2: F.win, texScale: floors });
  cnPush(box(vec(cx, h / 2, cz), vec(w, h, d), facade));
  cnPush(box(vec(cx, h + 0.16, cz), vec(w + 0.3, 0.32, d + 0.3), matC(F.base, { roughness: 0.8 }))); // parapet cap
  obBox(cx, cz, w, h, d);

  var near = Math.max(Math.abs(cx), Math.abs(cz)) <= 26;
  if (!near) return;

  // Rooftop machinery.
  cnPush(box(vec(cx - w * 0.22, h + 0.6, cz + d * 0.2), vec(1.4, 0.95, 1.4), mMetal()));
  cnPush(cyl(vec(cx + w * 0.24, h + 0.75, cz - d * 0.2), 0.7, 1.3, null, mMetal(), 8));   // water tank
  cnPush(cyl(vec(cx + w * 0.24, h + 1.7, cz - d * 0.2), 0.07, 1.8, null, mMetalDark(), 5)); // antenna
  if (srand() < 0.5) buildBillboardOn(cx, h + 1.4, cz + (cz > 0 ? -d / 2 - 0.2 : d / 2 + 0.2), cz > 0 ? 0 : 180);

  // Face toward the plaza: choose the dominant axis so props mount on one wall.
  var fxs = cx > 0 ? -1 : (cx < 0 ? 1 : 0), fzs = cz > 0 ? -1 : (cz < 0 ? 1 : 0);
  if (Math.abs(cx) >= Math.abs(cz)) fzs = 0; else fxs = 0;
  var ax = cx + fxs * (w / 2), az = cz + fzs * (d / 2);

  // Storefront awning + neon sign band.
  cnPush(box(vec(ax + fxs * 0.45, 2.5, az + fzs * 0.45), vec(fxs !== 0 ? 0.9 : w * 0.55, 0.14, fzs !== 0 ? 0.9 : d * 0.55), neon(col(0.75, 0.18, 0.18), 0.9)));
  cnPush(box(vec(ax + fxs * 0.12, 3.7, az + fzs * 0.12), vec(fxs !== 0 ? 0.2 : w * 0.6, 0.95, fzs !== 0 ? 0.2 : d * 0.6), neon(spick(NEONS), 2.0)));
  // Lit windows glowing on the plaza-facing wall.
  for (var wi = 0; wi < 4; wi++) {
    var yy = 5 + wi * 2.6;
    if (yy > h - 1) break;
    if (srand() < 0.35) continue;       // some windows are dark
    var jit = (fxs !== 0) ? srange(-d * 0.32, d * 0.32) : srange(-w * 0.32, w * 0.32);
    cnPush(box(
      vec(ax + fxs * 0.05 + (fxs !== 0 ? 0 : jit), yy, az + fzs * 0.05 + (fzs !== 0 ? 0 : jit)),
      vec(fxs !== 0 ? 0.12 : 0.95, 0.75, fzs !== 0 ? 0.12 : 0.95),
      neon(col(1.0, 0.84, 0.52), 1.3)));
  }
}

function cityBuildings() {
  // Grid of plots on an 11-unit pitch. Skip the central plaza and keep the two
  // main avenues (x=0, z=0) open as through-streets, leaving a dense skyline of
  // varied towers in the four quadrants with alleys between them.
  var coords = [-33, -22, -11, 11, 22, 33];
  for (var ix = 0; ix < coords.length; ix++) {
    for (var iz = 0; iz < coords.length; iz++) {
      var px = coords[ix], pz = coords[iz];
      if (Math.abs(px) < 13 && Math.abs(pz) < 13) continue;   // central blocks stay open (park + ring road)
      var radial = Math.max(Math.abs(px), Math.abs(pz));
      var jx = px + srange(-0.8, 0.8), jz = pz + srange(-0.8, 0.8);
      var w = srange(7.0, 9.2), d = srange(7.0, 9.2);
      // Taller towers toward the back of the skyline.
      var h = radial < 24 ? srange(7, 15) : srange(15, 32);
      buildBuilding(jx, jz, w, d, h, Math.floor(srand() * FACADES.length));
    }
  }
}

// ---- Lay out all the street furniture around the plaza + avenues ----------
function cityProps() {
  // Traffic lights at the four ring-road / avenue corners.
  buildTrafficLight(-12.3, -12.3, 45); buildTrafficLight(12.3, 12.3, 225);
  buildTrafficLight(12.3, -12.3, 315); buildTrafficLight(-12.3, 12.3, 135);

  // Street lamps marching down both sidewalks of each avenue.
  var lampZ = [-15, -22, -29, 15, 22, 29];
  for (var i = 0; i < lampZ.length; i++) {
    buildLamp(2.6, lampZ[i], false); buildLamp(-2.6, lampZ[i], false);   // N/S avenue
    buildLamp(lampZ[i], 2.6, false); buildLamp(lampZ[i], -2.6, false);   // E/W avenue
  }

  // Hydrants, bins, planters, bollards along the sidewalk corners.
  buildHydrant(-12.6, -6); buildHydrant(12.6, 6); buildHydrant(6, -12.6); buildHydrant(-6, 12.6);
  buildTrashCan(-12.4, 3); buildTrashCan(12.4, -3); buildTrashCan(3, 12.4); buildTrashCan(-3, -12.4);
  buildPlanter(-12.6, -2); buildPlanter(12.6, 2); buildPlanter(-2, 12.6); buildPlanter(2, -12.6);
  for (var b = -9; b <= 9; b += 3) {
    buildBollard(b, -10.7); buildBollard(b, 10.7);
    buildBollard(-10.7, b); buildBollard(10.7, b);
  }

  // Combat cover + clutter scattered on the ring road.
  buildBarrier(-7, -13.4, 0); buildBarrier(7, 13.4, 0);
  buildBarrier(-13.4, 7, 90); buildBarrier(13.4, -7, 90);
  buildCrates(11.0, -8.0); buildCrates(-11.5, 8.5);
  buildDumpster(13.0, -11.5, 20); buildDumpster(-13.0, 11.5, -20);
  buildBusStop(0, -13.6, 0); buildBusStop(0, 13.6, 180);
  buildCone(8.0, -11.0); buildCone(8.6, -11.4); buildCone(-8.0, 11.0); buildCone(-8.6, 11.4);
  buildCone(11.0, 8.0); buildCone(-11.0, -8.0);

  // Parked delivery trucks along the curb (real glTF models from the internet).
  buildParkedTruck(14.6, -3.5, 0, col(0.92, 0.93, 0.96));
  buildParkedTruck(-14.6, 3.5, PI, col(0.85, 0.45, 0.25));
  buildParkedTruck(-3.5, -14.6, PI / 2, col(0.45, 0.6, 0.85));
  buildParkedTruck(3.5, 14.6, -PI / 2, col(0.95, 0.85, 0.3));
}

function buildCity() {
  _CN = []; _OB = [];
  sreset();
  cityEnvironment();
  cityGround();
  cityRoadMarkings();
  cityPark();
  cityBuildings();
  cityProps();
  // Serialize the whole static city to a JSON fragment exactly once.
  var parts = [];
  for (var i = 0; i < _CN.length; i++) parts.push(JSON.stringify(_CN[i]));
  var frag = parts.join(',');
  var obs = _OB;
  _CN = null; _OB = null;
  return { fragment: frag, obstacles: obs };
}

// ════════════════════════════════════════════════════════════════════════
//  SCENE ASSEMBLY  (dynamic entities + spliced static city)
// ════════════════════════════════════════════════════════════════════════
function buildDynamicWorld() {
  var w = [];
  var p = G.player, c = G.cam;

  // Third-person follow camera.
  var f = camForward();
  var tx = p.x, ty = p.y + CAM_LOOK_H, tz = p.z;
  var cx = tx - f.x * CAM_DIST, cy = ty - f.y * CAM_DIST, cz = tz - f.z * CAM_DIST;
  if (cy < 0.7) cy = 0.7;
  w.push({
    type: 'camera', camera_type: 'Perspective', fov: 62, near: 0.1, far: 240,
    transform: { position: vec(cx, cy, cz), rotation: vec(deg(camPitchEff()), deg(c.yaw), 0) }
  });

  // Living city: foxes, traffic, ducks.
  addAmbientModels(w);

  // Player rig (always present so it streams in and is posed for combat).
  addPlayerModel(w);
  for (var i = 0; i < G.enemies.length; i++) addEnemyModel(w, G.enemies[i]);

  // Enemy projectiles.
  for (var i = 0; i < G.ebullets.length; i++) {
    var b = G.ebullets[i];
    w.push(mesh3d('Sphere', vec(b.x, b.y, b.z), vec(0, 0, 0), vec(1, 1, 1),
      matC(col(1, 0.55, 0.15), { unlit: true, emissive: col(1, 0.5, 0.1), estr: 2 }), { radius: 0.17, segments: 6 }));
  }
  // Pickups.
  for (var i = 0; i < G.pickups.length; i++) {
    var pk = G.pickups[i];
    var pc = pk.kind === 'health' ? col(0.2, 0.9, 0.35) : col(1, 0.8, 0.25);
    var node = box(vec(pk.x, pk.y + Math.sin(G.time * 3) * 0.12, pk.z), vec(0.4, 0.4, 0.4), matC(pc, { emissive: pc, estr: 0.8 }));
    node.transform.rotation = vec(0, pk.spin, 0);
    w.push(node);
  }

  addEffects(w);
  return w;
}

// Build the full scene JSON. The huge static city is spliced in from its
// pre-serialized fragment, so only the moving entities are encoded each frame.
function buildSceneJson() {
  var dyn = buildDynamicWorld();
  var parts = [];
  for (var i = 0; i < dyn.length; i++) parts.push(JSON.stringify(dyn[i]));
  var dynJson = parts.join(',');
  return '{"world":[' + CITY_FRAGMENT + (dynJson ? ',' + dynJson : '') + ']}';
}

// ════════════════════════════════════════════════════════════════════════
//  2D UI BUILDERS (HUD + controls)
// ════════════════════════════════════════════════════════════════════════
function pos(left, top, right, bottom, child) {
  var s = {};
  if (left !== null && left !== undefined) s.left = left;
  if (top !== null && top !== undefined) s.top = top;
  if (right !== null && right !== undefined) s.right = right;
  if (bottom !== null && bottom !== undefined) s.bottom = bottom;
  return { type: 'Positioned', style: s, children: [child] };
}
function container(w, h, bg, radius, o) {
  o = o || {};
  var s = {};
  if (w !== null && w !== undefined) s.width = w;
  if (h !== null && h !== undefined) s.height = h;
  if (bg) s.backgroundColor = bg;
  if (radius !== null && radius !== undefined) s.borderRadius = radius;
  if (o.borderColor) { s.borderColor = o.borderColor; s.borderWidth = o.borderWidth || 1; }
  if (o.opacity !== undefined) s.opacity = o.opacity;
  var node = { type: 'Container', style: s };
  if (o.key) node.key = o.key;
  if (o.events) node.events = o.events;
  if (o.children) node.children = o.children;
  else if (o.child) node.children = [o.child];
  return node;
}
function text(str, color, size, weight, o) {
  o = o || {};
  var s = { color: color || '#ffffff', fontSize: size || 14 };
  if (weight) s.fontWeight = weight;
  if (o.letter) s.letterSpacing = o.letter;
  return { type: 'Text', props: { text: str }, style: s };
}
function centerNode(child) { return { type: 'Center', children: [child] }; }
function fullRow(top, child) { return { type: 'Positioned', style: { left: 0, right: 0, top: top }, children: [centerNode(child)] }; }
function fill(bg) { return { type: 'Positioned', style: { left: 0, top: 0, right: 0, bottom: 0 }, children: [{ type: 'Container', style: { backgroundColor: bg } }] }; }

function pushHud(ch, W, H) {
  var p = G.player;
  // health
  var hf = clamp(p.health / p.maxHealth, 0, 1);
  ch.push(pos(14, 14, null, null, container(184, 20, 'rgba(10,14,22,0.65)', 10, { borderColor: 'rgba(120,160,200,0.5)', borderWidth: 1 })));
  ch.push(pos(17, 17, null, null, container(178 * hf, 14, hf > 0.5 ? '#36d27a' : (hf > 0.25 ? '#e6b800' : '#ef4444'), 7, {})));
  ch.push(pos(22, 16, null, null, text('HP ' + Math.round(p.health), '#eaf2ff', 12, 'bold')));
  // score / wave
  ch.push(pos(null, 14, 14, null, text('SCORE ' + G.score, '#eaf2ff', 17, 'bold')));
  ch.push(pos(null, 40, 14, null, text('WAVE ' + G.wave + '   KILLS ' + G.kills, '#9fb4d6', 12, 'bold')));
  ch.push(pos(null, 60, 14, null, text('HOSTILES ' + countAlive(), '#ff9a9a', 12, 'bold')));

  // minimap
  var MM = 112, mmx = W / 2 - MM / 2, mmy = 12;
  var mk = [container(MM, MM, 'rgba(8,12,20,0.55)', 8, { borderColor: 'rgba(120,160,200,0.4)', borderWidth: 1 })];
  mk.push(pos(MM / 2 - 3, MM / 2 - 3, null, null, container(6, 6, '#4cc9f0', 3, {})));
  var sc = (MM / 2 - 7) / PLAY;
  for (var i = 0; i < G.enemies.length; i++) {
    var e = G.enemies[i]; if (!e.alive) continue;
    var dx = e.x - p.x, dz = e.z - p.z;
    var ar = dx * Math.cos(G.cam.yaw) + dz * Math.sin(G.cam.yaw);
    var af = dx * Math.sin(G.cam.yaw) - dz * Math.cos(G.cam.yaw);
    var ex = clamp(MM / 2 + ar * sc, 4, MM - 8), ey = clamp(MM / 2 - af * sc, 4, MM - 8);
    mk.push(pos(ex, ey, null, null, container(5, 5, e.type === 'heavy' ? '#c050ff' : '#ff5252', 3, {})));
  }
  ch.push(pos(mmx, mmy, null, null, { type: 'Container', style: { width: MM, height: MM }, children: [{ type: 'Stack', style: { width: MM, height: MM }, children: mk }] }));

  // crosshair
  var cc = G.hitMarker > 0 ? '#ff5a5a' : 'rgba(255,255,255,0.85)';
  var cx = W / 2, cy = H / 2;
  ch.push(pos(cx - 1, cy - 13, null, null, container(2, 8, cc, 1, {})));
  ch.push(pos(cx - 1, cy + 5, null, null, container(2, 8, cc, 1, {})));
  ch.push(pos(cx - 13, cy - 1, null, null, container(8, 2, cc, 1, {})));
  ch.push(pos(cx + 5, cy - 1, null, null, container(8, 2, cc, 1, {})));
  ch.push(pos(cx - 2, cy - 2, null, null, container(4, 4, cc, 2, {})));

  // ammo
  var w = G.weapon;
  var ammo = w.reloading ? 'RELOADING' : (w.mag + ' / ' + w.reserve);
  ch.push(pos(null, null, 36, 152, text(ammo, (w.mag === 0 && !w.reloading) ? '#ff6b6b' : '#eaf2ff', 18, 'bold')));

  // damage vignette (below controls so it never blocks input)
  if (p.hurtT > 0) {
    var v = clamp(p.hurtT / 0.5, 0, 1) * 0.5;
    ch.push(fill('rgba(200,20,20,' + v.toFixed(2) + ')'));
  }
  // banner
  if (G.banner > 0) {
    var a = clamp(G.banner, 0, 1);
    ch.push(fullRow(H * 0.24, text(G.bannerText, 'rgba(255,255,255,' + a.toFixed(2) + ')', 30, 'bold', { letter: 3 })));
  }
}

function pushControls(ch, W, H) {
  // look pad (right side, transparent, fills its rect)
  ch.push({
    type: 'Positioned', style: { left: W * 0.34, top: 0, right: 0, bottom: 0 },
    children: [{ type: 'Container', key: 'lookPad', style: {}, events: { drag: 'onLook', dragstart: 'onLookStart', dragend: 'onLookEnd' } }]
  });

  // movement joystick (bottom-left)
  var tx = G.input.joyActive ? JOY_HALF + G.input.jdx : JOY_HALF;
  var ty = G.input.joyActive ? JOY_HALF + G.input.jdy : JOY_HALF;
  var ring = [
    { type: 'Container', style: { width: JOY, height: JOY, backgroundColor: 'rgba(20,28,40,0.40)', borderRadius: JOY, borderColor: 'rgba(140,180,220,0.5)', borderWidth: 2 } },
    pos(tx - THUMB / 2, ty - THUMB / 2, null, null, { type: 'Container', style: { width: THUMB, height: THUMB, backgroundColor: 'rgba(120,200,255,0.55)', borderRadius: THUMB, borderColor: 'rgba(220,240,255,0.85)', borderWidth: 2 } })
  ];
  ch.push(pos(24, null, null, 28, {
    type: 'Container', key: 'joyPad', style: { width: JOY, height: JOY },
    events: { pointerdown: 'onMoveStart', pointermove: 'onMove', pointerup: 'onMoveEnd', pointercancel: 'onMoveEnd' },
    children: [{ type: 'Stack', style: { width: JOY, height: JOY }, children: ring }]
  }));

  // fire button (bottom-right, on top of look pad)
  ch.push(pos(null, null, 30, 40, container(98, 98, 'rgba(200,60,50,0.45)', 98, {
    borderColor: 'rgba(255,170,160,0.85)', borderWidth: 3, key: 'fireBtn',
    events: { tapdown: 'onFireDown', tapup: 'onFireUp', tapcancel: 'onFireUp' },
    child: centerNode(text('FIRE', '#ffffff', 16, 'bold'))
  })));
  // reload
  ch.push(pos(null, null, 140, 58, container(64, 64, 'rgba(40,80,140,0.5)', 64, {
    borderColor: 'rgba(150,200,255,0.7)', borderWidth: 2, key: 'reloadBtn', events: { tap: 'onReload' },
    child: centerNode(text('RELOAD', '#ffffff', 10, 'bold'))
  })));
  // jump
  ch.push(pos(null, null, 142, 134, container(60, 60, 'rgba(60,140,90,0.5)', 60, {
    borderColor: 'rgba(150,255,190,0.7)', borderWidth: 2, key: 'jumpBtn', events: { tap: 'onJump' },
    child: centerNode(text('JUMP', '#ffffff', 12, 'bold'))
  })));
}

function pushMenu(ch, W, H) {
  ch.push({ type: 'Positioned', key: 'menuBg', style: { left: 0, top: 0, right: 0, bottom: 0 }, children: [{ type: 'Container', style: { backgroundColor: 'rgba(4,6,12,0.62)' } }] });
  ch.push(fullRow(H * 0.16, text('ELPIAN', '#4cc9f0', 52, 'bold', { letter: 8 })));
  ch.push(fullRow(H * 0.16 + 58, text('STRIKE FORCE', '#eaf2ff', 26, 'bold', { letter: 6 })));
  ch.push(fullRow(H * 0.16 + 92, text('· DOWNTOWN ·', '#ffae6b', 14, 'bold', { letter: 5 })));
  ch.push(fullRow(H * 0.40, text('Hold the city square against the waves', '#7f93b3', 13, 'bold')));
  ch.push(fullRow(H * 0.47, text('LEFT STICK move + auto-aim camera', '#9fb4d6', 13, 'bold')));
  ch.push(fullRow(H * 0.47 + 22, text('RIGHT DRAG optional free look', '#7f93b3', 12, 'bold')));
  ch.push(fullRow(H * 0.51, text('FIRE to shoot    use cover    survive', '#9fb4d6', 13, 'bold')));
  ch.push(fullRow(H * 0.64, container(230, 66, 'rgba(50,140,90,0.9)', 16, {
    borderColor: '#bdf3d0', borderWidth: 2, key: 'startBtn', events: { tap: 'onStart' },
    child: centerNode(text('START MISSION', '#ffffff', 18, 'bold', { letter: 2 }))
  })));
}

function pushDeath(ch, W, H) {
  ch.push({ type: 'Positioned', key: 'deathBg', style: { left: 0, top: 0, right: 0, bottom: 0 }, children: [{ type: 'Container', style: { backgroundColor: 'rgba(22,2,2,0.78)' } }] });
  ch.push(fullRow(H * 0.24, text('MISSION FAILED', '#ff5a5a', 40, 'bold', { letter: 4 })));
  ch.push(fullRow(H * 0.24 + 56, text('The city has fallen', '#e8b0b0', 16, 'bold')));
  ch.push(fullRow(H * 0.43, text('SCORE  ' + G.score, '#ffffff', 28, 'bold')));
  ch.push(fullRow(H * 0.50, text('WAVE  ' + G.wave + '      KILLS  ' + G.kills, '#cdd6f4', 16, 'bold')));
  ch.push(fullRow(H * 0.66, container(230, 66, 'rgba(200,60,50,0.92)', 16, {
    borderColor: '#ffd0c8', borderWidth: 2, key: 'restartBtn', events: { tap: 'onRestart' },
    child: centerNode(text('REDEPLOY', '#ffffff', 18, 'bold', { letter: 2 }))
  })));
}

// The GameScene's scene is left as a marker string here and spliced with the
// real (mostly pre-serialized) world JSON in render(), so the heavy static
// city is never rebuilt as a JS object graph each frame.
function buildTree() {
  readViewport();
  var W = VP.w, H = VP.h;
  var ch = [];
  ch.push({ type: 'GameScene', key: 'world3d', props: { scene: '__SCENE__', width: W, height: H, fps: 60, interactive: false } });
  pushHud(ch, W, H);
  if (G.state === 'playing') pushControls(ch, W, H);
  if (G.state === 'menu') pushMenu(ch, W, H);
  else if (G.state === 'dead') pushDeath(ch, W, H);
  return { type: 'Stack', key: 'root', style: { width: W, height: H }, children: ch };
}

// ════════════════════════════════════════════════════════════════════════
//  INPUT HANDLERS
// ════════════════════════════════════════════════════════════════════════
function updateJoy(ev) {
  var lp = ev.localPosition || ev.position || { x: JOY_HALF, y: JOY_HALF };
  var vx = numOr(lp.x, JOY_HALF) - JOY_HALF, vy = numOr(lp.y, JOY_HALF) - JOY_HALF;
  var mag = Math.sqrt(vx * vx + vy * vy);
  if (mag > JOY_HALF) { vx = vx / mag * JOY_HALF; vy = vy / mag * JOY_HALF; mag = JOY_HALF; }
  G.input.jdx = vx; G.input.jdy = vy;
  G.input.jx = vx / JOY_HALF; G.input.jz = -vy / JOY_HALF; G.input.jmag = mag / JOY_HALF;
  G.input.joyActive = true;
}
function joyOwnsEvent(ev) {
  if (!G.input.joyActive) return true;
  if (!ev || ev.pointerId === undefined || ev.pointerId === null) return true;
  return ev.pointerId === G.input.joyPointer;
}
function resetJoy() {
  G.input.joyActive = false; G.input.jx = 0; G.input.jz = 0; G.input.jmag = 0;
  G.input.jdx = 0; G.input.jdy = 0; G.input.joyPointer = -1;
}
function onMoveStart(input) {
  var ev = decodeEvent(input);
  G.input.joyPointer = (ev && ev.pointerId !== undefined && ev.pointerId !== null) ? ev.pointerId : -1;
  updateJoy(ev);
}
function onMove(input) { var ev = decodeEvent(input); if (joyOwnsEvent(ev)) updateJoy(ev); }
function onMoveEnd(input) { var ev = decodeEvent(input); if (joyOwnsEvent(ev)) resetJoy(); }

function onLookStart(input) {}
function onLook(input) {
  var d = (decodeEvent(input)).delta || { x: 0, y: 0 };
  G.cam.yaw += numOr(d.x, 0) * LOOK_SENS_X;
  G.cam.pitch = clamp(G.cam.pitch - numOr(d.y, 0) * LOOK_SENS_Y, -1.15, 0.42);
}
function onLookEnd(input) {}

function onFireDown(input) { G.input.firing = true; }
function onFireUp(input) { G.input.firing = false; }
function onReload(input) { startReload(); }
function onJump(input) { var p = G.player; if (p.grounded && p.y <= 0.01) { p.vy = JUMP_V; p.grounded = false; } }

// Start facing into the square (yaw 0 = world -Z) so "stick up = forward" lines
// up with the opening view; the menu orbit leaves cam.yaw at an arbitrary spin.
function aimCameraIntoArena() { G.cam.yaw = 0; G.cam.pitch = -0.22; G.player.yaw = 0; }
function onStart(input) { G.state = 'playing'; G.player.x = 0; G.player.z = 7; G.player.health = G.player.maxHealth; aimCameraIntoArena(); startWave(1); render(); }
function onRestart(input) { newGame(); G.state = 'playing'; aimCameraIntoArena(); startWave(1); render(); }

// ════════════════════════════════════════════════════════════════════════
//  RENDER + LOOP
// ════════════════════════════════════════════════════════════════════════
function render() {
  try {
    var treeJson = JSON.stringify(buildTree());
    treeJson = treeJson.replace('"scene":"__SCENE__"', '"scene":' + buildSceneJson());
    askHost('render', treeJson);
  } catch (e) { askHost('println', 'render error: ' + e); }
}
function gameTick() {
  try { updateGame(); render(); }
  catch (e) { askHost('println', 'tick error: ' + e); }
}

// ---- Boot ----
newGame();
readViewport();
render();
askHost('setInterval', { handler: 'gameTick', delay: 33 });
askHost('println', 'Elpian Strike Force — Downtown booted');
''';

const String tpsGameProgram2 = r'''
// ════════════════════════════════════════════════════════════════════════
//  ELPIAN STRIKE FORCE — a third-person shooter in one QuickJS script
// ════════════════════════════════════════════════════════════════════════

// ---- Typed-value decoding (event payloads arrive as Elpian typed values) ---
function decodeTypedValue(value) {
  if (value === null || value === undefined) return value;
  if (typeof value !== 'object') return value;
  if (!('type' in value) || !('data' in value)) return value;
  var t = value.type;
  var raw = (value.data || {}).value;
  if (t === 'object') {
    var o = {};
    if (raw && typeof raw === 'object') {
      for (var k in raw) { o[k] = decodeTypedValue(raw[k]); }
    }
    return o;
  }
  if (t === 'array') {
    if (!Array.isArray(raw)) return [];
    return raw.map(decodeTypedValue);
  }
  return raw;
}
function decodeEvent(input) {
  try { var v = decodeTypedValue(input); if (v && typeof v === 'object') return v; }
  catch (e) {}
  return {};
}

// ---- Tiny math helpers ----------------------------------------------------
var PI = Math.PI;
function numOr(v, d) { return (typeof v === 'number' && isFinite(v)) ? v : d; }
function clamp(v, a, b) { return v < a ? a : (v > b ? b : v); }
function lerp(a, b, t) { return a + (b - a) * t; }
function rand(a, b) { return a + Math.random() * (b - a); }
function deg(r) { return r * 180 / PI; }
function wrapAngle(a) { while (a > PI) a -= 2 * PI; while (a < -PI) a += 2 * PI; return a; }
// Step `cur` toward `target` (both radians) by at most `maxStep`, taking the
// shortest way around the circle. Used to make the camera trail the joystick.
function approachAngle(cur, target, maxStep) {
  var d = wrapAngle(target - cur);
  if (d > maxStep) d = maxStep; else if (d < -maxStep) d = -maxStep;
  return cur + d;
}
function dist2(ax, az, bx, bz) { var dx = bx - ax, dz = bz - az; return Math.sqrt(dx * dx + dz * dz); }
function col(r, g, b, a) { return { r: r, g: g, b: b, a: (a === undefined ? 1 : a) }; }
function vec(x, y, z) { return { x: x, y: y, z: z }; }

// ---- Tunables -------------------------------------------------------------
var DT = 0.0333;
var ARENA = 22;
var PLAYER_RADIUS = 0.5;
var CAM_DIST = 6.4, CAM_LOOK_H = 1.55;
var MOVE_SPEED = 6.4;
var GRAVITY = 19.0, JUMP_V = 7.4;
var FIRE_COOLDOWN = 0.11;
var MAG_SIZE = 24, RESERVE_START = 120;
var RELOAD_TIME = 1.15;
var BULLET_RANGE = 64;
var BULLET_DMG = 26;
var LOOK_SENS_X = 0.0066, LOOK_SENS_Y = 0.0055;
// How fast (rad/s) the camera yaw swings to follow the joystick travel
// direction, so the view + gun automatically aim where the player is heading.
var CAM_FOLLOW_RATE = 7.0;
var JOY = 132, JOY_HALF = 66, THUMB = 56;

// ---- Viewport (read from host environment) --------------------------------
var VP = { w: 420, h: 840 };
function readViewport() {
  var env = globalThis.__ELPIAN_HOST_ENV__ || globalThis.ELPIAN_HOST_ENV;
  if (env && env.viewport) {
    VP.w = numOr(env.viewport.width, VP.w);
    VP.h = numOr(env.viewport.height, VP.h);
  }
}

// ---- Character models -----------------------------------------------------
// Real, rigged glTF 2.0 / GLB characters streamed over the internet from the
// Khronos sample-asset CDN (CORS-enabled). Elpian's renderer downloads, parses,
// skins and animates them on the fly; until a model arrives a capsule
// placeholder stands in. CesiumMan is a textured walking human (the player);
// RiggedFigure is a lighter articulated humanoid (enemies). Both ship with a
// skeletal walk-cycle clip, so limbs, arms and body move like a real person.
var GLTF_BASE = 'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/';
var MODEL_PLAYER = GLTF_BASE + 'CesiumMan/glTF-Binary/CesiumMan.glb';
var MODEL_GRUNT = GLTF_BASE + 'RiggedFigure/glTF-Binary/RiggedFigure.glb';
var MODEL_HEAVY = GLTF_BASE + 'RiggedFigure/glTF-Binary/RiggedFigure.glb';
// Per-model tuning: uniform scale + yaw offset (deg) so the rig faces its
// travel direction in Elpian's -Z-forward, +Y-up world.
var PLAYER_SCALE = 1.12, PLAYER_YAW = 180;
var GRUNT_SCALE = 1.15, GRUNT_YAW = 180;
var HEAVY_SCALE = 1.62, HEAVY_YAW = 180;

// ════════════════════════════════════════════════════════════════════════
//  GAME STATE
// ════════════════════════════════════════════════════════════════════════
var G = null;

function newGame() {
  G = {
    state: 'menu',
    time: 0,
    wave: 0, kills: 0, score: 0,
    player: { x: 0, z: 8, y: 0, vy: 0, yaw: 0, health: 100, maxHealth: 100, grounded: true, hurtT: 0, animTime: 0 },
    cam: { yaw: 0.5, pitch: -0.22, recoil: 0 },
    weapon: { mag: MAG_SIZE, reserve: RESERVE_START, reloading: false, reloadT: 0, cool: 0 },
    input: { joyActive: false, jx: 0, jz: 0, jmag: 0, jdx: 0, jdy: 0, firing: false, joyPointer: -1 },
    enemies: [],
    ebullets: [],
    fx: [],
    pickups: [],
    enemiesToSpawn: 0, spawnT: 0,
    hitMarker: 0, banner: 0, bannerText: '',
    obstacles: buildObstacles()
  };
}

function buildObstacles() {
  var list = [];
  function b(x, z, sx, sy, sz, c) { list.push({ x: x, z: z, sx: sx, sy: sy, sz: sz, color: c }); }
  b(0, -6, 1.6, 1.6, 1.6, col(0.45, 0.40, 0.32));
  b(4, 2, 1.4, 1.4, 1.4, col(0.40, 0.36, 0.30));
  b(-5, 3, 1.4, 2.2, 1.4, col(0.38, 0.34, 0.30));
  b(7, -5, 1.2, 1.2, 3.0, col(0.42, 0.38, 0.32));
  b(-8, -7, 1.2, 1.2, 3.0, col(0.42, 0.38, 0.32));
  b(-3, -12, 2.4, 1.0, 1.2, col(0.40, 0.36, 0.30));
  b(9, 8, 1.6, 1.6, 1.6, col(0.45, 0.40, 0.32));
  b(-10, 9, 1.4, 2.6, 1.4, col(0.36, 0.33, 0.30));
  b(12, -2, 1.2, 2.0, 1.2, col(0.40, 0.36, 0.30));
  b(2, 12, 1.6, 1.2, 1.6, col(0.42, 0.38, 0.32));
  b(0, 0, 0.9, 3.6, 0.9, col(0.30, 0.32, 0.42));
  b(-14, -2, 0.9, 3.0, 0.9, col(0.30, 0.32, 0.42));
  b(14, 6, 0.9, 3.0, 0.9, col(0.30, 0.32, 0.42));
  return list;
}

// ════════════════════════════════════════════════════════════════════════
//  CORE VECTOR / AIM
// ════════════════════════════════════════════════════════════════════════
function forwardVec(yaw, pitch) {
  return {
    x: Math.sin(yaw) * Math.cos(pitch),
    y: Math.sin(pitch),
    z: -Math.cos(yaw) * Math.cos(pitch)
  };
}
function camPitchEff() { return clamp(G.cam.pitch + G.cam.recoil, -1.2, 0.5); }
function camForward() { return forwardVec(G.cam.yaw, camPitchEff()); }

function aimDir() {
  var f = camForward();
  var p = G.player, mx = p.x, my = p.y + CAM_LOOK_H, mz = p.z;
  var best = null, bestDot = Math.cos(0.21), bestDist = 1e9;
  for (var i = 0; i < G.enemies.length; i++) {
    var e = G.enemies[i];
    if (!e.alive) continue;
    var dx = e.x - mx, dy = (e.y + 1.0) - my, dz = e.z - mz;
    var d = Math.sqrt(dx * dx + dy * dy + dz * dz);
    if (d < 0.001 || d > BULLET_RANGE) continue;
    var dot = (dx * f.x + dy * f.y + dz * f.z) / d;
    if (dot > bestDot && d < bestDist) { best = { x: dx / d, y: dy / d, z: dz / d }; bestDist = d; }
  }
  return best || f;
}

// ════════════════════════════════════════════════════════════════════════
//  COLLISION
// ════════════════════════════════════════════════════════════════════════
function resolveObstacles(o, radius) {
  for (var i = 0; i < G.obstacles.length; i++) {
    var b = G.obstacles[i];
    var hx = b.sx / 2 + radius, hz = b.sz / 2 + radius;
    var dx = o.x - b.x, dz = o.z - b.z;
    if (Math.abs(dx) < hx && Math.abs(dz) < hz) {
      var px = hx - Math.abs(dx), pz = hz - Math.abs(dz);
      if (px < pz) { o.x = b.x + (dx < 0 ? -hx : hx); }
      else { o.z = b.z + (dz < 0 ? -hz : hz); }
    }
  }
}
function rayBlocked(mx, my, mz, dir, maxT) {
  var step = 0.45, t = 0;
  while (t < maxT) {
    var x = mx + dir.x * t, y = my + dir.y * t, z = mz + dir.z * t;
    if (y < 0) return t;
    for (var i = 0; i < G.obstacles.length; i++) {
      var b = G.obstacles[i];
      if (Math.abs(x - b.x) < b.sx / 2 && Math.abs(z - b.z) < b.sz / 2 && y < b.sy && y > 0) return t;
    }
    t += step;
  }
  return maxT;
}
function hasLineOfSight(e, p) {
  var ax = e.x, ay = 1.1, az = e.z;
  var dx = p.x - ax, dy = (p.y + 1.0) - ay, dz = p.z - az;
  var d = Math.sqrt(dx * dx + dy * dy + dz * dz);
  if (d < 0.001) return true;
  dx /= d; dy /= d; dz /= d;
  var t = 0.5;
  while (t < d) {
    var x = ax + dx * t, y = ay + dy * t, z = az + dz * t;
    for (var i = 0; i < G.obstacles.length; i++) {
      var b = G.obstacles[i];
      if (Math.abs(x - b.x) < b.sx / 2 && Math.abs(z - b.z) < b.sz / 2 && y < b.sy && y > 0) return false;
    }
    t += 0.55;
  }
  return true;
}

// ════════════════════════════════════════════════════════════════════════
//  WEAPONS / EFFECTS
// ════════════════════════════════════════════════════════════════════════
function addTracer(ax, ay, az, bx, by, bz) { G.fx.push({ k: 'tracer', ax: ax, ay: ay, az: az, bx: bx, by: by, bz: bz, life: 0.075, max: 0.075 }); }
function addMuzzle(x, y, z) { G.fx.push({ k: 'muzzle', x: x, y: y, z: z, life: 0.06, max: 0.06 }); }
function addImpact(x, y, z, c) { G.fx.push({ k: 'impact', x: x, y: y, z: z, color: c, life: 0.28, max: 0.28 }); }

function fireHitscan() {
  var p = G.player;
  var dir = aimDir();
  var mx = p.x + dir.x * 0.6, my = p.y + CAM_LOOK_H + dir.y * 0.6, mz = p.z + dir.z * 0.6;
  var bestT = rayBlocked(mx, my, mz, dir, BULLET_RANGE);
  var hit = null;
  for (var i = 0; i < G.enemies.length; i++) {
    var e = G.enemies[i];
    if (!e.alive) continue;
    var ex = e.x - mx, ey = (e.y + 1.05) - my, ez = e.z - mz;
    var t = ex * dir.x + ey * dir.y + ez * dir.z;
    if (t < 0 || t > bestT) continue;
    var cx = mx + dir.x * t, cy = my + dir.y * t, cz = mz + dir.z * t;
    var dd = Math.sqrt((cx - e.x) * (cx - e.x) + (cy - (e.y + 1.05)) * (cy - (e.y + 1.05)) + (cz - e.z) * (cz - e.z));
    if (dd < 0.75) { bestT = t; hit = e; }
  }
  var hx = mx + dir.x * bestT, hy = my + dir.y * bestT, hz = mz + dir.z * bestT;
  addTracer(mx, my, mz, hx, hy, hz);
  addMuzzle(mx, my, mz);
  if (hit) { damageEnemy(hit, BULLET_DMG, hx, hy, hz); G.hitMarker = 0.16; }
  else { addImpact(hx, hy, hz, col(0.95, 0.88, 0.7)); }
}

function damageEnemy(e, dmg, hx, hy, hz) {
  e.health -= dmg; e.flash = 0.12;
  addImpact(hx, hy, hz, col(1.0, 0.45, 0.25));
  if (e.health <= 0 && e.alive) {
    e.alive = false; e.dying = 0.5;
    G.kills++; G.score += e.score;
    for (var i = 0; i < 7; i++) addImpact(e.x + rand(-0.4, 0.4), 0.6 + rand(0, 1.1), e.z + rand(-0.4, 0.4), col(1.0, 0.35, 0.2));
    maybeDropPickup(e);
  }
}

function startReload() {
  var w = G.weapon;
  if (w.reloading || w.mag === MAG_SIZE || w.reserve <= 0) return;
  w.reloading = true; w.reloadT = RELOAD_TIME;
}
function finishReload() {
  var w = G.weapon;
  var take = Math.min(MAG_SIZE - w.mag, w.reserve);
  w.mag += take; w.reserve -= take; w.reloading = false;
}

// ════════════════════════════════════════════════════════════════════════
//  ENEMIES
// ════════════════════════════════════════════════════════════════════════
function countAlive() { var n = 0; for (var i = 0; i < G.enemies.length; i++) if (G.enemies[i].alive) n++; return n; }

function spawnEnemy() {
  var ang = Math.random() * PI * 2;
  var ex = Math.cos(ang) * (ARENA - 2.5), ez = Math.sin(ang) * (ARENA - 2.5);
  var heavy = (G.wave >= 3 && Math.random() < 0.32);
  G.enemies.push({
    x: ex, z: ez, y: 0, yaw: 0, animTime: rand(0, 2),
    health: heavy ? 170 : 80, maxHealth: heavy ? 170 : 80, alive: true, flash: 0, dying: 0,
    speed: heavy ? 2.5 : 3.5, attackRange: heavy ? 6 : 9, viewRange: 30,
    fireT: rand(0.6, 1.8), fireRate: heavy ? 1.5 : 2.0, projSpeed: heavy ? 13 : 11,
    dmg: heavy ? 16 : 10, melee: 26, score: heavy ? 25 : 10, type: heavy ? 'heavy' : 'grunt'
  });
}

function enemyShoot(e, p) {
  var ax = e.x, ay = 1.15, az = e.z;
  var dx = p.x - ax, dy = (p.y + 1.0) - ay, dz = p.z - az;
  var d = Math.sqrt(dx * dx + dy * dy + dz * dz);
  if (d < 0.01) return;
  var s = e.projSpeed;
  G.ebullets.push({ x: ax, y: ay, z: az, vx: dx / d * s, vy: dy / d * s, vz: dz / d * s, life: 3.5, dmg: e.dmg });
  addImpact(ax + dx / d * 0.6, ay + dy / d * 0.6, az + dz / d * 0.6, col(1.0, 0.5, 0.15));
}

function updateEnemies() {
  var p = G.player;
  for (var i = 0; i < G.enemies.length; i++) {
    var e = G.enemies[i];
    if (e.flash > 0) e.flash -= DT;
    if (!e.alive) { e.dying -= DT; continue; }
    var dx = p.x - e.x, dz = p.z - e.z;
    var d = Math.sqrt(dx * dx + dz * dz);
    e.yaw = Math.atan2(dx, -dz);
    if (d > e.attackRange) {
      var sp = e.speed * DT;
      e.x += dx / d * sp; e.z += dz / d * sp;
      resolveObstacles(e, 0.55);
      e.x = clamp(e.x, -ARENA + 1, ARENA - 1);
      e.z = clamp(e.z, -ARENA + 1, ARENA - 1);
      // Drive the skeletal walk cycle while the enemy is on the move.
      e.animTime += DT * (1.0 + e.speed * 0.16);
    }
    e.fireT -= DT;
    if (G.state === 'playing' && d < e.viewRange && e.fireT <= 0 && hasLineOfSight(e, p)) {
      e.fireT = e.fireRate; enemyShoot(e, p);
    }
    if (d < 1.2) hurtPlayer(e.melee * DT);
  }
  G.enemies = G.enemies.filter(function (e) { return e.alive || e.dying > 0; });
}

// ════════════════════════════════════════════════════════════════════════
//  PROJECTILES / PICKUPS / WAVES
// ════════════════════════════════════════════════════════════════════════
function updateEBullets() {
  var p = G.player;
  for (var i = 0; i < G.ebullets.length; i++) {
    var b = G.ebullets[i];
    b.x += b.vx * DT; b.y += b.vy * DT; b.z += b.vz * DT; b.life -= DT;
    var dx = b.x - p.x, dy = b.y - (p.y + 1.0), dz = b.z - p.z;
    if (dx * dx + dy * dy + dz * dz < 0.62 * 0.62) { hurtPlayer(b.dmg); b.life = 0; addImpact(b.x, b.y, b.z, col(1, 0.4, 0.2)); continue; }
    if (b.y < 0) { b.life = 0; addImpact(b.x, 0.05, b.z, col(0.85, 0.5, 0.2)); continue; }
    for (var j = 0; j < G.obstacles.length; j++) {
      var o = G.obstacles[j];
      if (Math.abs(b.x - o.x) < o.sx / 2 && Math.abs(b.z - o.z) < o.sz / 2 && b.y < o.sy && b.y > 0) { b.life = 0; addImpact(b.x, b.y, b.z, col(0.85, 0.5, 0.2)); break; }
    }
  }
  G.ebullets = G.ebullets.filter(function (b) { return b.life > 0; });
}

function maybeDropPickup(e) {
  var r = Math.random();
  if (r < 0.20) G.pickups.push({ x: e.x, z: e.z, y: 0.6, kind: 'health', spin: 0 });
  else if (r < 0.46) G.pickups.push({ x: e.x, z: e.z, y: 0.6, kind: 'ammo', spin: 0 });
}
function updatePickups() {
  var p = G.player;
  for (var i = 0; i < G.pickups.length; i++) {
    var pk = G.pickups[i];
    pk.spin += DT * 130;
    if (dist2(pk.x, pk.z, p.x, p.z) < 1.25) {
      pk.taken = true;
      if (pk.kind === 'health') { p.health = clamp(p.health + 30, 0, p.maxHealth); flashBanner('+30 HP', 1.0); addImpact(pk.x, 1.0, pk.z, col(0.3, 1, 0.4)); }
      else { G.weapon.reserve += 24; flashBanner('+24 AMMO', 1.0); addImpact(pk.x, 1.0, pk.z, col(1, 0.85, 0.3)); }
    }
  }
  G.pickups = G.pickups.filter(function (pk) { return !pk.taken; });
}

function startWave(n) {
  G.wave = n;
  G.enemiesToSpawn = 3 + n * 2;
  G.spawnT = 0;
  flashBanner('WAVE ' + n, 2.0);
}
function updateWaves() {
  if (G.state !== 'playing') return;
  if (G.enemiesToSpawn > 0) {
    G.spawnT -= DT;
    if (G.spawnT <= 0 && countAlive() < 7) { spawnEnemy(); G.enemiesToSpawn--; G.spawnT = 0.7; }
  } else if (G.enemies.length === 0) {
    startWave(G.wave + 1);
  }
}
function flashBanner(txt, t) { G.bannerText = txt; G.banner = t; }

// ════════════════════════════════════════════════════════════════════════
//  PLAYER
// ════════════════════════════════════════════════════════════════════════
function hurtPlayer(dmg) {
  if (G.state !== 'playing') return;
  G.player.health -= dmg; G.player.hurtT = 0.5;
  if (G.player.health <= 0) { G.player.health = 0; G.state = 'dead'; G.input.firing = false; }
}

function updatePlayer() {
  var p = G.player, inp = G.input, c = G.cam, w = G.weapon;
  // Single-stick steering. The joystick maps to an ABSOLUTE world heading
  // (up = forward / world -Z, right = world +X), independent of where the
  // camera is currently pointing. The camera then yaws to FOLLOW that heading,
  // so the direction you push == the way the player runs == where the camera
  // looks == the gun's aim.
  //
  // The stick is deliberately read in this fixed world frame rather than
  // relative to the live (rotating) camera: feeding a camera-relative vector
  // back into a camera that chases it makes you circle forever, and freezing a
  // camera-relative frame at press-time goes stale as the camera turns (which
  // is what made movement feel inverted after steering around). A fixed frame
  // has neither problem — hold a direction and you travel dead straight while
  // the camera simply settles in behind you.
  var mx = inp.jx;    // stick right -> world +X
  var mz = -inp.jz;   // stick up    -> world -Z (forward, into the arena)
  var ml = Math.sqrt(mx * mx + mz * mz);
  var movingNow = false;
  if (ml > 0.001) {
    mx /= ml; mz /= ml;
    var spd = MOVE_SPEED * Math.min(1, inp.jmag);
    p.x += mx * spd * DT; p.z += mz * spd * DT;
    movingNow = inp.jmag > 0.06;
    // Swing the camera (and therefore the gun aim) toward the travel heading.
    var targetYaw = Math.atan2(mx, -mz);
    c.yaw = approachAngle(c.yaw, targetYaw, CAM_FOLLOW_RATE * Math.min(1, inp.jmag) * DT);
  }
  // Advance the skeletal walk clip only while moving; freeze to a planted
  // stance when idle so the feet don't slide.
  p.animTime += DT * (movingNow ? (1.1 + Math.min(1, inp.jmag) * 0.7) : 0.0);
  p.yaw = c.yaw;
  p.x = clamp(p.x, -ARENA + 0.7, ARENA - 0.7);
  p.z = clamp(p.z, -ARENA + 0.7, ARENA - 0.7);
  resolveObstacles(p, PLAYER_RADIUS);

  if (!p.grounded || p.y > 0) {
    p.vy -= GRAVITY * DT; p.y += p.vy * DT;
    if (p.y <= 0) { p.y = 0; p.vy = 0; p.grounded = true; }
  }

  if (w.cool > 0) w.cool -= DT;
  if (w.reloading) { w.reloadT -= DT; if (w.reloadT <= 0) finishReload(); }
  if (inp.firing && !w.reloading && w.cool <= 0) {
    if (w.mag > 0) { w.mag--; w.cool = FIRE_COOLDOWN; c.recoil = Math.min(0.10, c.recoil + 0.022); fireHitscan(); }
    else { startReload(); }
  }
  c.recoil *= 0.80;
  if (p.hurtT > 0) p.hurtT -= DT;
  if (p.hurtT <= 0 && p.health < p.maxHealth) p.health = clamp(p.health + 7 * DT, 0, p.maxHealth);
}

function updateFx() {
  for (var i = 0; i < G.fx.length; i++) G.fx[i].life -= DT;
  G.fx = G.fx.filter(function (f) { return f.life > 0; });
  if (G.hitMarker > 0) G.hitMarker -= DT;
  if (G.banner > 0) G.banner -= DT;
}

function updateGame() {
  G.time += DT;
  if (G.state === 'menu') { G.cam.yaw += DT * 0.12; updateFx(); return; }
  if (G.state === 'dead') { updateEnemies(); updateEBullets(); updateFx(); return; }
  updatePlayer();
  updateWaves();
  updateEnemies();
  updateEBullets();
  updatePickups();
  updateFx();
}

// ════════════════════════════════════════════════════════════════════════
//  3D SCENE DSL
// ════════════════════════════════════════════════════════════════════════
function meshOf(shape, params) {
  if (!params) return shape;
  var m = { shape: shape };
  for (var k in params) m[k] = params[k];
  return m;
}
function mesh3d(shape, pos, rot, scale, mat, params) {
  return {
    type: 'mesh3d', mesh: meshOf(shape, params), material: mat,
    transform: { position: pos, rotation: rot || vec(0, 0, 0), scale: scale || vec(1, 1, 1) }
  };
}
function box(pos, size, mat) { return mesh3d('Cube', pos, vec(0, 0, 0), size, mat); }
function matC(c, o) {
  o = o || {};
  var m = { base_color: c, metallic: o.metallic || 0.0, roughness: (o.roughness === undefined ? 0.7 : o.roughness) };
  if (o.emissive) { m.emissive = o.emissive; m.emissive_strength = o.estr || 1.0; }
  if (o.unlit) m.unlit = true;
  if (o.alpha !== undefined) { m.alpha = o.alpha; m.alpha_mode = 'blend'; }
  if (o.double) m.double_sided = true;
  if (o.tex) { m.texture = o.tex; if (o.tex2) m.texture_color2 = o.tex2; if (o.texScale) m.texture_scale = o.texScale; }
  return m;
}
function mixHurt(c, h) { if (h <= 0) return c; return col(lerp(c.r, 1, h), lerp(c.g, 0.3, h), lerp(c.b, 0.3, h)); }

// Emit a real rigged glTF character node. The renderer streams/caches the
// model, samples its skeletal walk clip at `animTime`, skins the mesh on the
// CPU and draws it textured + lit. `yaw` is the entity's facing (radians);
// `yawOff` rotates the rig to face its travel direction.
function modelNode(url, x, y, z, yaw, animTime, scale, yawOff, opts) {
  opts = opts || {};
  var n = {
    type: 'model3d',
    model: url,
    anim_time: animTime,
    transform: {
      position: vec(x, y, z),
      rotation: vec(0, deg(yaw) + (yawOff || 0), 0),
      scale: vec(scale, scale, scale)
    }
  };
  if (opts.anim !== undefined) n.animation = opts.anim;
  if (opts.tint) n.tint = opts.tint;
  if (opts.emissive) { n.emissive = opts.emissive; n.emissive_strength = opts.estr || 1.0; }
  return n;
}

// A held weapon prop, parented to the character's right side and aimed along
// its facing. (The glTF rigs have no gun, so we attach one procedurally.)
function addWeaponProp(w, x, y, z, yaw) {
  var ch = [];
  ch.push(box(vec(0, 0, -0.42), vec(0.12, 0.12, 0.72), matC(col(0.08, 0.09, 0.11), { roughness: 0.4, metallic: 0.6 })));
  ch.push(box(vec(0, 0, -0.88), vec(0.10, 0.10, 0.18), matC(col(0.05, 0.05, 0.06), {})));
  ch.push(box(vec(0, -0.13, -0.06), vec(0.08, 0.18, 0.12), matC(col(0.10, 0.10, 0.13), { roughness: 0.5 })));
  var rgtx = Math.cos(yaw), rgtz = Math.sin(yaw), fwx = Math.sin(yaw), fwz = -Math.cos(yaw);
  var gx = x + rgtx * 0.32 + fwx * 0.14;
  var gz = z + rgtz * 0.32 + fwz * 0.14;
  w.push({ type: 'group', transform: { position: vec(gx, y + 1.15, gz), rotation: vec(0, deg(yaw), 0), scale: vec(1, 1, 1) }, children: ch });
}

function addPlayerModel(w) {
  var p = G.player;
  var opts = {};
  if (p.hurtT > 0) { var h = clamp(p.hurtT / 0.5, 0, 1); opts.emissive = col(0.7 * h, 0.04, 0.04); opts.estr = 2.2; }
  w.push(modelNode(MODEL_PLAYER, p.x, p.y, p.z, p.yaw, p.animTime, PLAYER_SCALE, PLAYER_YAW, opts));
  addWeaponProp(w, p.x, p.y, p.z, p.yaw);
}

function addEnemyModel(w, e) {
  var heavy = e.type === 'heavy';
  var sc = heavy ? HEAVY_SCALE : GRUNT_SCALE;
  var topple = 0;
  if (!e.alive) { var k = clamp(e.dying / 0.5, 0, 1); sc *= Math.max(0.2, k); topple = (1 - k) * 82; }
  var opts = { tint: heavy ? col(0.72, 0.45, 1.0) : col(1.0, 0.55, 0.5) };
  if (e.flash > 0) { opts.emissive = col(0.95, 0.92, 0.92); opts.estr = 2.0; }
  else { opts.emissive = heavy ? col(0.20, 0.0, 0.24) : col(0.22, 0.0, 0.0); opts.estr = 0.55; }
  var url = heavy ? MODEL_HEAVY : MODEL_GRUNT;
  var yawOff = heavy ? HEAVY_YAW : GRUNT_YAW;
  var n = modelNode(url, e.x, e.y, e.z, e.yaw, e.animTime, sc, yawOff, opts);
  // Topple backwards while dying (rotate about X, keep facing + rig offset).
  n.transform.rotation = vec(topple, deg(e.yaw) + yawOff, 0);
  w.push(n);
  if (e.alive) {
    var frac = clamp(e.health / e.maxHealth, 0, 1);
    w.push(box(vec(e.x, 2.4, e.z), vec(1.0, 0.10, 0.06), matC(col(0.08, 0.08, 0.08), { unlit: true })));
    w.push(box(vec(e.x - (1.0 * (1 - frac)) / 2, 2.41, e.z), vec(Math.max(0.03, 1.0 * frac), 0.13, 0.07),
      matC(frac > 0.5 ? col(0.2, 0.9, 0.3) : col(0.95, 0.6, 0.1), { unlit: true, emissive: col(0.1, 0.4, 0.1), estr: 0.4 })));
  }
}

function addEffects(w) {
  for (var i = 0; i < G.fx.length; i++) {
    var f = G.fx[i], a = clamp(f.life / f.max, 0, 1);
    if (f.k === 'muzzle') {
      var s = 0.32 + (1 - a) * 0.22;
      w.push(box(vec(f.x, f.y, f.z), vec(s, s, s), matC(col(1, 0.9, 0.45), { unlit: true, emissive: col(1, 0.85, 0.3), estr: 3, alpha: a })));
    } else if (f.k === 'impact') {
      var r = 0.16 + (1 - a) * 0.55;
      w.push(mesh3d('Sphere', vec(f.x, f.y, f.z), vec(0, 0, 0), vec(1, 1, 1),
        matC(f.color || col(1, 0.8, 0.4), { unlit: true, emissive: f.color || col(1, 0.8, 0.4), estr: 2, alpha: a }), { radius: r, segments: 6 }));
    } else if (f.k === 'tracer') {
      var n = 6;
      for (var j = 0; j < n; j++) {
        var tt = j / (n - 1);
        w.push(mesh3d('Sphere', vec(lerp(f.ax, f.bx, tt), lerp(f.ay, f.by, tt), lerp(f.az, f.bz, tt)), vec(0, 0, 0), vec(1, 1, 1),
          matC(col(1, 0.95, 0.6), { unlit: true, emissive: col(1, 0.9, 0.4), estr: 3, alpha: a }), { radius: 0.05, segments: 4 }));
      }
    }
  }
}

function buildScene() {
  var w = [];
  var p = G.player, c = G.cam;
  w.push({
    type: 'environment',
    ambient_light: { r: 0.34, g: 0.36, b: 0.44 }, ambient_intensity: 0.55,
    sky_color_top: { r: 0.05, g: 0.07, b: 0.16 }, sky_color_bottom: { r: 0.5, g: 0.45, b: 0.55 },
    fog_type: 'linear', fog_color: { r: 0.40, g: 0.40, b: 0.50 }, fog_near: 26, fog_distance: 64
  });
  w.push({ type: 'light', light_type: 'Directional', color: { r: 1.0, g: 0.96, b: 0.85 }, intensity: 1.5, transform: { rotation: { x: -55, y: 35, z: 0 } } });
  w.push({ type: 'light', light_type: 'Directional', color: { r: 0.35, g: 0.45, b: 0.8 }, intensity: 0.5, transform: { rotation: { x: -18, y: 210, z: 0 } } });

  var f = camForward();
  var tx = p.x, ty = p.y + CAM_LOOK_H, tz = p.z;
  var cx = tx - f.x * CAM_DIST, cy = ty - f.y * CAM_DIST, cz = tz - f.z * CAM_DIST;
  if (cy < 0.6) cy = 0.6;
  w.push({
    type: 'camera', camera_type: 'Perspective', fov: 62, near: 0.1, far: 220,
    transform: { position: vec(cx, cy, cz), rotation: vec(deg(camPitchEff()), deg(c.yaw), 0) }
  });

  w.push(mesh3d('Plane', vec(0, 0, 0), vec(0, 0, 0), vec(1, 1, 1),
    matC(col(0.16, 0.18, 0.22), { roughness: 0.95, double: true, tex: 'checkerboard', tex2: col(0.11, 0.13, 0.17), texScale: 26 }), { size: ARENA * 2 }));

  var wallMat = matC(col(0.22, 0.24, 0.30), { roughness: 0.9 });
  w.push(box(vec(0, 1.3, -ARENA), vec(ARENA * 2, 2.6, 0.6), wallMat));
  w.push(box(vec(0, 1.3, ARENA), vec(ARENA * 2, 2.6, 0.6), wallMat));
  w.push(box(vec(-ARENA, 1.3, 0), vec(0.6, 2.6, ARENA * 2), wallMat));
  w.push(box(vec(ARENA, 1.3, 0), vec(0.6, 2.6, ARENA * 2), wallMat));

  for (var i = 0; i < G.obstacles.length; i++) {
    var o = G.obstacles[i];
    w.push(box(vec(o.x, o.sy / 2, o.z), vec(o.sx, o.sy, o.sz), matC(o.color, { roughness: 0.85 })));
  }

  // Always render the player rig (even on the menu) so its model streams in
  // and is posed/ready the moment combat begins.
  addPlayerModel(w);
  for (var i = 0; i < G.enemies.length; i++) addEnemyModel(w, G.enemies[i]);

  for (var i = 0; i < G.ebullets.length; i++) {
    var b = G.ebullets[i];
    w.push(mesh3d('Sphere', vec(b.x, b.y, b.z), vec(0, 0, 0), vec(1, 1, 1),
      matC(col(1, 0.55, 0.15), { unlit: true, emissive: col(1, 0.5, 0.1), estr: 2 }), { radius: 0.17, segments: 6 }));
  }
  for (var i = 0; i < G.pickups.length; i++) {
    var pk = G.pickups[i];
    var pc = pk.kind === 'health' ? col(0.2, 0.9, 0.35) : col(1, 0.8, 0.25);
    var node = box(vec(pk.x, pk.y + Math.sin(G.time * 3) * 0.12, pk.z), vec(0.4, 0.4, 0.4), matC(pc, { emissive: pc, estr: 0.8 }));
    node.transform.rotation = vec(0, pk.spin, 0);
    w.push(node);
  }

  addEffects(w);
  return { world: w };
}

// ════════════════════════════════════════════════════════════════════════
//  2D UI BUILDERS (HUD + controls)
// ════════════════════════════════════════════════════════════════════════
function pos(left, top, right, bottom, child) {
  var s = {};
  if (left !== null && left !== undefined) s.left = left;
  if (top !== null && top !== undefined) s.top = top;
  if (right !== null && right !== undefined) s.right = right;
  if (bottom !== null && bottom !== undefined) s.bottom = bottom;
  return { type: 'Positioned', style: s, children: [child] };
}
function container(w, h, bg, radius, o) {
  o = o || {};
  var s = {};
  if (w !== null && w !== undefined) s.width = w;
  if (h !== null && h !== undefined) s.height = h;
  if (bg) s.backgroundColor = bg;
  if (radius !== null && radius !== undefined) s.borderRadius = radius;
  if (o.borderColor) { s.borderColor = o.borderColor; s.borderWidth = o.borderWidth || 1; }
  if (o.opacity !== undefined) s.opacity = o.opacity;
  var node = { type: 'Container', style: s };
  if (o.key) node.key = o.key;
  if (o.events) node.events = o.events;
  if (o.children) node.children = o.children;
  else if (o.child) node.children = [o.child];
  return node;
}
function text(str, color, size, weight, o) {
  o = o || {};
  var s = { color: color || '#ffffff', fontSize: size || 14 };
  if (weight) s.fontWeight = weight;
  if (o.letter) s.letterSpacing = o.letter;
  return { type: 'Text', props: { text: str }, style: s };
}
function centerNode(child) { return { type: 'Center', children: [child] }; }
function fullRow(top, child) { return { type: 'Positioned', style: { left: 0, right: 0, top: top }, children: [centerNode(child)] }; }
function fill(bg) { return { type: 'Positioned', style: { left: 0, top: 0, right: 0, bottom: 0 }, children: [{ type: 'Container', style: { backgroundColor: bg } }] }; }

function pushHud(ch, W, H) {
  var p = G.player;
  // health
  var hf = clamp(p.health / p.maxHealth, 0, 1);
  ch.push(pos(14, 14, null, null, container(184, 20, 'rgba(10,14,22,0.65)', 10, { borderColor: 'rgba(120,160,200,0.5)', borderWidth: 1 })));
  ch.push(pos(17, 17, null, null, container(178 * hf, 14, hf > 0.5 ? '#36d27a' : (hf > 0.25 ? '#e6b800' : '#ef4444'), 7, {})));
  ch.push(pos(22, 16, null, null, text('HP ' + Math.round(p.health), '#eaf2ff', 12, 'bold')));
  // score / wave
  ch.push(pos(null, 14, 14, null, text('SCORE ' + G.score, '#eaf2ff', 17, 'bold')));
  ch.push(pos(null, 40, 14, null, text('WAVE ' + G.wave + '   KILLS ' + G.kills, '#9fb4d6', 12, 'bold')));
  ch.push(pos(null, 60, 14, null, text('HOSTILES ' + countAlive(), '#ff9a9a', 12, 'bold')));

  // minimap
  var MM = 112, mmx = W / 2 - MM / 2, mmy = 12;
  var mk = [container(MM, MM, 'rgba(8,12,20,0.55)', 8, { borderColor: 'rgba(120,160,200,0.4)', borderWidth: 1 })];
  mk.push(pos(MM / 2 - 3, MM / 2 - 3, null, null, container(6, 6, '#4cc9f0', 3, {})));
  var sc = (MM / 2 - 7) / ARENA;
  for (var i = 0; i < G.enemies.length; i++) {
    var e = G.enemies[i]; if (!e.alive) continue;
    var dx = e.x - p.x, dz = e.z - p.z;
    var ar = dx * Math.cos(G.cam.yaw) + dz * Math.sin(G.cam.yaw);
    var af = dx * Math.sin(G.cam.yaw) - dz * Math.cos(G.cam.yaw);
    var ex = clamp(MM / 2 + ar * sc, 4, MM - 8), ey = clamp(MM / 2 - af * sc, 4, MM - 8);
    mk.push(pos(ex, ey, null, null, container(5, 5, e.type === 'heavy' ? '#c050ff' : '#ff5252', 3, {})));
  }
  ch.push(pos(mmx, mmy, null, null, { type: 'Container', style: { width: MM, height: MM }, children: [{ type: 'Stack', style: { width: MM, height: MM }, children: mk }] }));

  // crosshair
  var cc = G.hitMarker > 0 ? '#ff5a5a' : 'rgba(255,255,255,0.85)';
  var cx = W / 2, cy = H / 2;
  ch.push(pos(cx - 1, cy - 13, null, null, container(2, 8, cc, 1, {})));
  ch.push(pos(cx - 1, cy + 5, null, null, container(2, 8, cc, 1, {})));
  ch.push(pos(cx - 13, cy - 1, null, null, container(8, 2, cc, 1, {})));
  ch.push(pos(cx + 5, cy - 1, null, null, container(8, 2, cc, 1, {})));
  ch.push(pos(cx - 2, cy - 2, null, null, container(4, 4, cc, 2, {})));

  // ammo
  var w = G.weapon;
  var ammo = w.reloading ? 'RELOADING' : (w.mag + ' / ' + w.reserve);
  ch.push(pos(null, null, 36, 152, text(ammo, (w.mag === 0 && !w.reloading) ? '#ff6b6b' : '#eaf2ff', 18, 'bold')));

  // damage vignette (below controls so it never blocks input)
  if (p.hurtT > 0) {
    var v = clamp(p.hurtT / 0.5, 0, 1) * 0.5;
    ch.push(fill('rgba(200,20,20,' + v.toFixed(2) + ')'));
  }
  // banner
  if (G.banner > 0) {
    var a = clamp(G.banner, 0, 1);
    ch.push(fullRow(H * 0.24, text(G.bannerText, 'rgba(255,255,255,' + a.toFixed(2) + ')', 30, 'bold', { letter: 3 })));
  }
}

function pushControls(ch, W, H) {
  // look pad (right side, transparent, fills its rect)
  ch.push({
    type: 'Positioned', style: { left: W * 0.34, top: 0, right: 0, bottom: 0 },
    children: [{ type: 'Container', key: 'lookPad', style: {}, events: { drag: 'onLook', dragstart: 'onLookStart', dragend: 'onLookEnd' } }]
  });

  // movement joystick (bottom-left)
  var tx = G.input.joyActive ? JOY_HALF + G.input.jdx : JOY_HALF;
  var ty = G.input.joyActive ? JOY_HALF + G.input.jdy : JOY_HALF;
  var ring = [
    { type: 'Container', style: { width: JOY, height: JOY, backgroundColor: 'rgba(20,28,40,0.40)', borderRadius: JOY, borderColor: 'rgba(140,180,220,0.5)', borderWidth: 2 } },
    pos(tx - THUMB / 2, ty - THUMB / 2, null, null, { type: 'Container', style: { width: THUMB, height: THUMB, backgroundColor: 'rgba(120,200,255,0.55)', borderRadius: THUMB, borderColor: 'rgba(220,240,255,0.85)', borderWidth: 2 } })
  ];
  // Driven by raw POINTER events (not drag/pan): a Listener stays out of the
  // gesture arena, so it reliably receives pointerup/pointercancel even when the
  // pointer leaves the pad or another recogniser is active. That guarantees the
  // stick recentres and the character halts the instant the finger lifts —
  // pan's onPanEnd was being dropped in the per-frame rebuild, leaving it stuck.
  ch.push(pos(24, null, null, 28, {
    type: 'Container', key: 'joyPad', style: { width: JOY, height: JOY },
    events: { pointerdown: 'onMoveStart', pointermove: 'onMove', pointerup: 'onMoveEnd', pointercancel: 'onMoveEnd' },
    children: [{ type: 'Stack', style: { width: JOY, height: JOY }, children: ring }]
  }));

  // fire button (bottom-right, on top of look pad)
  ch.push(pos(null, null, 30, 40, container(98, 98, 'rgba(200,60,50,0.45)', 98, {
    borderColor: 'rgba(255,170,160,0.85)', borderWidth: 3, key: 'fireBtn',
    events: { tapdown: 'onFireDown', tapup: 'onFireUp', tapcancel: 'onFireUp' },
    child: centerNode(text('FIRE', '#ffffff', 16, 'bold'))
  })));
  // reload
  ch.push(pos(null, null, 140, 58, container(64, 64, 'rgba(40,80,140,0.5)', 64, {
    borderColor: 'rgba(150,200,255,0.7)', borderWidth: 2, key: 'reloadBtn', events: { tap: 'onReload' },
    child: centerNode(text('RELOAD', '#ffffff', 10, 'bold'))
  })));
  // jump
  ch.push(pos(null, null, 142, 134, container(60, 60, 'rgba(60,140,90,0.5)', 60, {
    borderColor: 'rgba(150,255,190,0.7)', borderWidth: 2, key: 'jumpBtn', events: { tap: 'onJump' },
    child: centerNode(text('JUMP', '#ffffff', 12, 'bold'))
  })));
}

function pushMenu(ch, W, H) {
  ch.push({ type: 'Positioned', key: 'menuBg', style: { left: 0, top: 0, right: 0, bottom: 0 }, children: [{ type: 'Container', style: { backgroundColor: 'rgba(4,6,12,0.70)' } }] });
  ch.push(fullRow(H * 0.18, text('ELPIAN', '#4cc9f0', 52, 'bold', { letter: 8 })));
  ch.push(fullRow(H * 0.18 + 58, text('STRIKE FORCE', '#eaf2ff', 26, 'bold', { letter: 6 })));
  ch.push(fullRow(H * 0.40, text('A third-person shooter — pure Elpian + QuickJS', '#7f93b3', 13, 'bold')));
  ch.push(fullRow(H * 0.47, text('LEFT STICK move + auto-aim camera', '#9fb4d6', 13, 'bold')));
  ch.push(fullRow(H * 0.47 + 22, text('RIGHT DRAG optional free look', '#7f93b3', 12, 'bold')));
  ch.push(fullRow(H * 0.51, text('FIRE to shoot    survive the waves', '#9fb4d6', 13, 'bold')));
  ch.push(fullRow(H * 0.64, container(230, 66, 'rgba(50,140,90,0.9)', 16, {
    borderColor: '#bdf3d0', borderWidth: 2, key: 'startBtn', events: { tap: 'onStart' },
    child: centerNode(text('START MISSION', '#ffffff', 18, 'bold', { letter: 2 }))
  })));
}

function pushDeath(ch, W, H) {
  ch.push({ type: 'Positioned', key: 'deathBg', style: { left: 0, top: 0, right: 0, bottom: 0 }, children: [{ type: 'Container', style: { backgroundColor: 'rgba(22,2,2,0.78)' } }] });
  ch.push(fullRow(H * 0.24, text('MISSION FAILED', '#ff5a5a', 40, 'bold', { letter: 4 })));
  ch.push(fullRow(H * 0.24 + 56, text('You were overrun', '#e8b0b0', 16, 'bold')));
  ch.push(fullRow(H * 0.43, text('SCORE  ' + G.score, '#ffffff', 28, 'bold')));
  ch.push(fullRow(H * 0.50, text('WAVE  ' + G.wave + '      KILLS  ' + G.kills, '#cdd6f4', 16, 'bold')));
  ch.push(fullRow(H * 0.66, container(230, 66, 'rgba(200,60,50,0.92)', 16, {
    borderColor: '#ffd0c8', borderWidth: 2, key: 'restartBtn', events: { tap: 'onRestart' },
    child: centerNode(text('REDEPLOY', '#ffffff', 18, 'bold', { letter: 2 }))
  })));
}

function buildTree() {
  readViewport();
  var W = VP.w, H = VP.h;
  var ch = [];
  ch.push({ type: 'GameScene', key: 'world3d', props: { scene: buildScene(), width: W, height: H, fps: 60, interactive: false } });
  pushHud(ch, W, H);
  if (G.state === 'playing') pushControls(ch, W, H);
  if (G.state === 'menu') pushMenu(ch, W, H);
  else if (G.state === 'dead') pushDeath(ch, W, H);
  return { type: 'Stack', key: 'root', style: { width: W, height: H }, children: ch };
}

// ════════════════════════════════════════════════════════════════════════
//  INPUT HANDLERS
// ════════════════════════════════════════════════════════════════════════
function updateJoy(ev) {
  var lp = ev.localPosition || ev.position || { x: JOY_HALF, y: JOY_HALF };
  var vx = numOr(lp.x, JOY_HALF) - JOY_HALF, vy = numOr(lp.y, JOY_HALF) - JOY_HALF;
  var mag = Math.sqrt(vx * vx + vy * vy);
  if (mag > JOY_HALF) { vx = vx / mag * JOY_HALF; vy = vy / mag * JOY_HALF; mag = JOY_HALF; }
  G.input.jdx = vx; G.input.jdy = vy;
  G.input.jx = vx / JOY_HALF; G.input.jz = -vy / JOY_HALF; G.input.jmag = mag / JOY_HALF;
  G.input.joyActive = true;
}
// Only the finger that grabbed the pad steers it: remember its pointer id so a
// second touch (e.g. the fire hand sliding over the pad) can't hijack or, worse,
// fail to release the stick.
function joyOwnsEvent(ev) {
  if (!G.input.joyActive) return true;
  if (!ev || ev.pointerId === undefined || ev.pointerId === null) return true;
  return ev.pointerId === G.input.joyPointer;
}
function resetJoy() {
  G.input.joyActive = false; G.input.jx = 0; G.input.jz = 0; G.input.jmag = 0;
  G.input.jdx = 0; G.input.jdy = 0; G.input.joyPointer = -1;
}
function onMoveStart(input) {
  var ev = decodeEvent(input);
  G.input.joyPointer = (ev && ev.pointerId !== undefined && ev.pointerId !== null) ? ev.pointerId : -1;
  updateJoy(ev);
}
function onMove(input) { var ev = decodeEvent(input); if (joyOwnsEvent(ev)) updateJoy(ev); }
function onMoveEnd(input) { var ev = decodeEvent(input); if (joyOwnsEvent(ev)) resetJoy(); }

function onLookStart(input) {}
function onLook(input) {
  var d = (decodeEvent(input)).delta || { x: 0, y: 0 };
  G.cam.yaw += numOr(d.x, 0) * LOOK_SENS_X;
  G.cam.pitch = clamp(G.cam.pitch - numOr(d.y, 0) * LOOK_SENS_Y, -1.15, 0.42);
}
function onLookEnd(input) {}

function onFireDown(input) { G.input.firing = true; }
function onFireUp(input) { G.input.firing = false; }
function onReload(input) { startReload(); }
function onJump(input) { var p = G.player; if (p.grounded && p.y <= 0.01) { p.vy = JUMP_V; p.grounded = false; } }

// Start facing into the arena (yaw 0 = world -Z) so "stick up = forward" lines
// up with the opening view; the menu orbit leaves cam.yaw at an arbitrary spin.
function aimCameraIntoArena() { G.cam.yaw = 0; G.cam.pitch = -0.22; G.player.yaw = 0; }
function onStart(input) { G.state = 'playing'; G.player.x = 0; G.player.z = 8; G.player.health = G.player.maxHealth; aimCameraIntoArena(); startWave(1); render(); }
function onRestart(input) { newGame(); G.state = 'playing'; aimCameraIntoArena(); startWave(1); render(); }

// ════════════════════════════════════════════════════════════════════════
//  RENDER + LOOP
// ════════════════════════════════════════════════════════════════════════
function render() {
  try { askHost('render', JSON.stringify(buildTree())); }
  catch (e) { askHost('println', 'render error: ' + e); }
}
function gameTick() {
  try { updateGame(); render(); }
  catch (e) { askHost('println', 'tick error: ' + e); }
}

// ---- Boot ----
newGame();
readViewport();
render();
askHost('setInterval', { handler: 'gameTick', delay: 33 });
askHost('println', 'Elpian Strike Force booted');
''';
