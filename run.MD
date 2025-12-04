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