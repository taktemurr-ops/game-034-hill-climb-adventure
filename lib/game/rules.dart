import '../core/arcade.dart';
import '../core/missions.dart';
import '../core/stats.dart';
import 'hill_rules.dart';
import 'hill_spec.dart';

class HillClimbRules extends HillRules {
  HillClimbRules()
      : super(hillSpec, 'game-034-hill-climb-adventure', const [
          GameStat('distance_m', 'Gidilen yol (m)', 'Distance (m)', scale: 5000),
          GameStat('coins', 'Jeton', 'Coins', scale: 200),
          GameStat('flips', 'Takla', 'Flips', scale: 20),
        ], const [
          MissionTemplate('distance_m', 'distance_m', [1666, 3333, 5000]),
          MissionTemplate('coins', 'coins', [66, 133, 200]),
        ]);
}

ArcadeRules createRules() => HillClimbRules();
