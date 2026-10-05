using System.Runtime.InteropServices;
using FILETIME = System.Runtime.InteropServices.ComTypes.FILETIME;

namespace TokenStats.Providers;

/// <summary>
/// Windows-Anmeldeinformationsverwaltung, nur lesen – das Gegenstück zum macOS-Schlüsselbund.
/// CLIs auf Basis von zalando/go-keyring (z. B. <c>agy</c>) legen dort generische
/// Anmeldeinformationen namens <c>dienst:konto</c> ab.
/// </summary>
static class CredentialManager
{
    const int CredTypeGeneric = 1;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct Credential
    {
        public int Flags;
        public int Type;
        public IntPtr TargetName;
        public IntPtr Comment;
        public FILETIME LastWritten;
        public int CredentialBlobSize;
        public IntPtr CredentialBlob;
        public int Persist;
        public int AttributeCount;
        public IntPtr Attributes;
        public IntPtr TargetAlias;
        public IntPtr UserName;
    }

    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CredRead(string target, int type, int flags, out IntPtr credential);

    [DllImport("advapi32.dll")]
    static extern void CredFree(IntPtr buffer);

    /// <summary>Inhalt einer generischen Anmeldeinformation, oder null, wenn es sie nicht gibt.</summary>
    public static byte[]? ReadGeneric(string target)
    {
        if (!CredRead(target, CredTypeGeneric, 0, out var pointer)) return null;
        try
        {
            var credential = Marshal.PtrToStructure<Credential>(pointer);
            if (credential.CredentialBlob == IntPtr.Zero || credential.CredentialBlobSize <= 0) return null;
            var blob = new byte[credential.CredentialBlobSize];
            Marshal.Copy(credential.CredentialBlob, blob, 0, blob.Length);
            return blob;
        }
        finally
        {
            CredFree(pointer);
        }
    }
}
