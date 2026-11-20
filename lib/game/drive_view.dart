import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import '../app/arcade_stage.dart';
import '../app/play_kit.dart';
import '../app/services/audio.dart';
import '../core/arcade.dart';
import 'hill_engine.dart';
import 'park_engine.dart';
import 'road_engine.dart';

/// Colours of a driving game.
class DriveTheme {
  final Color ground, road, line, accent, sky;
  const DriveTheme(this.ground, this.road, this.line, this.accent, {this.sky = const Color(0xFF8ECAE6)});
}

const _carColors = [
  Color(0xFFE63946),
  Color(0xFF457B9D),
  Color(0xFF2A9D8F),
  Color(0xFFF4A261),
  Color(0xFF8338EC),
  Color(0xFFADB5BD),
];

void _hud(Canvas c, String left, String mid, String right, ArcadeSim s) {
  c.drawRect(const Rect.fromLTWH(0, 0, kWorldW, 120), Paint()..color = Colors.black45);
  paintText(c, left, const Offset(190, 60), 42, Colors.white);
  paintText(c, mid, const Offset(530, 60), 42, const Color(0xFFFFD60A));
  paintText(c, right, const Offset(840, 60), 42, Colors.white);
  for (var i = 0; i < s.lives.clamp(0, 5); i++) {
    c.drawCircle(Offset(40 + i * 36.0, 150), 13, Paint()..color = const Color(0xFFEF476F));
  }
  if (s.shield > 0) {
    paintText(c, '🛡', const Offset(960, 150), 36, Colors.white);
  }
}

/// Top-down car (pointing up) centred on the origin.
void _carShape(Canvas c, double w, double h, Color body, {bool police = false, double t = 0, bool open = false}) {
  final r = Rect.fromCenter(center: Offset.zero, width: w, height: h);
  c.drawRRect(RRect.fromRectAndRadius(r.shift(const Offset(6, 8)), Radius.circular(w * 0.3)), Paint()..color = Colors.black26);
  for (final sx in [-1.0, 1.0]) {
    for (final sy in [-1.0, 1.0]) {
      c.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(sx * w * 0.48, sy * h * 0.3), width: w * 0.18, height: h * 0.2), const Radius.circular(4)),
          Paint()..color = const Color(0xFF212529));
    }
  }
  c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(w * 0.3)), Paint()..color = body);
  if (open) {
    c.drawCircle(Offset(0, h * 0.05), w * 0.28, Paint()..color = Colors.white);
    c.drawCircle(Offset(0, h * 0.05), w * 0.18, Paint()..color = const Color(0xFF212529));
    return;
  }
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-w * 0.36, -h * 0.28, w * 0.72, h * 0.18), const Radius.circular(6)), Paint()..color = const Color(0xFFBDE0FE));
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-w * 0.34, h * 0.2, w * 0.68, h * 0.12), const Radius.circular(6)), Paint()..color = const Color(0xFF8FB8DE));
  if (police) {
    final on = (t * 6).floor().isEven;
    c.drawRect(Rect.fromLTWH(-w * 0.36, -h * 0.04, w * 0.36, h * 0.08), Paint()..color = on ? const Color(0xFFE63946) : const Color(0xFF6D0F17));
    c.drawRect(Rect.fromLTWH(0, -h * 0.04, w * 0.36, h * 0.08), Paint()..color = on ? const Color(0xFF0B1E5B) : const Color(0xFF1D4ED8));
  }
}

