### Windows 打包

```shell
dart run msix:create --signtool-options "/td SHA256"
```

### Android 通用

```shell
flutter build apk
```

### Android 分包

```shell
flutter build apk --split-per-abi
```

### macOS 打包

```shell
flutter build macos --release
```

如果想打包 dmg，则需要运行以下命令：

```shell
python3 -m venv .venv

# Windows
.venv\Scripts\activate
# Unix/Linux/MacOS
source .venv/bin/activate

pip install dmgbuild
dart run dmg --no-sign --no-notarization
```

> 参考链接：https://pub.dev/packages/dmg