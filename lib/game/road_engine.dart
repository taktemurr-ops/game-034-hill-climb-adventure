import 'dart:math' as math;

import '../core/arcade.dart';
import '../core/level_plan.dart';
import '../core/rng.dart';

/// Shared top-down driving engine (traffic racer, drift, truck, police
/// escape, kart race, boat race). The road scrolls vertically; the player
/// steers left/right (finger position or arrow keys) and accelerates
/// automatically. Everything is deterministic for a seed + input stream.

const double kPlayerY = 1250;
const double kSpawnAhead = 1700;

/// Holding the finger below this line brakes (while still steering).
const double kBrakeY = 1460;

enum RGoal { distance, escape, race, drift, gates, deliveries }

class RoadSpec {
  final String vehicle; // car, truck, kart, boat, drift
  final RGoal goal;
  final int lanes;
  final double laneW;
  final double curve; // 0..1 share of the possible curve amplitude
  final double maxSpeed;
  final double steer;
  final double traffic; // base traffic density
  final bool statics; // rocks / logs / road works
  final bool fuel;
  final bool police;
  final int opponents;
  final bool items;
  final bool current; // water current
  final List<String> mechanics;

  const RoadSpec({
    required this.vehicle,
    required this.goal,
    this.lanes = 4,
    this.laneW = 170,
    this.curve = 0.2,
    this.maxSpeed = 14,
    this.steer = 9,
    this.traffic = 0.35,
    this.statics = false,
    this.fuel = false,
    this.police = false,
    this.opponents = 0,
    this.items = false,
    this.current = false,
    this.mechanics = const [],
  });
}

class RoadLevel {
  final ArcadeMeta meta;
  final RoadSpec spec;
  final int target;
  final double courseLen;
  final int needPos;
  final List<double> oppSpeed;
  final List<double> oppStart;
  final double amp;
  final double ph1, ph2;
  final List<double> laneSpeed;
  final double density;
  final double rowGap;
  final bool oncoming, rain, night, blocks, oil;
  final double gateHw;

  const RoadLevel({
    required this.meta,
    required this.spec,
    required this.target,
    required this.courseLen,
    required this.needPos,
    required this.oppSpeed,
    required this.oppStart,
    required this.amp,
    required this.ph1,
    required this.ph2,
    required this.laneSpeed,
    required this.density,
    required this.rowGap,
    required this.oncoming,
    required this.rain,
    required this.night,
    required this.blocks,
    required this.oil,
    required this.gateHw,
  });

  RoadLevel withGoal({int? target, List<double>? oppSpeed}) => RoadLevel(
        meta: meta,
        spec: spec,
        target: target ?? this.target,
        courseLen: courseLen,
        needPos: needPos,
        oppSpeed: oppSpeed ?? this.oppSpeed,
        oppStart: oppStart,
        amp: amp,
        ph1: ph1,
        ph2: ph2,
        laneSpeed: laneSpeed,
        density: density,
        rowGap: rowGap,
        oncoming: oncoming,
        rain: rain,
        night: night,
        blocks: blocks,
        oil: oil,
        gateHw: gateHw,
      );

  double get halfW => spec.lanes * spec.laneW / 2;
}

/// Object kinds.
const int kCar = 0, kRock = 2, kCoin = 3, kFuel = 4, kBox = 5, kOil = 6, kCop = 7, kGate = 8, kDepot = 9, kOpp = 10;

class RObj {
  int kind;
  double d;
  double x;
  double v;
  int lane;
  bool alive = true;
  bool passed = false;
  int look; // visual variant
  double hw; // gate half width

  RObj(this.kind, this.d, this.x, {this.v = 0, this.lane = -1, this.look = 0, this.hw = 0});

  RObj clone() => RObj(kind, d, x, v: v, lane: lane, look: look, hw: hw)
    ..alive = alive
    ..passed = passed;

  bool get hazard => kind == kCar || kind == kRock || kind == kCop;
}

