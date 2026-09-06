/// Maps a NeoSync RetroArch emulator slug suffix (e.g. `finalburn-neo`,
/// `snes9x`, `mgba`) to the folder RetroArch sorts saves into (`core_name`),
/// plus the core-specific subfolder that the MAME/FBNeo family creates inside
/// it (`fbneo`, `mame`, ...).
///
/// Values come from the `corename` field of each libretro core's `.info` file
/// (see libretro/libretro-core-info) and the documented save directory of each
/// core. It is only used as a best-effort fallback when restoring a RetroArch
/// save whose cloud path carries a bare file name; the upload normally mirrors
/// the real on-disk sub-path, and the download mirrors that.
class RetroArchCoreFolder {
  final String folder;
  final String subfolder;

  const RetroArchCoreFolder(this.folder, [this.subfolder = '']);

  bool get hasSubfolder => subfolder.isNotEmpty;
}

const Map<String, RetroArchCoreFolder> retroArchCoreFolders = {
  'beetle-neopop': RetroArchCoreFolder('Beetle NeoPop'),
  'beetle-pce': RetroArchCoreFolder('Beetle PCE'),
  'beetle-pce-fast': RetroArchCoreFolder('Beetle PCE Fast'),
  'beetle-psx': RetroArchCoreFolder('Beetle PSX'),
  'beetle-psx-hw': RetroArchCoreFolder('Beetle PSX HW'),
  'beetle-saturn': RetroArchCoreFolder('Beetle Saturn'),
  'beetle-supergrafx': RetroArchCoreFolder('Beetle SuperGrafx'),
  'beetle-vb': RetroArchCoreFolder('Beetle VB'),
  'beetle-wonderswan': RetroArchCoreFolder('Beetle WonderSwan'),
  'bluemsx': RetroArchCoreFolder('blueMSX'),
  'bsnes': RetroArchCoreFolder('bsnes'),
  'desmume': RetroArchCoreFolder('DeSmuME'),
  'desmume-2015': RetroArchCoreFolder('DeSmuME 2015'),
  'doublecherrygb': RetroArchCoreFolder('DoubleCherryGB'),
  'fb-alpha-2012': RetroArchCoreFolder('FB Alpha 2012', 'fbalpha2012'),
  'fb-alpha-2012-cps-1': RetroArchCoreFolder(
    'FB Alpha 2012 CPS-1',
    'fbalpha2012_cps1',
  ),
  'fbneo': RetroArchCoreFolder('FinalBurn Neo', 'fbneo'),
  'fceumm': RetroArchCoreFolder('FCEUmm'),
  'finalburn-neo': RetroArchCoreFolder('FinalBurn Neo', 'fbneo'),
  'flycast': RetroArchCoreFolder('Flycast'),
  'fmsx': RetroArchCoreFolder('fMSX'),
  'fuse': RetroArchCoreFolder('Fuse'),
  'gambatte': RetroArchCoreFolder('Gambatte'),
  'gearboy': RetroArchCoreFolder('Gearboy'),
  'genesis-plus-gx': RetroArchCoreFolder('Genesis Plus GX'),
  'genesis-plus-gx-wide': RetroArchCoreFolder('Genesis Plus GX Wide'),
  'gpsp': RetroArchCoreFolder('gpSP'),
  'a5200': RetroArchCoreFolder('a5200'),
  'atari800': RetroArchCoreFolder('Atari800'),
  'beetle-pc-fx': RetroArchCoreFolder('Beetle PC-FX'),
  'geargrafx': RetroArchCoreFolder('Geargrafx'),
  'mame': RetroArchCoreFolder('MAME', 'mame'),
  'mame-2000': RetroArchCoreFolder('MAME 2000', 'mame2000'),
  'mame-2003-0.78': RetroArchCoreFolder('MAME 2003 (0.78)', 'mame2003'),
  'mame-2003-plus': RetroArchCoreFolder('MAME 2003-Plus', 'mame2003-plus'),
  'mame-2010': RetroArchCoreFolder('MAME 2010', 'mame2010'),
  'mame2003': RetroArchCoreFolder('MAME 2003 (0.78)', 'mame2003'),
  'noods': RetroArchCoreFolder('NooDS'),
  'prosystem': RetroArchCoreFolder('ProSystem'),
  'quicknes': RetroArchCoreFolder('QuickNES'),
  'supafaust': RetroArchCoreFolder('Beetle Supafaust'),
  'melonds': RetroArchCoreFolder('melonDS'),
  'melonds-ds': RetroArchCoreFolder('melonDS DS'),
  'mesen': RetroArchCoreFolder('Mesen'),
  'mesen-s': RetroArchCoreFolder('Mesen-S'),
  'mgba': RetroArchCoreFolder('mGBA'),
  'mupen64plus-next': RetroArchCoreFolder('Mupen64Plus-Next'),
  'neko-project-ii-kai': RetroArchCoreFolder('Neko Project II Kai'),
  'neocd': RetroArchCoreFolder('NeoCD'),
  'nestopia': RetroArchCoreFolder('Nestopia'),
  'opera': RetroArchCoreFolder('Opera'),
  'parallel-n64': RetroArchCoreFolder('ParaLLEl N64'),
  'pcsx-rearmed': RetroArchCoreFolder('PCSX-ReARMed'),
  'picodrive': RetroArchCoreFolder('PicoDrive'),
  'puae': RetroArchCoreFolder('PUAE'),
  'quasi88': RetroArchCoreFolder('QUASI88'),
  'sameboy': RetroArchCoreFolder('SameBoy'),
  'skyemu': RetroArchCoreFolder('SkyEmu'),
  'snes9x': RetroArchCoreFolder('Snes9x'),
  'snes9x-2005-plus': RetroArchCoreFolder('Snes9x 2005 Plus'),
  'snes9x-2010': RetroArchCoreFolder('Snes9x 2010'),
  'stella': RetroArchCoreFolder('Stella'),
  'swanstation': RetroArchCoreFolder('SwanStation'),
  'tgb-dual': RetroArchCoreFolder('TGB Dual'),
  'tic-80': RetroArchCoreFolder('TIC-80'),
  'vba-m': RetroArchCoreFolder('VBA-M'),
  'vba-next': RetroArchCoreFolder('VBA Next'),
  'virtual-jaguar': RetroArchCoreFolder('Virtual Jaguar'),
  'yabause': RetroArchCoreFolder('Yabause'),
};

