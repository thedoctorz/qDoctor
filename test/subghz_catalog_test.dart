import 'package:doctormobile/components/archive/category.dart';
import 'package:doctormobile/pages/archive/subghz_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a subghz path keeps its folder', () {
    final top = SubghzRemotePath.tryParse('/ext/subghz/Fiat.sub');
    expect(top, isNotNull);
    expect(top!.category, ArchiveCategory.subghz);
    expect(top.flipperDir, 'subghz');
    expect(top.subFolder, isEmpty);
    expect(top.name, 'Fiat');
    expect(top.fileName, 'Fiat.sub');

    final nested = SubghzRemotePath.tryParse('/ext/subghz/cars/remote.sub');
    expect(nested!.subFolder, 'cars');
    expect(nested.name, 'remote');
  });

  test('wardriving is separate and ignored folders are skipped', () {
    final ward = SubghzRemotePath.tryParse('/ext/subghz/wardriving/log.sub');
    expect(ward!.category, ArchiveCategory.wardriving);
    expect(ward.flipperDir, 'subghz/wardriving');
    expect(ward.subFolder, isEmpty);

    final saved = SubghzRemotePath.tryParse(
      '/ext/subghz/wardriving/autosaved/log.sub',
    );
    expect(saved!.category, ArchiveCategory.wardriving);
    expect(saved.subFolder, 'autosaved');

    expect(SubghzRemotePath.tryParse('/ext/subghz/assets/x.sub'), isNull);
    expect(SubghzRemotePath.tryParse('/ext/subghz/.hidden/x.sub'), isNull);
    expect(SubghzRemotePath.tryParse('/ext/nfc/a.nfc'), isNull);
    expect(SubghzRemotePath.tryParse('/ext/subghz/note.txt'), isNull);
  });
}
