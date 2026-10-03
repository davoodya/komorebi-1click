# SCRIPTS-GUIDE — Komorebi + WHKD + YASB

> همه‌ی اسکریپت‌های این دایرکتوری **SAFE** و برای کانفیگ‌های فعلی (komorebi 0.1.41 / whkd 0.2.10 / yasb) آزمایش‌شده‌اند. هر `.bat` یک wrapper کاربرپسند برای یک `.ps1` است.
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
| `7-YASB-RESTART.ps1` | نسخه‌ی کامل‌ترِ D: علاوه بر restart، وضعیت PATH و autostart registration yasb را هم تشخیص می‌کند. پرچم `-DiagnoseOnly` فقط تشخیص می‌دهد و restart نمی‌کند. |

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
