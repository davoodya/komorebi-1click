# SCRIPTS-GUIDE — Komorebi + WHKD + YASB

> **⚠ Read this before restarting whkd.**
> If hotkeys are dead but the YASB bar still shows workspaces, do NOT restart
> whkd — that cannot fix it. whkd must be spawned by `komorebic start --whkd`;
> started any other way it registers every hotkey and then drops every command
> (LGUG2Z/komorebi#956). The repair is `komorebic stop --whkd`, clear the stale
> socket/hwnd state, then `komorebic start --whkd`.
> `Get-Health` / `4-STATUS.bat` reports this as `whkd PAIRING`.
> Full write-up: `docs/POSTMORTEM-20261004-whkd-pairing.md`.

> **⚠ And before you start komorebi from a script.**
> An unelevated komorebi cannot manage elevated windows, so a restart run from
> a non-elevated shell drops every elevated window and the Hermes window out of
> the layout. `restart-whkd.ps1` and `safe-restart.ps1` handle this: when they
> are not already elevated they stop the pair and trigger the installer's
> `Komorebi` logon task (RunLevel Highest) to bring it back elevated. Never
> replace that with a plain `Start-Process komorebic.exe start --whkd`.

> **⚠ Installer failures.**
> Komorebi and WHKD are primary — a failure aborts the install. YASB and
> AutoHotkey are secondary — a failure is reported with its cause and remedy and
> the install continues. Re-running the installer reinstalls only what failed,
> because every step detects what is already installed and skips it.
> Details: `docs/INSTALL-FAILURE-HANDLING.md`.

> Every script in this directory is SAFE and tested against the current
> configuration (komorebi 0.1.41 / whkd 0.2.10 / yasb). Each `.bat` is a
> user-friendly wrapper for one `.ps1`.
>
> **دایرکتوری معادل در WSL:** `~/Obsidian/Hermes/Knowledge/Windows/komorebi/final-scripts`
> **دایرکتوری اصلی (قدیمی):** `F:\Backups\Software-Backups\komorebi-whkd\managements` (هنوز پابرجاست؛ فقط نسخه‌های قدیمی در آن است)

---

## ⭐ اسکریپت اصلی — همیشه از این استفاده کن

| اسکریپت | کارکرد |
|---|---|
| **`0-SAFE-RESTART.bat`** | **_restart + reload komorebi, whkd و yasb.** تنها اسکریپتی است که باید برای اعمال تغییر در کانفیگ اجرا کنی. watchdog را برای کل پنجره‌ی restart غیرفعال می‌کند (جلوگیری از double-start race)، از پنجره‌های tile‌شده snapshot می‌گیرد و پس از restart تأیید می‌کند هیچ پنجره‌ای جا نمانده، و ترتیب workspaceها را per-monitor گزارش می‌دهد. موتور: `safe-restart.ps1`. |

> ⚠️ **`1-RUN-RESTART.bat` حذف شد.** آن اسکریپت علت از کار افتادن workspaceها بود: watchdog race + pipe inheritance hang. جایگزین safe آن `0-SAFE-RESTART.bat` است.

---

## ۱. Startup و سرویس

| اسکریپت | کارکرد |
|---|---|
| `2-ADD-TO-STARTUP.bat` | komorebi + whkd را به startup ویندوز اضافه می‌کند (logon scheduled task + watchdog task). Idempotent — اجرای مجدد بی‌ضرر است. موتور: `komorebi-service.ps1 -Action install`. |
| `3-REMOVE-FROM-STARTUP.bat` | scheduled taskها را حذف می‌کند تا komorebi دیگر با بوت اجرا نشود. session در حال اجرا را متوقف نمی‌کند. موتور: `komorebi-service.ps1 -Action uninstall`. |
| `4-STATUS.bat` | **Read-only.** گزارش سلامت: processها، socket، مانیتورها، layouts، hotkeys، و هر مشکلی که باید بدانی. موتور: `komorebi-service.ps1 -Action status`. |

---

## ۲. Restart سرویس‌ها

| اسکریپت | کارکرد |
|---|---|
| `A-RESTART-ALL.bat` | restart komorebi + whkd + yasb با هم (نسخه‌ی سبک‌تر از 0-SAFE-RESTART). موتور: `restart-all.ps1`. |
| `B-RESTART-KOMOREBI.bat` | **فقط komorebi** — برای اعمال `komorebi.json` تغییر یافته. watchdog-safe. موتور: `restart-komorebi.ps1`. |
| `C-RESTART-WHKD.bat` | **فقط whkd** — برای اعمال `whkdrc` تغییر یافته. watchdog-safe. موتور: `restart-whkd.ps1`. |
| `D-RESTART-YASB.bat` | **فقط yasb** — برای اعمال `config.yaml` تغییر یافته. PATH را از registry بازسازی می‌کند (تا event listener بتواند `komorebic.exe` را پیدا کند) و verdict اتصال را از log چاپ می‌کند. موتور: `restart-yasb.ps1`. |
| ~~`7-YASB-RESTART.ps1`~~ | **REMOVED — merged into `restart-yasb.ps1`.** Its diagnosis half is now the `-DiagnoseOnly` switch on `restart-yasb.ps1` (prints the registry-vs-inherited PATH status and how YASB is registered at logon, then exits without restarting). Use `D-RESTART-YASB.bat` to restart, or `powershell -File restart-yasb.ps1 -DiagnoseOnly` to diagnose only. |

> **چرا restart کامل yasb به‌جای hot-reload؟** YASB در زمان launch، PATH خود را می‌خواند. اگر آن PATH قدیمی‌تر از نصب komorebi باشد، `komorebic.exe` پیدا نمی‌شود و widgetهای komorebi می‌میرند. علاوه بر این `watch_config` ویرایش‌های انجام‌شده از WSL (drvfs) را نمی‌بیند.

---

## ۳. Start و Stop

| اسکریپت | کارکرد |
|---|---|
| `9-START-ALL.bat` | komorebi + whkd + yasb را (در صورت اجرا نبودن) اجرا می‌کند. komorebi اول اجرا می‌شود چون whkd/yasb با socket آن صحبت می‌کنند. موتور: `start-all.ps1`. |
| `8-KILL-ALL.bat` | komorebi + whkd + yasb را کاملاً متوقف می‌کند. پنجره‌ها سرجایشان می‌مانند. watchdog آن‌ها را برنمی‌گرداند — برای بازگرداندن `9-START-ALL.bat` را اجرا کن. موتور: `kill-all.ps1`. |

---

## ۴. Workspaces و Monitors

| اسکریپت | کارکرد |
|---|---|
| `5-RESET-WORKSPACES.bat` | ترتیب workspaceها را روی همه‌ی مانیتورها دوباره ۱..۹ می‌کند. komorebi workspaceها را به‌صورت یک vector نگه می‌دارد که با جابجایی بین workspaceها order آن عوض می‌شود و `retile` آن را مرتب نمی‌کند — تنها راه، stop/start کامل است که این اسکریپت watchdog-safe انجام می‌دهد. موتور: `reset-workspaces.ps1`. |
| `6-DISPLAY-DIAG.bat` | **Read-only.** geometry مانیتورها را در سه منبع مقایسه می‌کند: `EnumDisplaySettings` (native pixels)، Windows Forms (DPI-scaled)، و komorebi. برای زمانی که `4-STATUS` مانیتوری با عرض منفی نشان می‌دهد. موتور: `display-diag.ps1`. |
| `E-RECOVER-MONITORS.bat` | **بعد از plug/unplug یا روشن/خاموش کردن مانیتور** اجرا کن. پنجره‌های orphan را restore می‌کند، display index preferences را دوباره اعمال می‌کند، و retile می‌کند. موتور: `recover-monitors.ps1`. |

---

## ۵. Config Backup و Restore

| اسکریپت | کارکرد |
|---|---|
| `EXPORT-CONFIG.bat` | کانفیگ زنده (whkdrc, komorebi.json, applications.json, restart-whkd.cmd, toggle-transparency.ps1, komorebi-watchdog.*) را داخل `F:\Backups\Software-Backups\komorebi-whkd\config` کپی می‌کند. **Read-only برای سیستم.** موتور: `komorebi-backup.ps1 -Mode export`. |
| `IMPORT-CONFIG.bat` | کانفیگ را از backup folder بازمی‌گرداند. **ابتدا کانفیگ فعلی را به پوشه‌ی `pre-import-<timestamp>` کپی می‌کند، پس همیشه قابل بازگشت است.** سپس WM را stop می‌کند، فایل‌ها را جایگزین می‌کند، و دوباره start می‌کند. موتور: `komorebi-backup.ps1 -Mode import`. |

---

## ۶. Uninstall و Cleanup

| اسکریپت | کارکرد |
|---|---|
| `UNINSTALL-KOMOREBI-WHKD.bat` | **komorebi + whkd (نرم‌افزار) را حذف می‌کند.** scheduled taskها را برمی‌دارد، processها را stop می‌کند، و از طریق MSI uninstallentries پکیج‌ها را حذف می‌کند (winget روی این ماشین hangs). **کانفیگ‌ها دست نخورده باقی می‌مانند.** موتور: `uninstall-komorebi-whkd.ps1`. |
| `CLEANUP-KOMOREBI-WHKD.bat` | **بعد از UNINSTALL اجرا کن.** هر trace باقی‌مانده را پاک می‌کند: install directories، config files، state و logs، helper binaries، و PATH entries. ابتدا یک safety copy از کانفیگ‌ها کنار خود اسکریپت می‌نویسد و کلمه‌ی `DELETE` را می‌خواهد. موتور: `cleanup-komorebi-whkd.ps1`. |
| `AHK-UNINSTALL.bat` | **AutoHotkey v1 و v2 (نرم‌افزار) را حذف می‌کند.** interpreter processها را stop می‌کند، MSI uninstall را اجرا می‌کند، و `AppRunner.vbs` تولیدشده را از Startup برمی‌دارد. **اسکریپت‌های `.ahk` در repository دست نخورده می‌مانند.** موتور: `ahk-uninstall.ps1`. |
| `AHK-CLEANUP.bat` | **بعد از UNINSTALL اجرا کن.** leftover‌های فضای کاربر را پاک می‌کند: `AppRunner.vbs` تولیدشده، فایل وضعیت enable/disable، و هر process در حال اجرای یکی از اسکریپت‌های این repo. **interpreterها را حذف نمی‌کند.** موتور: `ahk-cleanup.ps1`. |

---

## ۶ب. AutoHotkey lifecycle (تیکت ۰۸)

این چهار اسکریپت AutoHotkey را به یک بخش first-class از محیط تبدیل می‌کنند:

| اسکریپت | کارکرد |
|---|---|
| `AHK-SCRIPT.bat` | **یک اسکریپت را enable/disable می‌کند.** بدون آرگومان: لیست سه اسکریپت همراه با وضعیت فعلی. با آرگومان: `AHK-SCRIPT.bat NewFile disabled` خط مربوطه را در `AppRunner.vbs` کامنت می‌کند، process را فوراً kill می‌کند، و state را در `autohotkey\ahk-state.json` ذخیره می‌کند تا در logon بعدی هم off بماند. موتور: `ahk-script.ps1`. |
| `AHK-TOGGLE-ALL.bat` | **همه‌ی سه اسکریپت را یکجا روشن یا خاموش می‌کند.** `AHK-TOGGLE-ALL.bat disabled` هر سه را disable می‌کند. موتور: `ahk-toggle.ps1`. |
| `AHK-CLEANUP.bat` | leftover‌ها (همان ردیف بالا). |
| `AHK-UNINSTALL.bat` | uninstall (همان ردیف بالا). |

**نکته‌ی مهم:** این اسکریپت‌ها فقط اسکریپت‌های موجود در `autohotkey\` همین repository را مدیریت می‌کنند. هر اسکریپت AutoHotkey که کاربر از مسیر دیگری اجرا می‌کند کاملاً دست‌نخورده باقی می‌ماند — حتی اگر هم‌نام باشد.

---

## ۷. ابزارهای کمکی

| اسکریپت | کارکرد |
|---|---|
| `F-REPAIR-WHKDRC.bat` | `whkdrc` را در دقیقاً همان شکلی که whkd قبول می‌کند بازنویسی می‌کند: بدون BOM، LF line endings، فقط ASCII، و `.shell` به‌صورت bare name.Bindings باقی‌مانده حفظ می‌شوند و یک backup کنار فایل نوشته می‌شود. **برای زمانی که whkd با `could not load whkdrc` crash می‌کند.** موتور: `repair-whkdrc.ps1`. |
| `toggle-transparency.ps1` | پنجره‌ی فعال را بین ۸۵٪ شفاف و کاملاً کدر toggle می‌کند. **به hotkey `alt+ctrl+t` در whkdrc متصل است** — مستقیماً اجرا نمی‌شود. |

---

## ۸. وابستگی‌ها (مستقیماً اجرا نکن)

این فایل‌ها helper‌های مشترک یا موتورهای داخلی‌اند. wrapper‌های `.bat` آن‌ها را صدا می‌زنند:

| فایل | نقش |
|---|---|
| `common.ps1` | helper‌های مشترک: `Resolve-KomorebiExe`، `Resolve-KomorebicExe`، `Resolve-WhkdExe`، `Test-Process`، `Stop-ProcessTree`. توسط kill-all / start-all / restart-* dot-sourced می‌شود. |
| `komorebi-service.ps1` | موتور مرکزی برای install/uninstall/start/restart/status/watchdog. **این همان اسکریپتی است که watchdog scheduled task اجرا می‌کند** (از مسیر Temp کاربر). mutex-protected است تا restart هرگز با watchdog race نزند. |

---

## نکات مهم

1. **هرگز `komorebic.exe reload-configuration` را اجرا نکن.** برای اعمال کانفیگ: stop WM → جایگزینی فایل‌ها → start. `0-SAFE-RESTART.bat` این کار را safely انجام می‌دهد.
2. **whkd 0.2.10 `.shell` فقط `cmd` / `powershell` / `pwsh` را قبول می‌کند.** هر چیز دیگر → `panic!("unsupported shell")` → همه‌ی hotkeys می‌میرند.
3. **`focus-workspace N` در whkdrc ۰-ایندکس و per-monitor است** (۰ = workspace "1"). `focus-named-workspace` global است و به مانیتور اصلی می‌پرد — استفاده نکن.
4. **YASB `label_zero_index: false`** تا workspaceها از ۱ نمایش داده شوند.
5. **`.bat` wrapperها را با دابل‌کلیک از Explorer اجرا کن.** `%~dp0` به مسیر خود فایل refer می‌کند، پس از هر کپی از دایرکتوری هم کار می‌کنند.
6. **کانفیگ‌های مرجع (canonical) در:** `F:\Backups\Software-Backups\komorebi-whkd\config\` — `EXPORT-CONFIG` آنجا می‌نویسد و `IMPORT-CONFIG` از آنجا می‌خواند.

---

## نقشه‌ی سریع: چه زمانی چه اسکریپتی

| می‌خواهم... | اسکریپت |
|---|---|
| کانفیگ را تغییر دادم و می‌خواهم اعمال شود | **`0-SAFE-RESTART.bat`** |
| فقط `config.yaml` (yasb) را تغییر دادم | `D-RESTART-YASB.bat` |
| فقط `whkdrc` (hotkeys) را تغییر دادم | `C-RESTART-WHKD.bat` |
| فقط `komorebi.json` را تغییر دادم | `B-RESTART-KOMOREBI.bat` |
| ببینم همه چیز سالم است | `4-STATUS.bat` |
| ترتیب workspaceها بهم ریخته | `5-RESET-WORKSPACES.bat` |
| مانیتوری را وصل/قطع کردم | `E-RECOVER-MONITORS.bat` |
| مانیتور geometry اشتباه نشان می‌دهد | `6-DISPLAY-DIAG.bat` |
| سرویس‌ها را کلاً متوقف کنم | `8-KILL-ALL.bat` |
| دوباره همه را شروع کنم | `9-START-ALL.bat` |
| از کانفیگ بکاپ بگیرم | `EXPORT-CONFIG.bat` |
| کانفیگ را بازگردانم | `IMPORT-CONFIG.bat` |
| کاملاً حذف کنم | `UNINSTALL-KOMOREBI-WHKD.bat` سپس `CLEANUP-KOMOREBI-WHKD.bat` |
| whkd کِرَش کرد با `could not load whkdrc` | `F-REPAIR-WHKDRC.bat` |

<!--
  Persian original, preserved for Davood. SCRIPTS-GUIDE.md is the
  English one and is authoritative for shipping; keep the two in sync when
  either changes. This copy still mentions the retired F:\Backups path.
-->
