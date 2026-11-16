param(
    [int]$Width = 1280,
    [int]$Height = 720,
    [switch]$Current,
    [switch]$Probe,
    [switch]$Restore,
    [switch]$Fullscreen,
    [switch]$Borderless,
    [switch]$Windowed,
    [switch]$TrustClassOnly,
    [switch]$NoClassFilter,
    [string[]]$ClassName = @("UnityWndClass")
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if ($Width -lt 1 -or $Height -lt 1) {
    Write-Host "错误：宽高必须为正整数"
    exit 2
}

Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class Win32Langrisser {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetParent(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsZoomed(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(
        IntPtr hWnd, IntPtr hWndInsertAfter,
        int X, int Y, int cx, int cy, uint uFlags);

    [DllImport("user32.dll")]
    public static extern int GetSystemMetrics(int nIndex);

    [DllImport("user32.dll")]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll")]
    public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    public const int SW_RESTORE = 9;

    public const uint SWP_NOSIZE       = 0x0001;
    public const uint SWP_NOMOVE       = 0x0002;
    public const uint SWP_NOZORDER     = 0x0004;
    public const uint SWP_NOACTIVATE   = 0x0010;
    public const uint SWP_FRAMECHANGED = 0x0020;

    public const int GWL_STYLE      = -16;
    public const int SM_CXSCREEN    = 0;
    public const int SM_CYSCREEN    = 1;
    public const int WS_CAPTION     = 0x00C00000;
    public const int WS_THICKFRAME  = 0x00040000;
    public const int WS_MINIMIZEBOX = 0x00020000;
    public const int WS_MAXIMIZEBOX = 0x00010000;
    public const int WS_SYSMENU     = 0x00080000;

    public static List<IntPtr> Find(string[] keys, string[] classes) {
        var list = new List<IntPtr>();

        EnumWindowsProc cb = delegate(IntPtr h, IntPtr l) {
            if (h == IntPtr.Zero) return true;
            if (!IsWindowVisible(h)) return true;
            if (GetParent(h) != IntPtr.Zero) return true;

            int n = GetWindowTextLength(h);
            bool hasKeys = (keys != null && keys.Length > 0);

            var sb = new StringBuilder(n + 1);
            GetWindowText(h, sb, n + 1);
            string title = sb.ToString();

            if (hasKeys) {
                if (n <= 0) return true;
                bool titleOk = false;
                foreach (string k in keys) {
                    if (title.Contains(k)) { titleOk = true; break; }
                }
                if (!titleOk) return true;
            }

            if (classes != null && classes.Length > 0) {
                var cb2 = new StringBuilder(256);
                GetClassName(h, cb2, 256);
                string cls = cb2.ToString();

                bool clsOk = false;
                foreach (string c in classes) {
                    if (string.Equals(cls, c, StringComparison.Ordinal)) {
                        clsOk = true;
                        break;
                    }
                }
                if (!clsOk) return true;
            }

            list.Add(h);
            return true;
        };

        EnumWindows(cb, IntPtr.Zero);
        return list;
    }

    public static string Title(IntPtr h) {
        int n = GetWindowTextLength(h);
        var sb = new StringBuilder(n + 1);
        GetWindowText(h, sb, n + 1);
        return sb.ToString();
    }

    public static string ClassName(IntPtr h) {
        var sb = new StringBuilder(256);
        GetClassName(h, sb, 256);
        return sb.ToString();
    }

    public static int[] WindowSize(IntPtr h) {
        RECT r;
        GetWindowRect(h, out r);
        return new int[] { r.Right - r.Left, r.Bottom - r.Top };
    }

    public static int[] ClientSize(IntPtr h) {
        RECT r;
        GetClientRect(h, out r);
        return new int[] { r.Right, r.Bottom };
    }

    public static int[] Pos(IntPtr h) {
        RECT r;
        GetWindowRect(h, out r);
        return new int[] { r.Left, r.Top };
    }

    public static int[] ScreenSize() {
        return new int[] { GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN) };
    }

    public static void SetSize(IntPtr h, int w, int hgt) {
        if (!SetWindowPos(h, IntPtr.Zero, 0, 0, w, hgt,
            SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE))
            throw new System.ComponentModel.Win32Exception();
    }

    public static int[] ForceClient(IntPtr h, int tw, int th, int maxIter) {
        for (int i = 0; i < maxIter; i++) {
            int[] c = ClientSize(h);
            if (c[0] == tw && c[1] == th)
                return new int[] { i, c[0], c[1] };

            int[] w = WindowSize(h);
            int nw = w[0] + (tw - c[0]);
            int nh = w[1] + (th - c[1]);

            if (nw < 1 || nh < 1)
                throw new Exception("推算出的窗口尺寸非法");

            SetSize(h, nw, nh);
        }

        int[] cc = ClientSize(h);
        return new int[] { maxIter, cc[0], cc[1] };
    }

    private static void StripFrame(IntPtr h) {
        int style = GetWindowLong(h, GWL_STYLE);
        style &= ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU);
        SetWindowLong(h, GWL_STYLE, style);
    }

    private static void AddFrame(IntPtr h) {
        int style = GetWindowLong(h, GWL_STYLE);
        style |= (WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU);
        SetWindowLong(h, GWL_STYLE, style);
    }

    public static int[] ForceFullscreen(IntPtr h) {
        int[] s = ScreenSize();
        StripFrame(h);
        if (!SetWindowPos(h, IntPtr.Zero, 0, 0, s[0], s[1],
            SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED))
            throw new System.ComponentModel.Win32Exception();
        return new int[] { s[0], s[1] };
    }

    public static int[] ForceBorderless(IntPtr h, int tw, int th) {
        int[] s = ScreenSize();
        int x = (s[0] - tw) / 2;
        int y = (s[1] - th) / 2;
        if (x < 0) x = 0;
        if (y < 0) y = 0;
        StripFrame(h);
        if (!SetWindowPos(h, IntPtr.Zero, x, y, tw, th,
            SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED))
            throw new System.ComponentModel.Win32Exception();
        return new int[] { x, y };
    }

    public static void RestoreFrame(IntPtr h) {
        AddFrame(h);
        if (!SetWindowPos(h, IntPtr.Zero, 0, 0, 0, 0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED))
            throw new System.ComponentModel.Win32Exception();
    }
}
"@

# ---- 找窗口 ----
if ($TrustClassOnly) {
    $keys = @()
} else {
    $keys = @("梦幻模拟战", "Langrisser")
}

if ($NoClassFilter) {
    $classes = @()
} else {
    $classes = $ClassName
}

$wins = @([Win32Langrisser]::Find($keys, $classes))

if ($wins.Count -eq 0) {
    Write-Host "未找到标题含『梦幻模拟战 / Langrisser』且类名匹配的可见顶层窗口。"
    Write-Host "  - 请先启动游戏"
    Write-Host "  - 若类名不是 UnityWndClass，用 -ClassName 指定"
    Write-Host "  - 也可加 -TrustClassOnly 只按类名匹配"
    exit 1
}

function Show-WindowInfo($h, $tag) {
    $win = [Win32Langrisser]::WindowSize($h)
    $cli = [Win32Langrisser]::ClientSize($h)
    $pos = [Win32Langrisser]::Pos($h)

    $state = @()
    if ([Win32Langrisser]::IsIconic($h)) { $state += "最小化" }
    if ([Win32Langrisser]::IsZoomed($h)) { $state += "最大化" }
    $st = "普通"
    if ($state.Count -gt 0) { $st = $state -join "/" }

    $title = [Win32Langrisser]::Title($h)
    $cls = [Win32Langrisser]::ClassName($h)

    Write-Host ("  [{0}] 标题={1}  窗口类={2}  状态={3}" -f $tag, $title, $cls, $st)
    Write-Host ("       窗口整体={0}x{1}  客户区={2}x{3}  位置=({4},{5})" -f `
        $win[0], $win[1], $cli[0], $cli[1], $pos[0], $pos[1])
}

function Ensure-Restored($h) {
    if ([Win32Langrisser]::IsIconic($h) -or [Win32Langrisser]::IsZoomed($h)) {
        if ($Restore) {
            [Win32Langrisser]::ShowWindow($h, 9) | Out-Null
            Start-Sleep -Milliseconds 100
            Write-Host "  已恢复窗口为普通状态"
        } else {
            Write-Host "  注意：窗口最小化/最大化，尺寸调整可能不生效，可加 -Restore"
        }
    }
}

Write-Host ("找到 {0} 个匹配窗口：" -f $wins.Count)
foreach ($h in $wins) { Show-WindowInfo $h "当前" }

if ($Probe) {
    Write-Host "`n-Probe：仅查询，未做任何修改。"
    exit 0
}

# ---- 全屏 ----
if ($Fullscreen) {
    foreach ($h in $wins) {
        $title = [Win32Langrisser]::Title($h)
        Write-Host "`n[全屏] $title"
        Ensure-Restored $h

        $res = [Win32Langrisser]::ForceFullscreen($h)
        Start-Sleep -Milliseconds 150

        $cli = [Win32Langrisser]::ClientSize($h)
        Write-Host ("  屏幕={0}x{1}  实际客户区={2}x{3}" -f $res[0], $res[1], $cli[0], $cli[1])
        if ($cli[0] -ne $res[0] -or $cli[1] -ne $res[1]) {
            Write-Host "  ⚠ 客户区未等于屏幕尺寸，游戏可能拒绝改样式"
            exit 1
        }
    }
    Write-Host "`n完成：已设为无边框全屏（客户区 = 屏幕分辨率）。"
    exit 0
}

# ---- 无边框窗口（保留客户区尺寸，视觉上像全屏） ----
if ($Borderless) {
    foreach ($h in $wins) {
        $title = [Win32Langrisser]::Title($h)
        Write-Host ("`n[无边框] {0}  目标客户区={1}x{2}" -f $title, $Width, $Height)
        Ensure-Restored $h

        $pos = [Win32Langrisser]::ForceBorderless($h, $Width, $Height)
        Start-Sleep -Milliseconds 150

        $cli = [Win32Langrisser]::ClientSize($h)
        Write-Host ("  窗口位置=({0},{1})  实际客户区={2}x{3}" -f $pos[0], $pos[1], $cli[0], $cli[1])
        if ($cli[0] -ne $Width -or $cli[1] -ne $Height) {
            Write-Host "  ⚠ 客户区未等于目标，可再跑一次默认模式微调"
        }
    }
    Write-Host ("`n完成：已设为无边框窗口（客户区 {0}x{1}）。" -f $Width, $Height)
    exit 0
}

# ---- 恢复窗口化 ----
if ($Windowed) {
    foreach ($h in $wins) {
        $title = [Win32Langrisser]::Title($h)
        Write-Host "`n[恢复窗口化] $title"
        Ensure-Restored $h

        [Win32Langrisser]::RestoreFrame($h)
        Start-Sleep -Milliseconds 150

        $before = [Win32Langrisser]::ClientSize($h)
        $null   = [Win32Langrisser]::ForceClient($h, $Width, $Height, 4)
        $cli    = [Win32Langrisser]::ClientSize($h)

        Write-Host ("  调整前客户区={0}x{1} → 调整后={2}x{3}" -f `
            $before[0], $before[1], $cli[0], $cli[1])
        if ($cli[0] -ne $Width -or $cli[1] -ne $Height) {
            Write-Host "  ⚠ 未精确收敛到目标"
        }
    }
    Write-Host ("`n完成：窗口已恢复边框并调整到客户区 {0}x{1}。" -f $Width, $Height)
    exit 0
}

# ---- 默认模式：只调客户区，不动样式 ----
if ($Current) {
    $tgt = [Win32Langrisser]::ClientSize($wins[0])
    $targetW = $tgt[0]
    $targetH = $tgt[1]
    Write-Host ("`n-Current：以窗口此刻客户区 {0}x{1} 作为目标。" -f $targetW, $targetH)
} else {
    $targetW = $Width
    $targetH = $Height
    Write-Host ("`n目标客户区分辨率：{0}x{1}" -f $targetW, $targetH)
}

foreach ($h in $wins) {
    $title = [Win32Langrisser]::Title($h)
    Ensure-Restored $h

    $before = [Win32Langrisser]::ClientSize($h)
    if ($before[0] -eq $targetW -and $before[1] -eq $targetH) {
        Write-Host ("  [{0}] 客户区已是 {1}x{2}，无需改动。" -f $title, $before[0], $before[1])
        continue
    }

    $res = [Win32Langrisser]::ForceClient($h, $targetW, $targetH, 4)
    $cli = [Win32Langrisser]::ClientSize($h)
    $win = [Win32Langrisser]::WindowSize($h)
    $pos = [Win32Langrisser]::Pos($h)

    Write-Host ("  [{0}] 调整前客户区={1}x{2} → 调整后={3}x{4}（迭代 {5} 次）" -f `
        $title, $before[0], $before[1], $cli[0], $cli[1], $res[0])
    Write-Host ("       最终窗口整体={0}x{1}  位置=({2},{3})" -f $win[0], $win[1], $pos[0], $pos[1])

    if ($cli[0] -ne $targetW -or $cli[1] -ne $targetH) {
        Write-Host "  ⚠ 未精确收敛到目标，游戏可能限制了窗口尺寸"
        exit 1
    }
}

Write-Host ("`n完成：客户区已调整为 {0}x{1}。" -f $targetW, $targetH)
exit 0