RoadLevel generateRoadLevel(LevelSpec s, RoadSpec spec, {bool calibrate = true}) {
  final m = ArcadeMeta.of(s);
  final d = s.difficulty;
  final rr = SeededRandom(mixSeed([s.seed, 3131]));
  final halfW = spec.lanes * spec.laneW / 2;
  final maxAmp = math.max(0.0, 470 - halfW);
  final amp = maxAmp * spec.curve * (0.55 + 0.045 * d);
  final oncoming = (s.has('oncoming') || (spec.vehicle == 'car' && d >= 7)) && spec.lanes >= 4 && spec.traffic > 0;
  // All lanes of one direction share a speed so that the "free lane in
  // every row" guarantee keeps holding while the traffic moves.
  final fwd = spec.maxSpeed * (0.36 + rr.nextDouble() * 0.12);
  final back = -spec.maxSpeed * (0.3 + rr.nextDouble() * 0.1);
  final laneSpeed = <double>[
    for (var i = 0; i < spec.lanes; i++) oncoming && i < spec.lanes ~/ 2 ? back : fwd,
  ];
  var target = 0;
  var course = 0.0;
  var needPos = 1;
  if (m.goal) {
    switch (spec.goal) {
      case RGoal.distance:
      case RGoal.escape:
        target = 16000 + d * 3200;
      case RGoal.race:
        course = 22000 + d * 2600.0;
        needPos = d <= 3 ? 3 : (d <= 7 ? 2 : 1);
      case RGoal.drift:
        course = 20000 + d * 2200.0;
        target = 1;
      case RGoal.gates:
        target = 10 + d * 2;
      case RGoal.deliveries:
        target = 2 + d ~/ 3;
    }
  }
  final oppStart = <double>[for (var i = 0; i < spec.opponents; i++) 120.0 + i * 70 + rr.nextDouble() * 40];
  var lvl = RoadLevel(
    meta: m,
    spec: spec,
    target: target,
    courseLen: course,
    needPos: math.min(needPos, spec.opponents + 1),
    oppSpeed: const [],
    oppStart: oppStart,
    amp: amp,
    ph1: rr.nextDouble() * 6.28,
    ph2: rr.nextDouble() * 6.28,
    laneSpeed: laneSpeed,
    density: math.min(0.5, spec.traffic * (0.75 + d * 0.06) + (s.has('busy') ? 0.12 : 0)),
    rowGap: math.max(620.0, 920 - d * 30.0),
    oncoming: oncoming,
    rain: s.has('rain'),
    night: s.has('night'),
    blocks: s.has('roadblocks') || (spec.statics && d >= 4),
    oil: s.has('oil') || (spec.items && d >= 5),
    gateHw: math.max(spec.laneW * 0.62, spec.laneW * (1.15 - d * 0.045)),
  );
  if (!calibrate || !m.goal) return lvl;
  if (spec.goal == RGoal.race) {
    // Measure how fast the autopilot drives this course alone and set the
    // rivals around that pace: the first (needPos-1) may be faster, the
    // rest are slightly slower => always winnable, never trivial.
    final probe = RoadSim(lvl.withGoal(oppSpeed: const []))..probe = true;
    runBot(probe, roadBot, 60 * 60 * 6);
    final avg = probe.dist / math.max(1, probe.ticks);
    final sp = <double>[];
    for (var i = 0; i < spec.opponents; i++) {
      if (i < lvl.needPos - 1) {
        sp.add(avg * (1.03 + rr.nextDouble() * 0.05));
      } else {
        sp.add(avg * math.min(0.972, 0.9 + d * 0.006 + rr.nextDouble() * 0.03));
      }
    }
    lvl = lvl.withGoal(oppSpeed: sp);
    // Race the full field with the autopilot; ease the rivals until the
    // required place is reachable (bumps and items change the pace).
    for (var k = 0; k < 8; k++) {
      final r = RoadSim(lvl);
      runBot(r, roadBot, 60 * 60 * 6);
      if (r.won) break;
      lvl = lvl.withGoal(oppSpeed: [for (var i = 0; i < sp.length; i++) i < lvl.needPos - 1 ? sp[i] : lvl.oppSpeed[i] * 0.965]);
    }
  } else if (spec.goal == RGoal.drift) {
    final probe = RoadSim(lvl.withGoal(target: 1 << 30))..probe = true;
    runBot(probe, roadBot, 60 * 60 * 6);
    lvl = lvl.withGoal(target: math.max(1, (probe.driftPts * (0.55 + 0.035 * d)).floor()));
  }
  return lvl;
}

