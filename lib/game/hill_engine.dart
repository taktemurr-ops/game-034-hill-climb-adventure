import 'dart:math' as math;

import '../core/arcade.dart';
import '../core/level_plan.dart';
import '../core/rng.dart';

/// Shared side-view driving engine (hill climb, motocross, monster truck).
/// Hold the right half to accelerate (lean back in the air), the left half
/// to brake / reverse (lean forward in the air). Land on your wheels!

const double kSeg = 320;
const double kGrav = 0.32;
const double kCamX = 330;
const double kGroundScreenY = 1050;

enum HGoal { distance, finish, crush }

class HillSpec {
  final String vehicle; // jeep, bike, monster
  final HGoal goal;
  final double accel;
  final double lean;
  final double drag;
  final double baseDh;
  final bool fuel;
  final bool crush;
  final List<String> mechanics;

  const HillSpec({
    required this.vehicle,
    required this.goal,
    this.accel = 0.26,
    this.lean = 0.0042,
    this.drag = 0.024,
    this.baseDh = 50,
    this.fuel = false,
    this.crush = false,
    this.mechanics = const [],
  });
}

class HillLevel {
  final ArcadeMeta meta;
  final HillSpec spec;
  final int target;
  final double courseLen;
  final double maxDh;
  final bool ramps, scarce, mud, rocks;

  const HillLevel(this.meta, this.spec, this.target, this.courseLen, this.maxDh, this.ramps, this.scarce, this.mud, this.rocks);

  HillLevel withTarget(int t) => HillLevel(meta, spec, t, courseLen, maxDh, ramps, scarce, mud, rocks);
}

HillLevel generateHillLevel(LevelSpec s, HillSpec spec) {
  final m = ArcadeMeta.of(s);
  final d = s.difficulty;
  final course = m.goal ? 9000 + d * 1700.0 : 0.0;
  var l = HillLevel(
    m,
    spec,
    m.goal ? (spec.goal == HGoal.crush ? 1 : (course).round()) : 0,
    course,
    math.min(118.0, spec.baseDh + d * 8.0 + (s.has('steep') ? 18 : 0)),
    s.has('ramps') || spec.vehicle == 'bike',
    s.has('scarce_fuel'),
    s.has('mud'),
    s.has('rocks') || d >= 6,
  );
  if (m.goal && spec.goal == HGoal.crush) {
    final p = HillSim(l.withTarget(1 << 30))..probe = true;
    runBot(p, hillBot, 60 * 60 * 6);
    l = l.withTarget(math.max(1, (p.crushed * (0.5 + 0.04 * d)).floor()));
  }
  return l;
}

class HObj {
  final int kind; // 0 coin, 1 fuel, 2 car (crushable), 3 checkpoint, 4 rock
  final double x;
  bool alive = true;
  HObj(this.kind, this.x);
}

class HillSim extends ArcadeSim {
  final HillLevel level;
  HillSpec get spec => level.spec;
  final Map<int, double> _h = {};
  double px = 200, py = 0, v = 0, vx = 0, vy = 0, ang = 0, angVel = 0;
  bool ground = true;
  double airRot = 0;
  double fuel = 100;
  int outOfFuel = 0;
  int coins = 0, flips = 0, crushed = 0, airTicks = 0, bestAir = 0;
  double checkpoint = 200;
  double maxX = 200;
  final Set<int> taken = {};
  int lastEvent = 0; // 1 coin, 2 crash, 3 flip, 4 crush, 5 fuel, 6 land
  bool probe = false;
  double landDiff = 0;
  int gas = 0; // -1, 0, 1 (for painting)

  HillSim(this.level) : super(level.meta) {
    py = h(px);
  }

  HillSim._(this.level, HillSim o) : super(o.meta) {
    _h.addAll(o._h);
    px = o.px;
    py = o.py;
    v = o.v;
    vx = o.vx;
    vy = o.vy;
    ang = o.ang;
    angVel = o.angVel;
    ground = o.ground;
    airRot = o.airRot;
    fuel = o.fuel;
    outOfFuel = o.outOfFuel;
    coins = o.coins;
    flips = o.flips;
    crushed = o.crushed;
    airTicks = o.airTicks;
    bestAir = o.bestAir;
    checkpoint = o.checkpoint;
    maxX = o.maxX;
    taken.addAll(o.taken);
    ticks = o.ticks;
    score = o.score;
    lives = o.lives;
    revives = o.revives;
    shield = o.shield;
    slow = o.slow;
    probe = o.probe;
  }

  HillSim copy() => HillSim._(level, this);

  double _ctrl(int k) {
    if (k <= 3) return 0;
    final c = _h[k];
    if (c != null) return c;
    final prev = _ctrl(k - 1);
    final rr = SeededRandom(mixSeed([meta.seed, k, 3434]));
    final ramp = level.ramps && k % 7 == 3;
    final dh = level.maxDh * (meta.goal ? 1 : math.min(1.0, 0.6 + k / 150));
    double next;
    if (ramp) {
      next = prev + dh * 1.25;
    } else if (level.ramps && k % 7 == 4) {
      next = prev - dh * 1.1;
    } else {
      // Bias back towards the band [-400, 1200] so the hills never drift away.
      final bias = prev > 1200 ? -0.35 : (prev < -400 ? 0.35 : 0.08);
      next = prev + dh * ((rr.nextDouble() * 2 - 1) + bias).clamp(-1.0, 1.0);
    }
    _h[k] = next;
    return next;
  }

