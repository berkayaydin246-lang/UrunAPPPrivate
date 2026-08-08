/// Exact identifiers used only by the updated beverage nutrition methodology.
///
/// Version 2023.1 follows the Nutri-Score 2023 beverage methodology's
/// non-nutritive sweetener scope. Polyols remain explicitly excluded. This is
/// not an additive risk or safety classification catalog.
abstract final class NnsCanonicalIdentifiers {
  static const version = 'nutri-score-2023.1';

  static const qualifyingENumbers = {
    '950',
    '951',
    '952',
    '954',
    '955',
    '957',
    '959',
    '960',
    '961',
    '962',
    '969',
  };

  static const qualifyingAliases = {
    'asesülfam k',
    'asesülfam potasyum',
    'acesulfame k',
    'acesulfame potassium',
    'aspartam',
    'aspartame',
    'siklamat',
    'cyclamate',
    'sakarin',
    'saccharin',
    'sukraloz',
    'sucralose',
    'taumatin',
    'thaumatin',
    'neohesperidin dc',
    'steviol glikozitleri',
    'steviol glycosides',
    'neotam',
    'neotame',
    'aspartam asesülfam tuzu',
    'aspartame acesulfame salt',
    'advantam',
    'advantame',
  };

  static const excludedPolyolENumbers = {
    '420',
    '421',
    '953',
    '964',
    '965',
    '966',
    '967',
    '968',
  };
}
