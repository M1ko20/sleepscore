-- Pevné číselníky: tagy a achievementy (patří do migrace, ne do seed.sql,
-- protože je potřebuje i produkce).

insert into public.tags (slug, label, emoji, sort) values
  ('alcohol',        'Alkohol',            '🍺', 10),
  ('late_coffee',    'Kafe po 15:00',      '☕', 20),
  ('evening_workout','Večerní trénink',    '🏋️', 30),
  ('phone_in_bed',   'Telefon v posteli',  '📱', 40),
  ('late_meal',      'Pozdní jídlo',       '🍕', 50),
  ('kid',            'Dítě',               '👶', 60),
  ('sick',           'Nemoc',              '🤒', 70);

insert into public.achievements (code, name, description, category, sort) values
  ('coma',              'Kóma',               '10 a víc hodin spánku',                          'sleep',      10),
  ('zombie',            'Zombie',             'méně než 5 hodin spánku',                        'sleep',      20),
  ('night_shift',       'Noční směna',        'usnutí po 3:00',                                 'sleep',      30),
  ('didnt_move',        'Ani se nehnul',      'celá noc bez jediného probuzení',                'sleep',      40),
  ('deep_diver',        'Hlubinář',           '2 a víc hodin hlubokého spánku',                 'sleep',      50),
  ('perfect_night',     'Dokonalá noc',       'sleep score 95 a víc',                           'sleep',      60),
  ('either_or',         'Buď, nebo',          'sleep score pod 30',                             'sleep',      70),
  ('swiss_watch',       'Švýcarské hodinky',  '14 dní usnutí v okně ±15 minut',                 'regularity', 110),
  ('double_life',       'Dvojí život',        'o víkendu usneš o 3+ hodiny později než v týdnu','regularity', 120),
  ('streak_7',          'Týden v kuse',       '7denní série',                                   'regularity', 130),
  ('streak_30',         'Měsíc v kuse',       '30denní série',                                  'regularity', 140),
  ('streak_100',        'Stovka',             '100denní série',                                 'regularity', 150),
  ('despite_it',        'Navzdory',           'tag alkohol a sleep score 85 a víc',             'tags',       210),
  ('beer_won',          'Pivo vyhrálo',       'tag alkohol a sleep score pod 50',               'tags',       220),
  ('first_soul',        'První duše',         'první vyhraný souboj',                           'challenges', 310),
  ('collector',         'Sběratel',           '10 získaných duší',                              'challenges', 320),
  ('undefeated',        'Neporazitelný',      '5 vyhraných soubojů v řadě',                     'challenges', 330),
  ('revenge',           'Odplata',            'porazit toho, kdo tě naposledy porazil',         'challenges', 340),
  ('by_a_hair',         'O chlup',            'výhra v souboji o méně než 1 bod průměru',       'challenges', 350),
  ('forgot_watch',      'Zapomněl hodinky',   'noc se skóre 0 ve výzvě',                        'challenges', 360),
  ('stolen_hour',       'Ukradená hodina',    'noc po přechodu na letní čas',                   'seasonal',   410),
  ('new_year_survivor', 'Novoroční přeživší', 'usnutí po 4:00 v noci na 1. ledna',              'seasonal',   420);