void paintRoad(Canvas c, ArcadeSim sim, ArcadePalette p, double t, bool tr, DriveTheme th) {
  final s = sim as RoadSim;
  final spec = s.spec;
  final boat = spec.vehicle == 'boat';
  c.drawRect(const Rect.fromLTWH(0, 0, kWorldW, kWorldH), Paint()..color = th.ground);
  // scenery dots (trees / reeds / sand) moving with the road
  final deco = Paint()..color = Color.lerp(th.ground, Colors.black, 0.18)!;
  for (var i = 0; i < 26; i++) {
    final dd = ((s.dist / 260).floor() + i) * 260.0;
    final y = kPlayerY - (dd - s.dist);
    final side = (i * 7919) % 2 == 0 ? -1 : 1;
    final x = s.center(dd) + side * (s.level.halfW + 60 + (i * 37) % 120);
    c.drawCircle(Offset(x, y), 26 + (i % 3) * 8.0, deco);
  }
  // road / river surface
  final path = Path();
  final left = <Offset>[], right = <Offset>[];
  for (var y = -40.0; y <= kWorldH + 40; y += 40) {
    final d = s.dist + (kPlayerY - y);
    final cx = s.center(d);
    left.add(Offset(cx - s.level.halfW, y));
    right.add(Offset(cx + s.level.halfW, y));
  }
  path.addPolygon([...left, ...right.reversed], true);
  c.drawPath(path, Paint()..color = th.road);
  final edge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = boat ? 14 : 10
    ..color = boat ? const Color(0xFFE9C46A) : th.line;
  c.drawPoints(PointMode.polygon, left, edge);
  c.drawPoints(PointMode.polygon, right, edge);
  // lane marks / waves
  final mark = Paint()
    ..color = boat ? Colors.white24 : th.line.withValues(alpha: 0.85)
    ..strokeWidth = 7;
  for (var y = -40.0; y <= kWorldH; y += 40) {
    final d = s.dist + (kPlayerY - y);
    if ((d / 160).floor().isOdd) continue;
    final d2 = d - 40;
    for (var l = 1; l < spec.lanes; l++) {
      final x1 = s.center(d) - s.level.halfW + l * spec.laneW;
      final x2 = s.center(d2) - s.level.halfW + l * spec.laneW;
      if (boat) {
        c.drawLine(Offset(x1 - 18, y), Offset(x1 + 18, y + 6), mark);
      } else {
        c.drawLine(Offset(x1, y), Offset(x2, y + 40), mark);
      }
    }
  }
  // finish line for races
  if (s.level.courseLen > 0) {
    final y = kPlayerY - (s.finishAt - s.dist);
    if (y > -60 && y < kWorldH) {
      final cx = s.center(s.finishAt);
      for (var k = 0; k < 16; k++) {
        for (var r = 0; r < 2; r++) {
          final w = s.level.halfW * 2 / 16;
          c.drawRect(Rect.fromLTWH(cx - s.level.halfW + k * w, y + r * w, w, w), Paint()..color = (k + r).isEven ? Colors.white : Colors.black);
        }
      }
    }
  }
  // objects
  for (final o in s.objs) {
    if (!o.alive) continue;
    final y = kPlayerY - (o.d - s.dist);
    if (y < -200 || y > kWorldH + 200) continue;
    c.save();
    c.translate(o.x, y);
    switch (o.kind) {
      case kCar:
        if (boat) {
          _boatShape(c, 70, 150, _carColors[o.look % _carColors.length]);
        } else {
          if (o.v < 0) c.rotate(math.pi);
          _carShape(c, 84, 170, _carColors[o.look % _carColors.length]);
        }
      case kCop:
        _carShape(c, 86, 172, Colors.white, police: true, t: t);
      case kRock:
        if (boat) {
          c.drawOval(const Rect.fromLTWH(-60, -40, 120, 80), Paint()..color = const Color(0xFF6C757D));
          c.drawOval(const Rect.fromLTWH(-40, -30, 60, 40), Paint()..color = const Color(0xFFADB5BD));
        } else if (spec.vehicle == 'kart' || spec.vehicle == 'drift') {
          for (final dx in [-40.0, 0.0, 40.0]) {
            c.drawCircle(Offset(dx, 0), 24, Paint()..color = const Color(0xFF212529));
            c.drawCircle(Offset(dx, 0), 10, Paint()..color = const Color(0xFF495057));
          }
        } else {
          final r = const Rect.fromLTWH(-80, -26, 160, 52);
          c.drawRect(r, Paint()..color = Colors.white);
          for (var k = 0; k < 4; k++) {
            c.drawRect(Rect.fromLTWH(-80 + k * 40.0, -26, 20, 52), Paint()..color = const Color(0xFFE63946));
          }
        }
      case kCoin:
        c.drawCircle(Offset.zero, 26, Paint()..color = const Color(0xFFFFD60A));
        c.drawCircle(Offset.zero, 16, Paint()..color = const Color(0xFFFFB703));
      case kFuel:
        c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-26, -32, 52, 64), const Radius.circular(8)), Paint()..color = const Color(0xFFD62828));
        paintText(c, '⛽', Offset.zero, 32, Colors.white);
      case kBox:
        final a = p.reducedMotion ? 0.0 : t * 2;
        c.rotate(a);
        c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-34, -34, 68, 68), const Radius.circular(10)),
            Paint()..color = HSVColor.fromAHSV(1, (t * 120) % 360, 0.7, 1).toColor());
        c.rotate(-a);
        paintText(c, '?', Offset.zero, 46, Colors.white);
      case kOil:
        c.drawOval(const Rect.fromLTWH(-60, -34, 120, 68), Paint()..color = const Color(0xDD111111));
      case kGate:
        final ok = o.passed;
        final col = ok ? const Color(0xFF52B788) : const Color(0xFFFB8500);
        c.drawLine(Offset(-o.hw, 0), Offset(o.hw, 0), Paint()
          ..color = col.withValues(alpha: 0.6)
          ..strokeWidth = 6);
        for (final sx in [-1.0, 1.0]) {
          c.drawCircle(Offset(sx * o.hw, 0), 26, Paint()..color = col);
          c.drawCircle(Offset(sx * o.hw, -6), 10, Paint()..color = Colors.white);
        }
      case kDepot:
        c.translate(-o.x, 0);
        final cx = s.center(o.d);
        c.drawRect(Rect.fromLTWH(cx - s.level.halfW, -40, s.level.halfW * 2, 80), Paint()..color = const Color(0xCC2A9D8F));
        paintText(c, tr ? 'TESLİMAT' : 'DELIVERY', Offset(cx, 0), 44, Colors.white);
    }
    c.restore();
  }
  for (final o in s.opps) {
    final y = kPlayerY - (o.d - s.dist);
    if (y < -200 || y > kWorldH + 200) continue;
    c.save();
    c.translate(o.x, y);
    if (boat) {
      _boatShape(c, 70, 150, _carColors[o.look % _carColors.length]);
    } else {
      _carShape(c, 72, 120, _carColors[o.look % _carColors.length], open: spec.vehicle == 'kart');
    }
    c.restore();
  }
  // player
  c.save();
  c.translate(s.x, kPlayerY);
  c.rotate(clampD(s.vx * (s.drifting ? 0.06 : 0.025), -0.5, 0.5));
  if (s.boost > 0 && !p.reducedMotion) {
    final fl = 30 + math.sin(t * 40) * 10;
    c.drawPath(
        Path()
          ..moveTo(-22, 80)
          ..lineTo(0, 80 + fl * 2)
          ..lineTo(22, 80)
          ..close(),
        Paint()..color = const Color(0xFFFB8500));
  }
  if (s.drifting && !p.reducedMotion) {
    for (var k = 0; k < 4; k++) {
      c.drawCircle(Offset(-30 + k * 20.0, 100 + k * 12.0), 16 + k * 4.0, Paint()..color = Colors.white.withValues(alpha: 0.25));
    }
  }
  switch (spec.vehicle) {
    case 'boat':
      c.drawPath(
          Path()
            ..moveTo(-34, 70)
            ..lineTo(0, 140 + s.speed * 4)
            ..lineTo(34, 70),
          Paint()..color = Colors.white30);
      _boatShape(c, 78, 160, th.accent);
    case 'truck':
      c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-46, -10, 92, 200), const Radius.circular(8)), Paint()..color = const Color(0xFFE9ECEF));
      c.translate(0, -60);
      _carShape(c, 92, 110, th.accent);
    case 'kart':
      _carShape(c, 76, 124, th.accent, open: true);
    default:
      _carShape(c, 86, 172, th.accent);
  }
  if (s.shield > 0) {
    c.drawCircle(Offset.zero, 110, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = const Color(0xAA8ECAE6));
  }
  c.restore();
  if (s.level.night) {
    c.drawRect(const Rect.fromLTWH(0, 0, kWorldW, kWorldH), Paint()..color = const Color(0x88000814));
    c.drawPath(
        Path()
          ..moveTo(s.x - 30, kPlayerY - 80)
          ..lineTo(s.x - 260, kPlayerY - 760)
          ..lineTo(s.x + 260, kPlayerY - 760)
          ..lineTo(s.x + 30, kPlayerY - 80)
          ..close(),
        Paint()..color = const Color(0x33FFF3B0));
  }
  if (s.level.rain && !p.reducedMotion) {
    final rain = Paint()
      ..color = Colors.white24
      ..strokeWidth = 3;
    for (var i = 0; i < 60; i++) {
      final x = (i * 173.0 + t * 90) % kWorldW, y = (i * 311.0 + t * 1400) % kWorldH;
      c.drawLine(Offset(x, y), Offset(x - 10, y + 36), rain);
    }
  }
  // brake strip
  c.drawRect(const Rect.fromLTWH(0, kBrakeY, kWorldW, kWorldH - kBrakeY), Paint()..color = Colors.black26);
  paintText(c, tr ? '▼ FREN (parmağını burada tut)' : '▼ BRAKE (hold here)', const Offset(500, 1530), 32, Colors.white54);
  // HUD
  final kmh = (s.speed * 14).round();
  final mid = switch (spec.goal) {
    RGoal.race => s.goalText,
    RGoal.drift => s.driftCombo > 20 ? 'DRIFT x${1 + s.driftCombo ~/ 60}' : '● ${s.coins}',
    _ => '● ${s.coins}',
  };
  _hud(c, s.goalText, mid, '$kmh km/h', s);
  if (spec.fuel) {
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(700, 135, 260, 28), const Radius.circular(14)), Paint()..color = Colors.black45);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(704, 139, 252 * s.fuel / 100, 20), const Radius.circular(10)),
        Paint()..color = s.fuel < 25 ? const Color(0xFFE63946) : const Color(0xFF52B788));
    paintText(c, '⛽', const Offset(675, 149), 28, Colors.white);
  }
}