class RoadSim extends ArcadeSim {
  final RoadLevel level;
  RoadSpec get spec => level.spec;
  double dist = 0;
  double x = 500;
  double speed = 0;
  double vx = 0;
  double fuel = 100;
  int boost = 0, spin = 0, fuelOut = 0;
  int coins = 0, nearMiss = 0, gates = 0, deliveries = 0, copsCrashed = 0, overtakes = 0;
  double driftPts = 0;
  int driftCombo = 0;
  bool drifting = false;
  double finishAt;
  int finalPos = 0;
  int nextRow = 0;
  double nextGate = 1800, nextDepot = 9000, nextCop = 2500;
  List<RObj> objs = [];
  List<RObj> opps = [];
  int lastEvent = 0; // 1 coin, 2 crash, 3 near miss, 4 gate, 5 boost, 6 delivery, 7 miss

  /// Probe runs (calibration) never fail the race / drift goal.
  bool probe = false;

  // autopilot memory
  int botLane = -2;
  int botNext = 0;
  int botBrake = 0;

  RoadSim(this.level)
      : finishAt = level.courseLen,
        super(level.meta) {
    x = laneX(0, spec.lanes ~/ 2);
    for (var i = 0; i < level.oppSpeed.length; i++) {
      opps.add(RObj(kOpp, level.oppStart[i], 0, v: 0, lane: i % spec.lanes, look: i));
      opps.last.x = laneX(opps.last.d, opps.last.lane);
    }
  }

  RoadSim._(this.level, RoadSim o)
      : finishAt = o.finishAt,
        super(o.meta) {
    dist = o.dist;
    x = o.x;
    speed = o.speed;
    vx = o.vx;
    fuel = o.fuel;
    boost = o.boost;
    spin = o.spin;
    fuelOut = o.fuelOut;
    coins = o.coins;
    nearMiss = o.nearMiss;
    gates = o.gates;
    deliveries = o.deliveries;
    copsCrashed = o.copsCrashed;
    overtakes = o.overtakes;
    driftPts = o.driftPts;
    driftCombo = o.driftCombo;
    nextRow = o.nextRow;
    nextGate = o.nextGate;
    nextDepot = o.nextDepot;
    nextCop = o.nextCop;
    objs = [for (final b in o.objs) b.clone()];
    opps = [for (final b in o.opps) b.clone()];
    ticks = o.ticks;
    score = o.score;
    lives = o.lives;
    revives = o.revives;
    shield = o.shield;
    slow = o.slow;
    probe = o.probe;
  }

  RoadSim copy() => RoadSim._(level, this);

  double center(double d) {
    if (level.amp <= 0) return 500;
    return 500 + level.amp * (0.62 * math.sin(d / 2300 + level.ph1) + 0.38 * math.sin(d / 1050 + level.ph2));
  }

  double laneX(double d, int lane) => center(d) - level.halfW + spec.laneW * (lane + 0.5);

  int laneOf(double d, double px) => ((px - (center(d) - level.halfW)) / spec.laneW).floor().clamp(0, spec.lanes - 1);

  bool get offRoad => (x - center(dist)).abs() > level.halfW - 22;

  double get progressDist => dist;

  double get _density => level.meta.goal ? level.density : math.min(0.66, level.density * 0.8 + dist / 400000);

