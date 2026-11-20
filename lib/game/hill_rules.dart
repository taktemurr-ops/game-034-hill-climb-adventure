import '../core/arcade.dart';
import '../core/level_plan.dart';
import '../core/missions.dart';
import '../core/stats.dart';
import 'hill_engine.dart';

/// Rules shared by every side-view driving game; each game passes its own
/// [HillSpec], stats and missions.
class HillRules extends ArcadeRules<HillLevel> {
  final HillSpec spec;
  final String id;
  final List<GameStat> stats;
  final List<MissionTemplate> missions;

  HillRules(this.spec, this.id, this.stats, this.missions);

  @override
  String get gameId => id;

  @override
  List<String> get optionalMechanics => spec.mechanics;

  @override
  List<GameStat> get gameStats => stats;

  @override
  List<MissionTemplate> get missionTemplates => missions;

  @override
  HillLevel generate(LevelSpec s) => generateHillLevel(s, spec);

  @override
  ArcadeMeta metaOf(HillLevel l) => l.meta;

  @override
  ArcadeSim createSim(HillLevel l) => HillSim(l);

  @override
  ArcadeInput bot(ArcadeSim sim) => hillBot(sim);

  @override
  int maxTicks(HillLevel l) => 60 * 60 * 8;
}
