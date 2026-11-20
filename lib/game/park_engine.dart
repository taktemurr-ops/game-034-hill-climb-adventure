import 'dart:math' as math;

import '../core/arcade.dart';
import '../core/level_plan.dart';
import '../core/rng.dart';

/// Top-down parking engine. Hold the finger where the car should drive; tap
/// the gear button for reverse. Stop inside the marked bay, lined up.

const int kPCols = 5, kPRows = 7;
const double kPCell = 180;
const double kPX0 = 50, kPY0 = 190;
const double kCarL = 132, kCarW = 66;
const double kVMax = 3.0, kVRev = 2.2;
final gearRect = (x: 20.0, y: 1470.0, w: 200.0, h: 110.0);

class PRect {
  final double x, y, w, h; // axis aligned
  final int look; // 0 parked car, 1 wall, 2 cone
  const PRect(this.x, this.y, this.w, this.h, this.look);
  double get cx => x + w / 2;
  double get cy => y + h / 2;
}

class PCourse {
  final List<(int, int)> path; // cells from start to bay
  final List<PRect> obstacles;
  final int bayDir; // 0 up 1 right 2 down 3 left (direction of the last move)
  final (int, int)? moverCell;
  final bool moverHorizontal;
  const PCourse(this.path, this.obstacles, this.bayDir, this.moverCell, this.moverHorizontal);

  (double, double) center(int i) => cellCenter(path[i]);
  (double, double) get bay => cellCenter(path.last);
}

(double, double) cellCenter((int, int) c) => (kPX0 + (c.$1 + 0.5) * kPCell, kPY0 + (c.$2 + 0.5) * kPCell);

const _dirs = [(0, -1), (1, 0), (0, 1), (-1, 0)];

PCourse makeCourse(int seed, int stage, int difficulty, {bool long = false, bool tight = false, bool traffic = false, bool cones = false}) {
  for (var attempt = 0; attempt < 60; attempt++) {
    final rr = SeededRandom(mixSeed([seed, stage, attempt, 3232]));
    final len = math.min(10, 3 + difficulty ~/ 2 + (long ? 2 : 0) + rr.nextInt(2));
    final path = <(int, int)>[(2, kPRows - 1)];
    final seen = {path.first};
    var lastDir = 0;
    var ok = true;
    for (var i = 1; i < len && ok; i++) {
      final (cx, cy) = path.last;
      final opts = <int>[];
      for (var d = 0; d < 4; d++) {
        if (d == 2 && difficulty < 5) continue;
        if (i == 1 && d != 0) continue; // leave the start straight
        final n = (cx + _dirs[d].$1, cy + _dirs[d].$2);
        if (n.$1 < 0 || n.$1 >= kPCols || n.$2 < 0 || n.$2 >= kPRows || seen.contains(n)) continue;
        // keep corridors apart: the new cell may only touch the previous one
        var touches = 0;
        for (final dd in _dirs) {
          if (seen.contains((n.$1 + dd.$1, n.$2 + dd.$2))) touches++;
        }
        if (touches > 1) continue;
        opts.add(d);
        if (d == lastDir) opts.add(d); // prefer straight a bit
      }
      if (opts.isEmpty) {
        ok = false;
        break;
      }
      final d = opts[rr.nextInt(opts.length)];
      final n = (cx + _dirs[d].$1, cy + _dirs[d].$2);
      path.add(n);
      seen.add(n);
      lastDir = d;
    }
    if (!ok || path.length < 3) continue;
    // the bay must be entered straight: last two moves the same direction
    final a = path[path.length - 2], b = path.last, p0 = path[path.length - 3];
    final dLast = _dirOf(a, b), dPrev = _dirOf(p0, a);
    if (dLast != dPrev) continue;
    final obstacles = <PRect>[];
    final inset = tight ? 14.0 : 30.0;
    final dens = math.min(0.95, 0.45 + difficulty * 0.05 + (cones ? 0.1 : 0));
    final blocked = <(int, int)>{};
    for (var y = 0; y < kPRows; y++) {
      for (var x = 0; x < kPCols; x++) {
        final c = (x, y);
        if (seen.contains(c)) continue;
        var adj = false;
        for (final dd in _dirs) {
          if (seen.contains((x + dd.$1, y + dd.$2))) adj = true;
        }
        if (!adj) continue;
        // bay neighbours are always parked cars
        final bayN = _isSide(c, b, dLast);
        final beyond = c == (b.$1 + _dirs[dLast].$1, b.$2 + _dirs[dLast].$2);
        if (!bayN && !beyond && !rr.chance(dens)) continue;
        blocked.add(c);
        final x0 = kPX0 + x * kPCell, y0 = kPY0 + y * kPCell;
        if (beyond) {
          obstacles.add(PRect(x0 + inset, y0 + inset, kPCell - inset * 2, kPCell - inset * 2, 1));
        } else if (bayN || rr.chance(0.6)) {
          final vertical = bayN ? dLast % 2 == 0 : rr.chance(0.5);
          final w = vertical ? kCarW + 4 : kCarL + 4, h = vertical ? kCarL + 4 : kCarW + 4;
          obstacles.add(PRect(x0 + (kPCell - w) / 2, y0 + (kPCell - h) / 2, w, h, 0));
        } else if (cones || rr.chance(0.4)) {
          for (var k = 0; k < 3; k++) {
            obstacles.add(PRect(x0 + inset + k * (kPCell - inset * 2 - 36) / 2, y0 + kPCell / 2 - 18, 36, 36, 2));
          }
        } else {
          obstacles.add(PRect(x0 + inset, y0 + inset, kPCell - inset * 2, kPCell - inset * 2, 1));
        }
      }
    }
    (int, int)? mover;
    var horiz = false;
    if (traffic && path.length >= 5) {
      for (var i = 2; i < path.length - 2; i++) {
        final d1 = _dirOf(path[i - 1], path[i]), d2 = _dirOf(path[i], path[i + 1]);
        if (d1 != d2) continue;
        final side1 = (path[i].$1 + _dirs[(d1 + 1) % 4].$1, path[i].$2 + _dirs[(d1 + 1) % 4].$2);
        final side2 = (path[i].$1 + _dirs[(d1 + 3) % 4].$1, path[i].$2 + _dirs[(d1 + 3) % 4].$2);
        bool inside((int, int) c) => c.$1 >= 0 && c.$1 < kPCols && c.$2 >= 0 && c.$2 < kPRows;
        if (!inside(side1) || !inside(side2) || seen.contains(side1) || seen.contains(side2)) continue;
        obstacles.removeWhere((o) {
          for (final s in [side1, side2]) {
            final x0 = kPX0 + s.$1 * kPCell, y0 = kPY0 + s.$2 * kPCell;
            if (o.cx > x0 && o.cx < x0 + kPCell && o.cy > y0 && o.cy < y0 + kPCell) return true;
          }
          return false;
        });
        mover = path[i];
        horiz = d1 % 2 == 0;
        break;
      }
    }
    return PCourse(path, obstacles, dLast, mover, horiz);
  }
  // Fallback: straight drive into a bay.
  final path = [for (var y = kPRows - 1; y >= kPRows - 4; y--) (2, y)];
  return PCourse(path, const [], 0, null, false);
}