  void _spawnRows() {
    while (nextRow * level.rowGap < dist + kSpawnAhead) {
      final k = nextRow++;
      if (k < 2) continue;
      final rd = k * level.rowGap;
      final rr = SeededRandom(mixSeed([level.meta.seed, k, 31]));
      final fw = [for (var l = 0; l < spec.lanes; l++) if (level.laneSpeed[l] >= 0) l];
      final rockRow = level.blocks && spec.statics && rr.chance(spec.traffic > 0 ? 0.22 : 0.45 + level.meta.difficulty * 0.03);
      final taken = <int>{};
      final hazards = <int>[];
      // Lanes where moving traffic will be when the player arrives here.
      final eta = (rd - dist) / math.max(4.0, spec.maxSpeed);
      final busy = <int>{};
      for (final o in objs) {
        if (o.alive && o.kind == kCar && (o.d + o.v * eta - rd).abs() < 420) busy.add(o.lane);
      }
      final nearGate = spec.goal == RGoal.gates && ((rd - 1800) % 1700 < 320 || (rd - 1800) % 1700 > 1700 - 320);
      for (var l = 0; l < spec.lanes; l++) {
        if (busy.contains(l) || nearGate) continue;
        if (rockRow) {
          if (rr.chance(0.5)) hazards.add(-l - 1);
        } else if (spec.traffic > 0 && rr.chance(level.laneSpeed[l] < 0 ? _density * 0.8 : _density)) {
          hazards.add(l);
        }
      }
      // Always leave free same-direction lanes (two when there are four or more).
      final need = fw.length >= 4 ? 2 : 1;
      bool blocked(int l) => busy.contains(l) || hazards.contains(l) || hazards.contains(-l - 1);
      while (fw.where((l) => !blocked(l)).length < need && hazards.isNotEmpty) {
        final inFw = hazards.where((h) => fw.contains(h >= 0 ? h : -h - 1)).toList();
        if (inFw.isEmpty) break;
        hazards.remove(inFw[rr.nextInt(inFw.length)]);
      }
      if (fw.where((l) => !blocked(l)).length < need) hazards.removeWhere((h) => h < 0);
      for (final h in hazards) {
        final l = h >= 0 ? h : -h - 1;
        taken.add(l);
        if (h >= 0) {
          objs.add(RObj(kCar, rd, laneX(rd, l), v: level.laneSpeed[l], lane: l, look: rr.nextInt(6)));
        } else {
          objs.add(RObj(kRock, rd, laneX(rd, l), lane: l, look: rr.nextInt(3)));
        }
      }
      taken.addAll(busy);
      final freeLanes = [for (var l = 0; l < spec.lanes; l++) if (!taken.contains(l)) l];
      if (freeLanes.isEmpty) continue;
      final pl = freeLanes[rr.nextInt(freeLanes.length)];
      final pd = rd + level.rowGap / 2;
      if (spec.fuel && k % 9 == 4) {
        objs.add(RObj(kFuel, pd, laneX(pd, pl), lane: pl));
      } else if (spec.items && k % 3 == 1) {
        objs.add(RObj(kBox, pd, laneX(pd, pl), lane: pl));
      } else if (level.oil && k % 5 == 2) {
        objs.add(RObj(kOil, pd, laneX(pd, pl), lane: pl));
      } else if (rr.chance(0.45)) {
        objs.add(RObj(kCoin, pd, laneX(pd, pl), lane: pl));
      }
    }
    if (spec.goal == RGoal.gates) {
      while (nextGate < dist + kSpawnAhead) {
        final gi = (nextGate / 1700).round();
        final rr = SeededRandom(mixSeed([level.meta.seed, gi, 77]));
        final gd = nextGate;
        final lane = rr.nextInt(spec.lanes);
        // Gate centre between two lanes or on a lane; never inside a hazard row.
        final gx = laneX(gd, lane) + (rr.nextDouble() - 0.5) * spec.laneW * 0.5;
        objs.removeWhere((o) => o.hazard && (o.d - gd).abs() < 260 && (o.x - gx).abs() < level.gateHw + 120);
        objs.add(RObj(kGate, gd, gx, hw: level.gateHw));
        nextGate += 1700;
      }
    }
    if (spec.goal == RGoal.deliveries || spec.fuel) {
      while (nextDepot < dist + kSpawnAhead) {
        objs.removeWhere((o) => o.hazard && (o.d - nextDepot).abs() < 250);
        objs.add(RObj(kDepot, nextDepot, 500));
        nextDepot += 9000;
      }
    }
    if (spec.police && !level.meta.zen) {
      if (dist >= nextCop) {
        objs.add(RObj(kCop, dist - 520, x, v: speed));
        nextCop = dist + math.max(2600.0, 6200 - level.meta.difficulty * 380.0);
      }
    }
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    _spawnRows();
    // --- steering
    final rate = spec.steer * (level.rain ? 0.8 : 1) * (spin > 0 ? 0.3 : 1);
    var tx = x;
    var steering = false;
    if (input.down && input.x >= 0) {
      tx = input.x;
      steering = (tx - x).abs() > 4;
    }
    if (input.dirX != 0) {
      tx = x + input.dirX * 1000;
      steering = true;
    }
    final want = moveToward(x, tx, rate) - x;
    vx = level.rain ? vx * 0.82 + want * 0.18 : want;
    x += vx;
    if (spec.current) x += math.sin(dist / 1400 + level.ph2) * 1.1;
    x = clampD(x, 45, 955);
    // --- speed
    if (spec.fuel && !level.meta.zen) {
      fuel -= speed * 0.0016 * (1 + level.meta.difficulty * 0.03);
      if (fuel <= 0) {
        fuel = 0;
        fuelOut++;
        if (fuelOut > 90) {
          fuelOut = 0;
          lastEvent = 2;
          hit();
          fuel = 45;
        }
      } else {
        fuelOut = 0;
      }
    }
    final braking = input.dirY > 0 || (input.down && input.y >= kBrakeY);
    final top = spec.maxSpeed *
        (braking ? 0.4 : 1) *
        (offRoad ? 0.45 : 1) *
        (boost > 0 ? 1.45 : 1) *
        (spin > 0 ? 0.45 : 1) *
        (fuel <= 0 ? 0.05 : 1);
    speed += (top - speed) * (top > speed ? 0.014 : (braking ? 0.05 : 0.06));
    dist += speed;
    if (boost > 0) boost--;
    if (spin > 0) spin--;
    // --- drift
    drifting = spec.goal == RGoal.drift && steering && speed > spec.maxSpeed * 0.6 && vx.abs() > rate * 0.5;
    if (drifting) {
      driftCombo++;
      final g = speed * vx.abs() * 0.02 * (1 + math.min(driftCombo, 240) / 120);
      driftPts += g;
    } else {
      if (driftCombo > 30) score += driftCombo ~/ 3;
      driftCombo = 0;
    }
    // --- objects
    final px = x;
    for (final o in objs) {
      if (!o.alive) continue;
      switch (o.kind) {
        case kCar:
          o.d += o.v;
          o.x = laneX(o.d, o.lane);
        case kCop:
          final fast = speed >= spec.maxSpeed * 0.93;
          o.v = fast ? speed - 0.35 : spec.maxSpeed * 1.02;
          o.d += o.v;
          o.x = moveToward(o.x, px, spec.steer * 0.5);
          for (final c in objs) {
            if (c.alive && (c.kind == kCar || c.kind == kRock) && (c.d - o.d).abs() < 160 && (c.x - o.x).abs() < 80) {
              o.alive = false;
              copsCrashed++;
              score += 100;
              break;
            }
          }
          if (o.d < dist - 1100) o.alive = false;
        default:
          if (o.lane >= 0 && o.kind != kCar) o.x = laneX(o.d, o.lane);
      }
    }
    for (final o in opps) {
      final i = o.look;
      final vmax = level.oppSpeed[i];
      o.v += (vmax - o.v) * 0.014;
      o.d += o.v;
      final weave = math.sin(o.d / 900 + i * 1.7) * spec.laneW * 0.35;
      o.x = laneX(o.d, o.lane) + weave;
      final dd = o.d - dist;
      if (dd.abs() < 150 && (o.x - x).abs() < 80) {
        speed *= 0.985;
        x += x < o.x ? -2 : 2;
      }
      if (!o.passed && o.d < dist) {
        o.passed = true;
        overtakes++;
        score += 40;
      } else if (o.passed && o.d > dist) {
        o.passed = false;
      }
    }
    _collide();
    objs.removeWhere((o) => !o.alive || o.d < dist - 700 || (o.kind == kCar && o.d > dist + 3000));
    // --- goals
    if (ticks % 6 == 0) score += (speed / 3).round();
    if (level.meta.goal && !probe) {
      switch (spec.goal) {
        case RGoal.distance:
        case RGoal.escape:
          if (dist >= level.target) win();
        case RGoal.gates:
          if (gates >= level.target) win();
        case RGoal.deliveries:
          if (deliveries >= level.target) win();
        case RGoal.race:
          if (dist >= finishAt) {
            finalPos = position;
            finalPos <= level.needPos ? win() : _fail();
          }
        case RGoal.drift:
          if (dist >= finishAt) {
            driftPts >= level.target ? win() : _fail();
          }
      }
    } else if (probe && level.courseLen > 0 && dist >= level.courseLen) {
      win();
    }
  }

