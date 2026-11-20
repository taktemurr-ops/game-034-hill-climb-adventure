import 'package:flutter_test/flutter_test.dart';
import 'package:game_034_hill_climb_adventure/core/arcade.dart';
import 'package:game_034_hill_climb_adventure/core/level_plan.dart';
import 'package:game_034_hill_climb_adventure/game/hill_engine.dart';
import 'package:game_034_hill_climb_adventure/game/rules.dart';

void main() {
  final rules = HillClimbRules();
  final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: rules.optionalMechanics);

  test('gas (right half) drives forward, the vehicle stays on the terrain', () {
    final s = HillSim(rules.build(planner.spec(1)).puzzle);
    for (var i = 0; i < 120; i++) {
      s.tick(const ArcadeInput(down: true, x: 900, y: 1400));
    }
    expect(s.px, greaterThan(300));
    if (s.ground) expect(s.py, closeTo(s.h(s.px), 0.001));
  });

  test('terrain is deterministic and never steeper than climbable', () {
    final a = HillSim(rules.build(planner.spec(9000)).puzzle);
    final b = HillSim(rules.build(planner.spec(9000)).puzzle);
    for (var x = 0.0; x < 30000; x += 37) {
      expect(a.h(x), b.h(x));
      expect(a.slope(x).abs(), lessThan(0.75));
    }
  });

  test('landing upside down costs a life and respawns at the checkpoint', () {
    final s = HillSim(rules.build(planner.spec(1)).puzzle);
    s.ground = false;
    s.px = 900;
    s.py = s.h(900) + 5;
    s.vx = 1;
    s.vy = -2;
    s.ang = 3.0;
    final lives = s.lives;
    for (var i = 0; i < 20 && !s.ground; i++) {
      s.tick(ArcadeInput.idle);
    }
    expect(s.lives, lives - 1);
    expect(s.px, s.checkpoint);
  });

  test('turbo booster refuels and kicks the speed', () {
    final s = HillSim(rules.build(planner.spec(3)).puzzle);
    s.fuel = 5;
    expect(s.useBooster(), isTrue);
    expect(s.fuel, 100);
    expect(s.v, greaterThanOrEqualTo(9));
  });
}