void _boatShape(Canvas c, double w, double h, Color col) {
  c.drawPath(
      Path()
        ..moveTo(0, -h / 2)
        ..quadraticBezierTo(w / 2, -h * 0.2, w / 2, h * 0.35)
        ..lineTo(-w / 2, h * 0.35)
        ..quadraticBezierTo(-w / 2, -h * 0.2, 0, -h / 2)
        ..close(),
      Paint()..color = col);
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-w * 0.3, -h * 0.1, w * 0.6, h * 0.25), const Radius.circular(8)), Paint()..color = Colors.white70);
}

// ---------------------------------------------------------------- hill

void paintHill(Canvas c, ArcadeSim sim, ArcadePalette p, double t, bool tr, DriveTheme th) {
  final s = sim as HillSim;
  final camX = s.px - kCamX;
  final camY = s.ground ? s.py : s.h(s.px) * 0.4 + s.py * 0.6;
  double sy(double wy) => kGroundScreenY - (wy - camY);
  final sky = const Rect.fromLTWH(0, 0, kWorldW, kWorldH);
  c.drawRect(
      sky,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [th.sky, Color.lerp(th.sky, Colors.white, 0.5)!],
        ).createShader(sky));
  // parallax hills
  final far = Path()..moveTo(0, kWorldH);
  for (var x = 0.0; x <= kWorldW; x += 20) {
    final wx = camX * 0.3 + x;
    far.lineTo(x, 800 + math.sin(wx / 260) * 90 + math.sin(wx / 97) * 30);
  }
  far
    ..lineTo(kWorldW, kWorldH)
    ..close();
  c.drawPath(far, Paint()..color = Color.lerp(th.ground, th.sky, 0.55)!);
  // terrain
  final ground = Path()..moveTo(0, kWorldH);
  final top = <Offset>[];
  for (var x = 0.0; x <= kWorldW + 10; x += 10) {
    final o = Offset(x, sy(s.h(camX + x)));
    ground.lineTo(o.dx, o.dy);
    top.add(o);
  }
  ground
    ..lineTo(kWorldW, kWorldH)
    ..close();
  c.drawPath(ground, Paint()..color = th.ground);
  c.drawPoints(PointMode.polygon, top, Paint()
    ..color = th.road
    ..strokeWidth = 22);
  if (s.level.mud) {
    for (var x = 0.0; x <= kWorldW; x += 10) {
      final wx = camX + x;
      if ((wx ~/ 1600).isOdd) c.drawLine(Offset(x, sy(s.h(wx))), Offset(x, sy(s.h(wx)) + 26), Paint()
        ..color = const Color(0xFF6F4518)
        ..strokeWidth = 11);
    }
  }
  // objects
  final c0 = (camX / 100).floor() - 1, c1 = ((camX + kWorldW) / 100).floor() + 1;
  for (var k = c0; k <= c1; k++) {
    final o = s.objAt(k);
    if (o == null) continue;
    final x = o.x - camX, gy = sy(s.h(o.x));
    final taken = s.taken.contains(k);
    switch (o.kind) {
      case 0:
        if (!taken) {
          c.drawCircle(Offset(x, gy - 80), 22, Paint()..color = const Color(0xFFFFD60A));
          c.drawCircle(Offset(x, gy - 80), 13, Paint()..color = const Color(0xFFFFB703));
        }
      case 1:
        if (!taken) {
          c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - 26, gy - 90, 52, 64), const Radius.circular(8)), Paint()..color = const Color(0xFFD62828));
          paintText(c, '⛽', Offset(x, gy - 58), 30, Colors.white);
        }
      case 2:
        final h = taken ? 24.0 : 70.0;
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - 90, gy - h, 180, h), const Radius.circular(12)),
            Paint()..color = _carColors[k % _carColors.length]);
        if (!taken) c.drawRect(Rect.fromLTWH(x - 50, gy - 62, 100, 24), Paint()..color = const Color(0xFFBDE0FE));
      case 3:
        c.drawLine(Offset(x, gy), Offset(x, gy - 140), Paint()
          ..color = Colors.white
          ..strokeWidth = 6);
        c.drawRect(Rect.fromLTWH(x, gy - 140, 60, 36), Paint()..color = taken || o.x <= s.checkpoint ? const Color(0xFF52B788) : th.accent);
      case 4:
        if (!taken) c.drawOval(Rect.fromLTWH(x - 40, gy - 50, 80, 60), Paint()..color = const Color(0xFF6C757D));
    }
  }
  if (s.level.courseLen > 0 && s.spec.goal != HGoal.crush) {
    final fx = 200 + s.level.courseLen;
    final x = fx - camX;
    if (x > -100 && x < kWorldW + 100) {
      final gy = sy(s.h(fx));
      for (var r = 0; r < 6; r++) {
        for (var k = 0; k < 2; k++) {
          c.drawRect(Rect.fromLTWH(x + k * 24, gy - 200 + r * 24, 24, 24), Paint()..color = (r + k).isEven ? Colors.white : Colors.black);
        }
      }
    }
  }
  // vehicle
  c.save();
  c.translate(kCamX, sy(s.py));
  c.rotate(-s.ang);
  final body = Paint()..color = th.accent;
  final tyre = Paint()..color = const Color(0xFF212529);
  final hub = Paint()..color = const Color(0xFFADB5BD);
  final spin = s.px / 30;
  void wheel(double x, double y, double r) {
    c.drawCircle(Offset(x, y), r, tyre);
    c.drawCircle(Offset(x, y), r * 0.45, hub);
    c.drawLine(Offset(x, y), Offset(x + math.cos(spin) * r * 0.8, y + math.sin(spin) * r * 0.8), tyre..strokeWidth = 5);
  }
  switch (s.spec.vehicle) {
    case 'bike':
      wheel(-70, -36, 36);
      wheel(70, -36, 36);
      c.drawPath(
          Path()
            ..moveTo(-70, -40)
            ..lineTo(-10, -90)
            ..lineTo(70, -40)
            ..lineTo(20, -60)
            ..close(),
          body);
      c.drawCircle(const Offset(-6, -170), 22, Paint()..color = Colors.white);
      c.drawLine(const Offset(-10, -150), const Offset(-20, -96), Paint()
        ..color = const Color(0xFF212529)
        ..strokeWidth = 14);
      c.drawLine(const Offset(-14, -130), const Offset(50, -100), Paint()
        ..color = const Color(0xFF212529)
        ..strokeWidth = 10);
    case 'monster':
      wheel(-78, -58, 58);
      wheel(78, -58, 58);
      c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-110, -170, 220, 70), const Radius.circular(18)), body);
      c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-40, -215, 90, 50), const Radius.circular(10)), Paint()..color = const Color(0xFFBDE0FE));
    default:
      wheel(-62, -34, 34);
      wheel(62, -34, 34);
      c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-95, -110, 190, 60), const Radius.circular(16)), body);
      c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-30, -160, 80, 54), const Radius.circular(10)), Paint()..color = const Color(0xFFBDE0FE));
      c.drawCircle(const Offset(10, -140), 16, Paint()..color = const Color(0xFFFFD6A5));
  }
  if (s.shield > 0) {
    c.drawCircle(const Offset(0, -80), 140, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = const Color(0xAA8ECAE6));
  }
  c.restore();
  // pedals
  final gasOn = s.gas > 0, brakeOn = s.gas < 0;
  c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(30, 1420, 260, 150), const Radius.circular(26)), Paint()..color = brakeOn ? Colors.white38 : Colors.black26);
  c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(710, 1420, 260, 150), const Radius.circular(26)), Paint()..color = gasOn ? Colors.white38 : Colors.black26);
  paintText(c, tr ? 'FREN' : 'BRAKE', const Offset(160, 1495), 40, Colors.white);
  paintText(c, tr ? 'GAZ' : 'GAS', const Offset(840, 1495), 40, Colors.white);
  final mid = switch (s.spec.goal) { HGoal.crush => '💥 ${s.crushed}', _ => '● ${s.coins}' };
  _hud(c, s.goalText, mid, s.flips > 0 ? '↻ ${s.flips}' : '${(s.v.abs() * 12).round()} km/h', s);
  if (s.spec.fuel) {
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(700, 135, 260, 28), const Radius.circular(14)), Paint()..color = Colors.black45);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(704, 139, 252 * s.fuel / 100, 20), const Radius.circular(10)),
        Paint()..color = s.fuel < 25 ? const Color(0xFFE63946) : const Color(0xFF52B788));
    paintText(c, '⛽', const Offset(675, 149), 28, Colors.white);
  }
}