  int get position => 1 + opps.where((o) => o.d > dist).length;

  void _fail() {
    shield = 0;
    lives = 1;
    hit();
  }

  @override
  void revive() {
    super.revive();
    if (spec.goal == RGoal.race || spec.goal == RGoal.drift) {
      finishAt = dist + 5000;
    }
  }

  void _collide() {
    for (final o in objs) {
      if (!o.alive) continue;
      final dd = o.d - dist;
      final dx = (o.x - x).abs();
      switch (o.kind) {
        case kCar:
        case kRock:
        case kCop:
          final len = o.kind == kRock ? 120 : 170;
          if (dd.abs() < len && dx < (o.kind == kRock ? 90 : 84)) {
            if (shield > 0) {
              if (o.kind != kCop) {
                o.alive = false;
                score += 20;
              }
              continue;
            }
            o.alive = false;
            speed *= 0.25;
            lastEvent = 2;
            hit();
          } else if (o.kind == kCar && !o.passed && dd < -len) {
            o.passed = true;
            if (dx < spec.laneW * 1.15) {
              nearMiss++;
              score += 30;
              if (lastEvent == 0) lastEvent = 3;
            }
          }
        case kCoin:
        case kFuel:
        case kBox:
        case kOil:
          if (dd.abs() < 90 && dx < 80) {
            o.alive = false;
            if (o.kind == kCoin) {
              coins++;
              score += 10;
              lastEvent = 1;
            } else if (o.kind == kFuel) {
              fuel = math.min(100, fuel + 40);
              lastEvent = 1;
            } else if (o.kind == kBox) {
              boost = 150;
              lastEvent = 5;
            } else {
              spin = 70;
              lastEvent = 2;
            }
          }
        case kGate:
          if (!o.passed && dd < 0) {
            o.passed = true;
            if ((o.x - x).abs() <= o.hw - 30) {
              gates++;
              score += 50;
              lastEvent = 4;
            } else {
              lastEvent = 7;
              if (!level.meta.zen) hit();
            }
          }
        case kDepot:
          if (!o.passed && dd < 0) {
            o.passed = true;
            deliveries++;
            fuel = 100;
            score += 200;
            lastEvent = 6;
          }
      }
    }
  }