int _dirOf((int, int) a, (int, int) b) {
  for (var d = 0; d < 4; d++) {
    if (a.$1 + _dirs[d].$1 == b.$1 && a.$2 + _dirs[d].$2 == b.$2) return d;
  }
  return 0;
}

bool _isSide((int, int) c, (int, int) bay, int d) {
  final l = (bay.$1 + _dirs[(d + 1) % 4].$1, bay.$2 + _dirs[(d + 1) % 4].$2);
  final r = (bay.$1 + _dirs[(d + 3) % 4].$1, bay.$2 + _dirs[(d + 3) % 4].$2);
  return c == l || c == r;
}

class ParkLevel {
  final ArcadeMeta meta;
  final int target; // bays to park, 0 = endless
  final bool long, tight, traffic, cones, timer;
  const ParkLevel(this.meta, this.target, this.long, this.tight, this.traffic, this.cones, this.timer);
}

ParkLevel generateParkLevel(LevelSpec s) {
  final m = ArcadeMeta.of(s);
  final d = s.difficulty;
  return ParkLevel(m, m.goal ? (d <= 3 ? 1 : (d <= 7 ? 2 : 3)) : 0, s.has('long'), s.has('tight'), s.has('traffic') || d >= 8, s.has('cones'), s.has('timer'));
}

class ParkSim extends ArcadeSim {
  final ParkLevel level;
  int stage = 0;
  late PCourse course;
  double x = 0, y = 0, th = -math.pi / 2, v = 0;
  bool reverse = false;
  int parkedTicks = 0;
  int parks = 0, crashes = 0, perfect = 0;
  int stageStart = 0;
  int lastEvent = 0; // 1 gear, 2 crash, 3 parked
  bool _wasDown = false;
  // autopilot memory
  int botIdx = 1;
  int botWait = 0;
  bool moverHit = false;

  ParkSim(this.level) : super(level.meta) {
    _load();
  }

