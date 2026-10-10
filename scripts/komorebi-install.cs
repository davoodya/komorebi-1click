// komorebi-install: the EXE entry point for the komorebi-1click installer.
//
// WHY THIS EXISTS
//   Three entry points must reach the SAME installed end state:
//     1. double-clicking this EXE,
//     2. running Install.ps1 directly,
//     3. `irm <url>/install.ps1 | iex`.
//   Entry points 1 and 2 both land on Install.ps1, which is the single source
//   of truth for the whole install. This binary only bridges the gap between a
//   double-click and that script. It holds no installer logic of its own, so
//   it cannot drift from the .ps1 path (ADR-0004).
//
// WHAT IT DOES, AND NOTHING ELSE
//   1. Locates Install.ps1 next to itself.
//   2. If it is not already elevated, relaunches itself elevated
//      (Process.Start with "runas") and waits, then forwards the child's code.
//      Needed because the MSIs require Admin. DavoodYa is NOT in
//      Administrators on the reference host, so the elevation has to be
//      requested, not assumed.
//   3. Runs the installer with -NoProfile -ExecutionPolicy Bypass and
//      -SkipElevationCheck (it already elevated, so the script's own prompt
//      would be a redundant second UAC dialog). The switch goes AFTER -File:
//      PowerShell's own argument parser owns everything before -File and
//      rejects an unknown switch there, so the ordering is load-bearing.
//   4. Forwards the installer's exit code verbatim. Exit 0 is success, and the
//      installer uses 1/2/3/4/10 to say exactly which stage failed. Swallowing
//      it once reported a broken install as a success, so it is returned
//      unchanged.
//
// WHY A SEPARATE .cs AND NOT ps2exe
//   ps2exe wraps a script in a generated host whose UAC handling and exit-code
//   behaviour are not ours to control, and ADR-0004 rejected both it and Inno
//   Setup. ~20 KB of hand-written C# over the inbox Windows API has no
//   target-machine dependency: csc.exe is a BUILD-time tool only.
//
// POWERSHELL CHOICE
//   ADR-0004 specifies pwsh. A target machine may only have the inbox Windows
//   PowerShell 5.1, and Install.ps1 is written to run on either, so pwsh is
//   preferred when present and powershell.exe is the fallback. Falling back is
//   strictly better than failing on a machine that has no pwsh at all.

using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Principal;
using System.Windows.Forms;

internal static class Program
{
    // Exit codes the wrapper itself produces. They deliberately do not collide
    // with the installer's 1/2/3/4/10: a wrapper failure is a different class
    // of problem from an install failure.
    private const int ExitOk             = 0;
    private const int ExitSelfFailed     = 1;
    private const int ExitNoShell        = 3;
    private const int ExitNoInstaller    = 4;
    private const int ExitElevateRefused = 5;

    private const string InstallerFileName = "Install.ps1";
    private const string InstallerSwitch   = "-SkipElevationCheck";

    private static int Main(string[] args)
    {
        try
        {
            string selfDir = SelfDirectory();
            if (selfDir == null)
            {
                Report("could not determine this executable's own directory");
                return ExitSelfFailed;
            }

            string installer = Path.Combine(selfDir, InstallerFileName);
            if (!File.Exists(installer))
            {
                // The commonest cause is the EXE being copied away from the
                // repository. Say exactly where it looked, because the fix is
                // to keep the two files together.
                Report("Install.ps1 was not found next to this executable."
                     + Environment.NewLine + "  looked in: " + selfDir
                     + Environment.NewLine + "  expected : " + installer
                     + Environment.NewLine
                     + "  Install.ps1 and this EXE must stay in the same folder.");
                return ExitNoInstaller;
            }

#if !K1C_TEST_FORCE_ELEVATED
            // Already elevated (the relaunch above, or an admin double-click)?
            // Then run the installer directly.
            if (!IsElevated())
            {
                // Not elevated: ask for it, wait, and forward the child's
                // code.
                return RelaunchElevated(selfDir, installer, args);
            }
#else
            // Build-time hook for the wrapper test: K1C_TEST_FORCE_ELEVATED
            // jumps straight to RunInstaller so a test can EXECUTE the built
            // binary without a UAC prompt. Production builds never define it.
#endif
            return RunInstaller(installer, args);
        }
        catch (Exception ex)
        {
            Report(ex.ToString());
            return ExitSelfFailed;
        }
    }

