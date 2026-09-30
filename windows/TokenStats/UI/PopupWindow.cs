using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Threading;
using TokenStats.Model;
using TokenStats.Usage;
using Forms = System.Windows.Forms;

namespace TokenStats.UI;

/// <summary>
/// Rahmenloses Fenster über dem Infobereich, entspricht dem NSPopover der macOS-Version.
/// Schließt sich, sobald es den Fokus verliert.
/// </summary>
public sealed class PopupWindow : Window
{
    /// <summary>Platz für den Schatten rund um die Karte.</summary>
    const double ShadowMargin = 14;
    /// <summary>Abstand zur Taskleiste bzw. zum Bildschirmrand, in physischen Pixeln (skaliert).</summary>
    const double ScreenGap = 10;

    readonly PopupView view;
    readonly Border card;
    readonly UsageStore store;
    readonly ConsumptionStore consumption;
    readonly AppSettings settings;
    readonly DispatcherTimer clock = new() { Interval = TimeSpan.FromSeconds(30) };
    DateTime hiddenAt;
    System.Drawing.Point anchor;

    public PopupWindow(UsageStore store, ConsumptionStore consumption, AppSettings settings, Action openSettings)
    {
        this.store = store;
        this.consumption = consumption;
        this.settings = settings;
        view = new PopupView(store, consumption, settings, openSettings);
        view.NeedsRender += Render;

        Title = "Token Stats";
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        Topmost = true;
        SizeToContent = SizeToContent.WidthAndHeight;
        UseLayoutRounding = true;

        card = new Border
        {
            Margin = new Thickness(ShadowMargin),
            CornerRadius = new CornerRadius(8),
            BorderThickness = new Thickness(1),
            Effect = new DropShadowEffect { BlurRadius = 16, ShadowDepth = 3, Direction = 270, Opacity = 0.28 },
        };
        Content = card;

        Deactivated += (_, _) => HidePopup();
        PreviewKeyDown += (_, e) =>
        {
            if (e.Key == Key.Escape) HidePopup();
            // Strg+, öffnet die Einstellungen, solange das Popup offen ist (⌘, auf macOS).
            if (e.Key == Key.OemComma && Keyboard.Modifiers == ModifierKeys.Control) openSettings();
        };
        SizeChanged += (_, _) => Place();
        clock.Tick += (_, _) => Render();
    }

    /// <summary>Gerade geschlossen, weil der Klick aufs Tray-Symbol den Fokus genommen hat?</summary>
    public bool JustClosed => DateTime.UtcNow - hiddenAt < TimeSpan.FromMilliseconds(300);

    public void ShowNearTray()
    {
        anchor = Forms.Cursor.Position;
        view.Reset();
        store.Changed += Render;
        consumption.Changed += Render;
        settings.Changed += Render;
        clock.Start();
        Render();
        Opacity = 0;
        Show();
        Place();
        Opacity = 1;
        Activate();
    }

    public void HidePopup()
    {
        if (!IsVisible) return;
        store.Changed -= Render;
        consumption.Changed -= Render;
        settings.Changed -= Render;
        clock.Stop();
        hiddenAt = DateTime.UtcNow;
        Hide();
    }

    void Render()
    {
        var palette = new Palette(SystemTheme.AppsDark);
        view.Palette = palette;
        card.Background = palette.Background;
        card.BorderBrush = palette.Separator;
        // Innenleben an den runden Ecken der Karte abschneiden.
        var inner = new Border { Child = view.Build() };
        inner.SizeChanged += (_, e) => inner.Clip = new RectangleGeometry(new Rect(e.NewSize), 7, 7);
        card.Child = inner;
    }

    /// <summary>
    /// Neben dem Klickpunkt über (bzw. neben) der Taskleiste, in physischen Pixeln –
    /// so passt es auch bei gemischten DPI-Stufen.
    /// </summary>
    void Place()
    {
        if (!IsVisible) return;
        var handle = new WindowInteropHelper(this).Handle;
        if (handle == IntPtr.Zero || !GetWindowRect(handle, out var rect)) return;
        var width = rect.Right - rect.Left;
        var height = rect.Bottom - rect.Top;
        var scale = VisualTreeHelper.GetDpi(this).DpiScaleX;
        var shadow = (int)Math.Round(ShadowMargin * scale);
        var gap = (int)Math.Round(ScreenGap * scale) - shadow;

        var screen = Forms.Screen.FromPoint(anchor);
        var area = screen.WorkingArea;
        var bounds = screen.Bounds;
        int x, y;
        if (area.Bottom < bounds.Bottom && anchor.Y >= area.Bottom)
        {
            // Taskleiste unten (Standard): über der Taskleiste, mittig zum Klickpunkt.
            x = anchor.X - width / 2;
            y = area.Bottom - height - gap;
        }
        else if (area.Top > bounds.Top && anchor.Y <= area.Top)
        {
            x = anchor.X - width / 2;
            y = area.Top + gap;
        }
        else if (area.Left > bounds.Left && anchor.X <= area.Left)
        {
            x = area.Left + gap;
            y = anchor.Y - height / 2;
        }
        else if (area.Right < bounds.Right && anchor.X >= area.Right)
        {
            x = area.Right - width - gap;
            y = anchor.Y - height / 2;
        }
        else
        {
            // Überlaufbereich oder unbekannte Lage: in die Ecke unten rechts.
            x = area.Right - width - gap;
            y = area.Bottom - height - gap;
        }
        x = Math.Clamp(x, area.Left - shadow, Math.Max(area.Left - shadow, area.Right - width + shadow));
        y = Math.Clamp(y, area.Top - shadow, Math.Max(area.Top - shadow, area.Bottom - height + shadow));
        SetWindowPos(handle, IntPtr.Zero, x, y, 0, 0, SwpNoSize | SwpNoZOrder | SwpNoActivate);
    }

    const uint SwpNoSize = 0x0001, SwpNoZOrder = 0x0004, SwpNoActivate = 0x0010;

    [StructLayout(LayoutKind.Sequential)]
    struct NativeRect { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll")]
    static extern bool GetWindowRect(IntPtr handle, out NativeRect rect);

    [DllImport("user32.dll")]
    static extern bool SetWindowPos(IntPtr handle, IntPtr after, int x, int y, int width, int height, uint flags);
}
