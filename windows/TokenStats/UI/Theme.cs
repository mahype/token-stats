using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;
using TokenStats.Model;

namespace TokenStats.UI;

/// <summary>Farben des Popups, je für Hell und Dunkel. Zustandsfarben aus dem Entwurf (Theme.swift).</summary>
public sealed class Palette
{
    public bool IsDark { get; }
    public Brush Background { get; }
    public Brush Primary { get; }
    public Brush Secondary { get; }
    public Brush Separator { get; }
    /// <summary>Balken-Hintergrund, Pills, Kapsel des Seitenumschalters.</summary>
    public Brush Fill { get; }
    public Brush Footer { get; }
    /// <summary>Fläche von Buttons, Tiles und aktivem Seitenumschalter.</summary>
    public Brush Control { get; }
    public Brush Accent { get; }

    public Palette(bool dark)
    {
        IsDark = dark;
        Background = Solid(dark ? 0x2B2B2B : 0xF9F9F9);
        Primary = Solid(dark ? 0xFFFFFF : 0x1B1B1B);
        Secondary = Solid(dark ? 0xA8A8A8 : 0x616161);
        Separator = Solid(dark ? 0x3F3F3F : 0xE3E3E3);
        Fill = Solid(dark ? 0x3A3A3A : 0xE8E8E8);
        Footer = Solid(dark ? 0x242424 : 0xF1F1F1);
        Control = Solid(dark ? 0x353535 : 0xFFFFFF);
        Accent = Solid(dark ? 0x60CDFF : 0x005FB8);
    }

    public Brush SeverityBrush(Severity severity) => Solid(SeverityColor(severity, IsDark));

    public static int SeverityColor(Severity severity, bool dark) => severity switch
    {
        Severity.Ok => dark ? 0x4CBE83 : 0x2F8F5B,
        Severity.Warn => dark ? 0xE0A838 : 0xC1860F,
        _ => dark ? 0xE7705A : 0xC04329,
    };

    public static Color ColorOf(int rgb, byte alpha = 255) =>
        Color.FromArgb(alpha, (byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb);

    public static SolidColorBrush Solid(int rgb, byte alpha = 255)
    {
        var brush = new SolidColorBrush(ColorOf(rgb, alpha));
        brush.Freeze();
        return brush;
    }
}

public static class SystemTheme
{
    const string Personalize = @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";

    /// <summary>Apps im dunklen Modus (Einstellungen → Personalisierung → Farben).</summary>
    public static bool AppsDark => ReadFlag("AppsUseLightTheme") == 0;

    /// <summary>Taskleiste dunkel? Bestimmt die Farbe des Tray-Symbols ohne Zustandsfarbe.</summary>
    public static bool TaskbarDark => ReadFlag("SystemUsesLightTheme") == 0;

    static int? ReadFlag(string name)
    {
        using var key = Registry.CurrentUser.OpenSubKey(Personalize);
        return key?.GetValue(name) as int?;
    }
}

/// <summary>Roboterkopf aus dem Entwurf, in einem 24×24-Raster gezeichnet.</summary>
public static class RobotGlyph
{
    static readonly Geometry Strokes = Frozen(new GeometryGroup
    {
        Children =
        {
            new RectangleGeometry(new Rect(4, 8, 16, 11), 3.2, 3.2),
            new LineGeometry(new Point(12, 4.2), new Point(12, 8)),
            new LineGeometry(new Point(9.5, 16.3), new Point(14.5, 16.3)),
            new LineGeometry(new Point(4, 11.5), new Point(2.4, 11.5)),
            new LineGeometry(new Point(20, 11.5), new Point(21.6, 11.5)),
        },
    });

    static readonly Geometry Fills = Frozen(new GeometryGroup
    {
        Children =
        {
            new EllipseGeometry(new Point(9, 13), 1.35, 1.35),
            new EllipseGeometry(new Point(15, 13), 1.35, 1.35),
            new EllipseGeometry(new Point(12, 3.4), 1.3, 1.3),
        },
    });

    static Geometry Frozen(Geometry geometry)
    {
        geometry.Freeze();
        return geometry;
    }

    /// <summary>Zeichnet den Roboter in <paramref name="rect"/>; Linienstärke 1,8 im 24er-Raster, mindestens <paramref name="minLine"/>.</summary>
    public static void Draw(DrawingContext context, Rect rect, Brush brush, double minLine = 0)
    {
        var scale = Math.Min(rect.Width, rect.Height) / 24;
        Draw(context, scale, rect.X + (rect.Width - 24 * scale) / 2, rect.Y + (rect.Height - 24 * scale) / 2, brush, minLine);
    }

    /// <summary>Tatsächliche Kontur im 24er-Raster, inklusive halber Linienstärke.</summary>
    static readonly Rect Outline = new(1.5, 2.1, 21, 18.3);

    /// <summary>
    /// Zeichnet den Roboter so groß, dass seine Kontur <paramref name="rect"/> ausfüllt – für das
    /// 16-px-Tray-Symbol, wo jeder Pixel zählt.
    /// </summary>
    public static void DrawFitted(DrawingContext context, Rect rect, Brush brush, double minLine = 0)
    {
        var scale = Math.Min(rect.Width / Outline.Width, rect.Height / Outline.Height);
        Draw(context, scale,
             rect.X + (rect.Width - Outline.Width * scale) / 2 - Outline.X * scale,
             rect.Y + (rect.Height - Outline.Height * scale) / 2 - Outline.Y * scale,
             brush, minLine);
    }

    static void Draw(DrawingContext context, double scale, double x, double y, Brush brush, double minLine)
    {
        var pen = new Pen(brush, Math.Max(1.8, minLine / scale))
        {
            StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round,
        };
        context.PushTransform(new TranslateTransform(x, y));
        context.PushTransform(new ScaleTransform(scale, scale));
        context.DrawGeometry(null, pen, Strokes);
        context.DrawGeometry(brush, null, Fills);
        context.Pop();
        context.Pop();
    }
}

/// <summary>Roboter als Element, z. B. im Kopf des Popups.</summary>
public sealed class RobotIcon : FrameworkElement
{
    public Brush Foreground { get; init; } = Brushes.Black;

    public RobotIcon(double size = 15)
    {
        Width = size;
        Height = size;
    }

    protected override void OnRender(DrawingContext context) =>
        RobotGlyph.Draw(context, new Rect(0, 0, ActualWidth, ActualHeight), Foreground);
}