// ---------------------------------------------------------------- park

void paintPark(Canvas c, ArcadeSim sim, ArcadePalette p, double t, bool tr, DriveTheme th) {
  final s = sim as ParkSim;
  c.drawRect(const Rect.fromLTWH(0, 0, kWorldW, kWorldH), Paint()..color = th.ground);
  final area = Rect.fromLTWH(kPX0, kPY0, kPCols * kPCell, kPRows * kPCell);
  c.drawRect(area, Paint()..color = th.road);
  final grid = Paint()
    ..color = Colors.white10
    ..strokeWidth = 2;
  for (var i = 1; i < kPCols; i++) {
    c.drawLine(Offset(kPX0 + i * kPCell, kPY0), Offset(kPX0 + i * kPCell, kPY0 + kPRows * kPCell), grid);
  }
  for (var i = 1; i < kPRows; i++) {
    c.drawLine(Offset(kPX0, kPY0 + i * kPCell), Offset(kPX0 + kPCols * kPCell, kPY0 + i * kPCell), grid);
  }
  c.drawRect(area, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 10
    ..color = const Color(0xFFE9ECEF));
  // guide arrows along the route
  final guide = Paint()
    ..color = Colors.white24
    ..strokeWidth = 8
    ..strokeCap = StrokeCap.round;
  final path = s.course.path;
  for (var i = 0; i + 1 < path.length; i++) {
    final (x1, y1) = s.course.center(i);
    final (x2, y2) = s.course.center(i + 1);
    for (var k = 0; k < 3; k++) {
      final f = (k + 0.5) / 3;
      final x = x1 + (x2 - x1) * f, y = y1 + (y2 - y1) * f;
      c.drawLine(Offset(x - (x2 - x1) * 0.06, y - (y2 - y1) * 0.06), Offset(x + (x2 - x1) * 0.06, y + (y2 - y1) * 0.06), guide);
    }
  }
  // bay
  final (bx, by) = s.course.bay;
  final vertical = s.course.bayDir % 2 == 0;
  final bay = Rect.fromCenter(center: Offset(bx, by), width: vertical ? 110 : 170, height: vertical ? 170 : 110);
  final glow = s.parkedTicks > 0 ? const Color(0xFF52B788) : const Color(0xFFFFD60A);
  c.drawRect(bay, Paint()..color = glow.withValues(alpha: 0.18));
  c.drawRect(bay, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 8
    ..color = glow);
  paintText(c, 'P', Offset(bx, by), 70, glow.withValues(alpha: 0.6));
  // obstacles
  for (final o in s.course.obstacles) {
    final r = Rect.fromLTWH(o.x, o.y, o.w, o.h);
    switch (o.look) {
      case 0:
        c.save();
        c.translate(r.center.dx, r.center.dy);
        if (o.w > o.h) c.rotate(math.pi / 2);
        _carShape(c, kCarW, kCarL, _carColors[(o.x + o.y).round() % _carColors.length]);
        c.restore();
      case 1:
        c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(10)), Paint()..color = const Color(0xFF8D99AE));
        for (var k = 0.0; k < r.width; k += 40) {
          c.drawLine(Offset(r.left + k, r.top), Offset(r.left + k, r.bottom), Paint()
            ..color = const Color(0xFF6C757D)
            ..strokeWidth = 3);
        }
      default:
        c.drawPath(
            Path()
              ..moveTo(r.center.dx, r.top)
              ..lineTo(r.right, r.bottom)
              ..lineTo(r.left, r.bottom)
              ..close(),
            Paint()..color = const Color(0xFFFB8500));
        c.drawRect(Rect.fromLTWH(r.left + r.width * 0.25, r.center.dy, r.width * 0.5, 6), Paint()..color = Colors.white);
    }
  }
  final m = s.mover;
  if (m != null) {
    c.save();
    c.translate(m.cx, m.cy);
    if (m.w > m.h) c.rotate(math.pi / 2);
    _carShape(c, kCarW, kCarL, const Color(0xFF6A4C93));
    c.restore();
  }
  // player
  c.save();
  c.translate(s.x, s.y);
  c.rotate(s.th + math.pi / 2);
  _carShape(c, kCarW, kCarL, th.accent);
  if (s.reverse) {
    c.drawRect(const Rect.fromLTWH(-28, kCarL / 2 - 8, 16, 8), Paint()..color = Colors.white);
    c.drawRect(const Rect.fromLTWH(12, kCarL / 2 - 8, 16, 8), Paint()..color = Colors.white);
  }
  if (s.shield > 0) {
    c.drawCircle(Offset.zero, 90, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = const Color(0xAA8ECAE6));
  }
  c.restore();
  // gear button
  final g = Rect.fromLTWH(gearRect.x, gearRect.y, gearRect.w, gearRect.h);
  c.drawRRect(RRect.fromRectAndRadius(g, const Radius.circular(24)), Paint()..color = s.reverse ? const Color(0xFFE63946) : const Color(0xFF2A9D8F));
  paintText(c, s.reverse ? 'R' : 'D', g.center.translate(-40, 0), 64, Colors.white);
  paintText(c, tr ? 'vites' : 'gear', g.center.translate(40, 0), 30, Colors.white70);
  paintText(c, tr ? 'Gitmek istediğin yere dokunup basılı tut' : 'Hold where you want to drive', const Offset(610, 1525), 30, Colors.white60);
  final time = s.level.timer && s.meta.goal ? '⏱ ${math.max(0, s.secondsLeft)}' : '⏱ ${(s.ticks - s.stageStart) ~/ 60}';
  _hud(c, s.goalText, time, '${(s.v.abs() * 10).round()} km/h', s);
}

Sfx? roadSound(ArcadeSim sim) => switch ((sim as RoadSim).lastEvent) {
      1 => Sfx.coin,
      2 => Sfx.lose,
      3 => Sfx.tap,
      4 => Sfx.clear,
      5 => Sfx.combo,
      6 => Sfx.unlock,
      7 => Sfx.error,
      _ => null,
    };

Sfx? hillSound(ArcadeSim sim) => switch ((sim as HillSim).lastEvent) {
      1 => Sfx.coin,
      2 => Sfx.lose,
      3 => Sfx.combo,
      4 => Sfx.clear,
      5 => Sfx.unlock,
      6 => Sfx.place,
      _ => null,
    };

Sfx? parkSound(ArcadeSim sim) => switch ((sim as ParkSim).lastEvent) {
      1 => Sfx.tap,
      2 => Sfx.lose,
      3 => Sfx.win,
      _ => null,
    };
