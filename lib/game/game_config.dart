import 'package:flutter/material.dart';

import '../app/arcade_stage.dart';
import '../app/game_api.dart';
import '../core/game_rules.dart';
import 'hill_engine.dart';
import 'drive_view.dart';
import 'rules.dart';

const _theme = DriveTheme(Color(0xFF6B4226), Color(0xFF6A994E), Color(0xFFFFFFFF), Color(0xFFE76F51));



final gameConfig = GameConfig(
  gameId: 'game-034-hill-climb-adventure',
  title: const ['Tepe Tırmanışı', 'Hill Climb Adventure', 'Hill Climb Adventure', 'Hill Climb Adventure', 'Hill Climb Adventure'],
  tagline: const ['Tırman, zıpla ve yakıtın bitmesin!', 'Climb, jump and never run out of fuel!', 'Climb, jump and never run out of fuel!', 'Climb, jump and never run out of fuel!', 'Climb, jump and never run out of fuel!'],
  seedColor: const Color(0xFFE76F51),
  icon: Icons.terrain,
  rules: HillClimbRules(),
  buildPlay: (ctx) => ArcadeStage(
    ctx: ctx,
    create: () => HillSim((ctx.generated as GeneratedLevel<HillLevel>).puzzle),
    paint: (c, s, p, t) => paintHill(c, s, p, t, ctx.lang == 'tr', _theme),
    sound: hillSound,
    boosterIcon: Icons.local_gas_station,
    boosterLabel: (l) => l == 'tr' ? 'Turbo + yakıt' : 'Turbo + fuel',
    howTo: const [
      'Sağ yarı gaz, sol yarı fren. Havadayken gaz geriye, fren öne yatırır. Tekerlekler üstüne in, yakıtı topla.',
      'Right half: gas, left half: brake. In the air gas tilts back, brake tilts forward. Land on your wheels and grab fuel.',
      'Right half: gas, left half: brake. In the air gas tilts back, brake tilts forward. Land on your wheels and grab fuel.',
      'Right half: gas, left half: brake. In the air gas tilts back, brake tilts forward. Land on your wheels and grab fuel.',
      'Right half: gas, left half: brake. In the air gas tilts back, brake tilts forward. Land on your wheels and grab fuel.',
    ],
  ),
  tutorial: const [
    TutorialStep(Icons.touch_app, [
      'Sağ yarı: gaz. Sol yarı: fren / geri. Klavye: → gaz, ← fren.',
      'Right half: gas. Left half: brake / reverse. Keyboard: → gas, ← brake.',
      'Rechts Gas, links Bremse.',
      'Derecha gas, izquierda freno.',
      'Droite : gaz, gauche : frein.',
    ]),
    TutorialStep(Icons.rotate_right, [
      'Havadayken gaz aracı geriye, fren öne yatırır. Tekerlekler üstüne in!',
      'In the air gas tilts back, brake tilts forward. Land on your wheels!',
      'In der Luft kippt Gas nach hinten, Bremse nach vorn.',
      'En el aire, gas inclina atrás y freno adelante.',
      'En l\'air, gaz bascule en arrière, frein en avant.',
    ]),
    TutorialStep(Icons.flag, [
      'Bayraklar kontrol noktasıdır; kaza yaparsan oradan devam edersin.',
      'Flags are checkpoints; after a crash you restart there.',
      'Flaggen sind Checkpoints.',
      'Las banderas son puntos de control.',
      'Les drapeaux sont des points de contrôle.',
    ]),
  ],
);