  ParkSim._(this.level, ParkSim o) : super(o.meta) {
    stage = o.stage;
    course = o.course;
    x = o.x;
    y = o.y;
    th = o.th;
    v = o.v;
    reverse = o.reverse;
    parkedTicks = o.parkedTicks;
    parks = o.parks;
    crashes = o.crashes;
    perfect = o.perfect;
    stageStart = o.stageStart;
    _wasDown = o._wasDown;
    botIdx = o.botIdx;
    botWait = o.botWait;
    ticks = o.ticks;
    score = o.score;
    lives = o.lives;
    revives = o.revives;
    shield = o.shield;
    slow = o.slow;
  }

  ParkSim copy() => ParkSim._(level, this);

  int get difficulty => math.min(10, meta.difficulty + (meta.goal ? 0 : stage ~/ 2));

  void _load() {
    course = makeCourse(meta.seed, stage, difficulty,
        long: level.long, tight: level.tight, traffic: level.traffic, cones: level.cones);
    stageStart = ticks;
    _reset();
  }

  void _reset() {
    final (cx, cy) = course.center(0);
    x = cx;
    y = cy + 10;
    th = -math.pi / 2;
    v = 0;
    reverse = false;
    parkedTicks = 0;
    botIdx = 1;
  }

  int get timeLimit => 25 + course.path.length * 5;

  int get secondsLeft => timeLimit - (ticks - stageStart) ~/ 60;

  /// Moving car (traffic) rectangle at the current tick.
  PRect? get mover {
    final m = course.moverCell;
    if (m == null) return null;
    final (cx, cy) = cellCenter(m);
    final off = math.sin(ticks / 70) * kPCell;
    return course.moverHorizontal
        ? PRect(cx + off - kCarL / 2, cy - kCarW / 2, kCarL, kCarW, 0)
        : PRect(cx - kCarW / 2, cy + off - kCarL / 2, kCarW, kCarL, 0);
  }