  @override
  void hit() {
    if (meta.zen) {
      speed *= 0.5;
      return;
    }
    super.hit();
  }

  /// Booster: nitro (plus the standard short shield).
  @override
  bool useBooster() {
    if (over) return false;
    boost = 240;
    shield = 240;
    return true;
  }

  @override
  double get progress {
    switch (spec.goal) {
      case RGoal.race:
      case RGoal.drift:
        return level.courseLen == 0 ? 0 : (dist / finishAt).clamp(0.0, 1.0);
      default:
        if (level.target == 0) return 0;
        final v = switch (spec.goal) { RGoal.gates => gates, RGoal.deliveries => deliveries, _ => dist };
        return (v / level.target).clamp(0.0, 1.0).toDouble();
    }
  }

  @override
  String get goalText {
    final m = (dist / 10).floor();
    if (!level.meta.goal) return '$m m';
    return switch (spec.goal) {
      RGoal.distance || RGoal.escape => '$m/${level.target ~/ 10} m',
      RGoal.race => '#$position/${opps.length + 1}',
      RGoal.drift => '${driftPts.floor()}/${level.target}',
      RGoal.gates => '$gates/${level.target}',
      RGoal.deliveries => '$deliveries/${level.target}',
    };
  }

  @override
  Map<String, int> get stats => {
        'distance_m': (dist / 10).floor(),
        'coins': coins,
        'near_misses': nearMiss,
        'gates': gates,
        'deliveries': deliveries,
        'cops_crashed': copsCrashed,
        'overtakes': overtakes,
        'drift_points': driftPts.floor(),
      };

