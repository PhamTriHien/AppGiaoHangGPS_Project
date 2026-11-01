param([switch]$Apply)
$ErrorActionPreference = 'Stop'
$previousToken = $env:SUPABASE_ACCESS_TOKEN
try {
    if (-not $previousToken) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class GhstSupabaseCredential {
    [StructLayout(LayoutKind.Sequential)]
    private struct Credential {
        public uint Flags;
        public uint Type;
        public IntPtr TargetName;
        public IntPtr Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public IntPtr TargetAlias;
        public IntPtr UserName;
    }
    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredRead(string target, uint type, uint flags, out IntPtr credential);
    [DllImport("advapi32.dll")]
    private static extern void CredFree(IntPtr credential);
    public static byte[] ReadCliToken() {
        IntPtr pointer;
        if (!CredRead("Supabase CLI:supabase", 1, 0, out pointer)) return null;
        try {
            var credential = Marshal.PtrToStructure<Credential>(pointer);
            var bytes = new byte[credential.CredentialBlobSize];
            Marshal.Copy(credential.CredentialBlob, bytes, 0, bytes.Length);
            return bytes;
        } finally { CredFree(pointer); }
    }
}
'@
        $tokenBytes = [GhstSupabaseCredential]::ReadCliToken()
        if ($tokenBytes) {
            $cliToken = [Text.Encoding]::UTF8.GetString($tokenBytes)
            if ($cliToken.Contains([string][char]0)) {
                $cliToken = [Text.Encoding]::Unicode.GetString($tokenBytes)
            }
            if ($cliToken.Trim() -notmatch '^sbp_\S+$') { throw 'The Supabase CLI credential format is unsupported.' }
            # Pass only the CLI token to this child process; never persist or print it.
            $env:SUPABASE_ACCESS_TOKEN = $cliToken.Trim()
            [Array]::Clear($tokenBytes, 0, $tokenBytes.Length)
            $cliToken = $null
        }
    }
    $mode = if ($Apply) { '--apply' } else { '--check' }
    & node (Join-Path $PSScriptRoot 'setup-google-cloud.mjs') $mode
    $result = $LASTEXITCODE
} finally {
    $env:SUPABASE_ACCESS_TOKEN = $previousToken
}
exit $result