  /// Terrain height at x (world units, up is positive).
  double h(double x) {
    final k = (x / kSeg).floor();
    final t = x / kSeg - k;
    final a = _ctrl(k), b = _ctrl(k + 1);
    return a + (b - a) * (1 - math.cos(math.pi * t)) / 2;
  }

  double slopeD(double x) {
    final k = (x / kSeg).floor();
    final t = x / kSeg - k;
    final a = _ctrl(k), b = _ctrl(k + 1);
    return (b - a) * math.pi / (2 * kSeg) * math.sin(math.pi * t);
  }

  double curv(double x) {
    final k = (x / kSeg).floor();
    final t = x / kSeg - k;
    final a = _ctrl(k), b = _ctrl(k + 1);
    return (b - a) * math.pi * math.pi / (2 * kSeg * kSeg) * math.cos(math.pi * t);
  }

  double slope(double x) => math.atan(slopeD(x));

  /// Deterministic objects in the 100-unit cell `c`.
  HObj? objAt(int c) {
    if (c < 4) return null;
    final x = c * 100.0 + 50;
    if (c % 40 == 0) return HObj(3, x);
    if (spec.fuel && c % (level.scarce ? 52 : 34) == 17) return HObj(1, x);
    final rr = SeededRandom(mixSeed([meta.seed, c, 515]));
    if (spec.crush && c % 14 == 7 && slopeD(x).abs() < 0.35) return HObj(2, x);
    if (level.rocks && !spec.crush && c % 23 == 11 && slopeD(x).abs() < 0.25 && rr.chance(0.6)) return HObj(4, x);
    if (rr.chance(0.22)) return HObj(0, x);
    return null;
  }