  @override
  int get stars {
    if (!won) return 0;
    if (spec.goal == RGoal.race) return (4 - finalPos).clamp(1, 3);
    return lifeStars(this, 3);
  }
}

/// Autopilot: tries "follow lane L" for every lane on a copy of the
/// simulation and keeps the safest / most rewarding one.
ArcadeInput roadBot(ArcadeSim sim) {
  final s = sim as RoadSim;
  if (s.botLane < -1) s.botLane = s.laneOf(s.dist, s.x);
  if (s.ticks >= s.botNext) {
    s.botNext = s.ticks + 6;
    var best = -1e18;
    var bestL = s.botLane;
    var bestB = false;
    for (final brake in const [false, true]) {
      if (brake && best > -1e8) break;
      for (var l = s.spec.goal == RGoal.gates ? -1 : 0; l < s.spec.lanes; l++) {
        final v = _evalLane(s, l, 66, brake);
        final vv = v - (l < 0 || s.botLane < 0 ? 0 : (l - s.botLane).abs() * 3.0);
        if (vv > best) {
          best = vv;
          bestL = l;
          bestB = brake;
        }
      }
    }
    s.botLane = bestL;
    s.botBrake = bestB ? s.ticks + 30 : 0;
  }
  final br = s.ticks < s.botBrake;
  return ArcadeInput(down: true, x: _botX(s, s.botLane).roundToDouble(), y: br ? 1500 : 900);
}

/// Lane centre a little ahead, or (lane -1) the next gate's centre.
double _botX(RoadSim s, int lane) {
  if (lane < 0) {
    RObj? g;
    for (final o in s.objs) {
      if (o.kind == kGate && !o.passed && (g == null || o.d < g.d)) g = o;
    }
    if (g != null) return g.x;
    lane = s.laneOf(s.dist, s.x);
  }
  return s.laneX(s.dist + 260, lane);
}

double _evalLane(RoadSim s, int lane, int horizon, bool brake) {
  final c = s.copy();
  final lives0 = c.lives;
  final score0 = c.score;
  for (var t = 0; t < horizon; t++) {
    c.tick(ArcadeInput(down: true, x: _botX(c, lane).roundToDouble(), y: brake && t < 30 ? 1500 : 900));
    if (c.lives < lives0 || (c.over && !c.won)) return -1e9 + t * 1000.0;
    if (c.won) return 1e9;
  }
  var v = (c.dist - s.dist) * 1.0 + (c.score - score0) * 6.0;
  if (c.spec.fuel && c.fuel < 45) v += (c.fuel - s.fuel) * 40;
  if (c.spin > 0) v -= 400;
  if (c.offRoad) v -= 300;
  if (c.spec.goal == RGoal.drift) v += (c.driftPts - s.driftPts) * 4;
  // Look further: is there a hazard right ahead in that lane?
  for (final o in c.objs) {
    if (!o.alive || !o.hazard) continue;
    final dd = o.d - c.dist;
    if (dd > 0 && dd < 520 && (o.x - (lane < 0 ? c.x : c.laneX(o.d, lane))).abs() < c.spec.laneW * 0.75) {
      final rel = c.speed - o.v;
      if (rel > 0) v -= 2000 * (1 - dd / 520);
    }
  }
  return v;
}
