import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'dart:native_ffi';

/// 从 Edge 浏览器提取斗鱼 Cookie
/// 
/// 使用方式: dartvm.exe tool/_extract_douyu_cookie.dart

void main() async {
  print('=== Edge 浏览器斗鱼 Cookie 提取器 ===\n');

  // Step 1: 读取 master key
  final keyFile = File('E:/codex/pure_live/tool/_master_key.bin');
  if (!keyFile.existsSync()) {
    print('错误: 找不到 master key 文件，请先运行 PowerShell 脚本');
    exit(1);
  }
  final masterKey = keyFile.readAsBytesSync();
  print('Master key: ${masterKey.length} bytes');

  // Step 2: 复制并读取 SQLite cookie 数据库
  final dbSrc = File '${Platform.environment['LOCALAPPDATA']}\\Microsoft\\Edge\\User Data\\Default\\Network\\Cookies';
  final dbCopy = File('E:/codex/pure_live/tool/_edge_cookies_copy2');
  
  // 关闭 Edge 可能持有的锁
  await Process.run('taskkill', ['/f', '/im', 'msedge.exe'], runInShell: true).catchError((_) {});
  await Future.delayed(Duration(milliseconds: 500));
  
  try {
    dbSrc.copySync(dbCopy.path);
  } catch (e) {
    print('复制数据库失败: $e');
    // 尝试使用已有副本
    if (!dbCopy.existsSync()) {
      print('无可用的Cookie数据库');
      exit(1);
    }
  }
  
  print('Cookie 数据库已复制');

  // Step 3: 使用 sqlite3 读取 cookie
  // 由于 Dart 没有内置 sqlite3，我们用 subprocess 调用 sqlite3 命令行
  // 如果没有 sqlite3，使用另一种方法：直接用 dart:io 解析
  
  // 尝试用 PowerShell 调用 sqlite3
  final result = await Process.run('powershell', [
    '-Command',
    r'''
Add-Type -AssemblyName System.Data
$conn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=E:\codex\pure_live\tool\_edge_cookies_copy2;Version=3;Read Only=True;Journal Mode=Memory;")
$conn.Open()
$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT name, encrypted_value, host_key, path, expires_utc, is_secure, is_httponly FROM cookies WHERE host_key LIKE '%douyu%' ORDER BY name"
$reader = $cmd.ExecuteReader()
$json = @()
while ($reader.Read()) {
    $json += @{
        name = $reader.GetString(0)
        encrypted_value = [Convert]::ToBase64String($reader[1] as byte[])
        host = $reader.GetString(2)
        path = $reader.GetString(3)
        expires = $reader.GetInt64(4)
        secure = $reader.GetBoolean(5)
        httponly = $reader.GetBoolean(6)
    }
}
$conn.Close()
$json | ConvertTo-Json -Compress
''',
  ], runInShell: true);

  if (result.exitCode != 0) {
    print('SQLite 读取失败: ${result.stderr}');
    print('尝试使用 sqlite3.exe...');
    await extractWithSqlite3(masterKey);
    return;
  }

  final output = result.stdout.toString().trim();
  if (output.isEmpty || output == '[]') {
    print('未找到斗鱼 Cookie');
    exit(1);
  }

  // 解析 JSON
  final List<dynamic> cookies;
  try {
    // 可能是单个对象或数组
    if (output.startsWith('[')) {
      cookies = jsonDecode(output);
    } else {
      cookies = [jsonDecode(output)];
    }
  } catch (e) {
    print('JSON 解析失败: $e');
    print('Raw output: ${output.substring(0, output.length.clamp(0, 200))}');
    exit(1);
  }

  print('找到 ${cookies.length} 个斗鱼 Cookie:\n');

  // Step 4: 解密每个 cookie
  final cookieMap = <String, String>{};
  
  for (final cookie in cookies) {
    final name = cookie['name'] as String;
    final encB64 = cookie['encrypted_value'] as String;
    final host = cookie['host'] as String;
    
    final encBytes = base64Decode(encB64);
    
    String value;
    if (encBytes.length > 3 && 
        encBytes[0] == 0x76 && encBytes[1] == 0x31 && encBytes[2] == 0x30) {
      // v10 prefix - AES-256-GCM
      value = decryptAES256GCM(masterKey, encBytes.sublist(3));
    } else if (encBytes.length > 3 &&
        encBytes[0] == 0x76 && encBytes[1] == 0x31 && encBytes[2] == 0x31) {
      // v11 prefix - AES-256-GCM with app-bound key (newer Edge)
      value = '(v11 encrypted - 需要 Edge 未运行时解密)';
    } else if (encBytes.isEmpty) {
      value = '(空值)';
    } else {
      value = '(未知加密格式: ${encBytes[0].toRadixString(16)})';
    }
    
    cookieMap[name] = value;
    final displayValue = value.length > 40 ? '${value.substring(0, 40)}...' : value;
    print('  $host | $name = $displayValue');
  }

  // Step 5: 组装 Cookie 字符串
  print('\n=== 斗鱼 Cookie 字符串 ===');
  
  // 提取关键字段
  final importantKeys = ['acf_uid', 'acf_stk', 'acf_aa1', 'dy_did', 'acfЉ', 'ansLogin', 'fldt'];
  final parts = <String>[];
  
  for (final entry in cookieMap.entries) {
    if (entry.value.startsWith('(')) continue; // 跳过解密失败的
    parts.add('${entry.key}=${entry.value}');
  }
  
  final cookieStr = parts.join('; ');
  print(cookieStr);
  
  // 保存到文件
  final outFile = File('E:/codex/pure_live/tool/_douyu_cookie.txt');
  outFile.writeAsStringSync(cookieStr);
  print('\nCookie 已保存到: ${outFile.path}');
}

