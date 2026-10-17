import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:greennote/core/accounts/local_account.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<LocalAccount> createAccount() async =>
      LocalAccount(await SharedPreferences.getInstance());

  test('multiple anonymous accounts can be created and independently managed', () async {
    final account = await createAccount();

    // 默认初始具有一个账户
    expect(account.profiles.length, 1);
    expect(account.name, '匿名酷友');

    // 创建匿名账户 2 与 匿名账户 3
    final p2 = await account.createProfile(name: '匿名账户2', switchNow: false);
    final p3 = await account.createProfile(name: '匿名账户3', switchNow: false);

    expect(account.profiles.length, 3);
    expect(account.activeProfileId, 'anon_1');
    expect(account.name, '匿名酷友');

    // 为当前账户 (anon_1) 配置独立 UID、关注、收藏与机型关注
    await account.setPublicIdentity(
      uid: '10001',
      username: '酷友一号',
      userAvatar: 'https://example.com/avatar1.png',
    );
    await account.toggle('follows', '11', {'uid': '11', 'username': '博主A'});
    await account.toggle('productFollows', '21', {'id': '21', 'title': '手机A'});
    await account.toggle('favorites', '31', {'id': '31', 'message': '动态A'});

    expect(account.publicIdentity?['uid'], '10001');
    expect(account.follows.keys, contains('11'));
    expect(account.productFollows.keys, contains('21'));
    expect(account.favorites.keys, contains('31'));

    // 切换至 匿名账户 2
    await account.switchProfile(p2.id);
    expect(account.activeProfileId, p2.id);
    expect(account.name, '匿名账户2');
    // 验证账户 2 数据完全独立，不包含账户 1 的数据
    expect(account.publicIdentity, isNull);
    expect(account.follows, isEmpty);
    expect(account.productFollows, isEmpty);
    expect(account.favorites, isEmpty);

    // 为账户 2 配置其专属数据
    await account.setPublicIdentity(
      uid: '10002',
      username: '酷友二号',
      userAvatar: 'https://example.com/avatar2.png',
    );
    await account.toggle('follows', '12', {'uid': '12', 'username': '博主B'});
    await account.toggle('productFollows', '22', {'id': '22', 'title': '手机B'});
    await account.toggle('favorites', '32', {'id': '32', 'message': '动态B'});

    expect(account.publicIdentity?['uid'], '10002');
    expect(account.follows.keys, contains('12'));
    expect(account.productFollows.keys, contains('22'));
    expect(account.favorites.keys, contains('32'));

    // 切换至 匿名账户 3 并验证也是空白独立的
    await account.switchProfile(p3.id);
    expect(account.name, '匿名账户3');
    expect(account.publicIdentity, isNull);
    expect(account.follows, isEmpty);

    // 切换回 匿名账户 1，验证原数据完整保留
    await account.switchProfile('anon_1');
    expect(account.name, '匿名酷友');
    expect(account.publicIdentity?['uid'], '10001');
    expect(account.follows.keys, contains('11'));
    expect(account.follows.keys, isNot(contains('12')));
    expect(account.productFollows.keys, contains('21'));
    expect(account.favorites.keys, contains('31'));

    // 切换回 匿名账户 2，验证原数据完整保留
    await account.switchProfile(p2.id);
    expect(account.name, '匿名账户2');
    expect(account.publicIdentity?['uid'], '10002');
    expect(account.follows.keys, contains('12'));
    expect(account.follows.keys, isNot(contains('11')));

    // 持久化重新加载验证
    final reloaded = await createAccount();
    expect(reloaded.profiles.length, 3);
    expect(reloaded.activeProfileId, p2.id);
    expect(reloaded.name, '匿名账户2');
    expect(reloaded.publicIdentity?['uid'], '10002');

    // 删除 匿名账户 2
    await reloaded.deleteProfile(p2.id);
    expect(reloaded.profiles.length, 2);
    expect(reloaded.profiles.any((p) => p.id == p2.id), isFalse);
    // 激活账户自动回退至第一个有效账户
    expect(reloaded.activeProfileId, 'anon_1');
    expect(reloaded.name, '匿名酷友');
    expect(reloaded.publicIdentity?['uid'], '10001');
  });

  test('deleting all profiles resets cleanly to initial state', () async {
    final account = await createAccount();
    final p2 = await account.createProfile(name: '额外账户');
    expect(account.profiles.length, 2);

    await account.deleteProfile('anon_1');
    expect(account.profiles.length, 1);
    expect(account.activeProfileId, p2.id);

    // 删除最后一个账户触发自动重置
    await account.deleteProfile(p2.id);
    expect(account.profiles.length, 1);
    expect(account.name, '匿名酷友');
    expect(account.activeProfileId, 'anon_1');
  });
}
