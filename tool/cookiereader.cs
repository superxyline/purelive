using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

class CR
{
    delegate int sql_open(string f, out IntPtr db, int fl, IntPtr z);
    delegate int sql_close(IntPtr db);
    delegate int sql_prepare(IntPtr db, string sql, int n, out IntPtr st, IntPtr t);
    delegate int sql_step(IntPtr st);
    delegate IntPtr sql_text(IntPtr st, int n);
    delegate IntPtr sql_blob(IntPtr st, int n);
    delegate int sql_bytes(IntPtr st, int n);
    delegate int sql_finalize(IntPtr st);

    static string P2U(IntPtr p)
    {
        if (p == IntPtr.Zero) return "";
        int len = 0;
        while (Marshal.ReadByte(p, len) != 0) len++;
        byte[] b = new byte[len];
        Marshal.Copy(p, b, 0, len);
        return Encoding.UTF8.GetString(b);
    }

    static void Main()
    {
        IntPtr hs = LoadLibrary(@"C:\Program Files\MI\PcContinuity\1.1.2.36\sqlite3.dll");
        var fOpen = Marshal.GetDelegateForFunctionPointer<sql_open>(GetProcAddress(hs, "sqlite3_open_v2"));
        var fClose = Marshal.GetDelegateForFunctionPointer<sql_close>(GetProcAddress(hs, "sqlite3_close"));
        var fPrep = Marshal.GetDelegateForFunctionPointer<sql_prepare>(GetProcAddress(hs, "sqlite3_prepare_v2"));
        var fStep = Marshal.GetDelegateForFunctionPointer<sql_step>(GetProcAddress(hs, "sqlite3_step"));
        var fText = Marshal.GetDelegateForFunctionPointer<sql_text>(GetProcAddress(hs, "sqlite3_column_text"));
        var fBlob = Marshal.GetDelegateForFunctionPointer<sql_blob>(GetProcAddress(hs, "sqlite3_column_blob"));
        var fBytes = Marshal.GetDelegateForFunctionPointer<sql_bytes>(GetProcAddress(hs, "sqlite3_column_bytes"));
        var fFin = Marshal.GetDelegateForFunctionPointer<sql_finalize>(GetProcAddress(hs, "sqlite3_finalize"));
        byte[] mk = File.ReadAllBytes("E:/codex/pure_live/tool/_master_key.bin");
        IntPtr db;
        fOpen("E:/codex/pure_live/tool/_edge_cookies.db", out db, 1, IntPtr.Zero);
        IntPtr st;
        fPrep(db, "SELECT name,encrypted_value,host_key FROM cookies WHERE host_key LIKE '%douyu%' AND name IN ('acf_uid','acf_stk','dy_did') LIMIT 3", -1, out st, IntPtr.Zero);
        while (fStep(st) == 100)
        {
            string nm = P2U(fText(st, 0));
            IntPtr bp = fBlob(st, 1);
            int bl = fBytes(st, 1);
            string ho = P2U(fText(st, 2));
            byte[] ev = new byte[bl];
            Marshal.Copy(bp, ev, 0, bl);
            var hex = new StringBuilder();
            int show = Math.Min(bl, 40);
            for (int i = 0; i < show; i++) hex.Append(ev[i].ToString("x2") + " ");
            Console.WriteLine(ho + "|" + nm + " len=" + bl);
            Console.WriteLine("  hex: " + hex.ToString());
            if (bl > 3) Console.WriteLine("  prefix chars: '" + (char)ev[0] + (char)ev[1] + (char)ev[2] + "' bytes: " + ev[0] + "," + ev[1] + "," + ev[2]);
            if (bl > 31)
            {
                byte[] nc = new byte[12], tg = new byte[16], ct = new byte[bl - 31];
                Array.Copy(ev, 3, nc, 0, 12);
                Array.Copy(ev, bl - 16, tg, 0, 16);
                Array.Copy(ev, 15, ct, 0, ct.Length);
                Console.WriteLine("  DECRYPT: " + Decrypt(mk, nc, ct, tg));
            }
            Console.WriteLine();
        }
        fFin(st);
        fClose(db);
    }

    static string Decrypt(byte[] key, byte[] nc, byte[] ct, byte[] tg)
    {
        IntPtr ha = IntPtr.Zero, hk = IntPtr.Zero;
        try
        {
            int s = BCryptOpenAlgorithmProvider(out ha, "BCRYPT_AES_ALGORITHM", null, 0);
            if (s != 0) return "(OA:" + s + ")";
            byte[] cm = Encoding.Unicode.GetBytes("ChainingModeGCM");
            s = BCryptSetProperty(ha, "BCRYPT_CHAINING_MODE", cm, cm.Length, 0);
            if (s != 0) return "(GC:" + s + ")";
            s = BCryptGenerateSymmetricKey(ha, out hk, key, key.Length, null, 0, 0);
            if (s != 0) return "(GK:" + s + ")";
            byte[] buf = new byte[ct.Length + 16];
            int ol = 0;
            s = BCryptDecrypt(hk, ct, ct.Length, IntPtr.Zero, nc, nc.Length, buf, buf.Length, out ol, 0);
            if (s == 0) return Encoding.UTF8.GetString(buf, 0, ol);
            return "(DC:" + s + ")";
        }
        finally
        {
            if (hk != IntPtr.Zero) BCryptDestroyKey(hk);
            if (ha != IntPtr.Zero) BCryptCloseAlgorithmProvider(ha, 0);
        }
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr LoadLibrary(string p);
    [DllImport("kernel32.dll")]
    static extern IntPtr GetProcAddress(IntPtr m, string n);
    [DllImport("bcrypt.dll")]
    static extern int BCryptOpenAlgorithmProvider(out IntPtr ph, string a, string i, uint f);
    [DllImport("bcrypt.dll")]
    static extern int BCryptCloseAlgorithmProvider(IntPtr h, uint f);
    [DllImport("bcrypt.dll")]
    static extern int BCryptSetProperty(IntPtr h, string p, byte[] inp, int l, uint f);
    [DllImport("bcrypt.dll")]
    static extern int BCryptGenerateSymmetricKey(IntPtr ha, out IntPtr hk, byte[] ko, int kol, byte[] s, int sl, uint f);
    [DllImport("bcrypt.dll")]
    static extern int BCryptDecrypt(IntPtr hk, byte[] inp, int inl, IntPtr pi, byte[] iv, int ivl, byte[] outp, int outl, out int ol, uint f);
    [DllImport("bcrypt.dll")]
    static extern int BCryptDestroyKey(IntPtr h);
}