    // -----------------------------------------------------------------------
    // Elevation
    // -----------------------------------------------------------------------
    private static bool IsElevated()
    {
        try
        {
            using (WindowsIdentity id = WindowsIdentity.GetCurrent())
            {
                return new WindowsPrincipal(id).IsInRole(WindowsBuiltInRole.Administrator);
            }
        }
        catch { return false; }
    }

    private static int RelaunchElevated(string selfDir, string installer, string[] args)
    {
        string selfExe = Assembly.GetExecutingAssembly().Location;
        if (string.IsNullOrEmpty(selfExe) || !File.Exists(selfExe))
        {
            Report("could not determine this executable's own path for the elevated relaunch");
            return ExitSelfFailed;
        }

        var psi = new ProcessStartInfo
        {
            FileName = selfExe,
            Arguments = BuildArgs(args),
            // "runas" is what makes Windows show the UAC prompt. It requires
            // shell execution, so UseShellExecute must stay true here even
            // though the non-elevated path turns it off.
            UseShellExecute = true,
            Verb = "runas",
            WorkingDirectory = selfDir,
        };

        try
        {
            using (Process child = Process.Start(psi))
            {
                if (child == null)
                {
                    Report("the elevated relaunch did not start");
                    return ExitSelfFailed;
                }
                child.WaitForExit();
                return child.ExitCode;
            }
        }
        catch (System.ComponentModel.Win32Exception ex)
        {
            // Native error 1223 is ERROR_CANCELLED: the user dismissed the UAC
            // dialog. That is a deliberate choice, not a crash, so it gets its
            // own exit code and a plain-English message.
            if (ex.NativeErrorCode == 1223)
            {
                Report("elevation was declined, so the install did not run.");
                return ExitElevateRefused;
            }
            Report("could not request elevation: " + ex.Message);
            return ExitSelfFailed;
        }
    }

