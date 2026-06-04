/// The complete third-person shooter, authored as a single QuickJS program.
///
/// Everything game-specific lives here as JavaScript: state management, the
/// 3D scene-graph DSL, enemy AI, weapons, particles/effects, the HUD, and the
/// on-screen touch controls. It drives Elpian's renderer through
/// `askHost('render', ...)` and runs its frame loop via `askHost('setInterval')`.
///
/// Only foundational, reusable capabilities live in the Dart/Elpian layer:
/// the `GameScene` 3D widget, the geometry cache in the software renderer, and
/// the glTF 2.0 / GLB pipeline (streaming model loader, CPU skeletal-animation
/// skinning, and textured `drawVertices` batching). The player and enemies are
/// real rigged glTF characters streamed from the Khronos sample-asset CDN and
/// animated with their skeletal walk cycles — see `addPlayerModel` /
/// `addEnemyModel` and the `model3d` scene node they emit.
library;

const String tpsGameProgram = r'''
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
    input: { joyActive: false, jx: 0, jz: 0, jmag: 0, jdx: 0, jdy: 0, firing: false },
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
  ch.push(pos(24, null, null, 28, {
    type: 'Container', key: 'joyPad', style: { width: JOY, height: JOY }, events: { dragstart: 'onMoveStart', drag: 'onMove', dragend: 'onMoveEnd' },
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
function onMoveStart(input) { updateJoy(decodeEvent(input)); }
function onMove(input) { updateJoy(decodeEvent(input)); }
function onMoveEnd(input) { G.input.joyActive = false; G.input.jx = 0; G.input.jz = 0; G.input.jmag = 0; G.input.jdx = 0; G.input.jdy = 0; }

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
