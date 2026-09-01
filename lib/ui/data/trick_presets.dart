/// Common street tricks offered as one-tap chips on the setter's panel.
///
/// This is picker *content*, not a rule: the engine and the wire neither know
/// nor care that these names exist (ARCHITECTURE.md §3), free text stays the
/// canonical input, and tapping a preset only fills the field. Ordered roughly
/// easy → hard so the top of the row is where a beginner starts.
///
/// Every entry must survive `TRICK_SET`, whose `nameLen` is a uint8 — so a
/// name is at most 254 bytes once UTF-8 encoded (PROTOCOL.md §6).
const List<String> trickPresets = [
  'Ollie',
  'Nollie',
  'Fakie Ollie',
  'Shove-it',
  'Pop Shove-it',
  'FS Shove-it',
  'FS 180',
  'BS 180',
  'Kickflip',
  'Heelflip',
  'Fakie Kickflip',
  'Varial Kickflip',
  'Varial Heelflip',
  'BS Bigspin',
  'FS Bigspin',
  '360 Shove-it',
  'Hardflip',
  'Inward Heelflip',
  'Nollie Kickflip',
  'Nollie Heelflip',
  'Tre Flip',
  'Laser Flip',
  'Nollie Tre Flip',
];