    // -----------------------------------------------------------------------
    // Running the installer
    // -----------------------------------------------------------------------
    private static int RunInstaller(string installer, string[] args)
    {
        string shell = FindPowerShell();
        if (shell == null)
        {
            Report("neither pwsh.exe nor powershell.exe could be found."
                 + Environment.NewLine
                 + "  Windows PowerShell 5.1 ships with every supported Windows"
                 + Environment.NewLine
                 + "  version, so this normally means a broken or hardened PATH.");
            return ExitNoShell;
        }

        string quotedInstaller = "\"" + installer + "\"";
        // -SkipElevationCheck is a PARAMETER OF THE INSTALLER SCRIPT, so it
        // must come AFTER -File. Before the fix (2026-10-10) it sat between
        // -ExecutionPolicy and -File, where PowerShell's own launcher parser
        // rejected it ("The term '-SkipElevationCheck' is not recognized"),
        // exited 1/64 and never ran the installer - invisible to the user,
        // because this GUI wrapper has no console to show the error in.
        var psi = new ProcessStartInfo
        {
            FileName = shell,
            UseShellExecute = false,
            // Capture the shell's own stderr so a launch failure lands in the
            // log instead of disappearing: this wrapper has no console, so
            // anything PowerShell prints before the installer starts would
            // otherwise be seen by nobody. The installer's own output is not
            // redirected, so its console window still reaches the user.
            RedirectStandardError = true,
            // Wait for the installer's real console window; the wrapper has no
            // console of its own, so the output must go straight to the user.
            Arguments = "-NoProfile -ExecutionPolicy Bypass -File " + quotedInstaller
                      + " " + InstallerSwitch + " " + BuildArgs(args),
            WorkingDirectory = Path.GetDirectoryName(installer),
        };

        using (Process child = Process.Start(psi))
        {
            if (child == null)
            {
                Report("the installer process did not start");
                return ExitSelfFailed;
            }
            // Drain stderr before WaitForExit so a chatty shell can never
            // deadlock the wrapper on a full pipe.
            string shellError = child.StandardError.ReadToEnd();
            child.WaitForExit();
            int code = child.ExitCode;
            if (code != 0 && !string.IsNullOrWhiteSpace(shellError))
            {
                // The shell ran but failed without the installer reporting
                // (e.g. it rejected the argument list again). Say so, instead
                // of silently forwarding a bare exit code to nothing.
                Log("PowerShell host exited " + code
                    + " without running the installer. stderr: " + shellError);
                Report("The PowerShell host did not run the installer (exit code "
                     + code + ")." + Environment.NewLine
                     + "Details were written to "
                     + Path.Combine(Path.GetTempPath(), "komorebi-install.log")
                     + ".");
            }
            // Forwarded verbatim. The installer uses 1/2/3/4/10 to name the
            // failing stage and 0 for success; the wrapper adds nothing.
            return code;
        }
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------
    private static string SelfDirectory()
    {
        try
        {
            string loc = Assembly.GetExecutingAssembly().Location;
            if (string.IsNullOrEmpty(loc)) return null;
            return Path.GetDirectoryName(loc);
        }
        catch { return null; }
    }

    // Prefer pwsh (PowerShell 7) as ADR-0004 specifies, then fall back to the
    // inbox Windows PowerShell 5.1, which is guaranteed to exist on a target
    // machine that has never seen PowerShell 7. Both run Install.ps1: the
    // script is written to Windows PowerShell 5.1 compatibility throughout.
    private static string FindPowerShell()
    {
        string sys = Environment.GetFolderPath(Environment.SpecialFolder.System);
        string[] preferred =
        {
            Path.Combine(sys, "PowerShell", "7", "pwsh.exe"),
            @"C:\Program Files\PowerShell\7\pwsh.exe",
            Path.Combine(sys, "WindowsPowerShell", "v1.0", "powershell.exe"),
        };
        foreach (string f in preferred)
            if (File.Exists(f)) return f;

        string path = Environment.GetEnvironmentVariable("PATH") ?? "";
        foreach (string dir in path.Split(';'))
        {
            if (string.IsNullOrWhiteSpace(dir)) continue;
            try
            {
                string p = Path.Combine(dir.Trim(), "pwsh.exe");
                if (File.Exists(p)) return p;
            }
            catch { }
        }
        foreach (string dir in path.Split(';'))
        {
            if (string.IsNullOrWhiteSpace(dir)) continue;
            try
            {
                string p = Path.Combine(dir.Trim(), "powershell.exe");
                if (File.Exists(p)) return p;
            }
            catch { }
        }
        return null;
    }

    // .NET Framework's ProcessStartInfo has no ArgumentList, so the argument
    // string is built here. Only quote when the value actually needs it, and
    // refuse to quote a value that already contains a quote.
    private static string BuildArgs(string[] args)
    {
        if (args == null || args.Length == 0) return "";
        var sb = new System.Text.StringBuilder();
        foreach (string a in args)
        {
            if (a == null) continue;
            if (sb.Length > 0) sb.Append(' ');
            if (a.Length > 0 && a.IndexOf(' ') >= 0 && a.IndexOf('"') < 0)
                sb.Append('"').Append(a).Append('"');
            else
                sb.Append(a);
        }
        return sb.ToString();
    }

    // A GUI-subsystem binary has no console, so errors must be shown some other
    // way. A message box is the only option a double-clicking user will see.
    private static void Report(string message)
    {
        try
        {
            Log(message);
            MessageBox.Show(message, "komorebi-1click installer",
                            MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        catch { }
    }

    private static void Log(string message)
    {
        try
        {
            File.AppendAllText(
                Path.Combine(Path.GetTempPath(), "komorebi-install.log"),
                DateTime.Now.ToString("s") + " " + message + Environment.NewLine);
        }
        catch { }
    }
}
