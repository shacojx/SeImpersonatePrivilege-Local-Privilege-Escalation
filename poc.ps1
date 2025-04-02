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

# --- Nhúng mã C# để sử dụng CreateProcessAsUserW ---
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
    public static extern bool CreateProcessAsUserW(
        IntPtr hToken,
        string lpApplicationName,
        string lpCommandLine,
        IntPtr lpProcessAttributes,
        IntPtr lpThreadAttributes,
        bool bInheritHandles,
        uint dwCreationFlags,
        IntPtr lpEnvironment,
        string lpCurrentDirectory,
        ref STARTUPINFO lpStartupInfo,
        out PROCESS_INFORMATION lpProcessInformation);
    
    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool OpenProcessToken(
        IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);
}
"@
Add-Type -TypeDefinition $createProcessSource

# --- Mở token của tiến trình hiện tại ---
$TOKEN_ALL_ACCESS = 0xF01FF
$hToken = [IntPtr]::Zero

$processHandle = [System.Diagnostics.Process]::GetCurrentProcess().Handle
if (![ProcessUtil]::OpenProcessToken($processHandle, $TOKEN_ALL_ACCESS, [ref] $hToken)) {
    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    Write-Error "OpenProcessToken failed with error: $err"
    exit
}
Write-Output "[*] Opened process token: $hToken"

# --- Duplicate token ---
$hDupToken = [IntPtr]::Zero
if ([TokenUtil]::DuplicateTokenEx($hToken, $TOKEN_ALL_ACCESS, [IntPtr]::Zero, 2, 1, [ref] $hDupToken)) {
    Write-Output "[*] DuplicateTokenEx succeeded. Duplicated token: $hDupToken"
} else {
    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    Write-Error "DuplicateTokenEx failed with error: $err"
    exit
}

# --- Tạo process mới với CreateProcessAsUserW ---
$si = New-Object ProcessUtil+STARTUPINFO
$si.cb = [Runtime.InteropServices.Marshal]::SizeOf($si)
$si.lpDesktop = "winsta0\\default"  # Cần để đảm bảo cửa sổ hiển thị đúng
$pi = New-Object ProcessUtil+PROCESS_INFORMATION

$cmdPath = "C:\\Windows\\System32\\cmd.exe"
$cmdLine = "/k echo Hello"

Write-Output "[*] Creating process with token. Command: $cmdLine"
$result = [ProcessUtil]::CreateProcessAsUserW($hDupToken, $cmdPath, $cmdLine, [IntPtr]::Zero, [IntPtr]::Zero, $false, 0, [IntPtr]::Zero, $null, [ref] $si, [ref] $pi)
if ($result) {
    Write-Output "[+] Process created successfully. PID: $($pi.dwProcessId)"
} else {
    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    Write-Error "CreateProcessAsUserW failed with error: $err"
}