  static bool inGear(double px, double py) =>
      px >= gearRect.x && px <= gearRect.x + gearRect.w && py >= gearRect.y && py <= gearRect.y + gearRect.h;

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    var hold = false;
    double? tx, ty;
    if (input.down && input.x >= 0) {
      if (inGear(input.x, input.y)) {
        if (!_wasDown) {
          reverse = !reverse;
          lastEvent = 1;
        }
      } else {
        hold = true;
        tx = input.x;
        ty = input.y;
      }
    }
    _wasDown = input.down;
    var steerKey = 0;
    if (input.dirY != 0) {
      hold = true;
      reverse = input.dirY > 0;
      steerKey = input.dirX;
    } else if (input.dirX != 0) {
      hold = true;
      steerKey = input.dirX;
    }
    final target = hold ? (reverse ? -kVRev : kVMax) : 0.0;
    v = moveToward(v, target, hold ? 0.1 : 0.25);
    if (v.abs() > 0.01) {
      double want;
      if (tx != null && ty != null) {
        final a = math.atan2(ty - y, tx - x);
        want = reverse ? a + math.pi : a;
      } else {
        want = th + steerKey * 0.6 * (reverse ? -1 : 1);
      }
      var diff = (want - th) % (2 * math.pi);
      if (diff > math.pi) diff -= 2 * math.pi;
      final rate = 0.05 * (v.abs() / kVMax).clamp(0.3, 1.0);
      th += clampD(diff * 0.15, -rate, rate);
    }
    x += v * math.cos(th);
    y += v * math.sin(th);
    if (_collides()) {
      crashes++;
      lastEvent = 2;
      hit();
      if (!over) _reset();
      return;
    }
    if (level.timer && meta.goal && secondsLeft < 0) {
      lastEvent = 2;
      hit();
      if (!over) {
        stageStart = ticks;
        _reset();
      }
      return;
    }
    // parked?
    final (bx, by) = course.bay;
    final axis = course.bayDir % 2 == 0 ? math.pi / 2 : 0.0;
    var da = (th - axis) % math.pi;
    if (da > math.pi / 2) da -= math.pi;
    final inBay = (x - bx).abs() < 30 && (y - by).abs() < 30 && da.abs() < 0.22;
    if (inBay && v.abs() < 0.05) {
      parkedTicks++;
      if (parkedTicks >= 24) {
        parks++;
        final fast = (ticks - stageStart) < timeLimit * 30;
        if (fast) perfect++;
        score += 100 + (fast ? 50 : 0) + math.max(0, secondsLeft) * 2;
        lastEvent = 3;
        if (meta.goal && parks >= level.target) {
          win();
          return;
        }
        stage++;
        _load();
      }
    } else {
      parkedTicks = 0;
    }
  }

  List<(double, double)> carCorners([double? cx, double? cy, double? a]) {
    final px = cx ?? x, py = cy ?? y, t = a ?? th;
    final c = math.cos(t), s = math.sin(t);
    const hl = kCarL / 2, hw = kCarW / 2;
    return [
      for (final (u, w) in const [(hl, hw), (hl, -hw), (-hl, -hw), (-hl, hw)]) (px + u * c - w * s, py + u * s + w * c),
    ];
  }

  bool _collides() {
    final cs = carCorners();
    for (final (px, py) in cs) {
      if (px < kPX0 || px > kPX0 + kPCols * kPCell || py < kPY0 || py > kPY0 + kPRows * kPCell) return true;
    }
    for (final o in course.obstacles) {
      if (_obbHit(cs, o)) return true;
    }
    final m = mover;
    if (m != null && shield == 0 && _obbHit(cs, m)) {
      moverHit = true;
      return true;
    }
    return false;
  }

  bool _obbHit(List<(double, double)> cs, PRect r) {
    // SAT with the rectangle's axes and the car's axes.
    var minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9;
    for (final (px, py) in cs) {
      minX = math.min(minX, px);
      maxX = math.max(maxX, px);
      minY = math.min(minY, py);
      maxY = math.max(maxY, py);
    }
    if (maxX < r.x || minX > r.x + r.w || maxY < r.y || minY > r.y + r.h) return false;
    final rc = [(r.x, r.y), (r.x + r.w, r.y), (r.x + r.w, r.y + r.h), (r.x, r.y + r.h)];
    for (final ax in [(math.cos(th), math.sin(th)), (-math.sin(th), math.cos(th))]) {
      var a0 = 1e9, a1 = -1e9, b0 = 1e9, b1 = -1e9;
      for (final (px, py) in cs) {
        final p = px * ax.$1 + py * ax.$2;
        a0 = math.min(a0, p);
        a1 = math.max(a1, p);
      }
      for (final (px, py) in rc) {
        final p = px * ax.$1 + py * ax.$2;
        b0 = math.min(b0, p);
        b1 = math.max(b1, p);
      }
      if (a1 < b0 || b1 < a0) return false;
    }
    return true;
  }

  @override
  void hit() {
    if (meta.zen) {
      _reset();
      return;
    }
    super.hit();
  }

  @override
  void revive() {
    super.revive();
    stageStart = ticks;
    _reset();
  }

  /// Booster: ghost mode — pass through the moving car and refresh the timer.
  @override
  bool useBooster() {
    if (over) return false;
    shield = 600;
    stageStart = ticks;
    return true;
  }

  @override
  double get progress => level.target == 0 ? 0 : (parks / level.target).clamp(0.0, 1.0);

  @override
  String get goalText => level.target == 0 ? 'P $parks' : 'P $parks/${level.target}';

  @override
  Map<String, int> get stats => {'cars_parked': parks, 'perfect_parks': perfect, 'crashes': crashes};

  @override
  int get stars => lifeStars(this, 3);
}

/// Autopilot: follows the corridor cell centres (pure pursuit), waits for
/// the moving car, and brakes to a stop in the bay.
ArcadeInput parkBot(ArcadeSim sim) {
  final s = sim as ParkSim;
  if (s.ticks < s.botWait) return ArcadeInput.idle;
  final i = _parkDrive(s);
  if (s.course.moverCell != null && i.down) {
    // Would the moving car hit us in the next moments? Then wait.
    final k = s.copy();
    for (var t = 0; t < 45 && !k.over; t++) {
      k.tick(_parkDrive(k));
      if (k.moverHit) {
        s.botWait = s.ticks + 8;
        return ArcadeInput.idle;
      }
    }
  }
  return i;
}

ArcadeInput _parkDrive(ParkSim s) {
  final c = s.course;
  final last = c.path.length - 1;
  while (s.botIdx < last) {
    final (wx, wy) = c.center(s.botIdx);
    if (math.sqrt((wx - s.x) * (wx - s.x) + (wy - s.y) * (wy - s.y)) < 95) {
      s.botIdx++;
    } else {
      break;
    }
  }
  var (tx, ty) = c.center(s.botIdx);
  if (s.botIdx >= last) {
    // Final approach: steer onto the bay's axis and stop on its centre.
    final u = _dirs[c.bayDir];
    final r = (tx - s.x) * u.$1 + (ty - s.y) * u.$2;
    if (r <= s.v * s.v / 0.5 + 2) return ArcadeInput.idle;
    final look = 100 - r;
    tx += u.$1 * look;
    ty += u.$2 * look;
  }
  return ArcadeInput(down: true, x: tx.roundToDouble(), y: ty.roundToDouble());
}
