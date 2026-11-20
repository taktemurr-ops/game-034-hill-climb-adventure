import '../core/arcade.dart';
import '../core/level_plan.dart';
import '../core/missions.dart';
import '../core/stats.dart';
import 'park_engine.dart';

class ParkRules extends ArcadeRules<ParkLevel> {
  final String id;
  final List<GameStat> stats;
  final List<MissionTemplate> missions;

  ParkRules(this.id, this.stats, this.missions);

  @override
  String get gameId => id;

  @override
  List<String> get optionalMechanics => const ['traffic', 'tight', 'cones', 'long', 'timer'];

  @override
  List<GameStat> get gameStats => stats;

  @override
  List<MissionTemplate> get missionTemplates => missions;

  @override
  ParkLevel generate(LevelSpec s) => generateParkLevel(s);

  @override
  ArcadeMeta metaOf(ParkLevel l) => l.meta;

  @override
  ArcadeSim createSim(ParkLevel l) => ParkSim(l);

  @override
  ArcadeInput bot(ArcadeSim sim) => parkBot(sim);
}