/// Returns the on-disk RetroArch sub-path (core folder, plus the core's own
/// subfolder for MAME/FBNeo) for a `retroarch.<slug>` emulator slug, or null
/// when the core is unknown. For example `retroarch.finalburn-neo` yields
/// `FinalBurn Neo/fbneo`.
String? retroArchCoreFolderPath(String emulatorSlug) {
  const prefix = 'retroarch.';
  if (!emulatorSlug.startsWith(prefix)) return null;
  final slug = emulatorSlug.substring(prefix.length);
  final entry = retroArchCoreFolders[slug];
  if (entry == null) return null;
  return entry.hasSubfolder
      ? '${entry.folder}/${entry.subfolder}'
      : entry.folder;
}

/// Returns only the RetroArch core_name folder for a `retroarch.<slug>` slug,
/// without the core's internal subfolder (used for save states, which RetroArch
/// stores directly under the core_name folder, e.g. `FinalBurn Neo/`).
String? retroArchCoreFolderName(String emulatorSlug) {
  const prefix = 'retroarch.';
  if (!emulatorSlug.startsWith(prefix)) return null;
  final entry = retroArchCoreFolders[emulatorSlug.substring(prefix.length)];
  return entry?.folder;
}

/// Returns only the core-internal subfolder (e.g. `fbneo`, `mame`) for a
/// `retroarch.<slug>` emulator slug, or null when the core has none.
String? retroArchCoreSubfolder(String emulatorSlug) {
  const prefix = 'retroarch.';
  if (!emulatorSlug.startsWith(prefix)) return null;
  final entry = retroArchCoreFolders[emulatorSlug.substring(prefix.length)];
  if (entry == null || !entry.hasSubfolder) return null;
  return entry.subfolder;
}