  double get distance => px - 200;

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    var g = 0;
    if (input.down && input.x >= 0) g = input.x >= 500 ? 1 : -1;
    if (input.dirX != 0) g = input.dirX;
    if (input.dirY < 0) g = 1;
    if (spec.fuel && fuel <= 0 && g > 0) g = 0;
    gas = g;
    if (ground) {
      final s = slope(px);
      final traction = level.mud && (px ~/ 1600).isOdd ? 0.86 : 1.0;
      var a = -kGrav * math.sin(s) - v * spec.drag;
      if (g > 0) a += spec.accel * traction;
      if (g < 0) a += v > 0.5 ? -0.35 : -spec.accel * 0.6;
      v += a;
      if (v < -4) v = -4;
      final dx = v * math.cos(s);
      px += dx;
      // Takeoff over a convex crest.
      final k = curv(px);
      if (k < 0 && v * v * (-k) > kGrav * math.cos(s) * 1.05 && v > 3) {
        ground = false;
        vx = v * math.cos(s);
        vy = v * math.sin(s);
        py = h(px) + 1;
        ang = s;
        angVel = 0;
        airRot = 0;
        airTicks = 0;
      } else {
        py = h(px);
        ang = slope(px);
      }
      if (px < 60) {
        px = 60;
        v = 0;
      }
      if (spec.fuel && g > 0) fuel -= 0.05;
    } else {
      airTicks++;
      vy -= kGrav;
      px += vx;
      py += vy;
      if (g != 0) angVel += g * spec.lean;
      angVel = clampD(angVel * 0.985, -0.11, 0.11);
      ang += angVel;
      airRot += angVel;
      if (spec.fuel && g > 0) fuel -= 0.02;
      final gy = h(px);
      if (py <= gy) {
        final s = slope(px);
        var diff = (ang - s) % (2 * math.pi);
        if (diff > math.pi) diff -= 2 * math.pi;
        ground = true;
        py = gy;
        landDiff = diff.abs();
        if (diff.abs() > 1.05) {
          lastEvent = 2;
          _crash();
        } else {
          v = vx * math.cos(s) + vy * math.sin(s);
          v *= 1 - diff.abs() * 0.4;
          ang = s;
          final f = (airRot.abs() / (2 * math.pi - 0.7)).floor();
          if (f > 0) {
            flips += f;
            score += 150 * f;
            lastEvent = 3;
          } else {
            lastEvent = 6;
          }
          if (airTicks > bestAir) bestAir = airTicks;
          if (airTicks > 40) score += airTicks;
        }
      }
    }
    if (spec.fuel && fuel <= 0) {
      fuel = 0;
      if (ground && v.abs() < 0.3) {
        outOfFuel++;
        if (outOfFuel > 120) {
          outOfFuel = 0;
          lastEvent = 2;
          _crash();
          fuel = 50;
        }
      }
    } else {
      outOfFuel = 0;
    }
    _objects();
    if (px > maxX) {
      if (ticks % 10 == 0) score += ((px - maxX) / 10).round();
      maxX = px;
    }
    if (meta.goal && !probe) {
      switch (spec.goal) {
        case HGoal.distance:
        case HGoal.finish:
          if (distance >= level.courseLen) win();
        case HGoal.crush:
          if (crushed >= level.target) win();
      }
    } else if (probe && distance >= level.courseLen) {
      win();
    }
  }

  void _objects() {
    final c0 = ((px - 120) / 100).floor(), c1 = ((px + 120) / 100).floor();
    for (var c = c0; c <= c1; c++) {
      if (taken.contains(c)) continue;
      final o = objAt(c);
      if (o == null) continue;
      final dx = (o.x - px).abs();
      switch (o.kind) {
        case 0:
          if (dx < 60 && (py + 30 - (h(o.x) + 80)).abs() < 120) {
            taken.add(c);
            coins++;
            score += 10;
            lastEvent = 1;
          }
        case 1:
          if (dx < 70 && (py - h(o.x)).abs() < 200) {
            taken.add(c);
            fuel = 100;
            lastEvent = 5;
          }
        case 3:
          if (px >= o.x) {
            taken.add(c);
            checkpoint = o.x;
          }
        case 2:
          if (dx < 110 && py - h(o.x) < 90) {
            final speed = ground ? v : math.sqrt(vx * vx + vy * vy);
            if (speed > 2.5 || (!ground && vy < -2)) {
              taken.add(c);
              crushed++;
              score += 100;
              lastEvent = 4;
              if (ground) v *= 0.85;
            } else if (ground && px < o.x) {
              px = o.x - 110;
              v = 0;
            }
          }
        case 4:
          if (dx < 60 && py - h(o.x) < 50) {
            if (ground && v > 6) {
              // Rock bump: tossed into the air.
              ground = false;
              vx = v * 0.8;
              vy = 5;
              airRot = 0;
              airTicks = 0;
              taken.add(c);
            } else if (ground) {
              v *= 0.6;
              taken.add(c);
            }
          }
      }
    }
  }

  void _crash() {
    hit();
    if (!over) _respawn();
  }

  void _respawn() {
    px = checkpoint;
    py = h(px);
    v = 0;
    ground = true;
    ang = slope(px);
    angVel = 0;
  }

  @override
  void hit() {
    if (meta.zen) {
      _respawn();
      return;
    }
    super.hit();
  }

  @override
  void onLifeLost() {}

  @override
  void revive() {
    super.revive();
    _respawn();
    if (spec.fuel) fuel = 100;
  }

  /// Booster: turbo — refuel and a speed kick.
  @override
  bool useBooster() {
    if (over) return false;
    fuel = 100;
    if (ground) v = math.max(v, 9);
    shield = 120;
    return true;
  }

  @override
  double get progress => switch (spec.goal) {
        HGoal.crush => level.target == 0 ? 0 : (crushed / level.target).clamp(0.0, 1.0).toDouble(),
        _ => level.courseLen == 0 ? 0 : (distance / level.courseLen).clamp(0.0, 1.0).toDouble(),
      };

  @override
  String get goalText {
    final m = (distance / 10).floor();
    if (!meta.goal) return '$m m';
    return switch (spec.goal) {
      HGoal.crush => '$crushed/${level.target}',
      _ => '$m/${(level.courseLen / 10).round()} m',
    };
  }

  @override
  Map<String, int> get stats => {
        'distance_m': (maxX / 10).floor(),
        'coins': coins,
        'flips': flips,
        'crushed': crushed,
        'air_time': bestAir ~/ 60,
      };

  @override
  int get stars => lifeStars(this, 3);
}

/// Autopilot: full throttle on the ground; in the air it tries gas / brake /
/// nothing on copies and keeps the one that lands closest to the slope.
ArcadeInput hillBot(ArcadeSim sim) {
  final s = sim as HillSim;
  if (s.ground) {
    // Brake on very fast descents into a crest so jumps stay controllable.
    if (s.v > 13 && s.curv(s.px + 150) < -0.004) return const ArcadeInput(down: true, x: 100, y: 1200);
    return const ArcadeInput(down: true, x: 900, y: 1200);
  }
  var best = 1e9;
  var choice = 0;
  for (final g in const [0, 1, -1]) {
    final c = s.copy();
    final lives = c.lives;
    var t = 0;
    while (!c.ground && t < 400) {
      final gg = t < 6 ? g : 0;
      c.tick(gg == 0 ? ArcadeInput.idle : ArcadeInput(down: true, x: gg > 0 ? 900 : 100, y: 1200));
      t++;
    }
    var diff = c.ground ? c.landDiff : 5.0;
    if (c.lives < lives) diff = 10.0;
    if (diff < best - 0.01) {
      best = diff;
      choice = g;
    }
  }
  if (choice == 0) return ArcadeInput.idle;
  return ArcadeInput(down: true, x: choice > 0 ? 900 : 100, y: 1200);
}