/// AES-256-GCM 解密 (Chromium v10 cookie 格式)
/// 
/// 加密格式: nonce(12 bytes) + ciphertext + tag(16 bytes)
String decryptAES256GCM(List<int> key, List<int> data) {
  if (data.length < 28) { // 12 nonce + 16 tag minimum
    return '(数据太短: ${data.length} bytes)';
  }
  
  final nonce = Uint8List.fromList(data.sublist(0, 12));
  final ciphertext = data.sublist(12);
  
  // 使用 dart:crypto 或者 Windows CNG API
  // 这里使用 Windows Bcrypt API via FFI
  
  try {
    final result = _decryptWithBcrypt(key, nonce, ciphertext);
    return utf8.decode(result, allowMalformed: true);
  } catch (e) {
    return '(解密失败: $e)';
  }
}

/// 使用 Windows BCrypt API 解密 AES-256-GCM
List<int> _decryptWithBcrypt(List<int> key, Uint8List nonce, List<int> ciphertextWithTag) {
  // 动态加载 bcrypt.dll
  final bcrypt = DynamicLibrary.open('bcrypt.dll');
  
  // BCryptOpenAlgorithmProvider
  final openAlg = bcrypt.lookupFunction<
    Int32 Function(Pointer<Utf16>, Pointer<Uint32>, Pointer<Uint32>, Uint32),
    int Function(Pointer<Utf16>, Pointer<Uint32>, Pointer<Uint32>, int)
  >('BCryptOpenAlgorithmProvider');
  
  // BCryptCloseAlgorithmProvider
  final closeAlg = bcrypt.lookupFunction<
    Int32 Function(Pointer, Uint32),
    int Function(Pointer, int)
  >('BCryptCloseAlgorithmProvider');
  
  // BCryptSetProperty
  final setProp = bcrypt.lookupFunction<
    Int32 Function(Pointer, Pointer<Utf16>, Pointer<Uint8>, Uint32, Uint32),
    int Function(Pointer, Pointer<Utf16>, Pointer<Uint8>, int, int)
  >('BCryptSetProperty');
  
  // BCryptGenerateSymmetricKey
  final genKey = bcrypt.lookupFunction<
    Int32 Function(Pointer, Pointer<Pointer>, Pointer<Uint8>, Uint32, Pointer<Uint8>, Uint32, Uint32),
    int Function(Pointer, Pointer<Pointer>, Pointer<Uint8>, int, Pointer<Uint8>, int, int)
  >('BCryptGenerateSymmetricKey');
  
  // BCryptDecrypt
  final decryptFn = bcrypt.lookupFunction<
    Int32 Function(Pointer, Pointer<Uint8>, Uint32, Pointer, Pointer<Uint8>, Uint32,
        Pointer<Uint8>, Uint32, Pointer<Uint8>, Uint32, Pointer<Uint32>, Uint32),
    int Function(Pointer, Pointer<Uint8>, int, Pointer, Pointer<Uint8>, int,
        Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint32>, int)
  >('BCryptDecrypt');
  
  // BCryptDestroyKey
  final destroyKey = bcrypt.lookupFunction<
    Int32 Function(Pointer),
    int Function(Pointer)
  >('BCryptDestroyKey');

  // 分配内存
  final arena = Arena();
  
  try {
    // BCRYPT_AES_ALGORITHM
    final algName = 'BCRYPT_AES_ALGORITHM'.toNativeUtf16(allocator: arena);
    final algHandle = calloc<Pointer>();
    
    int status = openAlg(algName, algHandle, nullptr, 0);
    if (status != 0) throw Exception('BCryptOpenAlgorithmProvider failed: $status');
    
    // Set chaining mode to GCM
    final chainMode = 'BCRYPT_CHAINING_MODE'.toNativeUtf16(allocator: arena);
    final gcmMode = 'ChainingModeGCM'.toNativeUtf16(allocator: arena);
    final gcmModeBytes = gcmMode.cast<Uint8>();
    // Get the byte length of the UTF-16 string
    final gcmModeLen = 'ChainingModeGCM'.length * 2 + 2;
    status = setProp(algHandle.value, chainMode, gcmModeBytes, gcmModeLen, 0);
    if (status != 0) throw Exception('BCryptSetProperty(GCM) failed: $status');
    
    // Generate symmetric key
    final keyHandle = calloc<Pointer>();
    final keyPtr = Uint8List.fromList(key);
    final keyData = calloc<Uint8>(key.length);
    keyData.asTypedList(key.length).setAll(0, keyPtr);
    
    status = genKey(algHandle.value, keyHandle, keyData, key.length, nullptr, 0, 0);
    if (status != 0) throw Exception('BCryptGenerateSymmetricKey failed: $status');
    
    // Prepare GCM auth info (nonce/tag)
    final tagSize = 16;
    final ciphertextOnly = Uint8List.fromList(ciphertextWithTag.sublist(0, ciphertextWithTag.length - tagSize));
    final tag = Uint8List.fromList(ciphertextWithTag.sublist(ciphertextWithTag.length - tagSize));
    
    // BCryptDecrypt with BCRYPT_AUTHENTICATED_CIPHERTEXT_INFO
    // For GCM, we need to pass the nonce as IV
    final ivBuffer = calloc<Uint8>(nonce.length);
    ivBuffer.asTypedList(nonce.length).setAll(0, nonce);
    
    final outputSize = ciphertextOnly.length;
    final outputBuffer = calloc<Uint8>(outputSize);
    final outputLen = calloc<Uint32>();
    
    status = decryptFn(
      keyHandle.value,
      ciphertextOnly.length > 0 ? calloc<Uint8>(ciphertextOnly.length).asTypedList(ciphertextOnly.length).buffer.asUint8List().cast() : nullptr,
      ciphertextOnly.length,
      nullptr, // pPaddingInfo
      ivBuffer, // pbIV
      nonce.length, // cbIV
      outputBuffer,
      outputSize,
      nullptr, // pbAuthData
      0, // cbAuthData
      outputLen,
      0, // dwFlags - BCRYPT_BLOCK_PADDING = 0x00000001 but for GCM we don't use it
    );
    
    if (status == 0) {
      final result = outputBuffer.asTypedList(outputLen.value).toList();
      destroyKey(keyHandle.value);
      closeAlg(algHandle.value, 0);
      return result;
    }
    
    // If the simple approach failed, try with auth tag
    // Reset and try with BCRYPT_AUTHENTICATED_CIPHERTEXT_INFO approach
    destroyKey(keyHandle.value);
    closeAlg(algHandle.value, 0);
    
    return _decryptGCMWithAuthInfo(key, nonce, ciphertextOnly, tag);
  } finally {
    arena.release();
  }
}

List<int> _decryptGCMWithAuthInfo(List<int> key, Uint8List nonce, Uint8List ciphertext, Uint8List tag) {
  final bcrypt = DynamicLibrary.open('bcrypt.dll');
  
  // Use BCryptDecrypt with BCRYPT_AUTHENTICATED_CIPHERTEXT_INFO
  // This is complex FFI - let's use a simpler approach with Bcrypt.Net via PowerShell
  
  // Fallback: use PowerShell with .NET's AesGcm or similar
  throw Exception('FFI GCM 解密需要更复杂的实现');
}

// Arena allocator for FFI
class Arena implements Finalizer {
  final List<Pointer> _pointers = [];
  
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) {
    final ptr = calloc<Uint8>(byteCount).cast<T>();
    _pointers.add(ptr);
    return ptr;
  }
  
  void release() {
    for (final ptr in _pointers) {
      calloc.free(ptr);
    }
    _pointers.clear();
  }
  
  @override
  void attach(Object token, Pointer pointer, {Object? detach}) {}
  
  @override
  void detach(Object token) {}
}
