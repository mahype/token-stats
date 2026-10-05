using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using TokenStats.Model;
using TokenStats.Providers;
using TokenStats.UI;
using TokenStats.Usage;
using Forms = System.Windows.Forms;

namespace TokenStats.App;

/// <summary>
/// Tray-Symbol: Linksklick öffnet das Popup, Rechtsklick ein Kurzmenü (SPEC §2).
/// Entspricht dem AppDelegate der macOS-Version.
/// </summary>
public sealed class TrayApp : IDisposable
{
    static string DataDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TokenStats");

    public AppSettings Settings { get; }
    public UsageStore Store { get; }
    public ConsumptionStore Consumption { get; }

    readonly Forms.NotifyIcon notifyIcon = new() { Text = "Token Stats" };
    readonly PopupWindow popup;
    SettingsWindow? settingsWindow;
    IntPtr iconHandle;
    readonly DispatcherTimer themeTimer = new() { Interval = TimeSpan.FromSeconds(5) };
    bool taskbarDark = SystemTheme.TaskbarDark;

    public TrayApp(bool demo = false)
    {
        Settings = new AppSettings(demo ? null : Path.Combine(DataDirectory, "settings.json"));
        Store = new UsageStore([new ClaudeProvider(), new CodexProvider(), new AntigravityProvider(), new OllamaProvider()], Settings,
                               demo ? null : Path.Combine(DataDirectory, "state.json"));
        Consumption = new ConsumptionStore(Settings, demo ? null : UsageLedger.DefaultPath);
        popup = new PopupWindow(Store, Consumption, Settings, OpenSettings);
    }

    public void Start()
    {
        notifyIcon.MouseUp += (_, e) =>
        {
            if (e.Button == Forms.MouseButtons.Left) TogglePopup();
        };
        notifyIcon.ContextMenuStrip = new Forms.ContextMenuStrip();
        notifyIcon.ContextMenuStrip.Opening += (_, _) => BuildMenu(notifyIcon.ContextMenuStrip);

        Store.Changed += UpdateIcon;
        Settings.Changed += UpdateIcon;
        // Hell/Dunkel der Taskleiste kann sich jederzeit ändern; das Symbol zieht nach.
        themeTimer.Tick += (_, _) =>
        {
            if (SystemTheme.TaskbarDark == taskbarDark) return;
            taskbarDark = SystemTheme.TaskbarDark;
            UpdateIcon();
        };
        themeTimer.Start();

        UpdateIcon();
        notifyIcon.Visible = true;
        Store.Start();
        Consumption.Start();
    }

    // Symbol

    void UpdateIcon()
    {
        var pick = Store.Displayed;
        var snapshot = pick is null ? null : Store.State(pick.ProviderId).Snapshot;
        var paused = Store.InstalledProviders.Any(p => Store.State(p.Id).IsRateLimited);
        var size = Forms.SystemInformation.SmallIconSize.Width;
        var bitmap = StatusIcon.Render(new StatusIcon.Input(
            Settings.MenuBarMode, pick?.Window.Severity, pick?.Window.Percent,
            snapshot?.Windows.Take(2).Select(w => w.Percent).ToList() ?? [],
            Settings.UseStateColor, paused, taskbarDark), size);

        var previous = iconHandle;
        using (var gdiBitmap = ToGdi(bitmap))
        {
            iconHandle = gdiBitmap.GetHicon();
        }
        notifyIcon.Icon = System.Drawing.Icon.FromHandle(iconHandle);
        if (previous != IntPtr.Zero) DestroyIcon(previous);

        // Der Tooltip des Infobereichs fasst höchstens 127 Zeichen.
        var tooltip = pick is null ? "Token Stats" : $"{pick.ProviderName} · {pick.Window.Name}: {Format.Percent(pick.Window.Percent)}";
        notifyIcon.Text = tooltip.Length > 127 ? tooltip[..127] : tooltip;
    }

    static System.Drawing.Bitmap ToGdi(BitmapSource source)
    {
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(source));
        var stream = new MemoryStream();
        encoder.Save(stream);
        stream.Position = 0;
        return new System.Drawing.Bitmap(stream);
    }

    [DllImport("user32.dll")]
    static extern bool DestroyIcon(IntPtr handle);

    // Klicks

    void TogglePopup()
    {
        if (popup.IsVisible || popup.JustClosed) return;
        // Frischer Stand bei jedem Öffnen: knappster Tab aktiv, immer Seite „Limits“.
        Consumption.Refresh();
        popup.ShowNearTray();
    }

    void BuildMenu(Forms.ContextMenuStrip menu)
    {
        menu.Items.Clear();
        menu.Items.Add("Aktualisieren", null, (_, _) => Store.Refresh(manual: true));

        var modes = new Forms.ToolStripMenuItem("Anzeige-Modus");
        foreach (var mode in MenuBarModes.All)
        {
            var item = new Forms.ToolStripMenuItem(mode.Label()) { Checked = Settings.MenuBarMode == mode };
            item.Click += (_, _) => Settings.MenuBarMode = mode;
            modes.DropDownItems.Add(item);
        }
        menu.Items.Add(modes);

        var login = new Forms.ToolStripMenuItem("Bei Anmeldung starten") { Checked = Settings.LaunchAtLogin };
        login.Click += (_, _) => Settings.LaunchAtLogin = !Settings.LaunchAtLogin;
        menu.Items.Add(login);

        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Einstellungen …", null, (_, _) => OpenSettings());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Token Stats beenden", null, (_, _) => Application.Current.Shutdown());
    }

    void OpenSettings()
    {
        popup.HidePopup();
        if (settingsWindow is null)
        {
            settingsWindow = new SettingsWindow(Settings, Store, Consumption);
            settingsWindow.Closed += (_, _) => settingsWindow = null;
            settingsWindow.Show();
        }
        if (settingsWindow.WindowState == WindowState.Minimized) settingsWindow.WindowState = WindowState.Normal;
        settingsWindow.Activate();
    }

    public void Dispose()
    {
        notifyIcon.Visible = false;
        notifyIcon.Dispose();
        if (iconHandle != IntPtr.Zero) DestroyIcon(iconHandle);
    }
}
