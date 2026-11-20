import '../core/arcade.dart';
import '../core/level_plan.dart';
import '../core/missions.dart';
import '../core/stats.dart';
import 'road_engine.dart';

/// Rules shared by every top-down driving game; each game passes its own
/// [RoadSpec], stats and missions.
class RoadRules extends ArcadeRules<RoadLevel> {
  final RoadSpec spec;
  final String id;
  final List<GameStat> stats;
  final List<MissionTemplate> missions;

  RoadRules(this.spec, this.id, this.stats, this.missions);

  @override
  String get gameId => id;

  @override
  List<String> get optionalMechanics => spec.mechanics;

  @override
  List<GameStat> get gameStats => stats;

  @override
  List<MissionTemplate> get missionTemplates => missions;

  @override
  RoadLevel generate(LevelSpec s) => generateRoadLevel(s, spec);

  @override
  ArcadeMeta metaOf(RoadLevel l) => l.meta;

  @override
  ArcadeSim createSim(RoadLevel l) => RoadSim(l);

  @override
  ArcadeInput bot(ArcadeSim sim) => roadBot(sim);

  @override
  int maxTicks(RoadLevel l) => 60 * 60 * 8;
}
