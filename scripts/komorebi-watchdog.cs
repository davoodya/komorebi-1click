// komorebi-watchdog: a windowless launcher for the komorebi watchdog task.
//
// WHY THIS EXISTS
//   The watchdog is a Windows scheduled task that runs every few minutes to
//   restart komorebi/whkd if they died. It was launched as:
//
//       powershell.exe -NoProfile -WindowStyle Hidden ... -File ... -Action watchdog
//
//   Task Scheduler creates a console for powershell.exe FIRST and only hides
//   it afterwards, so a CMD/PowerShell window flashes on screen every time
//   the task fires. -WindowStyle Hidden does not prevent that.
//
//   This binary is compiled as a GUI-subsystem app, so Windows never gives it
//   a console at all. It forwards every argument to the real powershell.exe
//   and waits, so the watchdog logic is unchanged.
//
// WHY NOT DO THE SAME FOR whkd
//   whkd's `.shell` line is parsed strictly and rejects every form except a
//   bare `powershell`, so a GUI launcher cannot be injected there. The blink
//   that remained came from this task, not from hotkey presses: a keypress
//   would flash once per press, whereas the blink was observed only once or
//   twice, matching this task's interval.

using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;

internal static class Program
{
    private static int Main(string[] args)
    {
        try
        {
            string real = FindRealPowerShell();
            if (real == null) { Log("could not locate the real powershell.exe"); return 3; }

            var psi = new ProcessStartInfo
            {
                FileName = real,
                UseShellExecute = false,
                CreateNoWindow = true,           // belt and braces
                WindowStyle = ProcessWindowStyle.Hidden,
                Arguments = BuildArgs(args),
            };

            using (Process p = Process.Start(psi))
            {
                if (p == null) return 4;
                p.WaitForExit();
                return p.ExitCode;
            }
        }
        catch (Exception ex) { Log(ex.ToString()); return 1; }
    }

    // .NET Framework's ProcessStartInfo has no ArgumentList, so build the
    // string ourselves, re-quoting only what actually needs it.
    private static string BuildArgs(string[] args)
    {
        var sb = new System.Text.StringBuilder();
        foreach (string a in args)
        {
            if (sb.Length > 0) sb.Append(' ');
            if (a.Length > 0 && a.IndexOf(' ') >= 0 && a.IndexOf('"') < 0)
                sb.Append('"').Append(a).Append('"');
            else
                sb.Append(a);
        }
        return sb.ToString();
    }

    // Find the genuine powershell.exe, never this launcher itself.
    private static string FindRealPowerShell()
    {
        string selfDir = "";
        try { selfDir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location) ?? ""; }
        catch { }

        string sys = Environment.GetFolderPath(Environment.SpecialFolder.System);
        string[] fixedPaths =
        {
            Path.Combine(sys, "WindowsPowerShell", "v1.0", "powershell.exe"),
            @"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe",
        };
        foreach (string f in fixedPaths)
            if (File.Exists(f)) return f;

        string path = Environment.GetEnvironmentVariable("PATH") ?? "";
        foreach (string dir in path.Split(';'))
        {
            if (string.IsNullOrWhiteSpace(dir)) continue;
            try
            {
                string d = dir.Trim();
                if (string.Equals(d, selfDir, StringComparison.OrdinalIgnoreCase)) continue;
                string c = Path.Combine(d, "powershell.exe");
                if (File.Exists(c)) return c;
            }
            catch { }
        }
        return null;
    }

    private static void Log(string msg)
    {
        try
        {
            File.AppendAllText(Path.Combine(Path.GetTempPath(), "komorebi-watchdog.log"),
                DateTime.Now.ToString("s") + " " + msg + Environment.NewLine);
        }
        catch { }
    }
}
