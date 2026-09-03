using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Data.Sqlite;

class Program
{
    static void Main(string[] args)
    {
        // 读取 master key
        byte[] masterKey = File.ReadAllBytes("E:/codex/pure_live/tool/_master_key.bin");
        Console.Error.WriteLine($"Master key: {masterKey.Length} bytes");

        // 复制 cookie 数据库
        string dbSrc = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            @"Microsoft\Edge\User Data\Default\Network\Cookies");
        string dbCopy = "E:/codex/pure_live/tool/_cookies_read.db";
        
        try { File.Copy(dbSrc, dbCopy, true); }
        catch { /* 可能已被锁定，使用已有副本 */ }
        
        if (!File.Exists(dbCopy)) {
            Console.Error.WriteLine("Cookie DB not found");
            return;
        }
        Console.Error.WriteLine("Cookie DB copied");

        // 读取 douyu cookies
        using var conn = new SqliteConnection($"Data Source={dbCopy};Mode=ReadOnly;Cache=Shared");
        conn.Open();
        
        using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT name, encrypted_value, host_key FROM cookies WHERE host_key LIKE '%douyu%'";
        
        using var reader = cmd.ExecuteReader();
        var cookies = new System.Collections.Generic.List<(string name, string value, string host)>();
        
        while (reader.Read())
        {
            string name = reader.GetString(0);
            byte[] encValue = (byte[])reader[1];
            string host = reader.GetString(2);
            
            string value;
            if (encValue.Length > 3 && encValue[0] == 'v' && encValue[1] == '1' && encValue[2] == '0')
            {
                // v10: AES-256-GCM
                value = DecryptAES256GCM(masterKey, encValue.AsSpan(3));
            }
            else
            {
                value = "(encrypted)";
            }
            
            cookies.Add((name, value, host));
        }
        
        // 输出 cookie 字符串
        var sb = new StringBuilder();
        foreach (var c in cookies)
        {
            Console.WriteLine($"{c.host}|{c.name}={c.value}");
            if (!c.value.StartsWith("("))
            {
                if (sb.Length > 0) sb.Append("; ");
                sb.Append($"{c.name}={c.value}");
            }
        }
        
        Console.Error.WriteLine($"\nFound {cookies.Count} douyu cookies");
        
        // 输出完整 cookie 字符串到 stdout
        Console.WriteLine("---COOKIE_START---");
        Console.WriteLine(sb.ToString());
        Console.WriteLine("---COOKIE_END---");
    }
    
    static string DecryptAES256GCM(byte[] key, ReadOnlySpan<byte> data)
    {
        if (data.Length < 28) return "(too short)";
        
        byte[] nonce = data.Slice(0, 12).ToArray();
        byte[] ciphertext = data.Slice(12, data.Length - 28).ToArray();
        byte[] tag = data.Slice(data.Length - 16, 16).ToArray();
        
        try
        {
            // 尝试使用 AesGcm (.NET Core 3.0+)
            using var aes = new AesGcm(key, 16);
            byte[] plaintext = new byte[ciphertext.Length];
            aes.Decrypt(nonce, ciphertext, tag, plaintext);
            return Encoding.UTF8.GetString(plaintext);
        }
        catch
        {
            // Fallback: try Windows BCrypt
            try
            {
                return DecryptWithBCrypt(key, nonce, ciphertext, tag);
            }
            catch (Exception ex)
            {
                return $"(decrypt error: {ex.Message})";
            }
        }
    }
    
    static string DecryptWithBCrypt(byte[] key, byte[] nonce, byte[] ciphertext, byte[] tag)
    {
        IntPtr hAlgorithm = IntPtr.Zero;
        IntPtr hKey = IntPtr.Zero;
        
        try
        {
            // Open AES algorithm
            int status = BCryptOpenAlgorithmProvider(out hAlgorithm, "BCRYPT_AES_ALGORITHM", null, 0);
            if (status != 0) throw new Exception($"OpenAlgorithm failed: {status}");
            
            // Set GCM mode
            byte[] chainMode = Encoding.Unicode.GetBytes("ChainingModeGCM\0");
            status = BCryptSetProperty(hAlgorithm, "BCRYPT_CHAINING_MODE", chainMode, chainMode.Length, 0);
            if (status != 0) throw new Exception($"SetProperty(GCM) failed: {status}");
            
            // Generate key
            status = BCryptGenerateSymmetricKey(hAlgorithm, out hKey, key, key.Length, null, 0, 0);
            if (status != 0) throw new Exception($"GenerateKey failed: {status}");
            
            // Build BCRYPT_AUTHENTICATED_CIPHERTEXT_INFO
            // For simplicity, use the tag as additional authenticated data
            byte[] iv = new byte[nonce.Length + tag.Length];
            Array.Copy(nonce, 0, iv, 0, nonce.Length);
            Array.Copy(tag, 0, iv, nonce.Length, tag.Length);
            
            int plainLen = 0;
            byte[] plainBuf = new byte[ciphertext.Length + 16]; // extra space for padding
            
            status = BCryptDecrypt(
                hKey,
                ciphertext, ciphertext.Length,
                IntPtr.Zero,
                iv, iv.Length,
                plainBuf, plainBuf.Length,
                out plainLen,
                0x20 // BCRYPT_BLOCK_NO_PADDING
            );
            
            if (status != 0) throw new Exception($"Decrypt failed: {status}");
            
            return Encoding.UTF8.GetString(plainBuf, 0, plainLen);
        }
        finally
        {
            if (hKey != IntPtr.Zero) BCryptDestroyKey(hKey);
            if (hAlgorithm != IntPtr.Zero) BCryptCloseAlgorithmProvider(hAlgorithm, 0);
        }
    }
    
    [System.Runtime.InteropServices.DllImport("bcrypt.dll")]
    static extern int BCryptOpenAlgorithmProvider(out IntPtr phAlgorithm, string pszAlgorithm, string pszImplementation, uint dwFlags);
    
    [System.Runtime.InteropServices.DllImport("bcrypt.dll")]
    static extern int BCryptCloseAlgorithmProvider(IntPtr hAlgorithm, uint dwFlags);
    
    [System.Runtime.InteropServices.DllImport("bcrypt.dll")]
    static extern int BCryptSetProperty(IntPtr hObject, string pszProperty, byte[] pbInput, int cbInput, uint dwFlags);
    
    [System.Runtime.InteropServices.DllImport("bcrypt.dll")]
    static extern int BCryptGenerateSymmetricKey(IntPtr hAlgorithm, out IntPtr phKey, byte[] pbKeyObject, int cbKeyObject, byte[] pbSecret, int cbSecret, uint dwFlags);
    
    [System.Runtime.InteropServices.DllImport("bcrypt.dll")]
    static extern int BCryptDecrypt(IntPtr hKey, byte[] pbInput, int cbInput, IntPtr pPaddingInfo, byte[] pbIV, int cbIV, byte[] pbOutput, int cbOutput, out int pcbResult, uint dwFlags);
    
    [System.Runtime.InteropServices.DllImport("bcrypt.dll")]
    static extern int BCryptDestroyKey(IntPtr hKey);
}
